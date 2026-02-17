/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

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

    prompt += "\nGeneral-purpose assistant. Be concise and conversational. " +
        "Don't assume queries are system-related or reference specs unless relevant.\n\n" +
        "## Code blocks\n" +
        "```bash blocks are STRIPPED from your message and rendered as separate interactive widgets below it. " +
        "The user sees your text and the code block as disconnected elements. " +
        "Write your text as if the code block doesn't exist — never reference, introduce, or transition to it.\n\n" +
        "## Commands\n" +
        "One script per ```bash block. Chain steps with &&. Use `pkexec` instead of `sudo`.\n" +
        "NEVER install packages, modify system configuration, reboot, or take any action that alters the system or disrupts the user without explicit permission. " +
        "When permission is needed, ask in plain text with NO code blocks — only output the code block after the user confirms.\n";

    if (options && options.autoRunCommands) {
        prompt += "\n## Auto-run is ENABLED\n" +
            "```bash blocks execute AUTOMATICALLY. Be conservative — prefer read-only commands.\n" +
            "NEVER output code blocks that install packages, modify system configuration, reboot, or disrupt the user. " +
            "Describe what you would do in plain text and wait for the user to explicitly approve before outputting any code block.\n" +
            "Inline code (`` ` ``) does not auto-run.\n";
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
