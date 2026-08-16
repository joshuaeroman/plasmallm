/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "restore_context";
var displayName = "Restore Context";
var description = "Restore the full verbatim text and tool outputs of previously compacted messages by specifying the start and end message IDs from a cited message range.";
var parameters = {
    type: "object",
    properties: {
        start_msg_id: {
            type: "string",
            description: "The ID or number of the first message in the range to restore (e.g. '1' or 'msg_1')"
        },
        end_msg_id: {
            type: "string",
            description: "The ID or number of the last message in the range to restore (e.g. '8' or 'msg_8')"
        }
    },
    required: ["start_msg_id", "end_msg_id"]
};

var sandboxed = false;
var sideEffect = false;
var uiHidden = true;

function execute(args, context) {
    var startId = String(args.start_msg_id || "").trim();
    var endId = String(args.end_msg_id || "").trim();

    if (!startId || !endId) {
        context.error("Both start_msg_id and end_msg_id are required.");
        return;
    }

    if (typeof context.getMessagesRange !== "function") {
        context.error("Conversation history store is not accessible from tool context.");
        return;
    }

    var restored = context.getMessagesRange(startId, endId);
    if (!restored || restored.length === 0) {
        context.onDone("No messages found matching range from " + startId + " to " + endId + ".", "", 0);
        return;
    }

    context.onDone(restored, "", 0);
}
