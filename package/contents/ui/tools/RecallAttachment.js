/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "recall_attachment";
var displayName = "Recall Attachment";
var description = "Retrieve the full content of a file previously attached in the conversation by specifying the filename (e.g. 'data.json') or message index (e.g. '19').";
var parameters = {
    type: "object",
    properties: {
        target: {
            type: "string",
            description: "The filename (e.g. '2026-08-15_23-26.jsonl') or message index (e.g. '19') of the attachment to recall."
        }
    },
    required: ["target"]
};

var sandboxed = false;
var sideEffect = false;
var uiHidden = true;

function execute(args, context) {
    var target = String(args.target || "").trim();
    if (!target) {
        context.error("Target filename or message ID is required.");
        return;
    }

    if (typeof context.getAttachmentInfo !== "function") {
        context.error("Attachment store is not accessible from tool context.");
        return;
    }

    var info = context.getAttachmentInfo(target);
    if (!info) {
        context.onDone("Attachment '" + target + "' was not found in earlier conversation turns.", "", 1);
        return;
    }

    if (info.textContent && info.textContent.length > 0) {
        context.onDone("=== Content of attached file: " + info.fileName + " (from message #" + info.msgIndex + ") ===\n" + info.textContent + "\n=== End of attached file ===", "", 0);
        return;
    }

    if (info.filePath && info.filePath.length > 0) {
        var max = (context.config && context.config.toolsReadMaxBytes) ? context.config.toolsReadMaxBytes : 524288;
        var cmd = "head -c " + max + " '" + info.filePath.replace(/'/g, "'\\''") + "'";
        context.exec(cmd, name, args);
        return;
    }

    context.onDone("Attachment '" + target + "' metadata found, but file path is unavailable.", "", 1);
}
