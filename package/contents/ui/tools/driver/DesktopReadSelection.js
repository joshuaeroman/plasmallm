/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../../driverManager.js" as DriverManager

var name = "DesktopReadSelection";
var displayName = "Desktop Read Selection";
var description = "Automatically copies any text currently selected (highlighted) on the screen and reads it back to the context. Saves one round trip by executing copy + clipboard-read in a single step.";
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
var sideEffect = false;
var uiHidden = true;

function execute(args, context) {
    var thinkingStr = "";
    if (args.observation) thinkingStr += "\n\n**Observation:** " + args.observation;
    if (args.pending_tasks) thinkingStr += "\n\n**Pending Tasks:** " + args.pending_tasks;
    if (args.planned_actions) thinkingStr += "\n\n**Planned Actions:** " + args.planned_actions;
    var baseMsg = "**Action:** Read active text selection" + thinkingStr;

    if (context.addDisplayMessage) {
        context.addDisplayMessage(baseMsg + "\n\n*Copying and reading text selection...*", "tool_running_rich", {
            toolSummary: "Reading Selection",
            toolIcon: "edit-copy",
            toolTitle: displayName
        });
    }

    DriverManager.executeCommand("read_selection", {}, function(err, result) {
        if (err) {
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", err, "error");
            }
            context.onDone("", err, 1);
        } else {
            var textVal = result.text || "";
            var displayVal = textVal ? ("\"" + textVal.substring(0, 300) + (textVal.length > 300 ? "..." : "") + "\"") : "No text selection found.";
            var userMsg = baseMsg + "\n\n*Text selection retrieved: " + displayVal + "*";
            var llmMsg = baseMsg + "\n\n*Retrieved selection content:*\n\n```text\n" + textVal + "\n```";

            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", userMsg, "tool_result_rich", {
                    toolSummary: "Selection Retrieved",
                    toolDataJson: JSON.stringify({ length: textVal.length }),
                    toolIcon: "edit-copy",
                    toolTitle: displayName
                });
            }
            context.onDone(JSON.stringify({ status: "success", detail: llmMsg }), "", 0);
        }
    });
}
