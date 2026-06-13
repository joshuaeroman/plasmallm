/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../../driverManager.js" as DriverManager

var name = "DesktopInput";
var displayName = "Desktop Input";
var description = "Type text, press keyboard shortcuts, or use the fill_text macro. Coordinates are relative to the active operating context window (if set via DesktopSetOperatingContext), or absolute screen coordinates otherwise.";
var parameters = {
    type: "object",
    properties: {
        observation: { type: "string", description: "What you see on the screen." },
        pending_tasks: { type: "string", description: "What you still need to do." },
        planned_actions: { type: "string", description: "What you plan to do." },
        action: { type: "string", enum: ["type", "press", "fill_text"], description: "Whether to 'type' text, 'press' a shortcut, or use 'fill_text' macro." },
        verification: { type: "string", description: "Mandatory: Describe what you are targeting at the specified coordinates." },
        nx: { type: "number", description: "Optional: Normalized X coordinate (0-1000) of the input field. Relative to active context." },
        ny: { type: "number", description: "Optional: Normalized Y coordinate (0-1000) of the input field. Relative to active context." },
        text: { type: "string", description: "The literal text to type. Do NOT include keys like enter, backspace, or control shortcuts here; use action: 'press' instead to send them." },
        key: { type: "string", description: "The keyboard shortcut to press (for action: 'press'). Examples: 'enter', 'ctrl+c', 'ctrl+alt+t'." },
        clear_first: { type: "boolean", description: "Whether to select all and delete existing text first (for action: 'fill_text')." },
        zoom: { type: "string", description: "Zoom level for confirmation crop: 'tight' or 'precise'. Defaults to 'tight'.", enum: ["tight", "precise"] }
    },
    required: ["observation", "pending_tasks", "planned_actions", "action", "verification"]
};
var sandboxed = false;
var sideEffect = true;
var uiHidden = true;

function execute(args, context) {
    if (JSON.stringify(args).indexOf("__CANCEL__") !== -1) {
        context.addDisplayMessage("Action safely cancelled by LLM (__CANCEL__).", "error");
        context.onDone(JSON.stringify({ status: "cancelled", detail: "Action safely cancelled because __CANCEL__ was detected in your arguments. You may now take your next turn." }), "", 0);
        return;
    }

    var method = args.action;
    
    var hasAnyCartesian = (args.nx !== undefined || args.ny !== undefined);

    if (hasAnyCartesian && method !== "fill_text") {
        context.addDisplayMessage("Action blocked: Coordinates only valid for fill_text. Coordinates (nx, ny) are only supported for action='fill_text'.", "error");
        context.onDone(JSON.stringify({ status: "error", message: "Coordinates (nx, ny) are only supported for action='fill_text'." }), "", 0);
        return;
    }

    if (hasAnyCartesian && (args.nx === undefined || args.ny === undefined)) {
        context.addDisplayMessage("Action blocked: Incomplete coordinates. You must provide both nx and ny for absolute coordinates.", "error");
        context.onDone(JSON.stringify({ status: "error", message: "You must provide both nx and ny for absolute coordinates." }), "", 0);
        return;
    }

    var params = {
        zoom: args.zoom || "tight"
    };

    var pathAfter = DriverManager.getNewScreenshotPath();
    if (pathAfter) {
        params.save_paths = [pathAfter, ""];
    }

    if (method === "type") {
        method = "input_text";
        params.text = args.text || "";
    } else if (method === "press") {
        method = "press_key";
        params.key = args.key || "";
    } else if (method === "fill_text") {
        params.text = args.text || "";
        params.clear_first = args.clear_first === true;
        if (hasAnyCartesian) {
            params.nx = args.nx;
            params.ny = args.ny;
        }
    }

    var details = "";
    if (args.action === "type") {
        details = "Type \"" + (args.text || "") + "\"";
    } else if (args.action === "press") {
        details = "Press key shortcut \"" + (args.key || "") + "\"";
    } else if (args.action === "fill_text") {
        var coordStr = hasAnyCartesian ? " at (" + args.nx + "," + args.ny + ")" : " at current mouse position";
        details = "Fill text \"" + (args.text || "") + "\"" + coordStr + (args.clear_first ? " (clearing first)" : "");
    }

    var thinkingStr = "";
    if (args.observation) thinkingStr += "\n\n**Observation:** " + args.observation;
    if (args.pending_tasks) thinkingStr += "\n\n**Pending Tasks:** " + args.pending_tasks;
    if (args.planned_actions) thinkingStr += "\n\n**Planned Actions:** " + args.planned_actions;
    if (args.verification) thinkingStr += "\n\n**Visual Verification:** " + args.verification;
    var baseMsg = "**Action:** " + details + thinkingStr;

    var displayParams = JSON.parse(JSON.stringify(params));

    if (context.addDisplayMessage) {
        context.addDisplayMessage(baseMsg + "\n\n*Emulating action...*", "tool_running_rich", {
            toolSummary: method + " event",
            toolIcon: "input-keyboard",
            toolTitle: displayName
        });
    }

    DriverManager.executeCommand(method, params, function(err, result) {
        if (err) {
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", err, "error");
            }
            context.onDone("", err, 1);
        } else {
            DriverManager.lastDesktopMoveTime = 0;
            var userMsg = baseMsg + "\n\n*Action executed.*";
            var llmMsg = baseMsg + "\n\n*Action executed. A confirmation crop image showing the result of your action is attached. Review the visual effect to determine your next step. NOTE: Your mouse pointer is currently positioned exactly in the middle of this image. You may call a click action with NO coordinates to click the exact center of this image.*";
            
            var focusedItem = result.focused_item;
            if (focusedItem) {
                var focusStr = "\n\n**Currently Focused UI Item:** [Role: " + focusedItem.role + "] Name: '" + focusedItem.name + "' (in application '" + focusedItem.app_name + "')";
                userMsg += focusStr;
                llmMsg += focusStr;
            }

            var images = (result && Array.isArray(result.images)) ? result.images : [];
            var atts = [];
            var attachmentsStr = "";
            var attachDataUrls = [];
            var filenames = images.length === 2 ? ["after.jpg", "screenshot.jpg"] : ["after.jpg"];
            for (var i = 0; i < images.length; i++) {
                if (images[i]) {
                    atts.push({ filePath: images[i], fileName: (filenames[i] || "image.jpg") });
                    attachDataUrls.push(images[i]);
                }
            }
            attachmentsStr = attachDataUrls.join("\n");

            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", userMsg, "tool_result_rich", {
                    toolSummary: method + " executed",
                    toolDataJson: JSON.stringify(displayParams),
                    toolIcon: "input-keyboard",
                    toolTitle: displayName,
                    attachmentsStr: attachmentsStr
                });
            }
            context.onDone(JSON.stringify({ status: "success", detail: llmMsg }), "", 0, JSON.stringify(atts));
        }
    });
}
