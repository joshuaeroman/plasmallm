/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "api.js" as Api

/**
 * Parses legacy V1 JSONL history files and synthesizes turn IDs on the fly.
 */
function loadV1(lines, chatMessages, displayMessages, fileReader, pendingFileReads, appendDisplay) {
    for (var i = 0; i < lines.length; i++) {
        if (!lines[i].trim()) continue;
        try {
            var data = JSON.parse(lines[i]);
            if (data._type === "api") {
                chatMessages.append({
                    msgId: "",
                    turnId: "",
                    role: data.role,
                    content: data.content,
                    tool_calls_json: data.tool_calls_json || "",
                    tool_call_id: data.tool_call_id || "",
                    thinking_blocks_json: data.thinking_blocks_json || "",
                    attachments_json: data.attachments_json || "",
                    timestamp_api: data.timestamp_api || ""
                });

                if (data.attachments_json && data.attachments_json.length > 0 && fileReader && pendingFileReads) {
                    try {
                        var atts = JSON.parse(data.attachments_json);
                        var msgIdx = chatMessages.count - 1;
                        for (var k = 0; k < atts.length; k++) {
                            if (Api.isImageFile(atts[k].filePath)) {
                                var cmd = "cat '" + atts[k].filePath.replace(/'/g, "'\\''") + "' | base64 -w0";
                                pendingFileReads[cmd] = { 
                                    filePath: atts[k].filePath, 
                                    fileName: atts[k].fileName, 
                                    isImage: true, 
                                    chatMessageIndex: msgIdx 
                                };
                                fileReader.connectSource(cmd);
                            }
                        }
                    } catch(e) {}
                }
            } else if (data._type === "display") {
                appendDisplay(data.role, data.content, {
                    msgId: data.msgId || data.id || "",
                    turnId: data.turnId || "",
                    apiMsgId: data.apiMsgId || "",
                    thinking: data.thinking || "",
                    shared: data.shared || false,
                    timestamp: data.timestamp || "",
                    attachmentsStr: data.attachmentsStr || "",
                    fromVoice: !!data.fromVoice,
                    toolTitle: data.toolTitle || "",
                    toolIcon: data.toolIcon || "",
                    toolSummary: data.toolSummary || "",
                    toolDataJson: data.toolDataJson || "",
                    toolView: data.toolView || "",
                    toolName: data.toolName || "",
                    toolArgs: data.toolArgs || "",
                    stdout: data.stdout || "",
                    stderr: data.stderr || "",
                    exitCode: data.exitCode !== undefined ? data.exitCode : 0,
                    outputScheme: data.outputScheme || "",
                    tool_call_id: data.tool_call_id || "",
                    callId: data.callId || ""
                });
            }
        } catch(e) {
            console.warn("LegacyChatLoader error parsing JSONL line: " + e);
        }
    }

    // Synthesize turn IDs and message IDs
    synthesizeTurnMetadata(chatMessages, displayMessages);
}

function synthesizeTurnMetadata(chatMessages, displayMessages) {
    var displayTurn = 0;
    var currentTurnId = "";
    
    for (var i = 0; i < displayMessages.count; i++) {
        var d = displayMessages.get(i);
        if (d.role === "user") {
            displayTurn++;
            currentTurnId = "turn_" + displayTurn;
        }
        displayMessages.setProperty(i, "turnId", currentTurnId || "turn_1");
        displayMessages.setProperty(i, "msgId", "msg_d_" + (i + 1));
    }

    var chatTurn = 0;
    var currentChatTurnId = "";
    for (var j = 0; j < chatMessages.count; j++) {
        var c = chatMessages.get(j);
        if (c.role === "system") {
            chatMessages.setProperty(j, "msgId", "msg_sys_0");
            chatMessages.setProperty(j, "turnId", "turn_0");
            continue;
        }
        if (c.role === "user") {
            chatTurn++;
            currentChatTurnId = "turn_" + chatTurn;
        }
        chatMessages.setProperty(j, "turnId", currentChatTurnId || "turn_1");
        chatMessages.setProperty(j, "msgId", "msg_c_" + j);
    }

    // Link apiMsgId
    for (var k = 0; k < displayMessages.count; k++) {
        var dm = displayMessages.get(k);
        for (var m = 1; m < chatMessages.count; m++) {
            var cm = chatMessages.get(m);
            if (cm.turnId === dm.turnId && cm.role === dm.role) {
                displayMessages.setProperty(k, "apiMsgId", cm.msgId || cm.id);
                break;
            }
        }
    }
}
