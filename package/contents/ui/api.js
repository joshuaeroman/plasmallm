/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

function localISODateTime() {
    var d = new Date();
    var pad = function(n) { return n < 10 ? "0" + n : "" + n; };
    var off = -d.getTimezoneOffset();
    var sign = off >= 0 ? "+" : "-";
    var absOff = Math.abs(off);
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) +
           "T" + pad(d.getHours()) + ":" + pad(d.getMinutes()) +
           sign + pad(Math.floor(absOff / 60)) + ":" + pad(absOff % 60);
}

function buildSystemPrompt(sysInfo, customAdditions, options) {
    var prompt = "You are a helpful assistant embedded in the user's Linux desktop.\n\n" +
        "## System\n";

    if (sysInfo.hostname) {
        prompt += "- Hostname: " + sysInfo.hostname + "\n";
    }
    if (sysInfo.osRelease) {
        prompt += "- OS: " + sysInfo.osRelease + "\n";
    }
    if (sysInfo.kernel) {
        prompt += "- Kernel: " + sysInfo.kernel + "\n";
    }
    if (sysInfo.desktop) {
        prompt += "- Desktop: " + sysInfo.desktop + "\n";
    }
    if (sysInfo.shell) {
        prompt += "- Shell: " + sysInfo.shell + "\n";
    }
    if (sysInfo.locale) {
        prompt += "- Locale: " + sysInfo.locale + "\n";
    }
    if (options && options.dateTime) {
        prompt += "- Current date/time: " + options.dateTime + "\n";
    }
    if (sysInfo.user) {
        prompt += "- User: " + sysInfo.user + "\n";
    }
    if (sysInfo.cpu) {
        prompt += "- CPU: " + sysInfo.cpu + "\n";
    }
    if (sysInfo.cpuCores) {
        prompt += "- CPU Cores: " + sysInfo.cpuCores + "\n";
    }
    if (sysInfo.cpuArch) {
        prompt += "- Architecture: " + sysInfo.cpuArch + "\n";
    }
    if (sysInfo.gpu) {
        prompt += "- GPU: " + sysInfo.gpu + "\n";
    }
    if (sysInfo.memory) {
        prompt += "- Memory:\n" + sysInfo.memory + "\n";
    }
    if (sysInfo.disk) {
        prompt += "- Block Devices:\n" + sysInfo.disk + "\n";
    }
    if (sysInfo.network) {
        prompt += "- Network Interfaces:\n" + sysInfo.network + "\n";
    }

    prompt += "\nGeneral-purpose assistant. Keep responses short (~1 paragraph) unless more detail is needed to properly answer. Be concise and conversational." +
        "Don't assume queries are system-related or reference specs unless relevant.\n\n" +
        "## Code blocks\n" +
        "```bash blocks are STRIPPED from your message and rendered as separate interactive widgets below it. " +
        "The user sees your text and the code block as disconnected elements. " +
        "Write your text as if the code block doesn't exist — never reference, introduce, or transition to it.\n\n" +
        "## Commands\n" +
        "One script per ```bash block. Chain steps with &&. Use `pkexec` instead of `sudo`.\n" +
        "Scripts run non-interactively with no stdin — never use read, select, or any command that waits for user input. Use `kdialog` for user prompts (e.g., `kdialog --inputbox \"prompt\"`).\n" +
        "NEVER install packages, modify system configuration, reboot, or take any action that alters the system or disrupts the user without explicit permission. " +
        "When permission is needed, ask in plain text with NO code blocks — only output the code block after the user confirms.\n";

    if (options && options.autoRunCommands) {
        prompt += "\n## Auto-run is ENABLED\n" +
            "```bash blocks execute AUTOMATICALLY. Be conservative — prefer read-only commands.\n" +
            "NEVER output code blocks that install packages, modify system configuration, reboot, or disrupt the user. " +
            "Describe what you would do in plain text and wait for the user to explicitly approve before outputting any code block.\n" +
            "Inline code (`` ` ``) does not auto-run.\n";
    }

    if (options && options.autoMode) {
        prompt += "\n## Full Auto mode is ACTIVE\n" +
            "Commands run AND their output is automatically shared back to you. " +
            "You are in an agentic loop. Prefer read-only commands unless the user explicitly requests a write operation.\n";
    }

    if (customAdditions && customAdditions.trim().length > 0) {
        prompt += "The below instructions are given by the user and take the utmost precedence over the instructions above.\n";
        prompt += "\n" + customAdditions.trim() + "\n";
    }

    prompt += "\nEND OF SYSTEM PROMPT\n";

    return prompt;
}

function sendChatRequest(endpoint, apiKey, model, messages, temperature, maxTokens, callback) {
    var xhr = new XMLHttpRequest();
    var url = endpoint.replace(/\/+$/, "") + "/chat/completions";

    xhr.open("POST", url);
    xhr.timeout = 60000;
    xhr.setRequestHeader("Content-Type", "application/json");
    if (apiKey && apiKey.length > 0) {
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
    }

    xhr.ontimeout = function() {
        callback("Request timed out after 60 seconds", null);
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    if (!response.choices || !response.choices.length ||
                        !response.choices[0].message ||
                        typeof response.choices[0].message.content !== "string") {
                        callback("Invalid response format: missing choices[0].message.content", null);
                        return;
                    }
                    var text = response.choices[0].message.content;
                    callback(null, text);
                } catch (e) {
                    callback("Failed to parse response: " + e.message, null);
                }
            } else {
                var errMsg;
                if (xhr.status === 401 || xhr.status === 403) {
                    errMsg = "Authentication failed (HTTP " + xhr.status + ") — check your API key";
                } else if (xhr.status === 429) {
                    errMsg = "Rate limited (HTTP 429) — too many requests, try again shortly";
                } else if (xhr.status === 404) {
                    errMsg = "Not found (HTTP 404) — check your API endpoint and model name";
                } else if (xhr.status > 0) {
                    errMsg = "API error " + xhr.status;
                } else {
                    errMsg = "Request failed (no response) — check your endpoint URL";
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
                callback(errMsg, null);
            }
        }
    };

    var body = {
        model: model,
        messages: messages,
        temperature: temperature / 100.0,
        max_tokens: maxTokens
    };

    var payload = JSON.stringify(body, null, 2);
    xhr.send(payload);
    return xhr;
}

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
        callback("Request timed out after 30 seconds", null);
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
                    callback("Failed to parse models: " + e.message, null);
                }
            } else {
                callback("Failed to fetch models: HTTP " + xhr.status, null);
            }
        }
    };

    xhr.send();
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

function buildTools(ollamaApiKey) {
    if (!ollamaApiKey || ollamaApiKey.length === 0) return [];
    return [{
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
    }];
}

function performWebSearch(ollamaApiKey, query, maxResults, callback) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", "https://ollama.com/api/web_search");
    xhr.timeout = 30000;
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Authorization", "Bearer " + ollamaApiKey);

    xhr.ontimeout = function() {
        callback("Web search timed out", null);
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    callback(null, response);
                } catch (e) {
                    callback("Failed to parse web search response: " + e.message, null);
                }
            } else {
                var errMsg = "Web search failed (HTTP " + xhr.status + ")";
                if (xhr.responseText) {
                    errMsg += ": " + xhr.responseText.substring(0, 200);
                }
                callback(errMsg, null);
            }
        }
    };

    var body = { query: query };
    if (maxResults && maxResults > 0) body.max_results = Math.min(maxResults, 10);
    xhr.send(JSON.stringify(body));
}

function sendStreamingChatRequest(endpoint, apiKey, model, messages, temperature, maxTokens, onChunk, onComplete, tools) {
    var xhr = new XMLHttpRequest();
    var url = endpoint.replace(/\/+$/, "") + "/chat/completions";

    xhr.open("POST", url);
    xhr.timeout = 120000;
    xhr.setRequestHeader("Content-Type", "application/json");
    if (apiKey && apiKey.length > 0) {
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
    }

    var pollTimer = null; // set externally via returned object
    var lastParseIndex = 0;
    var accumulatedText = "";
    var accumulatedToolCalls = []; // [{id, type, function: {name, arguments}}]
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
            if (tok.tool_calls_delta) {
                for (var t = 0; t < tok.tool_calls_delta.length; t++) {
                    var tcd = tok.tool_calls_delta[t];
                    var idx = tcd.index !== undefined ? tcd.index : 0;
                    // Initialize tool call entry on first appearance
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
            // Build an assistant message with tool_calls for the caller
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
                        onComplete("", "Invalid response format");
                    }
                } else {
                    onComplete("", "Invalid response format");
                }
            } catch (e) {
                onComplete("", "Failed to parse response: " + e.message);
            }
        }
    }

    xhr.ontimeout = function() {
        finish("Request timed out");
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 3) { // LOADING — data arriving
            if (pollTimer && !pollTimer.running) pollTimer.start();
            processBuffer();
        } else if (xhr.readyState === 4) { // DONE
            if (pollTimer && pollTimer.running) pollTimer.stop();
            if (xhr.status === 200) {
                processBuffer(); // process any remaining data
                finish(null);
            } else {
                var errMsg;
                if (xhr.status === 401 || xhr.status === 403) {
                    errMsg = "Authentication failed (HTTP " + xhr.status + ") — check your API key";
                } else if (xhr.status === 429) {
                    errMsg = "Rate limited (HTTP 429) — too many requests, try again shortly";
                } else if (xhr.status === 404) {
                    errMsg = "Not found (HTTP 404) — check your API endpoint and model name";
                } else if (xhr.status > 0) {
                    errMsg = "API error " + xhr.status;
                } else {
                    errMsg = "Request failed (no response) — check your endpoint URL";
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

function stripCodeBlocks(text) {
    return text.replace(/\n?```\w*\n[\s\S]*?```\n?/g, "\n");
}

function parseCommandBlocks(text) {
    var commands = [];
    var regex = /```(?:bash|sh|shell|zsh)\s*\r?\n([\s\S]*?)```/g;
    var match;
    while ((match = regex.exec(text)) !== null) {
        var cmd = match[1].trim();
        if (cmd.length > 0) {
            commands.push(cmd);
        }
    }
    return commands;
}
