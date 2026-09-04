/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

.import "api.js" as Api

function providerPresets() {
    return [
        { name: "OpenRouter", url: "https://openrouter.ai/api/v1" },
        { name: "Groq",       url: "https://api.groq.com/openai/v1" },
        { name: "Ollama",     url: "http://localhost:11434/v1" },
        { name: "OpenAI",     url: "https://api.openai.com/v1" },
        { name: "Gemini",     url: "https://generativelanguage.googleapis.com/v1beta/openai" },
        { name: "Custom",     url: "" }
    ];
}

/**
 * Calculates character count and finds candidate compaction slice
 * keeping the last `keepRecentTurns` full turns uncompacted.
 *
 * @param {ListModel} chatMessages - The API messages ListModel
 * @param {string} lastCompactedMsgId - The last msgId that was already compacted
 * @param {number} keepRecentTurns - Number of recent user turns to keep uncompacted
 * @returns {object|null} { startIndex, endIndex, totalChars, startMsgId, endMsgId }
 */
function findCompactionRange(chatMessages, lastCompactedMsgId, keepRecentTurns) {
    if (!chatMessages || chatMessages.count <= 1) return null;

    var recentTurns = Math.max(1, keepRecentTurns || 4);

    // 1. Find the start index (first message after lastCompactedMsgId)
    var startIndex = 1; // index 0 is system prompt
    if (lastCompactedMsgId && String(lastCompactedMsgId).length > 0) {
        for (var i = 1; i < chatMessages.count; i++) {
            var m = chatMessages.get(i);
            var mid = m.msgId || m.id;
            if (mid === lastCompactedMsgId || String(i) === String(lastCompactedMsgId) || ("msg_" + i) === String(lastCompactedMsgId)) {
                startIndex = i + 1;
                break;
            }
        }
    }

    if (startIndex >= chatMessages.count) return null;

    // 2. Identify the boundary of the last `keepRecentTurns` user turns
    var userTurnIndices = [];
    for (var j = 1; j < chatMessages.count; j++) {
        if (chatMessages.get(j).role === "user") {
            userTurnIndices.push(j);
        }
    }

    var endIndex = -1;
    if (userTurnIndices.length > recentTurns) {
        var keepFromTurnIndex = userTurnIndices[userTurnIndices.length - recentTurns];
        endIndex = keepFromTurnIndex - 1;
    } else {
        // Not enough interactive turns to compact older ones
        return null;
    }

    if (endIndex < startIndex) return null;

    // 3. Calculate total character count and candidate turn count across the range
    var totalChars = 0;
    var candidateTurns = 0;
    for (var k = startIndex; k <= endIndex; k++) {
        var msg = chatMessages.get(k);
        if (msg && msg.role === "user") candidateTurns++;
        if (msg && msg.content) totalChars += String(msg.content).length;
        if (msg && msg.tool_calls_json) totalChars += String(msg.tool_calls_json).length;
        if (msg && msg.attachments_json) totalChars += String(msg.attachments_json).length;
    }

    return {
        startIndex: startIndex,
        endIndex: endIndex,
        totalChars: totalChars,
        candidateTurns: candidateTurns,
        startMsgId: String(startIndex),
        endMsgId: String(endIndex)
    };
}

/**
 * Formats a slice of chatMessages into a plain-text transcript with explicit message IDs.
 */
function formatTranscript(messagesList, startIndex, endIndex) {
    var lines = [];
    for (var i = startIndex; i <= endIndex && i < messagesList.count; i++) {
        var m = messagesList.get(i);
        if (!m || m.role === "system") continue;

        var time = m.timestamp_api || "";
        var header = "[" + i + "] Role: " + m.role + (time ? " (" + time + ")" : "");
        lines.push(header);

        if (m.role === "tool") {
            if (m.tool_call_id) {
                lines.push("Tool Call ID: " + m.tool_call_id);
            }
            lines.push("Output:\n" + (m.content || ""));
        } else {
            if (m.attachments_json && m.attachments_json.length > 0) {
                try {
                    var atts = JSON.parse(m.attachments_json);
                    if (atts.length > 0) {
                        lines.push("Attachments:");
                        for (var a = 0; a < atts.length; a++) {
                            var fn = atts[a].fileName || atts[a].filePath || "file";
                            lines.push("  - " + fn);
                        }
                    }
                } catch(e) {}
            }
            if (m.tool_calls_json && m.tool_calls_json.length > 0) {
                try {
                    var calls = JSON.parse(m.tool_calls_json);
                    lines.push("Tool Calls:");
                    for (var c = 0; c < calls.length; c++) {
                        var fn = calls[c]["function"] || {};
                        lines.push("  - " + fn.name + "(" + (fn.arguments || "") + ")");
                    }
                } catch(e) {}
            }
            if (m.content && m.content.length > 0) {
                lines.push("Content:\n" + m.content);
            }
        }
        lines.push("");
    }
    return lines.join("\n");
}

/**
 * Asynchronously performs compaction using PlasmaLLM's adapter system.
 *
 * @param {object} opts
 * @param {string} [opts.apiType="openai"]
 * @param {string} opts.endpoint
 * @param {string} opts.apiKey
 * @param {string} opts.model
 * @param {string} opts.transcript
 * @param {string} [opts.previousSummary]
 * @param {string} [opts.instructions]
 * @param {string} [opts.geminiAuthMethod]
 * @param {string} [opts.geminiProjectId]
 * @param {string} [opts.geminiLocation]
 * @param {string} [opts.geminiVertexAuthType]
 * @param {boolean} [opts.usesResponsesAPI]
 * @param {function} callback - function(err, summaryText)
 */
function compactHistory(opts, callback) {
    if (!opts || !opts.endpoint || !opts.model) {
        if (callback) callback("Compaction endpoint and model name are required", null);
        return;
    }

    var apiType = opts.apiType || "openai";
    var endpoint = opts.endpoint;
    var apiKey = opts.apiKey || "";
    var model = opts.model;
    var transcript = opts.transcript || "";
    var previousSummary = opts.previousSummary || "";
    var instructions = opts.instructions || (
        "Summarize this conversation. Be very concise and use shorthand and abbreviations when possible. No prose. Retain important specifics when brief. For larger specifics like logs, use of restore_context/recall_attachment tool will work instead. Cite every item with a msgId or msgId range, e.g. [1], [3-6], [2,7-10]\n\n" +
        "When a previous compaction exists, use it as a starting point. Be conservative about removing things; update and merge new information rather than discarding established context unless subsequent messages prove it entirely out of scope. Always persist all attached files across compaction cycles.\n\n" +
        "Structure:\n# Key Topics\n<...>\n# User Goals\n<...>\n# Agent Goals\n<...>\n# Decisions\n<...>\n# Current Status\n<...>\n# Attachments\n- example.txt - brief description of its contents [msgId]"
    );

    var userPrompt = "";
    if (previousSummary && previousSummary.trim().length > 0) {
        userPrompt += "## Previous Compacted Summary:\n" + previousSummary.trim() + "\n\n";
    }
    userPrompt += "## Conversation Transcript to Compact:\n" + transcript + "\n\n";
    userPrompt += "Produce the updated compact summary with message ID citations:";

    var messages = [
        { role: "system", content: instructions },
        { role: "user", content: userPrompt }
    ];

    try {
        Api.sendStreaming(apiType, {
            endpoint: endpoint,
            apiKey: apiKey,
            sessionId: opts.sessionId,
            model: model,
            messages: messages,
            temperature: 0.2,
            maxTokens: 2048,
            geminiApiVariant: opts.geminiApiVariant,
            geminiAuthMethod: opts.geminiAuthMethod,
            geminiProjectId: opts.geminiProjectId,
            geminiLocation: opts.geminiLocation,
            geminiVertexAuthType: opts.geminiVertexAuthType,
            usesResponsesAPI: opts.usesResponsesAPI,
            providerName: opts.providerName,
            onChunk: function(chunk) {},
            onThinkingChunk: function(chunk) {},
            onComplete: function(fullText, error, toolCalls, assistantMsg) {
                if (error) {
                    if (callback) callback(error, null);
                } else {
                    if (callback) callback(null, (fullText || "").trim());
                }
            }
        });
    } catch (e) {
        if (callback) callback("Context compaction invocation error: " + e.toString(), null);
    }
}
