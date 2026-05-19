/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "write_file";
var description = "Write content to a file at the specified path. Access is restricted to allowed directories.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        path: { type: "string", description: "Absolute path to the file" },
        content: { type: "string", description: "The content to write" }
    },
    required: ["justification", "path", "content"]
};
var sandboxed = true;
var sideEffect = true;

function execute(args, context) {
    var max = context.config.toolsWriteMaxBytes || 1048576;
    var content = args.content || "";
    if (content.length > max) {
        context.error(context.i18n("Error: content exceeds max write size (%1 bytes)", max));
        return;
    }
    var escapedPath = args.path.replace(/'/g, "'\\''");
    var escapedContent = content.replace(/'/g, "'\\''");
    // Atomic write via temp file
    // Ensure parent directory exists before moving the file
    var cmd = "tmpfile=$(mktemp) && printf '%s' '" + escapedContent + "' > \"$tmpfile\" && mkdir -p \"$(dirname '" + escapedPath + "')\" && mv \"$tmpfile\" '" + escapedPath + "'";
    context.exec(cmd, name, args);
}
