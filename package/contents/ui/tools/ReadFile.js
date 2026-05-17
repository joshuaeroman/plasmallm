/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "read_file";
var description = "Read the contents of a file at the specified path. Access is restricted to allowed directories.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        path: { type: "string", description: "Absolute path to the file" }
    },
    required: ["justification", "path"]
};
var sandboxed = true;
var sideEffect = false;

function execute(args, context) {
    var max = context.config.toolsReadMaxBytes || 204800;

    var cmd = "head -c " + max + " '" + args.path.replace(/'/g, "'\\''") + "'";
    context.exec(cmd, name, args);
}
