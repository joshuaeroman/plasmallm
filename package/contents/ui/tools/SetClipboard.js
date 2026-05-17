/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "set_clipboard";
var description = "Set the content of the system clipboard.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        content: { type: "string", description: "The text to copy to the clipboard" }
    },
    required: ["justification", "content"]
};
var sandboxed = false;
var sideEffect = true;

function execute(args, context) {
    var escaped = (args.content || "").replace(/'/g, "'\\''");
    var cmd = "if command -v wl-copy >/dev/null 2>&1; then printf '%s' '" + escaped + "' | wl-copy; elif command -v xclip >/dev/null 2>&1; then printf '%s' '" + escaped + "' | xclip -i -selection clipboard; else echo 'Error: no clipboard tool found' >&2; exit 1; fi";
    context.exec(cmd, name, args);
}
