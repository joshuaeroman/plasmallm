/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Provider-neutral helpers + thin pass-throughs to the active adapter.
// Wire-level logic (request shapes, SSE parsing, tool schemas) lives in
// adapters/<id>.js and is selected via Plasmoid.configuration.apiType.

.import "adapters/index.js" as Adapters
.import "toolManager.js" as ToolManager

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

    if (options && options.sysInfoDateTime) {
        prompt += "- Current Date & Time: " + localISODateTime() + "\n";
    }

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

    prompt += "\nGeneral-purpose assistant. Keep responses short (~1 paragraph) unless more detail is needed to properly answer. Be concise and conversational. " +
        "Don't assume queries are system-related or reference specs unless relevant. " +
        "Always use the `~` alias instead of absolute paths when referring to the user's home directory in tool calls or text.\n\n";

    if (options && !options.commandToolEnabled) {
        prompt += "## Code blocks\n" +
            "Standard markdown code blocks (e.g., ```bash) are for display only and are NOT interactive. " +
            "Do NOT ask the user to click or run them. ";
    }

    if (options && options.sessionMultiplexer) {
        var parts = options.sessionMultiplexer.split(": ");
        var be = parts[0] || "tmux";
        var sess = parts[1] || "plasmallm";
        var attachCmd = be === "tmux" ? ("tmux new-session -A -s " + sess) : ("screen -xRR " + sess);
        prompt += "\n## Session Multiplexer\n" +
            "Commands run inside a persistent **" + be + "** session named `" + sess + "`. " +
            "Working directory, exported variables, and background jobs persist across calls. " +
            "Avoid `clear`, `reset`, `exit`, and full-screen TUIs (`htop`, `vim`); they would damage the shared shell. " +
            "The user can attach with `" + attachCmd + "`.\n";
    }

    if (options && options.autoMode) {
        prompt += "\n## Skip approvals mode is ACTIVE\n" +
            "Commands run AND their output is automatically shared back to you. " +
            "You are in an agentic loop. Prefer read-only commands unless the user explicitly requests a write operation.\n";
    }

    if (options && options.toolsConfig) {
        prompt += ToolManager.buildSystemPromptSection(options.toolsConfig);
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

function profileKeySlot(profileId) {
    return "apiKey:profile:" + profileId;
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

function fetchModels(apiType, endpoint, apiKey, usesResponsesAPI, opts, callback) {
    // If the caller didn't pass opts (it was introduced later)
    if (typeof opts === "function") {
        callback = opts;
        opts = null;
    }

    var ad = Adapters.getAdapter(apiType);
    // openai's fetchModels takes the extra flag; other adapters ignore it.
    if (apiType === "openai") {
        return ad.fetchModels(endpoint, apiKey, !!usesResponsesAPI, callback);
    }
    return ad.fetchModels(endpoint, apiKey, opts, callback);
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
