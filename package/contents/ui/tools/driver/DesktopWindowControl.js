/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../../driverManager.js" as DriverManager

var name = "DesktopWindowControl";
var displayName = "Desktop Window Control";
var description = "Performs window management actions (focusing/restoring, minimizing, maximizing, closing, or moving/resizing) on a window by its UUID.";
var parameters = {
    type: "object",
    properties: {
        observation: { type: "string", description: "What you see on the screen." },
        pending_tasks: { type: "string", description: "What you still need to do." },
        planned_actions: { type: "string", description: "What you plan to do." },
        uuid: { type: "string", description: "The ID of the target window (e.g. 'w1', 'w2', etc.)." },
        action: { type: "string", enum: ["minimize", "maximize", "restore", "close", "move_resize"], description: "The action to apply." },
        nx: { type: "integer", minimum: 0, maximum: 1000, description: "New X coordinate (0-1000) for the left edge of the window. Required only for 'move_resize'." },
        ny: { type: "integer", minimum: 0, maximum: 1000, description: "New Y coordinate (0-1000) for the top edge of the window. Required only for 'move_resize'." },
        nw: { type: "integer", minimum: 1, maximum: 1000, description: "New width (0-1000 scale) for the window. Required only for 'move_resize'." },
        nh: { type: "integer", minimum: 1, maximum: 1000, description: "New height (0-1000 scale) for the window. Required only for 'move_resize'." }
    },
    required: ["observation", "pending_tasks", "planned_actions", "uuid", "action"]
};
var sandboxed = false;
var sideEffect = true;
var uiHidden = true;

function execute(args, context) {
    var thinkingStr = "";
    if (args.observation) thinkingStr += "\n\n**Observation:** " + args.observation;
    if (args.pending_tasks) thinkingStr += "\n\n**Pending Tasks:** " + args.pending_tasks;
    if (args.planned_actions) thinkingStr += "\n\n**Planned Actions:** " + args.planned_actions;
    
    var geomStr = "";
    if (args.action === "move_resize") {
        geomStr = " to X=" + args.nx + ", Y=" + args.ny + ", W=" + args.nw + ", H=" + args.nh;
    }
    var baseMsg = "**Action:** Apply window action '" + args.action + "'" + geomStr + " on window `" + args.uuid + "`" + thinkingStr;

    if (context.addDisplayMessage) {
        context.addDisplayMessage(baseMsg + "\n\n*Applying window action...*", "tool_running_rich", {
            toolSummary: "Managing Window",
            toolIcon: "window-new",
            toolTitle: displayName
        });
    }

    var params = {
        uuid: args.uuid,
        action: args.action
    };
    if (args.action === "move_resize") {
        params.nx = args.nx;
        params.ny = args.ny;
        params.nw = args.nw;
        params.nh = args.nh;
    }

    DriverManager.executeCommand("apply_window_action", params, function(err, result) {
        if (err) {
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", err, "error");
            }
            context.onDone("", err, 1);
        } else {
            var userMsg = baseMsg + "\n\n*Window action '" + args.action + "' applied successfully.*";
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", userMsg, "tool_result_rich", {
                    toolSummary: "Window Action Applied",
                    toolDataJson: JSON.stringify({ uuid: args.uuid, action: args.action }),
                    toolIcon: "window-new",
                    toolTitle: displayName
                });
            }
            context.onDone(JSON.stringify({ status: "success", detail: userMsg }), "", 0);
        }
    });
}
