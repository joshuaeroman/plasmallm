/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "search_files";
var description = "Search for a pattern within files in a directory (recursive).";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        path: { type: "string", description: "Absolute path to the directory to search in" },
        pattern: { type: "string", description: "The regex pattern to search for" }
    },
    required: ["justification", "path", "pattern"]
};
var sandboxed = true;
var sideEffect = false;
var outputScheme = "console style";

function execute(args, context) {
    var cmd = "grep -rn --include='*' --max-count=200 -- '" + args.pattern.replace(/'/g, "'\\''") + "' '" + args.path.replace(/'/g, "'\\''") + "'";
    context.exec(cmd, name, args);
}
