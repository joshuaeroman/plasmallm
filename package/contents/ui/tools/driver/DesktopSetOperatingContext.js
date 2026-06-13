/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../../driverManager.js" as DriverManager

var name = "DesktopSetOperatingContext";
var displayName = "Desktop Set Operating Context";
var description = "Sets the operational context to a specific application window. Clicks, movement, and screenshots will be restricted to and scaled relative to this window's geometry.";
var parameters = {
    type: "object",
    properties: {
        observation: { type: "string", description: "What you see on the screen." },
        pending_tasks: { type: "string", description: "What you still need to do." },
        planned_actions: { type: "string", description: "What you plan to do." },
        uuid: { type: "string", description: "The ID of the target window to bind to (e.g. 'w1', 'w2', etc.)." }
    },
    required: ["observation", "pending_tasks", "planned_actions", "uuid"]
};
var sandboxed = false;
var sideEffect = true;
var uiHidden = true;

function execute(args, context) {
    var thinkingStr = "";
    if (args.observation) thinkingStr += "\n\n**Observation:** " + args.observation;
    if (args.pending_tasks) thinkingStr += "\n\n**Pending Tasks:** " + args.pending_tasks;
    if (args.planned_actions) thinkingStr += "\n\n**Planned Actions:** " + args.planned_actions;
    var baseMsg = "**Action:** Set operating context to window `" + args.uuid + "`" + thinkingStr;

    if (context.addDisplayMessage) {
        context.addDisplayMessage(baseMsg + "\n\n*Binding operating context...*", "tool_running_rich", {
            toolSummary: "Setting Context",
            toolIcon: "window-pin",
            toolTitle: displayName
        });
    }

    DriverManager.executeCommand("set_operating_context", { uuid: args.uuid }, function(err, result) {
        if (err) {
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", err, "error");
            }
            context.onDone("", err, 1);
        } else {
            var msg = "Operating context bound to window UUID `" + args.uuid + "` successfully.";
            var userMsg = baseMsg + "\n\n*" + msg + "*";
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", userMsg, "tool_result_rich", {
                    toolSummary: "Operating Context Set",
                    toolDataJson: JSON.stringify({ uuid: args.uuid }),
                    toolIcon: "window-pin",
                    toolTitle: displayName
                });
            }
            context.onDone(JSON.stringify({ status: "success", detail: userMsg }), "", 0);
        }
    });
}
