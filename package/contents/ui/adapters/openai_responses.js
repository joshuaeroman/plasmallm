/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Responses API strategy for the OpenAI-compatible adapter.
// Dispatched by openai.js when the active provider speaks /v1/responses
// (OpenAI native, Poe, OpenRouter, Azure). Translates the host's neutral
// OpenAI-shaped messages array into Responses' input-item form, parses
// typed SSE events, and round-trips reasoning items (with encrypted_content)
// across turns by storing them in chatMessages' thinking_blocks_json field.

function fetchModels(endpoint, apiKey, callback) {
    // Most Responses-API providers also expose /models with the same shape.
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
    // Responses API uses a flat tool definition (no {type:"function", function:{...}} wrapper).
    var tools = [];
    var ollamaApiKey = options && options.ollamaApiKey;
    var commandToolEnabled = options && options.commandToolEnabled;

    if (ollamaApiKey && ollamaApiKey.length > 0) {
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

    if (commandToolEnabled) {
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

// buildContentArray: returns Responses input parts with input_text / input_image
// types, or a string when no attachments. translateMessages also accepts string.
function buildContentArray(text, attachments) {
    if (!attachments || attachments.length === 0) return text;
    var parts = [];
    if (text && text.length > 0) {
        parts.push({ type: "input_text", text: text });
    }
    for (var i = 0; i < attachments.length; i++) {
        var att = attachments[i];
        if (att.dataUrl) {
            parts.push({ type: "input_image", image_url: att.dataUrl });
        } else if (att.textContent) {
            var label = att.fileName || "file";
            parts.push({ type: "input_text", text: "--- " + label + " ---\n" + att.textContent });
        }
    }
    return parts;
}

// Translate the host's OpenAI-shaped messages array into Responses' form:
// {instructions, input}. instructions captures system messages; input is an
// array of typed items (message, function_call, function_call_output,
// reasoning).
function translateMessages(neutralMessages) {
    var instructions = "";
    var input = [];

    for (var i = 0; i < neutralMessages.length; i++) {
        var m = neutralMessages[i];

        if (m.role === "system") {
            if (typeof m.content === "string") {
                instructions += (instructions.length > 0 ? "\n\n" : "") + m.content;
            }
            continue;
        }

        if (m.role === "tool") {
            input.push({
                type: "function_call_output",
                call_id: m.tool_call_id || "",
                output: typeof m.content === "string" ? m.content : ""
            });
            continue;
        }

        if (m.role === "assistant") {
            // Round-trip preserved reasoning items first (with encrypted_content
            // and id captured from the prior turn). This is required for
            // multi-turn reasoning continuity, especially around tool calls.
            if (m.thinkingBlocks && m.thinkingBlocks.length > 0) {
                for (var th = 0; th < m.thinkingBlocks.length; th++) {
                    var tb = m.thinkingBlocks[th];
                    if (!tb) continue;
                    var rItem = {
                        type: "reasoning",
                        id: tb.id || "",
                        summary: Array.isArray(tb.summary) ? tb.summary : []
                    };
                    if (tb.encrypted_content) rItem.encrypted_content = tb.encrypted_content;
                    input.push(rItem);
                }
            }

            // Assistant text as an output_text message.
            if (m.content && typeof m.content === "string" && m.content.length > 0) {
                input.push({
                    role: "assistant",
                    content: [{ type: "output_text", text: m.content }]
                });
            }

            // Tool calls become standalone function_call input items.
            if (m.tool_calls && m.tool_calls.length > 0) {
                for (var t = 0; t < m.tool_calls.length; t++) {
                    var tc = m.tool_calls[t];
                    var name = (tc["function"] && tc["function"].name) || "";
                    var args = (tc["function"] && tc["function"]["arguments"]) || "";
                    if (typeof args !== "string") args = JSON.stringify(args || {});
                    input.push({
                        type: "function_call",
                        call_id: tc.id || "",
                        name: name,
                        arguments: args
                    });
                }
            }
            continue;
        }

        if (m.role === "user") {
            var userContent;
            if (typeof m.content === "string") {
                userContent = [{ type: "input_text", text: m.content }];
            } else if (Array.isArray(m.content)) {
                userContent = m.content;
            } else {
                userContent = [{ type: "input_text", text: "" }];
            }
            input.push({ role: "user", content: userContent });
            continue;
        }
    }

    return { instructions: instructions, input: input };
}

// Parse Responses SSE buffer. Each event is "event: <name>\ndata: <json>\n\n".
// We only need the JSON payload — its `type` field carries the event name —
// so we ignore the "event:" preface lines and parse "data:" lines.
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
            switch (obj.type) {
            case "response.output_text.delta":
                if (typeof obj.delta === "string" && obj.delta.length > 0) {
                    tokens.push({ content: obj.delta });
                }
                break;
            case "response.output_text.done":
                // Fallback for providers that emit the full text in one event
                // (e.g. Poe for short replies). Marks the text as complete; the
                // accumulator decides whether to use it based on whether deltas
                // already produced output.
                if (typeof obj.text === "string" && obj.text.length > 0) {
                    tokens.push({ content_full: obj.text });
                }
                break;
            case "response.reasoning_summary_text.delta":
                if (typeof obj.delta === "string" && obj.delta.length > 0) {
                    tokens.push({ thinking_delta: obj.delta });
                }
                break;
            case "response.reasoning_summary_text.done":
                if (typeof obj.text === "string" && obj.text.length > 0) {
                    tokens.push({ thinking_full: obj.text });
                }
                break;
            case "response.output_item.added":
                if (obj.item) {
                    tokens.push({ item_added: obj.item });
                }
                break;
            case "response.output_item.done":
                if (obj.item) {
                    tokens.push({ item_done: obj.item });
                }
                break;
            case "response.function_call_arguments.delta":
                if (typeof obj.delta === "string" && obj.delta.length > 0) {
                    tokens.push({
                        function_args_delta: { item_id: obj.item_id || "", delta: obj.delta }
                    });
                }
                break;
            case "response.completed":
                tokens.push({ done: true });
                break;
            case "response.failed":
            case "error":
            case "response.error":
                var msg = (obj.error && obj.error.message) || obj.message || "stream error";
                tokens.push({ error: msg });
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
    var url = endpoint.replace(/\/+$/, "") + "/responses";

    xhr.open("POST", url);
    xhr.timeout = 120000;
    xhr.setRequestHeader("Content-Type", "application/json");
    if (apiKey && apiKey.length > 0) {
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
    }

    var pollTimer = null;
    var lastParseIndex = 0;
    var accumulatedText = "";
    var accumulatedThinkingText = "";
    // Tool calls accumulated by streaming item id, finalized into the neutral
    // OpenAI tool_call shape main.qml dispatches on.
    var toolCallsByItemId = {};
    var accumulatedToolCalls = [];
    // Reasoning blocks captured from item_done events keyed by reasoning id.
    // Order preserved via thinkingBlockOrder.
    var thinkingBlocks = [];
    // Tracks the id of an in-progress reasoning item between output_item.added
    // and output_item.done so finish() can synthesize a block if the stream
    // ends before item_done fires.
    var currentReasoningId = "";
    var streamDone = false;
    var completeCalled = false;
    var streamError = null;

    function processBuffer() {
        if (streamDone) return;
        var result = parseSSEChunks(xhr.responseText, lastParseIndex);
        lastParseIndex = result.newIndex;
        for (var i = 0; i < result.tokens.length; i++) {
            var tok = result.tokens[i];
            if (tok.done) { streamDone = true; continue; }
            if (tok.error) { streamError = tok.error; streamDone = true; continue; }
            if (tok.content) {
                accumulatedText += tok.content;
                onChunk(tok.content, accumulatedText);
            }
            if (typeof tok.content_full === "string") {
                // Whole-text fallback: only apply if streaming deltas didn't
                // already deliver content (otherwise we'd duplicate).
                if (accumulatedText.length === 0) {
                    accumulatedText = tok.content_full;
                    onChunk(tok.content_full, accumulatedText);
                }
            }
            if (typeof tok.thinking_delta === "string" && tok.thinking_delta.length > 0) {
                accumulatedThinkingText += tok.thinking_delta;
                if (onThinkingChunk) onThinkingChunk(tok.thinking_delta, accumulatedThinkingText);
            }
            if (typeof tok.thinking_full === "string") {
                if (accumulatedThinkingText.length === 0) {
                    accumulatedThinkingText = tok.thinking_full;
                    if (onThinkingChunk) onThinkingChunk(tok.thinking_full, accumulatedThinkingText);
                }
            }
            if (tok.item_added) {
                var ia = tok.item_added;
                if (ia.type === "reasoning") {
                    currentReasoningId = ia.id || "";
                } else if (ia.type === "function_call") {
                    var entry = {
                        id: ia.call_id || ia.id || "",
                        type: "function",
                        "function": {
                            name: ia.name || "",
                            arguments: typeof ia.arguments === "string" ? ia.arguments : ""
                        }
                    };
                    accumulatedToolCalls.push(entry);
                    toolCallsByItemId[ia.id] = entry;
                }
            }
            if (tok.function_args_delta) {
                var fad = tok.function_args_delta;
                var target = toolCallsByItemId[fad.item_id];
                if (target) target["function"]["arguments"] += fad.delta;
            }
            if (tok.item_done) {
                var idn = tok.item_done;
                if (idn.type === "reasoning") {
                    // Finalize a reasoning block. Capture id, summary, and
                    // encrypted_content (when include:["reasoning.encrypted_content"]
                    // was set) so the caller can round-trip them.
                    thinkingBlocks.push({
                        type: "reasoning",
                        id: idn.id || "",
                        summary: Array.isArray(idn.summary) ? idn.summary : [],
                        encrypted_content: idn.encrypted_content || ""
                    });
                    if (currentReasoningId === (idn.id || "")) currentReasoningId = "";
                    // If the streaming summary deltas didn't fire (some
                    // providers only send the full summary on item_done),
                    // synthesize text for the UI from the summary array.
                    if (accumulatedThinkingText.length === 0 && idn.summary && idn.summary.length > 0) {
                        for (var s = 0; s < idn.summary.length; s++) {
                            var segText = (idn.summary[s] && idn.summary[s].text) || "";
                            if (segText) {
                                accumulatedThinkingText += segText;
                                if (onThinkingChunk) onThinkingChunk(segText, accumulatedThinkingText);
                            }
                        }
                    }
                } else if (idn.type === "function_call") {
                    // Ensure the final arguments string is captured even if
                    // delta events were missed.
                    var t2 = toolCallsByItemId[idn.id];
                    if (t2 && typeof idn.arguments === "string" && idn.arguments.length > 0
                        && t2["function"]["arguments"].length === 0) {
                        t2["function"]["arguments"] = idn.arguments;
                    }
                }
            }
        }
    }

    // Synthesize a thinking block from accumulated reasoning deltas when the
    // stream ends without a corresponding output_item.done (or with deltas
    // arriving past the last item_done). Mirrors the Anthropic and Gemini
    // adapters which always derive thinking blocks from streamed content.
    function flushPendingThinking() {
        if (accumulatedThinkingText.length === 0) return;
        var alreadyCaptured = "";
        for (var i = 0; i < thinkingBlocks.length; i++) {
            var summary = thinkingBlocks[i].summary;
            if (Array.isArray(summary)) {
                for (var s = 0; s < summary.length; s++) {
                    alreadyCaptured += (summary[s] && summary[s].text) || "";
                }
            }
        }
        if (alreadyCaptured.length >= accumulatedThinkingText.length) return;
        var tail = accumulatedThinkingText.substring(alreadyCaptured.length);
        thinkingBlocks.push({
            type: "reasoning",
            id: currentReasoningId || "",
            summary: [{ type: "summary_text", text: tail }],
            encrypted_content: ""
        });
        currentReasoningId = "";
    }

    function finish(error) {
        if (completeCalled) return;
        completeCalled = true;
        if (pollTimer && pollTimer.running) pollTimer.stop();
        flushPendingThinking();

        if (error) {
            onComplete(accumulatedText, error, null, null);
        } else if (accumulatedToolCalls.length > 0) {
            var assistantMsg = {
                role: "assistant",
                content: accumulatedText || null,
                tool_calls: accumulatedToolCalls,
                thinkingBlocks: thinkingBlocks
            };
            onComplete(accumulatedText, null, accumulatedToolCalls, assistantMsg);
        } else if (accumulatedText.length > 0 || thinkingBlocks.length > 0) {
            onComplete(accumulatedText, null, null, {
                role: "assistant",
                content: accumulatedText,
                thinkingBlocks: thinkingBlocks
            });
        } else {
            // Non-streaming fallback: parse a single Response object.
            try {
                var response = JSON.parse(xhr.responseText);
                var text = "";
                var calls = [];
                var thinks = [];
                if (response.output && response.output.length) {
                    for (var i = 0; i < response.output.length; i++) {
                        var item = response.output[i];
                        if (item.type === "message" && item.content) {
                            for (var ci = 0; ci < item.content.length; ci++) {
                                var c = item.content[ci];
                                if (c.type === "output_text" && typeof c.text === "string") text += c.text;
                            }
                        } else if (item.type === "function_call") {
                            calls.push({
                                id: item.call_id || item.id || "",
                                type: "function",
                                "function": {
                                    name: item.name || "",
                                    arguments: typeof item.arguments === "string" ? item.arguments : JSON.stringify(item.arguments || {})
                                }
                            });
                        } else if (item.type === "reasoning") {
                            thinks.push({
                                type: "reasoning",
                                id: item.id || "",
                                summary: Array.isArray(item.summary) ? item.summary : [],
                                encrypted_content: item.encrypted_content || ""
                            });
                        }
                    }
                }
                if (calls.length > 0) {
                    onComplete(text, null, calls, {
                        role: "assistant", content: text || null, tool_calls: calls, thinkingBlocks: thinks
                    });
                } else if (text.length > 0 || thinks.length > 0) {
                    onComplete(text, null, null, {
                        role: "assistant", content: text, thinkingBlocks: thinks
                    });
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
        input: translated.input,
        stream: true,
        // Ensures reasoning items returned to us include the round-trippable
        // encrypted_content payload required to continue across turns.
        include: ["reasoning.encrypted_content"]
    };
    if (translated.instructions && translated.instructions.length > 0) {
        body.instructions = translated.instructions;
    }
    var reasoningOn = opts.reasoningEffort && opts.reasoningEffort !== "off";
    if (reasoningOn) {
        body.reasoning = { effort: opts.reasoningEffort, summary: "auto" };
    }
    if (typeof temperature === "number") {
        // Reasoning models reject any temperature other than 1 (Anthropic via
        // Poe is strict about this; OpenAI o-series silently ignores). Force
        // temperature to 1 whenever reasoning is on.
        body.temperature = reasoningOn ? 1 : temperature / 100.0;
    }
    if (maxTokens) {
        body.max_output_tokens = maxTokens;
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
