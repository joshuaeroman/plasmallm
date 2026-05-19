/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "get_clipboard";
var description = "Get the current content of the system clipboard.";
var parameters = { type: "object", properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." }
    } ,
    required: ["justification"]
};
var sandboxed = false;
var sideEffect = false;

function execute(args, context) {
    var cmd = "if command -v wl-paste >/dev/null 2>&1; then wl-paste; elif command -v xclip >/dev/null 2>&1; then xclip -o -selection clipboard; else echo 'Error: no clipboard tool found' >&2; exit 1; fi";
    context.exec(cmd, name, args);
}
