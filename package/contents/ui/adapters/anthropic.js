/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Native Anthropic Messages API adapter (POST /v1/messages, GET /v1/models).
// Translates the host's OpenAI-shaped neutral form to/from Anthropic wire
// format:
//   - Lifts the first {role:"system"} message into the top-level `system` field.
//   - Translates assistant tool_calls -> content array with {type:"tool_use"}.
//   - Translates {role:"tool", tool_call_id, content} -> {role:"user",
//     content:[{type:"tool_result", tool_use_id, content}]}.
//   - Streaming SSE: parses event/data line pairs; text_delta -> content chunk;
//     input_json_delta -> accumulated tool-call arguments. On message_stop,
//     reports an OpenAI-shaped tool_calls array so main.qml's existing handler
//     keeps working unchanged.

var id = "anthropic";
var displayName = "Anthropic";
var ANTHROPIC_VERSION = "2023-06-01";

var presets = [
    { name: "Anthropic", url: "https://api.anthropic.com" }
];

// Anthropic has a single endpoint, so the provider preset dropdown is hidden;
// the endpoint field stays visible for proxies. Both reasoning effort and
// thinking budget are meaningful: the effort gates whether thinking is on,
// the budget controls the token allowance.
var capabilities = {
    providerPresets: false,
    customEndpoint: true,
    reasoningEffort: true,
    thinkingBudget: true,
    fetchModels: true,
    reasoningHelp: i18n("Anthropic enables extended thinking when effort is not Off, using the token budget below. Temperature is forced to max while thinking.")
};

function setHeaders(xhr, apiKey) {
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("anthropic-version", ANTHROPIC_VERSION);
    // Required when the API is called from a browser-like UA. QML XHR uses
    // Qt's network stack, but Anthropic's edge inspects the header server-side.
    xhr.setRequestHeader("anthropic-dangerous-direct-browser-access", "true");
    if (apiKey && apiKey.length > 0) {
        xhr.setRequestHeader("x-api-key", apiKey);
    }
}

function fetchModels(endpoint, apiKey, callback) {
    var xhr = new XMLHttpRequest();
    var url = endpoint.replace(/\/+$/, "") + "/v1/models";

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
                    if (response.data) {
                        for (var i = 0; i < response.data.length; i++) {
                            models.push(response.data[i].id);
                        }
                    }
                    callback(null, models);
                } catch (e) {
                    callback(i18n("Failed to parse models: %1", e.message), null);
                }
            } else {
                callback(i18n("Failed to fetch models: HTTP %1", xhr.status), null);
            }
        }
    };

    xhr.send();
}

function buildTools(options) {
    var tools = [];
    var commandToolEnabled = options && options.commandToolEnabled;
    var webSearchEnabled = options && options.webSearchEnabled;
    var searchConfigured = options && options.searchConfigured;

    if (webSearchEnabled && searchConfigured) {
        tools.push({
            name: "web_search",
            description: "Search the web for current information. Use when you need up-to-date facts, recent events, or information you're not confident about.",
            input_schema: {
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
        tools.push({
            name: "run_command",
            description: "Execute a shell command on the user's system and return its output. Use this to run commands when the user asks you to perform system tasks.",
            input_schema: {
                type: "object",
                properties: {
                    command: { type: "string", description: "The shell command to execute" }
                },
                required: ["command"]
            }
        });
    }

    return tools;
}

function isImageMime(mime) {
    return mime && mime.indexOf("image/") === 0;
}

// Builds Anthropic-shaped content array from neutral (text + attachments).
// Returns string when no attachments, otherwise array of content blocks.
function buildContentArray(text, attachments) {
    if (!attachments || attachments.length === 0) return text;
    var parts = [];
    if (text && text.length > 0) {
        parts.push({ type: "text", text: text });
    }
    for (var i = 0; i < attachments.length; i++) {
        var att = attachments[i];
        if (att.dataUrl) {
            // dataUrl shape: "data:image/png;base64,XXXX"
            var m = /^data:([^;]+);base64,(.*)$/.exec(att.dataUrl);
            if (m && isImageMime(m[1])) {
                parts.push({
                    type: "image",
                    source: { type: "base64", media_type: m[1], data: m[2] }
                });
            }
        } else if (att.textContent) {
            var label = att.fileName || "file";
            parts.push({ type: "text", text: "--- " + label + " ---\n" + att.textContent });
        }
    }
    return parts;
}

// Translate the host's OpenAI-shaped messages array into Anthropic's
// {system, messages} form.
function translateMessages(neutralMessages) {
    var systemText = "";
    var out = [];

    // Map of OpenAI assistant tool_calls indexes to assistant message position
    // so we can pair tool messages back into user content.
    for (var i = 0; i < neutralMessages.length; i++) {
        var m = neutralMessages[i];

        if (m.role === "system") {
            // Concatenate all system messages (rare but possible)
            if (typeof m.content === "string") {
                systemText += (systemText.length > 0 ? "\n\n" : "") + m.content;
            }
            continue;
        }

        if (m.role === "tool") {
            // Convert into a user message with a tool_result content block.
            // Coalesce with the previous user message if it already exists with
            // content blocks (Anthropic merges consecutive same-role turns).
            var resultBlock = {
                type: "tool_result",
                tool_use_id: m.tool_call_id || "",
                content: typeof m.content === "string" ? m.content : (m.content || "")
            };
            var prev = out.length > 0 ? out[out.length - 1] : null;
            if (prev && prev.role === "user" && Array.isArray(prev.content)) {
                prev.content.push(resultBlock);
            } else {
                out.push({ role: "user", content: [resultBlock] });
            }
            continue;
        }

        if (m.role === "assistant") {
            var hasThinking = m.thinkingBlocks && m.thinkingBlocks.length > 0;
            var hasToolCalls = m.tool_calls && m.tool_calls.length > 0;
            // Extended-thinking-with-tool-use requires re-sending the original
            // signed thinking blocks before the tool_use block in the same turn.
            // Switch to the array-content shape whenever thinking blocks exist.
            if (hasToolCalls || hasThinking) {
                var blocks = [];
                if (hasThinking) {
                    for (var th = 0; th < m.thinkingBlocks.length; th++) {
                        var tb = m.thinkingBlocks[th];
                        if (tb && typeof tb.thinking === "string") {
                            blocks.push({
                                type: "thinking",
                                thinking: tb.thinking,
                                signature: tb.signature || ""
                            });
                        }
                    }
                }
                if (m.content && typeof m.content === "string" && m.content.length > 0) {
                    blocks.push({ type: "text", text: m.content });
                }
                if (hasToolCalls) {
                    for (var t = 0; t < m.tool_calls.length; t++) {
                        var tc = m.tool_calls[t];
                        var rawArgs = tc["function"] && tc["function"]["arguments"];
                        var input = {};
                        if (typeof rawArgs === "string" && rawArgs.length > 0) {
                            try { input = JSON.parse(rawArgs); } catch (e) { input = {}; }
                        } else if (rawArgs && typeof rawArgs === "object") {
                            input = rawArgs;
                        }
                        blocks.push({
                            type: "tool_use",
                            id: tc.id || "",
                            name: (tc["function"] && tc["function"].name) || "",
                            input: input
                        });
                    }
                }
                out.push({ role: "assistant", content: blocks });
            } else {
                out.push({ role: "assistant", content: m.content });
            }
            continue;
        }

        if (m.role === "user") {
            out.push({ role: "user", content: m.content });
            continue;
        }
    }

    return { system: systemText, messages: out };
}

// Parse Anthropic SSE buffer. Anthropic frames each event as:
//   event: <name>\n
//   data: <json>\n
//   \n
// We only care about content_block_start / content_block_delta /
// content_block_stop / message_stop / error. Returns neutral tokens consumed
// by sendStreaming below.
function parseSSEChunks(buffer, lastIndex) {
    var tokens = [];
    var searchFrom = lastIndex;
    while (true) {
        var nlPos = buffer.indexOf("\n", searchFrom);
        if (nlPos === -1) break;
        var line = buffer.substring(searchFrom, nlPos).replace(/\r$/, "");
        searchFrom = nlPos + 1;
        if (line === "") continue;
        if (line.substring(0, 6) !== "data: ") continue; // ignore "event:" preface lines
        var payload = line.substring(6);
        try {
            var obj = JSON.parse(payload);
            switch (obj.type) {
            case "content_block_start":
                if (obj.content_block && obj.content_block.type === "tool_use") {
                    tokens.push({
                        tool_use_start: {
                            index: obj.index,
                            id: obj.content_block.id || "",
                            name: obj.content_block.name || ""
                        }
                    });
                } else if (obj.content_block && obj.content_block.type === "thinking") {
                    tokens.push({ thinking_start: { index: obj.index } });
                }
                break;
            case "content_block_delta":
                if (obj.delta) {
                    if (obj.delta.type === "text_delta" && typeof obj.delta.text === "string") {
                        tokens.push({ content: obj.delta.text });
                    } else if (obj.delta.type === "input_json_delta" && typeof obj.delta.partial_json === "string") {
                        tokens.push({
                            tool_input_delta: { index: obj.index, partial_json: obj.delta.partial_json }
                        });
                    } else if (obj.delta.type === "thinking_delta" && typeof obj.delta.thinking === "string") {
                        tokens.push({
                            thinking_delta: { index: obj.index, text: obj.delta.thinking }
                        });
                    } else if (obj.delta.type === "signature_delta" && typeof obj.delta.signature === "string") {
                        tokens.push({
                            thinking_signature: { index: obj.index, signature: obj.delta.signature }
                        });
                    }
                }
                break;
            case "message_stop":
                tokens.push({ done: true });
                break;
            case "error":
                tokens.push({ error: obj.error && obj.error.message ? obj.error.message : "stream error" });
                break;
            default:
                break;
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
    var url = endpoint.replace(/\/+$/, "") + "/v1/messages";

    xhr.open("POST", url);
    xhr.timeout = 120000;
    setHeaders(xhr, apiKey);

    var pollTimer = null;
    var lastParseIndex = 0;
    var accumulatedText = "";
    // Map of content-block index -> entry in accumulatedToolCalls (OpenAI shape)
    var toolCallsByIndex = {};
    var accumulatedToolCalls = [];
    // Per-index thinking blocks; ordered list preserves block order within turn.
    var thinkingBlocksByIndex = {};
    var thinkingBlockOrder = [];
    var accumulatedThinkingText = "";
    var streamDone = false;
    var completeCalled = false;
    var streamError = null;

    function processBuffer() {
        if (streamDone) return;
        var result = parseSSEChunks(xhr.responseText, lastParseIndex);
        lastParseIndex = result.newIndex;
        for (var i = 0; i < result.tokens.length; i++) {
            var tok = result.tokens[i];
            if (tok.done) { streamDone = true; return; }
            if (tok.error) { streamError = tok.error; streamDone = true; return; }
            if (tok.content) {
                accumulatedText += tok.content;
                onChunk(tok.content, accumulatedText);
            }
            if (tok.tool_use_start) {
                var s = tok.tool_use_start;
                var entry = {
                    id: s.id,
                    type: "function",
                    "function": { name: s.name, arguments: "" }
                };
                accumulatedToolCalls.push(entry);
                toolCallsByIndex[s.index] = entry;
            }
            if (tok.tool_input_delta) {
                var d = tok.tool_input_delta;
                var target = toolCallsByIndex[d.index];
                if (target) {
                    target["function"]["arguments"] += d.partial_json;
                }
            }
            if (tok.thinking_start) {
                var ts = tok.thinking_start;
                if (!thinkingBlocksByIndex[ts.index]) {
                    var block = { type: "thinking", thinking: "", signature: "" };
                    thinkingBlocksByIndex[ts.index] = block;
                    thinkingBlockOrder.push(ts.index);
                }
            }
            if (tok.thinking_delta) {
                var td = tok.thinking_delta;
                var tBlock = thinkingBlocksByIndex[td.index];
                if (!tBlock) {
                    tBlock = { type: "thinking", thinking: "", signature: "" };
                    thinkingBlocksByIndex[td.index] = tBlock;
                    thinkingBlockOrder.push(td.index);
                }
                tBlock.thinking += td.text;
                accumulatedThinkingText += td.text;
                if (onThinkingChunk) onThinkingChunk(td.text, accumulatedThinkingText);
            }
            if (tok.thinking_signature) {
                var tss = tok.thinking_signature;
                var sBlock = thinkingBlocksByIndex[tss.index];
                if (sBlock) sBlock.signature = tss.signature;
            }
        }
    }

    function collectThinkingBlocks() {
        var out = [];
        for (var i = 0; i < thinkingBlockOrder.length; i++) {
            var b = thinkingBlocksByIndex[thinkingBlockOrder[i]];
            if (b && b.thinking && b.thinking.length > 0) out.push(b);
        }
        return out;
    }

    function finish(error) {
        if (completeCalled) return;
        completeCalled = true;
        if (pollTimer && pollTimer.running) pollTimer.stop();

        var thinkingBlocks = collectThinkingBlocks();

        if (error) {
            onComplete(accumulatedText, error, null, null);
        } else if (accumulatedToolCalls.length > 0) {
            var assistantMsg = { role: "assistant", content: accumulatedText || null, tool_calls: accumulatedToolCalls, thinkingBlocks: thinkingBlocks };
            onComplete(accumulatedText, null, accumulatedToolCalls, assistantMsg);
        } else if (accumulatedText.length > 0 || thinkingBlocks.length > 0) {
            onComplete(accumulatedText, null, null, { role: "assistant", content: accumulatedText, thinkingBlocks: thinkingBlocks });
        } else {
            // Non-streaming fallback
            try {
                var response = JSON.parse(xhr.responseText);
                if (response.content && response.content.length) {
                    var text = "";
                    var calls = [];
                    var thinks = [];
                    for (var i = 0; i < response.content.length; i++) {
                        var b = response.content[i];
                        if (b.type === "text") text += b.text;
                        else if (b.type === "thinking") {
                            thinks.push({ type: "thinking", thinking: b.thinking || "", signature: b.signature || "" });
                        }
                        else if (b.type === "tool_use") {
                            calls.push({
                                id: b.id,
                                type: "function",
                                "function": { name: b.name, arguments: JSON.stringify(b.input || {}) }
                            });
                        }
                    }
                    if (calls.length > 0) {
                        onComplete(text, null, calls, { role: "assistant", content: text || null, tool_calls: calls, thinkingBlocks: thinks });
                    } else if (text.length > 0 || thinks.length > 0) {
                        onComplete(text, null, null, { role: "assistant", content: text, thinkingBlocks: thinks });
                    } else {
                        onComplete("", i18n("Invalid response format"));
                    }
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
                var errMsg;
                if (xhr.status === 401 || xhr.status === 403) {
                    errMsg = i18n("Authentication failed (HTTP %1) — check your API key", xhr.status);
                } else if (xhr.status === 429) {
                    errMsg = i18n("Rate limited (HTTP 429) — too many requests, try again shortly");
                } else if (xhr.status === 404) {
                    errMsg = i18n("Not found (HTTP 404) — check your API endpoint and model name");
                } else if (xhr.status > 0) {
                    errMsg = i18n("API error %1", xhr.status);
                } else {
                    errMsg = i18n("Request failed (no response) — check your endpoint URL");
                }
                try {
                    var errBody = JSON.parse(xhr.responseText);
                    if (errBody.error && errBody.error.message) {
                        errMsg += ": " + errBody.error.message;
                    }
                } catch (e) {
                    if (xhr.responseText) {
                        errMsg += ": " + xhr.responseText.substring(0, 200);
                    }
                }
                finish(errMsg);
            }
        }
    };

    var body = {
        model: model,
        max_tokens: maxTokens,
        messages: translated.messages,
        temperature: temperature / 100.0,
        stream: true
    };
    // Extended thinking. Requires temperature=1 and max_tokens > budget_tokens,
    // so override both. The user's configured maxTokens still bounds the
    // visible reply (we add the budget on top).
    if (opts.reasoningEffort && opts.reasoningEffort !== "off"
            && opts.thinkingBudget && opts.thinkingBudget > 0) {
        body.thinking = { type: "enabled", budget_tokens: opts.thinkingBudget };
        body.temperature = 1;
        body.max_tokens = maxTokens + opts.thinkingBudget;
    }
    if (translated.system && translated.system.length > 0) {
        body.system = translated.system;
    }
    if (tools && tools.length > 0) {
        body.tools = tools;
    }

    var payload = JSON.stringify(body, null, 2);
    xhr.send(payload);

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
