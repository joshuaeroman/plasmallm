/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../../driverManager.js" as DriverManager

var name = "DesktopClick";
var displayName = "Desktop Click";
var description = "Emulate a mouse click or drag on the desktop. Optional coordinates can be supplied. Clicks and drags are relative to the active operating context window (if set via DesktopSetOperatingContext), or absolute screen coordinates otherwise.";
var parameters = {
    type: "object",
    properties: {
        observation: { type: "string", description: "What you see on the screen." },
        pending_tasks: { type: "string", description: "What you still need to do." },
        planned_actions: { type: "string", description: "What you plan to do." },
        action: { type: "string", enum: ["click", "double_click", "drag"], description: "The action to perform. To click, use 'click'. To double click, use 'double_click'. To drag, use 'drag'." },
        verification: { type: "string", description: "Mandatory: Describe what you are targeting at the specified coordinates." },
        nx: { type: "number", description: "Mandatory: X coordinate (0-1000). Relative to the active operating context window (0=left edge, 500=center, 1000=right edge) if set; absolute screen coordinate otherwise." },
        ny: { type: "number", description: "Mandatory: Y coordinate (0-1000). Relative to the active operating context window (0=top edge, 500=center, 1000=bottom edge) if set; absolute screen coordinate otherwise." },
        dx: { type: "number", description: "Normalized X coordinate (0-1000) of the drag destination (only for drag action). Relative to context." },
        dy: { type: "number", description: "Normalized Y coordinate (0-1000) of the drag destination (only for drag action). Relative to context." },
        path: {
            type: "array",
            items: {
                type: "object",
                properties: {
                    nx: { type: "integer" },
                    ny: { type: "integer" }
                },
                required: ["nx", "ny"]
            },
            description: "Optional list of coordinates for compound paths / bezier curves. If specified, overrides dx/dy for drag."
        },
        interpolation: { type: "string", enum: ["linear", "bezier"], description: "Interpolation style for drag (default: linear)." },
        button: { type: "integer", description: "Button code: 1 = Left, 2 = Middle, 3 = Right (default: 1)." },
        zoom: { type: "string", description: "Zoom level for confirmation crop: 'tight' or 'precise'. Defaults to 'tight'.", enum: ["tight", "precise"] },
        modifiers: {
            type: "array",
            items: { type: "string", enum: ["alt", "meta", "ctrl", "shift"] },
            description: "Optional list of keyboard modifiers to hold down during the action. Note: When dragging a window by its center/body instead of its title bar, you MUST pass modifiers=['meta'] for the drag to succeed on KDE."
        }
    },
    required: ["observation", "pending_tasks", "planned_actions", "action", "verification", "nx", "ny"]
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

    var method = args.action === "drag" ? "drag" : "click";
    
    var hasAnyCartesian = (args.nx !== undefined || args.ny !== undefined);
    
    if (hasAnyCartesian && (args.nx === undefined || args.ny === undefined)) {
        context.addDisplayMessage("Action blocked: Incomplete coordinates. You must provide both nx and ny.", "error");
        context.onDone(JSON.stringify({ status: "error", message: "You must provide both nx and ny." }), "", 0);
        return;
    }

    var params = {
        button: args.button || 1,
        zoom: args.zoom || DriverManager.lastZoom || "tight",
        clicks: args.action === "double_click" ? 2 : 1
    };

    if (args.modifiers) {
        params.modifiers = args.modifiers;
    }

    var pathAfter = DriverManager.getNewScreenshotPath();
    if (pathAfter) {
        params.save_paths = [pathAfter, ""];
    }

    if (hasAnyCartesian) {
        params.nx = args.nx;
        params.ny = args.ny;
    }

    if (method === "drag") {
        if (args.path && args.path.length >= 2) {
            params.path = args.path;
        } else {
            params.dx = args.dx;
            params.dy = args.dy;
        }
        params.interpolation = args.interpolation || "linear";
    }
    
    var details = "";
    var clickType = args.action === "double_click" ? "Double click" : "Click";
    if (method === "drag") {
        var pathStr = "";
        if (args.path && args.path.length >= 2) {
            pathStr = args.path.map(function(p) { return "(" + p.nx + "," + p.ny + ")"; }).join(" → ");
        } else {
            var startStr = hasAnyCartesian ? "(" + args.nx + "," + args.ny + ")" : "current pointer";
            pathStr = startStr + " → (" + (args.dx !== undefined ? args.dx : "") + "," + (args.dy !== undefined ? args.dy : "") + ")";
        }
        details = "Drag: " + pathStr + " (" + (args.interpolation || "linear") + ")";
    } else {
        var coordStr = hasAnyCartesian ? " at (" + args.nx + "," + args.ny + ")" : " at current mouse position";
        details = clickType + coordStr;
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
            toolIcon: "input-mouse",
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
                    toolIcon: "input-mouse",
                    toolTitle: displayName,
                    attachmentsStr: attachmentsStr
                });
            }
            context.onDone(JSON.stringify({ status: "success", detail: llmMsg }), "", 0, JSON.stringify(atts));
        }
    });
}
