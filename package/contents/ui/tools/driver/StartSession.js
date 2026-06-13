/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../../driverManager.js" as DriverManager

var name = "StartSession";
var displayName = "Start Session";
var description = "Start a desktop automation session. This handshake is required before using any other desktop automation tools. It prompts the user for permission. Once started, you can use DesktopGetState, DesktopClick, DesktopInput, DesktopMoveMouse, DesktopScroll, DesktopWindowControl, and DesktopReadSelection tools.";
var parameters = {
    type: "object",
    properties: {
        observation: { type: "string", description: "What you see on the screen." },
        pending_tasks: { type: "string", description: "What you still need to do." },
        planned_actions: { type: "string", description: "What you plan to do." }
    },
    required: ["observation", "pending_tasks", "planned_actions"]
};
var sandboxed = false;
var sideEffect = true;
var uiHidden = true;

function execute(args, context) {
    var thinkingStr = "";
    if (args.observation) thinkingStr += "\n\n**Observation:** " + args.observation;
    if (args.pending_tasks) thinkingStr += "\n\n**Pending Tasks:** " + args.pending_tasks;
    if (args.planned_actions) thinkingStr += "\n\n**Planned Actions:** " + args.planned_actions;
    var baseMsg = "**Action:** Start desktop automation session" + thinkingStr;

    if (context.addDisplayMessage) {
        context.addDisplayMessage(baseMsg + "\n\n*Starting desktop automation session...*", "tool_running_rich", {
            toolSummary: "Starting session",
            toolIcon: "input-mouse",
            toolTitle: displayName
        });
    }

    var startTime = Date.now();

    function finalizeWithScreenshot(isAlreadyAuthorized) {
        var authStatus = isAlreadyAuthorized ? " (already authorized)" : "";
        var params = { include_tree: false };
        var path = DriverManager.getNewScreenshotPath();
        if (path) {
            params.save_path = path;
        }
        DriverManager.executeCommand("get_desktop_state", params, function(err, result) {
            if (err) {
                var fallbackUserMsg = baseMsg + "\n\n*Session started successfully" + authStatus + ", but screenshot failed.*";
                var fallbackLlmMsg = baseMsg + "\n\n*Session started successfully" + authStatus + ", but capturing initial screenshot failed. You may need to call DesktopGetState manually.*";
                if (context.replaceDisplayMessage) {
                    context.replaceDisplayMessage("tool_running_rich", fallbackUserMsg, "tool_result_rich", {
                        toolSummary: "Session Active",
                        toolDataJson: JSON.stringify({ observation: args.observation || "", pending_tasks: args.pending_tasks || "", planned_actions: args.planned_actions || "" }),
                        toolIcon: "input-mouse",
                        toolTitle: displayName
                    });
                }
                context.onDone(JSON.stringify({ status: "success", detail: fallbackLlmMsg }), "", 0);
            } else {
                var atts = [];
                var attachmentsStr = "";
                if (result.image) {
                    atts = [{ filePath: result.image, fileName: "screenshot.jpg" }];
                    attachmentsStr = result.image;
                }
                
                var userMsg = baseMsg + "\n\n*Session started successfully" + authStatus + ".*";
                var llmMsg = baseMsg + "\n\n*Session started successfully" + authStatus + ". You are now authorized to drive the desktop. An initial screenshot is attached. Please analyze the image and use DesktopGetState to query interactive element trees and see window information as needed.*";
                
                if (context.replaceDisplayMessage) {
                    context.replaceDisplayMessage("tool_running_rich", userMsg, "tool_result_rich", {
                        toolSummary: "Session Active",
                        toolDataJson: JSON.stringify({ observation: args.observation || "", pending_tasks: args.pending_tasks || "", planned_actions: args.planned_actions || "" }),
                        toolIcon: "input-mouse",
                        toolTitle: displayName,
                        attachmentsStr: attachmentsStr
                    });
                }
                context.onDone(JSON.stringify({ status: "success", detail: llmMsg }), "", 0, JSON.stringify(atts));
            }
        });
    }

    function pollForAuthorization() {
        DriverManager.checkDriverSession(function(active) {
            if (active) {
                finalizeWithScreenshot(false);
            } else if (Date.now() - startTime > 60000) {
                // Timeout after 60 seconds
                var errorMsg = "Authorization request timed out or was denied by the user.";
                if (context.replaceDisplayMessage) {
                    context.replaceDisplayMessage("tool_running_rich", errorMsg, "error");
                }
                context.onDone("", errorMsg, 1);
            } else {
                context.setTimeout(pollForAuthorization, 500);
            }
        }, true);
    }

    var clientToken = context.config.desktopAutomationToken || "";
    DriverManager.startSession(clientToken, function(err, token, isAlreadyAuthorized) {
        if (err) {
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", err.error || err, "error");
            }
            context.onDone("", err.error || err, 1);
        } else if (isAlreadyAuthorized) {
            finalizeWithScreenshot(true);
        } else {
            // Update UI to show authorization pending, and block/poll
            var userMsg = baseMsg + "\n\n*Session request initiated. Please approve the authorization dialog on your screen.*";
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", userMsg, "tool_running_rich", {
                    toolSummary: "Authorization Pending",
                    toolIcon: "input-mouse",
                    toolTitle: displayName
                });
            }
            pollForAuthorization();
        }
    });
}
