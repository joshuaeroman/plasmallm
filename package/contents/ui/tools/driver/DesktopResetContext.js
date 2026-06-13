/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../../driverManager.js" as DriverManager

var name = "DesktopResetContext";
var displayName = "Desktop Reset Context";
var description = "Clears active window focus restrictions and returns back to the global full-screen mode. Returns a new visual and semantic global state in a single call.";
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
    var baseMsg = "**Action:** Reset operating context to global desktop" + thinkingStr;

    if (context.addDisplayMessage) {
        context.addDisplayMessage(baseMsg + "\n\n*Resetting context and fetching global state...*", "tool_running_rich", {
            toolSummary: "Resetting Context",
            toolIcon: "view-fullscreen",
            toolTitle: displayName
        });
    }

    var params = {};
    var path = DriverManager.getNewScreenshotPath();
    if (path) {
        params.save_path = path;
    }

    DriverManager.executeCommand("reset_context", params, function(err, result) {
        if (err) {
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", err, "error");
            }
            context.onDone("", err, 1);
        } else {
            var atts = [];
            var attachmentsStr = "";
            if (result.image) {
                atts = [{ filePath: result.image, fileName: "screenshot.jpg" }];
                attachmentsStr = result.image;
            }

            var windowsData = result.windows || [];
            var treeData = result.accessibility_tree || [];
            var formattedResult = "Context reset successfully. Current global desktop state:\n\n";
            
            if (windowsData.length > 0) {
                formattedResult += "### Open Windows:\n";
                for (var i = 0; i < windowsData.length; i++) {
                    var win = windowsData[i];
                    var stateStr = " [Minimized: " + (win.minimized ? "Yes" : "No") + 
                                   ", Active: " + (win.active ? "Yes" : "No") + 
                                   ", On Current Desktop: " + (win.on_current_desktop ? "Yes" : "No") + "]";
                    formattedResult += "- **" + win.title + "** (Window ID: `" + win.uuid + "`)" + stateStr + "\n";
                    formattedResult += "  - Normalized 0-1000 Bounds:\n";
                    formattedResult += "    - X: " + win.normalized_bounds.left_nx + " to " + win.normalized_bounds.right_nx + "\n";
                    formattedResult += "    - Y: " + win.normalized_bounds.top_ny + " to " + win.normalized_bounds.bottom_ny + "\n";
                    formattedResult += "    - Center: (" + win.normalized_bounds.center_nx + ", " + win.normalized_bounds.center_ny + ")\n";
                    formattedResult += "    - Window ID: `" + win.uuid + "`\n";
                }
                formattedResult += "\n";
            }
            
            if (treeData.length > 0) {
                formattedResult += "### Accessibility Tree (Interactive Elements):\n";
                for (var j = 0; j < treeData.length; j++) {
                    var elem = treeData[j];
                    formattedResult += "- [" + elem.role + "] Name: '" + elem.name + "' Bounds: " + 
                                       "X: " + elem.bounds.left_nx + " to " + elem.bounds.right_nx + ", " +
                                       "Y: " + elem.bounds.top_ny + " to " + elem.bounds.bottom_ny + " Center: (" + 
                                       elem.bounds.center_nx + ", " + elem.bounds.center_ny + ")\n";
                }
            }

            var userMsg = baseMsg + "\n\n*Context reset and global state retrieved successfully.*";
            var llmMsg = baseMsg + "\n\n*" + formattedResult + "*";

            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", userMsg, "tool_result_rich", {
                    toolSummary: "Context Reset",
                    toolDataJson: JSON.stringify({ window_count: windowsData.length }),
                    toolIcon: "view-fullscreen",
                    toolTitle: displayName,
                    attachmentsStr: attachmentsStr
                });
            }
            context.onDone(JSON.stringify({ status: "success", detail: llmMsg }), "", 0, JSON.stringify(atts));
        }
    });
}
