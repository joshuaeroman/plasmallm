/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../../driverManager.js" as DriverManager

var name = "DesktopScroll";
var displayName = "Desktop Scroll";
var description = "Simulates mouse wheel scrolling in a given direction at specific coordinates (relative to the active operating context window, if set).";
var parameters = {
    type: "object",
    properties: {
        observation: { type: "string", description: "What you see on the screen." },
        pending_tasks: { type: "string", description: "What you still need to do." },
        planned_actions: { type: "string", description: "What you plan to do." },
        direction: { type: "string", enum: ["up", "down", "left", "right"], description: "Scroll direction." },
        amount: { type: "integer", minimum: 1, maximum: 50, description: "Number of scroll ticks. Defaults to 1." },
        nx: { type: "integer", minimum: 0, maximum: 1000, description: "Mandatory X coordinate (0-1000). Relative to the active operating context window (0=left edge, 500=center, 1000=right edge) if set; absolute screen coordinate otherwise." },
        ny: { type: "integer", minimum: 0, maximum: 1000, description: "Mandatory Y coordinate (0-1000). Relative to the active operating context window (0=top edge, 500=center, 1000=bottom edge) if set; absolute screen coordinate otherwise." }
    },
    required: ["observation", "pending_tasks", "planned_actions", "direction", "nx", "ny"]
};
var sandboxed = false;
var sideEffect = true;
var uiHidden = true;

function execute(args, context) {
    var thinkingStr = "";
    if (args.observation) thinkingStr += "\n\n**Observation:** " + args.observation;
    if (args.pending_tasks) thinkingStr += "\n\n**Pending Tasks:** " + args.pending_tasks;
    if (args.planned_actions) thinkingStr += "\n\n**Planned Actions:** " + args.planned_actions;
    
    var coordStr = "";
    if (args.nx !== undefined && args.ny !== undefined) {
        coordStr = " at (" + args.nx + ", " + args.ny + ")";
    }
    var baseMsg = "**Action:** Scroll " + args.direction + coordStr + " (ticks: " + (args.amount || 1) + ")" + thinkingStr;

    if (context.addDisplayMessage) {
        context.addDisplayMessage(baseMsg + "\n\n*Scrolling...*", "tool_running_rich", {
            toolSummary: "Scrolling Content",
            toolIcon: "transform-move",
            toolTitle: displayName
        });
    }

    var params = {
        direction: args.direction,
        amount: args.amount || 1
    };
    if (args.nx !== undefined && args.ny !== undefined) {
        params.nx = args.nx;
        params.ny = args.ny;
    }

    DriverManager.executeCommand("scroll", params, function(err, result) {
        if (err) {
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", err, "error");
            }
            context.onDone("", err, 1);
        } else {
            var userMsg = baseMsg + "\n\n*Scroll completed successfully.*";
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", userMsg, "tool_result_rich", {
                    toolSummary: "Scroll Completed",
                    toolDataJson: JSON.stringify({ direction: args.direction, amount: args.amount || 1 }),
                    toolIcon: "transform-move",
                    toolTitle: displayName
                });
            }
            context.onDone(JSON.stringify({ status: "success", detail: userMsg }), "", 0);
        }
    });
}
