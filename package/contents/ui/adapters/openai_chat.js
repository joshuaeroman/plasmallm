/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Chat Completions strategy for the OpenAI-compatible adapter.
// Dispatched by openai.js when the active provider does not use the
// /v1/responses endpoint. The "neutral" wire shapes (messages array,
// accumulated tool_calls) intentionally match this baseline since other
// adapters translate to/from it.

function fetchModels(endpoint, apiKey, callback) {
    var xhr = new XMLHttpRequest();
    var url = endpoint.replace(/\/+$/, "") + "/models";

    xhr.open("GET", url);
    xhr.timeout = 30000;
    xhr.setRequestHeader("Content-Type", "application/json");
    if (apiKey && apiKey.length > 0) {
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
    }

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
    var ollamaApiKey = options && options.ollamaApiKey;
    var commandToolEnabled = options && options.commandToolEnabled;
    var webSearchEnabled = options && options.webSearchEnabled;

    if (webSearchEnabled && ollamaApiKey && ollamaApiKey.length > 0) {
        tools.push({
            type: "function",
            "function": {
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
            }
        });
    }

    if (commandToolEnabled) {
        tools.push({
            type: "function",
            "function": {
                name: "run_command",
                description: "Execute a shell command on the user's system and return its output. Use this to run commands when the user asks you to perform system tasks.",
                parameters: {
                    type: "object",
                    properties: {
                        command: { type: "string", description: "The shell command to execute" }
                    },
                    required: ["command"]
                }
            }
        });
    }

    return tools;
}

function buildContentArray(text, attachments) {
    if (!attachments || attachments.length === 0) return text;
    var parts = [];
    if (text && text.length > 0) {
        parts.push({ type: "text", text: text });
    }
    for (var i = 0; i < attachments.length; i++) {
        var att = attachments[i];
        if (att.dataUrl) {
            parts.push({ type: "image_url", image_url: { url: att.dataUrl } });
        } else if (att.textContent) {
            var label = att.fileName || "file";
            parts.push({ type: "text", text: "--- " + label + " ---\n" + att.textContent });
        }
    }
    return parts;
}

function parseSSEChunks(buffer, lastIndex) {
    var tokens = [];
    var searchFrom = lastIndex;
    while (true) {
        var nlPos = buffer.indexOf("\n", searchFrom);
        if (nlPos === -1) break; // incomplete line — wait for more data
        var line = buffer.substring(searchFrom, nlPos).replace(/\r$/, "");
        searchFrom = nlPos + 1;
        if (line === "") continue;
        if (line.substring(0, 6) !== "data: ") continue;
        var payload = line.substring(6);
        if (payload === "[DONE]") {
            tokens.push({ done: true });
            continue;
        }
        try {
            var obj = JSON.parse(payload);
            if (obj.choices && obj.choices[0] && obj.choices[0].delta) {
                var delta = obj.choices[0].delta;
                if (typeof delta.content === "string" && delta.content.length > 0) {
                    tokens.push({ content: delta.content });
                }
                // Reasoning text: OpenAI o-series via /chat/completions exposes
                // `delta.reasoning`; DeepSeek/Qwen-style providers use
                // `delta.reasoning_content`. Display-only — providers
                // explicitly say not to round-trip these on chat completions.
                if (typeof delta.reasoning === "string" && delta.reasoning.length > 0) {
                    tokens.push({ thinking_delta: delta.reasoning });
                } else if (typeof delta.reasoning_content === "string" && delta.reasoning_content.length > 0) {
                    tokens.push({ thinking_delta: delta.reasoning_content });
                }
                if (delta.tool_calls) {
                    tokens.push({ tool_calls_delta: delta.tool_calls });
                }
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
    var messages = opts.messages;
    var temperature = opts.temperature;
    var maxTokens = opts.maxTokens;
    var tools = opts.tools;
    var onChunk = opts.onChunk;
    var onThinkingChunk = opts.onThinkingChunk;
    var onComplete = opts.onComplete;

    var xhr = new XMLHttpRequest();
    var url = endpoint.replace(/\/+$/, "") + "/chat/completions";

    xhr.open("POST", url);
    xhr.timeout = 120000;
    xhr.setRequestHeader("Content-Type", "application/json");
    if (apiKey && apiKey.length > 0) {
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
    }

    var pollTimer = null;
    var lastParseIndex = 0;
    var accumulatedText = "";
    var accumulatedToolCalls = []; // [{id, type, function: {name, arguments}}]
    var accumulatedThinkingText = "";
    var streamDone = false;
    var completeCalled = false;

    function processBuffer() {
        if (streamDone) return;
        var result = parseSSEChunks(xhr.responseText, lastParseIndex);
        lastParseIndex = result.newIndex;
        for (var i = 0; i < result.tokens.length; i++) {
            var tok = result.tokens[i];
            if (tok.done) {
                streamDone = true;
                return;
            }
            if (tok.content) {
                accumulatedText += tok.content;
                onChunk(tok.content, accumulatedText);
            }
            if (typeof tok.thinking_delta === "string" && tok.thinking_delta.length > 0) {
                accumulatedThinkingText += tok.thinking_delta;
                if (onThinkingChunk) onThinkingChunk(tok.thinking_delta, accumulatedThinkingText);
            }
            if (tok.tool_calls_delta) {
                for (var t = 0; t < tok.tool_calls_delta.length; t++) {
                    var tcd = tok.tool_calls_delta[t];
                    var idx = tcd.index !== undefined ? tcd.index : 0;
                    if (!accumulatedToolCalls[idx]) {
                        accumulatedToolCalls[idx] = {
                            id: tcd.id || "",
                            type: tcd.type || "function",
                            "function": { name: "", arguments: "" }
                        };
                    }
                    if (tcd.id) accumulatedToolCalls[idx].id = tcd.id;
                    if (tcd["function"]) {
                        if (tcd["function"].name) accumulatedToolCalls[idx]["function"].name += tcd["function"].name;
                        if (tcd["function"].arguments) accumulatedToolCalls[idx]["function"]["arguments"] += tcd["function"]["arguments"];
                    }
                }
            }
        }
    }

    function finish(error) {
        if (completeCalled) return;
        completeCalled = true;
        if (pollTimer && pollTimer.running) pollTimer.stop();

        if (error) {
            onComplete(accumulatedText, error, null, null);
        } else if (accumulatedToolCalls.length > 0) {
            var assistantMsg = { role: "assistant", content: accumulatedText || null, tool_calls: accumulatedToolCalls };
            onComplete(accumulatedText, null, accumulatedToolCalls, assistantMsg);
        } else if (accumulatedText.length > 0) {
            onComplete(accumulatedText, null, null, null);
        } else {
            // Non-streaming fallback: server returned a regular JSON response
            try {
                var response = JSON.parse(xhr.responseText);
                if (response.choices && response.choices[0] && response.choices[0].message) {
                    var msg = response.choices[0].message;
                    if (msg.tool_calls && msg.tool_calls.length > 0) {
                        onComplete("", null, msg.tool_calls, msg);
                    } else if (typeof msg.content === "string") {
                        onComplete(msg.content, null);
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
        if (xhr.readyState === 3) { // LOADING
            if (pollTimer && !pollTimer.running) pollTimer.start();
            processBuffer();
        } else if (xhr.readyState === 4) { // DONE
            if (pollTimer && pollTimer.running) pollTimer.stop();
            if (xhr.status === 200) {
                processBuffer();
                finish(null);
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
        messages: messages,
        temperature: temperature / 100.0,
        max_tokens: maxTokens,
        stream: true
    };
    if (opts.reasoningEffort && opts.reasoningEffort !== "off") {
        body.reasoning_effort = opts.reasoningEffort;
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
