/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Native Google Gemini adapter (POST /v1beta/models/{model}:streamGenerateContent
// ?alt=sse, GET /v1beta/models). Translates the host's OpenAI-shaped neutral
// form to/from Gemini wire format:
//   - System messages -> top-level systemInstruction.
//   - role:"user" -> role:"user", role:"assistant" -> role:"model".
//   - Assistant tool_calls -> parts:[{functionCall:{name, args}}].
//   - role:"tool" -> role:"user" with parts:[{functionResponse:{name, response}}].
//     Gemini correlates calls and responses by name only (no IDs), so we look
//     up the originating tool_call's name via tool_call_id.
//   - SSE chunks: each is a partial GenerateContentResponse. text parts append
//     to accumulated text; functionCall parts become OpenAI-shaped tool_calls
//     with synthesized ids ("call_<n>") so main.qml's dispatch is unchanged.

var id = "gemini";
var displayName = "Google Gemini";

var presets = [
    { name: "Google Gemini (native)", url: "https://generativelanguage.googleapis.com" }
];

// Gemini uses thinkingBudget directly and ignores the effort dropdown, so the
// effort field is hidden. Provider preset dropdown is hidden — only one
// endpoint exists — but the endpoint field is kept editable for proxies.
var capabilities = {
    providerPresets: false,
    customEndpoint: true,
    reasoningEffort: false,
    thinkingBudget: true,
    fetchModels: true,
    reasoningHelp: i18n("Gemini uses the thinking token budget directly. Set to 0 to disable thinking on supported models.")
};

function setHeaders(xhr, apiKey) {
    xhr.setRequestHeader("Content-Type", "application/json");
    if (apiKey && apiKey.length > 0) {
        xhr.setRequestHeader("x-goog-api-key", apiKey);
    }
}

function fetchModels(endpoint, apiKey, callback) {
    var xhr = new XMLHttpRequest();
    var url = endpoint.replace(/\/+$/, "") + "/v1beta/models?pageSize=1000";

    xhr.open("GET", url);
    xhr.timeout = 30000;
    setHeaders(xhr, apiKey);

    xhr.ontimeout = function() {
        callback(i18n("Request timed out after 30 seconds"), null);
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    var models = [];
                    if (response.models) {
                        for (var i = 0; i < response.models.length; i++) {
                            var m = response.models[i];
                            var methods = m.supportedGenerationMethods || [];
                            if (methods.indexOf("generateContent") === -1) continue;
                            var name = m.name || "";
                            if (name.indexOf("models/") === 0) name = name.substring(7);
                            models.push(name);
                        }
                    }
                    callback(null, models);
                } catch (e) {
                    callback(i18n("Failed to parse models: %1", e.message), null);
                }
            } else {
                callback(formatGeminiError(xhr, i18n("Failed to fetch models")), null);
            }
        }
    };

    xhr.send();
}

// Google returns 400 INVALID_ARGUMENT for invalid API keys (not 401/403), so
// surface the real error message from the body instead of just the HTTP code.
function formatGeminiError(xhr, prefix) {
    var detail = "";
    try {
        var body = JSON.parse(xhr.responseText);
        if (body && body.error && body.error.message) {
            detail = body.error.message;
        }
    } catch (e) {
        if (xhr.responseText) detail = xhr.responseText.substring(0, 200);
    }
    if (xhr.status === 400 && detail.toLowerCase().indexOf("api key") !== -1) {
        return i18n("Authentication failed — check your API key (HTTP 400): %1", detail);
    }
    if (xhr.status === 401 || xhr.status === 403) {
        return i18n("Authentication failed (HTTP %1) — check your API key: %2", xhr.status, detail);
    }
    if (xhr.status > 0) {
        return prefix + " (HTTP " + xhr.status + ")" + (detail ? ": " + detail : "");
    }
    return prefix + ": " + i18n("no response — check your endpoint URL");
}

function buildTools(options) {
    var fns = [];
    var ollamaApiKey = options && options.ollamaApiKey;
    var commandToolEnabled = options && options.commandToolEnabled;

    if (ollamaApiKey && ollamaApiKey.length > 0) {
        fns.push({
            name: "web_search",
            description: "Search the web for current information. Use when you need up-to-date facts, recent events, or information you're not confident about.",
            parameters: {
                type: "object",
                properties: {
                    query: { type: "string", description: "Search query" },
                    max_results: { type: "integer", description: "Max results (1-10, default 5)" }
                },
                required: ["query"]
            }
        });
    }

    if (commandToolEnabled) {
        fns.push({
            name: "run_command",
            description: "Execute a shell command on the user's system and return its output. Use this to run commands when the user asks you to perform system tasks.",
            parameters: {
                type: "object",
                properties: {
                    command: { type: "string", description: "The shell command to execute" }
                },
                required: ["command"]
            }
        });
    }

    if (fns.length === 0) return [];
    return [{ functionDeclarations: fns }];
}

// buildContentArray: returns a Gemini parts array (or text string when there
// are no attachments, since translateMessages also accepts string content).
function buildContentArray(text, attachments) {
    if (!attachments || attachments.length === 0) return text;
    var parts = [];
    if (text && text.length > 0) {
        parts.push({ text: text });
    }
    for (var i = 0; i < attachments.length; i++) {
        var att = attachments[i];
        if (att.dataUrl) {
            var m = /^data:([^;]+);base64,(.*)$/.exec(att.dataUrl);
            if (m) {
                parts.push({ inlineData: { mimeType: m[1], data: m[2] } });
            }
        } else if (att.textContent) {
            var label = att.fileName || "file";
            parts.push({ text: "--- " + label + " ---\n" + att.textContent });
        }
    }
    return parts;
}

// Convert a neutral message's content (string OR array-of-parts as produced
// by buildContentArray) into a Gemini parts array.
function toParts(content) {
    if (typeof content === "string") {
        return [{ text: content }];
    }
    if (Array.isArray(content)) {
        // Already Gemini-shaped (came from buildContentArray)
        return content;
    }
    return [{ text: "" }];
}

// Build an id->name map for tool_call_id lookups when translating tool messages.
function buildToolCallIdMap(neutralMessages) {
    var map = {};
    for (var i = 0; i < neutralMessages.length; i++) {
        var m = neutralMessages[i];
        if (m.role === "assistant" && m.tool_calls) {
            for (var t = 0; t < m.tool_calls.length; t++) {
                var tc = m.tool_calls[t];
                if (tc.id && tc["function"] && tc["function"].name) {
                    map[tc.id] = tc["function"].name;
                }
            }
        }
    }
    return map;
}

function translateMessages(neutralMessages) {
    var systemText = "";
    var contents = [];
    var idToName = buildToolCallIdMap(neutralMessages);

    for (var i = 0; i < neutralMessages.length; i++) {
        var m = neutralMessages[i];

        if (m.role === "system") {
            if (typeof m.content === "string") {
                systemText += (systemText.length > 0 ? "\n\n" : "") + m.content;
            }
            continue;
        }

        if (m.role === "tool") {
            var fnName = idToName[m.tool_call_id] || "";
            var raw = typeof m.content === "string" ? m.content : "";
            var responsePart = {
                functionResponse: {
                    name: fnName,
                    response: { result: raw }
                }
            };
            var prev = contents.length > 0 ? contents[contents.length - 1] : null;
            if (prev && prev.role === "user") {
                prev.parts.push(responsePart);
            } else {
                contents.push({ role: "user", parts: [responsePart] });
            }
            continue;
        }

        if (m.role === "assistant") {
            var parts = [];
            // Prepend captured thinking parts (with thoughtSignatures) so the
            // model can continue its chain of thought across turns.
            if (m.thinkingBlocks && m.thinkingBlocks.length > 0) {
                for (var th = 0; th < m.thinkingBlocks.length; th++) {
                    var tb = m.thinkingBlocks[th];
                    if (!tb || typeof tb.thinking !== "string") continue;
                    var thoughtPart = { text: tb.thinking, thought: true };
                    if (tb.thoughtSignature) thoughtPart.thoughtSignature = tb.thoughtSignature;
                    parts.push(thoughtPart);
                }
            }
            if (m.content && typeof m.content === "string" && m.content.length > 0) {
                parts.push({ text: m.content });
            }
            if (m.tool_calls && m.tool_calls.length > 0) {
                for (var t = 0; t < m.tool_calls.length; t++) {
                    var tc = m.tool_calls[t];
                    var rawArgs = tc["function"] && tc["function"]["arguments"];
                    var args = {};
                    if (typeof rawArgs === "string" && rawArgs.length > 0) {
                        try { args = JSON.parse(rawArgs); } catch (e) { args = {}; }
                    } else if (rawArgs && typeof rawArgs === "object") {
                        args = rawArgs;
                    }
                    parts.push({
                        functionCall: {
                            name: (tc["function"] && tc["function"].name) || "",
                            args: args
                        }
                    });
                }
            }
            if (parts.length === 0) parts.push({ text: "" });
            contents.push({ role: "model", parts: parts });
            continue;
        }

        if (m.role === "user") {
            contents.push({ role: "user", parts: toParts(m.content) });
            continue;
        }
    }

    return { systemText: systemText, contents: contents };
}

// Parse Gemini SSE buffer. Each event is a single "data: <json>" line
// containing a partial GenerateContentResponse. There is no [DONE] sentinel;
// the connection close marks the end of the stream.
function parseSSEChunks(buffer, lastIndex) {
    var tokens = [];
    var searchFrom = lastIndex;
    while (true) {
        var nlPos = buffer.indexOf("\n", searchFrom);
        if (nlPos === -1) break;
        var line = buffer.substring(searchFrom, nlPos).replace(/\r$/, "");
        searchFrom = nlPos + 1;
        if (line === "") continue;
        if (line.substring(0, 6) !== "data: ") continue;
        var payload = line.substring(6);
        try {
            var obj = JSON.parse(payload);
            if (obj.candidates && obj.candidates[0] && obj.candidates[0].content) {
                var partsArr = obj.candidates[0].content.parts || [];
                for (var p = 0; p < partsArr.length; p++) {
                    var part = partsArr[p];
                    if (part.thought === true) {
                        // Thought parts may stream incrementally with partial
                        // text across multiple events. The thoughtSignature
                        // typically appears on the final part in the thought
                        // span; capture it whenever present.
                        var tt = typeof part.text === "string" ? part.text : "";
                        tokens.push({
                            thinking_delta: {
                                text: tt,
                                signature: part.thoughtSignature || ""
                            }
                        });
                    } else {
                        if (typeof part.text === "string" && part.text.length > 0) {
                            tokens.push({ content: part.text });
                        }
                        if (part.functionCall) {
                            tokens.push({
                                function_call: {
                                    name: part.functionCall.name || "",
                                    args: part.functionCall.args || {}
                                }
                            });
                        }
                        // A non-thought part may carry a thoughtSignature for
                        // the preceding thought span; surface it so the
                        // accumulator can attach it to the open block.
                        if (part.thoughtSignature) {
                            tokens.push({
                                thinking_signature: { signature: part.thoughtSignature }
                            });
                        }
                        // Closing the thought span when a non-thought part
                        // arrives lets multiple thought→action sequences in
                        // one turn become separate blocks.
                        tokens.push({ thinking_close: true });
                    }
                }
            }
            if (obj.error) {
                tokens.push({ error: (obj.error && obj.error.message) || "stream error" });
            }
        } catch (e) {
            // skip unparseable chunks
        }
    }
    return { tokens: tokens, newIndex: searchFrom };
}

function sendStreaming(opts) {
    var endpoint = opts.endpoint;
    var apiKey = opts.apiKey;
    var model = opts.model;
    var temperature = opts.temperature;
    var maxTokens = opts.maxTokens;
    var tools = opts.tools;
    var onChunk = opts.onChunk;
    var onThinkingChunk = opts.onThinkingChunk;
    var onComplete = opts.onComplete;

    var translated = translateMessages(opts.messages);

    var xhr = new XMLHttpRequest();
    var url = endpoint.replace(/\/+$/, "") +
              "/v1beta/models/" + encodeURIComponent(model) +
              ":streamGenerateContent?alt=sse";

    xhr.open("POST", url);
    xhr.timeout = 120000;
    setHeaders(xhr, apiKey);

    var pollTimer = null;
    var lastParseIndex = 0;
    var accumulatedText = "";
    var accumulatedToolCalls = [];
    var thinkingBlocks = [];
    var currentThinkingBlock = null;
    var accumulatedThinkingText = "";
    var streamError = null;
    var completeCalled = false;

    function processBuffer() {
        var result = parseSSEChunks(xhr.responseText, lastParseIndex);
        lastParseIndex = result.newIndex;
        for (var i = 0; i < result.tokens.length; i++) {
            var tok = result.tokens[i];
            if (tok.error) { streamError = tok.error; continue; }
            if (tok.content) {
                accumulatedText += tok.content;
                onChunk(tok.content, accumulatedText);
            }
            if (tok.function_call) {
                var fc = tok.function_call;
                // Synthesize an OpenAI-shaped id so main.qml's tool dispatch
                // (which keys on tool_call_id) keeps working.
                accumulatedToolCalls.push({
                    id: "call_" + accumulatedToolCalls.length,
                    type: "function",
                    "function": {
                        name: fc.name,
                        arguments: JSON.stringify(fc.args)
                    }
                });
            }
            if (tok.thinking_delta) {
                if (!currentThinkingBlock) {
                    currentThinkingBlock = { type: "thinking", thinking: "", thoughtSignature: "" };
                    thinkingBlocks.push(currentThinkingBlock);
                }
                if (tok.thinking_delta.text) {
                    currentThinkingBlock.thinking += tok.thinking_delta.text;
                    accumulatedThinkingText += tok.thinking_delta.text;
                    if (onThinkingChunk) onThinkingChunk(tok.thinking_delta.text, accumulatedThinkingText);
                }
                if (tok.thinking_delta.signature) {
                    currentThinkingBlock.thoughtSignature = tok.thinking_delta.signature;
                }
            }
            if (tok.thinking_signature && currentThinkingBlock) {
                currentThinkingBlock.thoughtSignature = tok.thinking_signature.signature;
            }
            if (tok.thinking_close) {
                currentThinkingBlock = null;
            }
        }
    }

    function collectThinkingBlocks() {
        var out = [];
        for (var i = 0; i < thinkingBlocks.length; i++) {
            var b = thinkingBlocks[i];
            if (b && b.thinking && b.thinking.length > 0) out.push(b);
        }
        return out;
    }

    function finish(error) {
        if (completeCalled) return;
        completeCalled = true;
        if (pollTimer && pollTimer.running) pollTimer.stop();

        var collectedThinking = collectThinkingBlocks();

        if (error) {
            onComplete(accumulatedText, error, null, null);
        } else if (accumulatedToolCalls.length > 0) {
            var assistantMsg = { role: "assistant", content: accumulatedText || null, tool_calls: accumulatedToolCalls, thinkingBlocks: collectedThinking };
            onComplete(accumulatedText, null, accumulatedToolCalls, assistantMsg);
        } else if (accumulatedText.length > 0 || collectedThinking.length > 0) {
            onComplete(accumulatedText, null, null, { role: "assistant", content: accumulatedText, thinkingBlocks: collectedThinking });
        } else {
            // Non-streaming fallback: parse a single GenerateContentResponse
            try {
                var response = JSON.parse(xhr.responseText);
                var text = "";
                var calls = [];
                var thinks = [];
                var openThink = null;
                if (response.candidates && response.candidates[0] && response.candidates[0].content) {
                    var partsArr = response.candidates[0].content.parts || [];
                    for (var i = 0; i < partsArr.length; i++) {
                        var part = partsArr[i];
                        if (part.thought === true) {
                            if (!openThink) {
                                openThink = { type: "thinking", thinking: "", thoughtSignature: "" };
                                thinks.push(openThink);
                            }
                            if (typeof part.text === "string") openThink.thinking += part.text;
                            if (part.thoughtSignature) openThink.thoughtSignature = part.thoughtSignature;
                        } else {
                            if (typeof part.text === "string") text += part.text;
                            else if (part.functionCall) {
                                calls.push({
                                    id: "call_" + calls.length,
                                    type: "function",
                                    "function": {
                                        name: part.functionCall.name || "",
                                        arguments: JSON.stringify(part.functionCall.args || {})
                                    }
                                });
                            }
                            if (openThink && part.thoughtSignature) openThink.thoughtSignature = part.thoughtSignature;
                            openThink = null;
                        }
                    }
                }
                if (calls.length > 0) {
                    onComplete(text, null, calls, { role: "assistant", content: text || null, tool_calls: calls, thinkingBlocks: thinks });
                } else if (text.length > 0 || thinks.length > 0) {
                    onComplete(text, null, null, { role: "assistant", content: text, thinkingBlocks: thinks });
                } else {
                    onComplete("", i18n("Invalid response format"));
                }
            } catch (e) {
                onComplete("", i18n("Failed to parse response: %1", e.message));
            }
        }
    }

    xhr.ontimeout = function() {
        finish(i18n("Request timed out"));
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 3) {
            if (pollTimer && !pollTimer.running) pollTimer.start();
            processBuffer();
        } else if (xhr.readyState === 4) {
            if (pollTimer && pollTimer.running) pollTimer.stop();
            if (xhr.status === 200) {
                processBuffer();
                finish(streamError);
            } else {
                finish(formatGeminiError(xhr, i18n("Request failed")));
            }
        }
    };

    var body = {
        contents: translated.contents,
        generationConfig: {
            temperature: temperature / 100.0,
            maxOutputTokens: maxTokens
        }
    };
    // Gemini uses the thinking budget directly; setting it to 0 explicitly
    // disables auto-thinking on 2.5-class models.
    body.generationConfig.thinkingConfig = { thinkingBudget: opts.thinkingBudget || 0 };
    if (translated.systemText && translated.systemText.length > 0) {
        body.systemInstruction = { parts: [{ text: translated.systemText }] };
    }
    if (tools && tools.length > 0) {
        body.tools = tools;
    }

    xhr.send(JSON.stringify(body, null, 2));

    var handle = {
        xhr: xhr,
        pollTimer: null,
        processBuffer: processBuffer,
        setPollTimer: function(timer) {
            pollTimer = timer;
            handle.pollTimer = timer;
        }
    };
    return handle;
}
