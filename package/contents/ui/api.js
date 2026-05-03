/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Provider-neutral helpers + thin pass-throughs to the active adapter.
// Wire-level logic (request shapes, SSE parsing, tool schemas) lives in
// adapters/<id>.js and is selected via Plasmoid.configuration.apiType.

.import "adapters/index.js" as Adapters
.import "search_adapters/index.js" as SearchAdapters

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
        "Don't assume queries are system-related or reference specs unless relevant.\n\n";

    if (options && options.commandToolEnabled) {
        prompt += "## Commands\n" +
            "You have a `run_command` tool available. Use it to execute shell commands when the user asks you to perform system tasks. " +
            "You can still use fenced code blocks to show code snippets that shouldn't be executed.\n" +
            "Chain steps with &&. Use `pkexec` instead of `sudo`.\n" +
            "Commands run non-interactively with no stdin — never use read, select, or any command that waits for user input. Use `kdialog` for user prompts (e.g., `kdialog --inputbox \"prompt\"`).\n" +
            "NEVER install packages, modify system configuration, reboot, or take any action that alters the system or disrupts the user without explicit permission. " +
            "When permission is needed, ask in plain text first — only use the tool after the user confirms.\n";
    } else {
        prompt += "## Code blocks\n" +
            "```bash blocks are STRIPPED from your message and rendered as separate interactive widgets below it. " +
            "The user sees your text and the code block as disconnected elements. " +
            "Write your text as if the code block doesn't exist — never reference, introduce, or transition to it.\n\n" +
            "## Commands\n" +
            "One script per ```bash block. Chain steps with &&. Use `pkexec` instead of `sudo`.\n" +
            "Scripts run non-interactively with no stdin — never use read, select, or any command that waits for user input. Use `kdialog` for user prompts (e.g., `kdialog --inputbox \"prompt\"`).\n" +
            "NEVER install packages, modify system configuration, reboot, or take any action that alters the system or disrupts the user without explicit permission. " +
            "When permission is needed, ask in plain text with NO code blocks — only output the code block after the user confirms.\n";
    }

    if (options && options.sessionMultiplexer) {
        var parts = options.sessionMultiplexer.split(": ");
        var be = parts[0] || "tmux";
        var sess = parts[1] || "plasmallm";
        var attachCmd = be === "tmux" ? ("tmux attach -t " + sess) : ("screen -r " + sess);
        prompt += "\n## Session Multiplexer\n" +
            "Commands run inside a persistent **" + be + "** session named `" + sess + "`. " +
            "Working directory, exported variables, and background jobs persist across calls. " +
            "Avoid `clear`, `reset`, `exit`, and full-screen TUIs (`htop`, `vim`); they would damage the shared shell. " +
            "The user can attach with `" + attachCmd + "`.\n";
    }

    if (options && options.autoRunCommands) {
        if (options.commandToolEnabled) {
            prompt += "\n## Auto-run is ENABLED\n" +
                "Commands from the `run_command` tool execute AUTOMATICALLY. Be conservative — prefer read-only commands.\n" +
                "NEVER run commands that install packages, modify system configuration, reboot, or disrupt the user. " +
                "Describe what you would do in plain text and wait for the user to explicitly approve before using the tool.\n";
        } else {
            prompt += "\n## Auto-run is ENABLED\n" +
                "```bash blocks execute AUTOMATICALLY. Be conservative — prefer read-only commands.\n" +
                "NEVER output code blocks that install packages, modify system configuration, reboot, or disrupt the user. " +
                "Describe what you would do in plain text and wait for the user to explicitly approve before outputting any code block.\n" +
                "Inline code (`` ` ``) does not auto-run.\n";
        }
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

function mimeForImage(filePath) {
    var ext = filePath.split(".").pop().toLowerCase();
    var mimeMap = {
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "webp": "image/webp", "bmp": "image/bmp",
        "svg": "image/svg+xml"
    };
    return mimeMap[ext] || "application/octet-stream";
}

function isImageFile(filePath) {
    var ext = filePath.split(".").pop().toLowerCase();
    return ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"].indexOf(ext) !== -1;
}

function stripCodeBlocks(text) {
    return text.replace(/\n?```\w*\n[\s\S]*?```\n?/g, "\n");
}

function stripLeadingTimestamp(text) {
    if (!text) return "";
    // Matches [YYYY-MM-DDTHH:MM:SS-HH:MM]: or similar variations
    return text.replace(/^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?[+-]\d{2}:\d{2}\]:\s*/, "");
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

function decodeHtmlEntities(text) {
    if (!text) return "";
    return text.replace(/&amp;/g, "&")
               .replace(/&quot;/g, '"')
               .replace(/&#39;/g, "'")
               .replace(/&#x27;/g, "'")
               .replace(/&lt;/g, "<")
               .replace(/&gt;/g, ">")
               .replace(/&nbsp;/g, " ")
               .replace(/&#(\d+);/g, function(match, dec) {
                   return String.fromCharCode(dec);
               })
               .replace(/&#x([0-9a-f]+);/gi, function(match, hex) {
                   return String.fromCharCode(parseInt(hex, 16));
               });
}

function isSearchConfigured(options) {
    if (!options) return false;
    var provider = options.webSearchProvider || "ollama";
    
    if (provider === "duckduckgo") {
        return true;
    } else if (provider === "searxng") {
        return !!(options.searxngUrl && options.searxngUrl.length > 0);
    } else if (provider === "ollama") {
        return !!(options.ollamaSearchApiKey && options.ollamaSearchApiKey.length > 0);
    }
    return false;
}

// performWebSearch orchestrates search via the selected provider adapter
function performWebSearch(options, query, maxResults, callback) {
    var provider = options.webSearchProvider || "ollama";
    var adapter = SearchAdapters.getSearchAdapter(provider);
    if (adapter && typeof adapter.performWebSearch === "function") {
        adapter.performWebSearch(options, query, maxResults, callback);
    } else {
        callback(i18n("Search provider %1 not supported", provider), null);
    }
}

// --- Adapter pass-throughs ---

function getAdapter(apiType) {
    return Adapters.getAdapter(apiType);
}

function getPresets(apiType) {
    return Adapters.getAdapter(apiType).presets;
}

function getCapabilities(apiType) {
    return Adapters.getAdapter(apiType).capabilities;
}

// Wallet entry name for an (adapter, provider) slot. Falls back to the adapter
// id when providerName is blank so adapters without presets still get a stable
// slot.
function apiKeySlot(apiType, providerName) {
    var t = apiType || "openai";
    var p = (providerName && providerName.length > 0) ? providerName : t;
    return "apiKey:" + t + ":" + p;
}

function getAdapterChoices() {
    return [
        { id: "openai",    name: i18n("OpenAI-compatible") },
        { id: "anthropic", name: i18n("Anthropic") },
        { id: "gemini",    name: i18n("Google Gemini") }
    ];
}

function getAllPresets() {
    return Adapters.getAllPresets();
}

function fetchModels(apiType, endpoint, apiKey, usesResponsesAPI, callback) {
    var ad = Adapters.getAdapter(apiType);
    // openai's fetchModels takes the extra flag; other adapters ignore it.
    if (apiType === "openai") {
        return ad.fetchModels(endpoint, apiKey, !!usesResponsesAPI, callback);
    }
    return ad.fetchModels(endpoint, apiKey, callback);
}

function buildTools(apiType, options) {
    if (options) {
        options.searchConfigured = isSearchConfigured(options);
    }
    return Adapters.getAdapter(apiType).buildTools(options);
}

function buildContentArray(apiType, text, attachments, usesResponsesAPI) {
    var ad = Adapters.getAdapter(apiType);
    if (apiType === "openai") {
        return ad.buildContentArray(text, attachments, !!usesResponsesAPI);
    }
    return ad.buildContentArray(text, attachments);
}

function sendStreaming(apiType, opts) {
    return Adapters.getAdapter(apiType).sendStreaming(opts);
}
