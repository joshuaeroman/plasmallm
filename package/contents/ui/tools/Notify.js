/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "notify";
var description = "Show a system notification.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        summary: { type: "string", description: "The title of the notification" },
        body: { type: "string", description: "The main text of the notification" }
    },
    required: ["justification", "summary", "body"]
};
var sandboxed = false;
var sideEffect = true;

function execute(args, context) {
    var cmd = "notify-send -- '" + (args.summary || "").replace(/'/g, "'\\''") + "' '" + (args.body || "").replace(/'/g, "'\\''") + "'";
    context.exec(cmd, name, args);
}
