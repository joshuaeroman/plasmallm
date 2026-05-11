/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Google Gemini Interactions API adapter (POST /v1beta/interactions?alt=sse).
// Stateful implementation using server-side interaction storage.
//   - Transitions from generateContent schema to Interactions (steps) schema.
//   - Maintains server-side context via previous_interaction_id.
//   - Falls back to full history input when continuity is broken (edits/clears).

var id = "gemini_interactions";
var displayName = "Google Gemini (Interactions API)";

var presets = [
    { name: "Google Gemini (Interactions API)", url: "https://generativelanguage.googleapis.com" }
];

var capabilities = {
    providerPresets: false,
    customEndpoint: true,
    reasoningEffort: true,
    thinkingBudget: false,
    fetchModels: true,
    nativeGoogleSearch: true,
    nativeCodeExecution: true,
    reasoningHelp: i18n("Gemini uses the thinking level dropdown directly.")
};

// State persistence for the current session.
var previousInteractionId = "";
var lastMessageCount = 0;

function setHeaders(xhr, apiKey, opts) {
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Api-Revision", "2026-05-20");
    if (apiKey && apiKey.length > 0) {
        if (opts && opts.geminiAuthMethod === "agentplatform") {
            // OAuth2 tokens usually start with 'ya29.' and are much longer than API keys.
            // API keys from Agent Platform/Vertex AI Express Mode should use x-goog-api-key.
            if (apiKey.indexOf("ya29.") === 0 || apiKey.length > 128) {
                xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
            } else {
                xhr.setRequestHeader("x-goog-api-key", apiKey);
            }
        } else {
            xhr.setRequestHeader("x-goog-api-key", apiKey);
        }
    }
}

function fetchModels(endpoint, apiKey, opts, callback) {
    // Some callers might still use the old signature (endpoint, apiKey, callback)
    if (typeof opts === "function") {
        callback = opts;
        opts = null;
    }

    var xhr = new XMLHttpRequest();
    var url;
    var location = (opts && opts.geminiLocation) || "global";
    var baseUrl = endpoint.replace(/\/+$/, "");

    // Automatically prefix location if it's not global and not already prefixed.
    if (location !== "global" && baseUrl.indexOf("://aiplatform.googleapis.com") !== -1) {
        baseUrl = baseUrl.replace("://", "://" + location + "-");
    }

    if (opts && opts.geminiAuthMethod === "agentplatform") {
        var projectId = opts.geminiProjectId || "";
        url = baseUrl + "/v1beta1/projects/" + encodeURIComponent(projectId) + "/locations/" + encodeURIComponent(location) + "/publishers/google/models";
    } else {
        url = baseUrl + "/v1beta/models?pageSize=1000";
    }

    xhr.open("GET", url);
    xhr.timeout = 30000;
    setHeaders(xhr, apiKey, opts);

    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    var models = [];
                    // Model Garden returns 'publisherModels', project models return 'models'
                    var rawModels = response.publisherModels || response.models || [];
                    for (var i = 0; i < rawModels.length; i++) {
                        var m = rawModels[i];
                        var name = m.name || "";
                        if (name.indexOf("models/") === 0) name = name.substring(7);
                        else if (name.indexOf("publishers/google/models/") !== -1) {
                            name = name.split("/").pop();
                        }

                        if (opts && opts.geminiAuthMethod === "agentplatform") {
                            // Filter for Gemini models if listing from Model Garden
                            if (name.toLowerCase().indexOf("gemini") !== -1) {
                                models.push(name);
                            }
                        } else {
                            var methods = m.supportedGenerationMethods || [];
                            if (methods.indexOf("generateContent") !== -1) {
                                models.push(name);
                            }
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
    return prefix + (xhr.status > 0 ? " (HTTP " + xhr.status + ")" : "") + (detail ? ": " + detail : "");
}

function buildTools(options) {
    var tools = [];
    if (options && options.nativeGoogleSearchEnabled) {
        tools.push({ type: "google_search" });
    } else if (options && options.webSearchEnabled && options.searchConfigured) {
        tools.push({
            type: "function",
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

    if (options && options.nativeCodeExecutionEnabled) {
        tools.push({ type: "code_execution" });
    }

    if (options && options.commandToolEnabled) {
        tools.push({
            type: "function",
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
    return tools;
}

function buildContentArray(text, attachments) {
    var content = [];
    if (text && text.length > 0) content.push({ type: "text", text: text });
    if (attachments) {
        for (var i = 0; i < attachments.length; i++) {
            var att = attachments[i];
            if (att.dataUrl) {
                var m = /^data:([^;]+);base64,(.*)$/.exec(att.dataUrl);
                if (m) content.push({ type: "image", image: { mime_type: m[1], data: m[2] } });
            } else if (att.textContent) {
                content.push({ type: "text", text: "--- " + (att.fileName || "file") + " ---\n" + att.textContent });
            }
        }
    }
    return content;
}

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

function translateMessages(neutralMessages, startIndex) {
    var systemInstruction = "";
    var input = [];
    var idToName = buildToolCallIdMap(neutralMessages);
    var start = startIndex || 0;

    for (var i = 0; i < neutralMessages.length; i++) {
        var m = neutralMessages[i];
        if (m.role === "system") {
            systemInstruction += (systemInstruction.length > 0 ? "\n\n" : "") + m.content;
            continue;
        }

        if (i < start) continue;

        if (m.role === "tool") {
            input.push({
                type: "function_result",
                name: idToName[m.tool_call_id] || "unknown",
                call_id: m.tool_call_id,
                result: [{ type: "text", text: typeof m.content === "string" ? m.content : JSON.stringify(m.content) }]
            });
            continue;
        }

        if (m.thinkingBlocks) {
            for (var th = 0; th < m.thinkingBlocks.length; th++) {
                var tb = m.thinkingBlocks[th];
                input.push({
                    type: "thought",
                    signature: tb.thoughtSignature || "legacy",
                    summary: [{ type: "text", text: tb.thinking }]
                });
            }
        }

        if (m.role === "assistant" && m.tool_calls) {
            for (var t = 0; t < m.tool_calls.length; t++) {
                var tc = m.tool_calls[t];
                input.push({
                    type: "function_call",
                    id: tc.id,
                    name: tc["function"].name,
                    arguments: typeof tc["function"].arguments === "string" ? JSON.parse(tc["function"].arguments) : tc["function"].arguments
                });
            }
        }

        var turn = {
            type: (m.role === "assistant" ? "model_output" : "user_input"),
            content: []
        };

        if (typeof m.content === "string" && m.content.length > 0) {
            turn.content.push({ type: "text", text: m.content });
        } else if (Array.isArray(m.content)) {
            turn.content = m.content;
        }

        if (turn.content.length > 0) {
            input.push(turn);
        }
    }
    return { systemInstruction: systemInstruction, input: input };
}

function parseSSEChunks(buffer, lastIndex) {
    var tokens = [];
    var searchFrom = lastIndex;
    while (true) {
        var nlPos = buffer.indexOf("\n", searchFrom);
        if (nlPos === -1) break;
        var line = buffer.substring(searchFrom, nlPos).replace(/\r$/, "");
        searchFrom = nlPos + 1;
        if (line === "" || line.substring(0, 6) !== "data: ") continue;
        var dataStr = line.substring(6);
        if (dataStr === "[DONE]") {
            continue;
        }
        try {
            var ev = JSON.parse(dataStr);
            var evType = ev.event_type || ev.type;
            if (evType === "interaction.created") {
                tokens.push({ interaction_id: ev.interaction.id });
            } else if (evType === "step.start") {
                var step = ev.step;
                if (step.type === "function_call") {
                    tokens.push({
                        function_call_start: {
                            id: step.id,
                            name: step.name,
                            args: step.arguments || ""
                        }
                    });
                } else if (step.type === "google_search_call") {
                    tokens.push({
                        function_call_start: {
                            id: step.id,
                            name: "native_google_search",
                            args: step.arguments ? JSON.stringify(step.arguments) : ""
                        }
                    });
                } else if (step.type === "code_execution_call") {
                    tokens.push({
                        function_call_start: {
                            id: step.id,
                            name: "native_code_execution",
                            args: step.arguments ? JSON.stringify(step.arguments) : ""
                        }
                    });
                } else if (step.type === "thought" && step.signature) {
                    tokens.push({ thinking_delta: { signature: step.signature } });
                } else if (step.type === "google_search_result") {
                    if (step.search_suggestions) {
                        tokens.push({ content: "\n\n" + step.search_suggestions + "\n" });
                    }
                } else if (step.type === "code_execution_result") {
                    if (step.result) {
                        tokens.push({ content: "\n\n[Code Output]\n" + step.result + "\n" });
                    }
                } else if (step.type === "model_output" && step.content) {
                    for (var c = 0; c < step.content.length; c++) {
                        var pt = step.content[c];
                        if (pt.type === "text" && pt.text) {
                            tokens.push({ content: pt.text });
                        }
                    }
                }
            } else if (evType === "step.delta") {
                var delta = ev.delta;
                if (delta.type === "text") {
                    tokens.push({ content: delta.text });
                } else if (delta.type === "thought") {
                    tokens.push({ thinking_delta: { text: delta.text } });
                } else if (delta.type === "signature") {
                    tokens.push({ thinking_delta: { signature: delta.signature || delta.text } });
                } else if (delta.arguments_delta) {
                    tokens.push({ function_call_delta: delta.arguments_delta });
                }
            } else if (evType === "step.stop") {
                tokens.push({ thinking_close: true });
            } else if (evType === "interaction.completed" || evType === "interaction.complete") {
                tokens.push({ complete_id: ev.interaction.id });
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
    var model = opts.model || "";
    var messages = opts.messages;

    // Pre-flight check for unsupported model versions combining native and custom tools
    if ((model.indexOf("gemini-1") !== -1 || model.indexOf("gemini-2") !== -1) && opts.tools && opts.tools.length > 1) {
        var hasNative = false;
        var hasCustom = false;
        for (var t = 0; t < opts.tools.length; t++) {
            if (opts.tools[t].type === "google_search" || opts.tools[t].type === "code_execution") hasNative = true;
            if (opts.tools[t].type === "function") hasCustom = true;
        }
        if (hasNative && hasCustom) {
            var errMsg = i18n("This model version does not support combining Native tools (Search/Code) with custom commands. Please select a newer model (e.g., Gemini 3+) or disable Native features in Settings.");
            return {
                xhr: { abort: function(){} },
                setPollTimer: function(t){},
                reported: false,
                processBuffer: function() {
                    if (!this.reported) {
                        this.reported = true;
                        opts.onComplete("", errMsg, null, null);
                    }
                }
            };
        }
    }

    var xhr = new XMLHttpRequest();
    var url;
    var baseUrl = endpoint.replace(/\/+$/, "");

    if (opts && opts.geminiAuthMethod === "agentplatform") {
        var projectId = opts.geminiProjectId || "";
        var location = opts.geminiLocation || "global";
        
        // Automatically prefix location if it's not global and not already prefixed.
        if (location !== "global" && baseUrl.indexOf("://aiplatform.googleapis.com") !== -1) {
            baseUrl = baseUrl.replace("://", "://" + location + "-");
        }

        url = baseUrl +
              "/v1beta1/projects/" + encodeURIComponent(projectId) +
              "/locations/" + encodeURIComponent(location) +
              "/interactions?alt=sse";
    } else {
        url = baseUrl + "/v1beta/interactions?alt=sse";
    }

    xhr.open("POST", url);
    setHeaders(xhr, apiKey, opts);

    var lastParseIndex = 0;
    var accumulatedText = "";
    var accumulatedToolCalls = [];
    var currentToolCall = null;
    var thinkingBlocks = [];
    var currentThinkingBlock = null;

    function processBuffer() {
        var result = parseSSEChunks(xhr.responseText, lastParseIndex);
        lastParseIndex = result.newIndex;
        for (var i = 0; i < result.tokens.length; i++) {
            var tok = result.tokens[i];
            if (tok.content) {
                accumulatedText += tok.content;
                opts.onChunk(tok.content, accumulatedText);
            }
            if (tok.function_call_start) {
                currentToolCall = {
                    id: tok.function_call_start.id,
                    type: "function",
                    "function": {
                        name: tok.function_call_start.name,
                        arguments: tok.function_call_start.args || ""
                    }
                };
                accumulatedToolCalls.push(currentToolCall);
            }
            if (tok.function_call_delta && currentToolCall) {
                currentToolCall["function"].arguments += tok.function_call_delta;
            }
            if (tok.thinking_delta) {
                if (!currentThinkingBlock) {
                    currentThinkingBlock = { type: "thinking", thinking: "", thoughtSignature: "" };
                    thinkingBlocks.push(currentThinkingBlock);
                }
                if (tok.thinking_delta.text) {
                    currentThinkingBlock.thinking += tok.thinking_delta.text;
                    if (opts.onThinkingChunk) opts.onThinkingChunk(tok.thinking_delta.text, currentThinkingBlock.thinking);
                }
                if (tok.thinking_delta.signature) {
                    currentThinkingBlock.thoughtSignature = tok.thinking_delta.signature;
                }
            }
            if (tok.thinking_close) {
                currentThinkingBlock = null;
            }
            if (tok.complete_id) {
                previousInteractionId = tok.complete_id;
                lastMessageCount = messages.length;
            }
        }
    }

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 3 || xhr.readyState === 4) {
            processBuffer();
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    var assistantMsg = { role: "assistant", content: accumulatedText || null, thinkingBlocks: thinkingBlocks };
                    if (accumulatedToolCalls.length > 0) {
                        assistantMsg.tool_calls = accumulatedToolCalls;
                        opts.onComplete(accumulatedText, null, accumulatedToolCalls, assistantMsg);
                    } else {
                        opts.onComplete(accumulatedText, null, null, assistantMsg);
                    }
                } else {
                    opts.onComplete("", formatGeminiError(xhr, i18n("Request failed")), null, null);
                }
            }
        }
    };

    var translated = translateMessages(messages);
    var body = {
        model: model,
        stream: true,
        store: true,
        generation_config: {
            temperature: opts.temperature / 100.0,
            max_output_tokens: opts.maxTokens
        }
    };

    if (opts.reasoningEffort && opts.reasoningEffort !== "off") {
        body.generation_config.thinking_level = opts.reasoningEffort;
        body.generation_config.thinking_summaries = "auto";
    }

    if (translated.systemInstruction) body.system_instruction = translated.systemInstruction;
    if (opts.tools && opts.tools.length > 0) {
        body.tools = opts.tools;
    }

    // Stateful continuity check
    if (previousInteractionId && messages.length > lastMessageCount) {
        body.previous_interaction_id = previousInteractionId;
        // In a continuation, we only send the steps derived from the NEW messages.
        var newOnly = translateMessages(messages, lastMessageCount);
        body.input = newOnly.input;
    } else {
        body.input = translated.input;
        previousInteractionId = "";
    }

    xhr.send(JSON.stringify(body));

    return {
        xhr: xhr,
        setPollTimer: function(t) {},
        processBuffer: processBuffer
    };
}
