/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "list_dir";
var description = "List the contents of a directory. Access is restricted to allowed directories.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        path: { type: "string", description: "Absolute path to the directory" }
    },
    required: ["justification", "path"]
};
var sandboxed = true;
var sideEffect = false;
var outputScheme = "console style";

function execute(args, context) {
    var cmd = "path='" + args.path.replace(/'/g, "'\\''") + "'; " +
              "count=$(ls -1A \"$path\" 2>/dev/null | wc -l); " +
              "printf 'Files: %d\\n---\\n' \"$count\"; " +
              "ls -1A \"$path\" 2>/dev/null | head -n 500; " +
              "if [ \"$count\" -gt 500 ]; then printf '... and %d more files\\n' \"$((count - 500))\"; fi";
    context.exec(cmd, name, args);
}
