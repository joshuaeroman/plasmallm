/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Provider-neutral helpers + thin pass-throughs to the active adapter.
// Wire-level logic (request shapes, SSE parsing, tool schemas) lives in
// adapters/<id>.js and is selected via Plasmoid.configuration.apiType.

.import "adapters/index.js" as Adapters
.import "toolManager.js" as ToolManager
.import "driverManager.js" as DriverManager
.import "walletCore.js" as WalletCore
.import "skills.js" as Skills
.import "memory.js" as Memory

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

function _tr(options, str) {
    var fn = (options && typeof options.i18n === "function") ? options.i18n : (typeof i18n === "function" ? i18n : null);
    if (fn) {
        var args = Array.prototype.slice.call(arguments, 1);
        return fn.apply(null, args);
    }
    var res = str;
    for (var i = 2; i < arguments.length; i++) {
        res = res.replace(new RegExp("%" + (i - 1), "g"), arguments[i]);
    }
    return res;
}

// Default system prompt template. Users may edit this wholesale; any of the
// {{placeholder}} tags below can be moved, duplicated, or removed.
var DEFAULT_SYSTEM_PROMPT_TEMPLATE = "You are a helpful assistant embedded in the user's Linux desktop.\n" +
    "\n" +
    "## System\n" +
    "{{system_info}}\n" +
    "\n" +
    "General-purpose assistant. Keep responses short (~1 paragraph) unless more detail is needed to properly answer. Be concise and conversational. Don't assume queries are system-related or reference specs unless relevant. Always use the `~` alias instead of absolute paths when referring to the user's home directory in tool calls or text.\n" +
    "\n" +
    "{{session_multiplexer}}\n" +
    "{{approval_mode}}\n" +
    "{{skills}}\n" +
    "{{memories}}\n" +
    "{{tools}}\n" +
    "{{driving_instructions}}";

function getLocalizedDefaultSystemPromptTemplate(i18nFn) {
    var fn = (typeof i18nFn === "function") ? i18nFn : (typeof i18n === "function" ? i18n : function(s) { return s; });
    return fn("You are a helpful assistant embedded in the user's Linux desktop.") + "\n\n" +
        "## System\n" +
        "{{system_info}}\n\n" +
        fn("General-purpose assistant. Keep responses short (~1 paragraph) unless more detail is needed to properly answer. Be concise and conversational. Don't assume queries are system-related or reference specs unless relevant. Always use the `~` alias instead of absolute paths when referring to the user's home directory in tool calls or text.") + "\n\n" +
        "{{session_multiplexer}}\n" +
        "{{approval_mode}}\n" +
        "{{skills}}\n" +
        "{{memories}}\n" +
        "{{tools}}\n" +
        "{{driving_instructions}}";
}

function buildSystemInfoSection(sysInfo, options) {
    var loc = options && options.localizeSystemPrompt;
    var lines = [];
    if (options && options.sysInfoDateTime) lines.push("- " + (loc ? _tr(options, "Current Date & Time: ") : "Current Date & Time: ") + localISODateTime());
    if (sysInfo.hostname) lines.push("- " + (loc ? _tr(options, "Hostname: ") : "Hostname: ") + sysInfo.hostname);
    if (sysInfo.osRelease) lines.push("- " + (loc ? _tr(options, "OS: ") : "OS: ") + sysInfo.osRelease);
    if (sysInfo.kernel) lines.push("- " + (loc ? _tr(options, "Kernel: ") : "Kernel: ") + sysInfo.kernel);
    if (sysInfo.desktop) lines.push("- " + (loc ? _tr(options, "Desktop: ") : "Desktop: ") + sysInfo.desktop);
    if (sysInfo.shell) lines.push("- " + (loc ? _tr(options, "Shell: ") : "Shell: ") + sysInfo.shell);
    if (sysInfo.locale) lines.push("- " + (loc ? _tr(options, "Locale: ") : "Locale: ") + sysInfo.locale);
    if (sysInfo.user) lines.push("- " + (loc ? _tr(options, "User: ") : "User: ") + sysInfo.user);
    if (sysInfo.cpu) lines.push("- " + (loc ? _tr(options, "CPU: ") : "CPU: ") + sysInfo.cpu);
    if (sysInfo.cpuCores) lines.push("- " + (loc ? _tr(options, "CPU Cores: ") : "CPU Cores: ") + sysInfo.cpuCores);
    if (sysInfo.cpuArch) lines.push("- " + (loc ? _tr(options, "Architecture: ") : "Architecture: ") + sysInfo.cpuArch);
    if (sysInfo.gpu) lines.push("- " + (loc ? _tr(options, "GPU: ") : "GPU: ") + sysInfo.gpu);
    if (sysInfo.memory) lines.push("- " + (loc ? _tr(options, "Memory:") : "Memory:") + "\n" + sysInfo.memory);
    if (sysInfo.disk) lines.push("- " + (loc ? _tr(options, "Block Devices:") : "Block Devices:") + "\n" + sysInfo.disk);
    if (sysInfo.network) lines.push("- " + (loc ? _tr(options, "Network Interfaces:") : "Network Interfaces:") + "\n" + sysInfo.network);
    return lines.join("\n");
}

function buildSessionMultiplexerSection(options) {
    if (!options || !options.sessionMultiplexer) return "";
    var parts = options.sessionMultiplexer.split(": ");
    var be = parts[0] || "tmux";
    var sess = parts[1] || "plasmallm";
    var attachCmd = be === "tmux" ? ("tmux new-session -A -s " + sess) : ("screen -xRR " + sess);
    if (options && options.localizeSystemPrompt) {
        return "## " + _tr(options, "Session Multiplexer") + "\n" +
            _tr(options, "Commands run inside a persistent **%1** session named `%2`. Working directory, exported variables, and background jobs persist across calls. Avoid `clear`, `reset`, `exit`, and full-screen TUIs (`htop`, `vim`); they would damage the shared shell. The user can attach with `%3`.", be, sess, attachCmd);
    }
    return "## Session Multiplexer\n" +
        "Commands run inside a persistent **" + be + "** session named `" + sess + "`. " +
        "Working directory, exported variables, and background jobs persist across calls. " +
        "Avoid `clear`, `reset`, `exit`, and full-screen TUIs (`htop`, `vim`); they would damage the shared shell. " +
        "The user can attach with `" + attachCmd + "`.";
}

function buildApprovalModeSection(options) {
    if (!options || !options.autoMode) return "";
    if (options && options.localizeSystemPrompt) {
        return "## " + _tr(options, "Skip approvals mode is ACTIVE") + "\n" +
            _tr(options, "Commands run AND their output is automatically shared back to you. You are in an agentic loop. Prefer read-only commands unless the user explicitly requests a write operation.");
    }
    return "## Skip approvals mode is ACTIVE\n" +
        "Commands run AND their output is automatically shared back to you. " +
        "You are in an agentic loop. Prefer read-only commands unless the user explicitly requests a write operation.";
}

// Renders a user-editable system prompt template. {{placeholders}} are replaced with
// dynamic content; unknown or empty placeholders resolve to "". Critical runtime
// sections (driving instructions, skip-approvals mode) are appended verbatim if
// the user's template omits them while they are active, so features never break.
function buildSystemPrompt(sysInfo, template, options) {
    sysInfo = sysInfo || {};
    options = options || {};

    var drivingText = DriverManager.getDrivingInstructions() || "";
    var systemInfoText = buildSystemInfoSection(sysInfo, options);
    var sessionText = buildSessionMultiplexerSection(options);
    var approvalText = buildApprovalModeSection(options);
    var trFn = (options && typeof options.i18n === "function") ? options.i18n : (typeof i18n === "function" ? i18n : null);
    var toolsText = options.toolsConfig ? ToolManager.buildSystemPromptSection(options.toolsConfig, trFn) : "";
    var skillsText = "";
    if (options.toolsConfig && options.toolsConfig.skillsEnabled) {
        skillsText = Skills.buildSystemPromptSection(
            options.toolsConfig.loadedSkills || [],
            options.toolsConfig.skillsDisabledList,
            options.toolsConfig.activeSkills || []
        );
    }
    var memoryText = "";
    if (options.toolsConfig) {
        memoryText = Memory.renderSection(options.toolsConfig.memoryPhrases);
    }

    var vars = {
        system_info: systemInfoText,
        tools: toolsText,
        skills: skillsText,
        memories: memoryText,
        session_multiplexer: sessionText,
        approval_mode: approvalText,
        driving_instructions: drivingText,
        datetime: options.sysInfoDateTime ? localISODateTime() : "",
        os: sysInfo.osRelease || "",
        kernel: sysInfo.kernel || "",
        hostname: sysInfo.hostname || "",
        desktop: sysInfo.desktop || "",
        shell: sysInfo.shell || "",
        user: sysInfo.user || "",
        home: sysInfo.userHome || "",
        locale: sysInfo.locale || "",
        cpu: sysInfo.cpu || "",
        cpu_cores: sysInfo.cpuCores || "",
        cpu_arch: sysInfo.cpuArch || "",
        gpu: sysInfo.gpu || "",
        memory: sysInfo.memory || "",
        disk: sysInfo.disk || "",
        network: sysInfo.network || ""
    };

    var tpl = (template && template.trim().length > 0) ? template.trim() : DEFAULT_SYSTEM_PROMPT_TEMPLATE;
    var tplLower = tpl.toLowerCase();

    var out = tpl.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, function(match, name) {
        var key = name.toLowerCase();
        return vars.hasOwnProperty(key) ? vars[key] : "";
    });

    if (drivingText && tplLower.indexOf("{{driving_instructions}}") === -1 && tplLower.indexOf("desktop automation") === -1) {
        out += "\n\n" + drivingText;
    }
    if (approvalText && tplLower.indexOf("{{approval_mode}}") === -1 && tplLower.indexOf("skip approvals mode") === -1) {
        out += "\n\n" + approvalText;
    }
    // Skills are force-appended like the critical runtime sections above:
    // without the index the model can never discover the skill tool's purpose.
    if (skillsText && tplLower.indexOf("{{skills}}") === -1 && tplLower.indexOf("<available_skills>") === -1) {
        out += "\n\n" + skillsText;
    }

    out = out.replace(/\n{3,}/g, "\n\n").trim();

    return out + "\n\nEND OF SYSTEM PROMPT\n";
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

// Breeze icon name for a non-image attachment, by extension.
function iconForFile(filePath) {
    var ext = filePath.split(".").pop().toLowerCase();
    if (ext === "pdf") return "application-pdf";
    if (["zip", "tar", "gz", "bz2", "xz", "7z", "rar"].indexOf(ext) !== -1) return "application-zip";
    if (["mp3", "wav", "ogg", "flac", "m4a", "opus"].indexOf(ext) !== -1) return "audio-x-generic";
    if (["mp4", "mkv", "webm", "mov", "avi"].indexOf(ext) !== -1) return "video-x-generic";
    if (["md", "markdown"].indexOf(ext) !== -1) return "text-markdown";
    return "text-x-generic";
}

function stripCodeBlocks(text) {
    return text.replace(/\n?```\w*\n[\s\S]*?```\n?/g, "\n");
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
    } else if (provider === "exa") {
        return !!(options.exaApiKey && options.exaApiKey.trim().length > 0);
    } else if (provider === "searxng") {
        return !!(options.searxngUrl && options.searxngUrl.length > 0);
    } else if (provider === "ollama") {
        return !!(options.ollamaSearchApiKey && options.ollamaSearchApiKey.trim().length > 0);
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

// Wallet entry names live in walletCore.js (v2| pipe names; v1/ and apiKey:* are read fallbacks).
var KEY_SLOT_SCHEME_VERSION = WalletCore.KEY_SLOT_SCHEME_VERSION;
var LEGACY_SEARCH_KEY_MAP = WalletCore.LEGACY_SEARCH_KEY_MAP;

function normalizeEndpoint(endpoint) { return WalletCore.normalizeEndpoint(endpoint); }
function slotApiType(apiType, geminiAuthMethod) { return WalletCore.slotApiType(apiType, geminiAuthMethod); }
function slotProviderPart(providerName, endpoint, apiType, geminiAuthMethod) {
    return WalletCore.slotProviderPart(providerName, endpoint, apiType, geminiAuthMethod);
}
function chatKeySlot(profileId, apiType, providerName, endpoint, geminiAuthMethod) {
    return WalletCore.chatKeySlot(profileId, apiType, providerName, endpoint, geminiAuthMethod);
}
function searchKeySlot(searchProvider) { return WalletCore.searchKeySlot(searchProvider); }
function searchLegacyKeySlots(searchProvider) { return WalletCore.searchLegacyKeySlots(searchProvider); }
function sttKeySlot(providerName, endpoint) { return WalletCore.sttKeySlot(providerName, endpoint); }
function sttLegacyKeySlots(providerName, endpoint) { return WalletCore.sttLegacyKeySlots(providerName, endpoint); }
function currentKeySlot(activeProfileId, apiType, providerName, endpoint, geminiAuthMethod) {
    return WalletCore.currentKeySlot(activeProfileId, apiType, providerName, endpoint, geminiAuthMethod);
}
function legacyProviderKeySlot(apiType, providerName, endpoint, geminiAuthMethod) {
    return WalletCore.legacyProviderKeySlot(apiType, providerName, endpoint, geminiAuthMethod);
}
function legacyProfileKeySlot(profileId) { return WalletCore.legacyProfileKeySlot(profileId); }
function legacyKeySlots(activeProfileId, apiType, providerName, endpoint, geminiAuthMethod) {
    return WalletCore.legacyKeySlots(activeProfileId, apiType, providerName, endpoint, geminiAuthMethod);
}
function apiKeySlot(apiType, providerName) { return WalletCore.apiKeySlot(apiType, providerName); }
function profileKeySlot(profileId) { return WalletCore.profileKeySlot(profileId); }
function providerKeySlot(apiType, providerName, endpoint, geminiAuthMethod) {
    return WalletCore.providerKeySlot(apiType, providerName, endpoint, geminiAuthMethod);
}
function compositeKeySlot(profileId, apiType, providerPart) {
    return WalletCore.compositeKeySlot(profileId, apiType, providerPart);
}
function isLegacyProfileOnlySlot(name) { return WalletCore.isLegacyProfileOnlySlot(name); }
function isProviderOnlyChatSlot(name) { return WalletCore.isProviderOnlyChatSlot(name); }
function parseProviderOnlySlot(name) { return WalletCore.parseProviderOnlySlot(name); }
function parseLegacyProfileOnlySlot(name) { return WalletCore.parseLegacyProfileOnlySlot(name); }
function modelCacheSlot(apiType, providerName, endpoint, activeProfileId, geminiAuthMethod) {
    return WalletCore.modelCacheSlot(apiType, providerName, endpoint, activeProfileId, geminiAuthMethod);
}
function clampGeminiApiVariant(variant, geminiAuthMethod, vertexAuthType) {
    return WalletCore.clampGeminiApiVariant(variant, geminiAuthMethod, vertexAuthType);
}
function resolvedApiType(apiType, geminiApiVariant, geminiAuthMethod, vertexAuthType) {
    return WalletCore.resolvedApiType(apiType, geminiApiVariant, geminiAuthMethod, vertexAuthType);
}

function getAdapterChoices() {
    return [
        { id: "openai",    name: _tr(null, "OpenAI-compatible") },
        { id: "anthropic", name: _tr(null, "Anthropic") },
        { id: "gemini",    name: _tr(null, "Google Gemini") },
        { id: "exa",       name: _tr(null, "Exa") }
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

// GREEK LETTERS AND MATH SYMBOLS FOR LATEX CHARACTER REPLACEMENT
const GREEK_LOWER = {
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
    "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
    "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
    "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ",
    "chi": "χ", "psi": "ψ", "omega": "ω", "varepsilon": "ϵ", "vartheta": "ϑ",
    "varphi": "ϕ"
};

const GREEK_UPPER = {
    "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Epsilon": "Ε",
    "Zeta": "Ζ", "Eta": "Η", "Theta": "Θ", "Iota": "Ι", "Kappa": "Κ",
    "Lambda": "Λ", "Mu": "Μ", "Nu": "Ν", "Xi": "Ξ", "Pi": "Π",
    "Rho": "Ρ", "Sigma": "Σ", "Tau": "Τ", "Upsilon": "Υ", "Phi": "Φ",
    "Chi": "Χ", "Psi": "Ψ", "Omega": "Ω"
};

const MATH_SYMBOLS = {
    "infty": "∞", "pm": "±", "times": "×", "div": "÷", "neq": "≠",
    "leq": "≤", "geq": "≥", "approx": "≈", "equiv": "≡", "cong": "≅",
    "propto": "∝", "partial": "∂", "nabla": "∇", "sum": "∑", "prod": "∏",
    "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮", "forall": "∀",
    "exists": "∃", "emptyset": "∅", "in": "∈", "notin": "∉", "subset": "⊂",
    "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "cup": "∪", "cap": "∩",
    "cdot": "·", "sqrt": "√", "hbar": "ℏ", "rightarrow": "→", "to": "→",
    "leftarrow": "←", "uparrow": "↑", "downarrow": "↓", "leftrightarrow": "↔",
    "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔",
    "sin": "sin", "cos": "cos", "tan": "tan", "log": "log", "ln": "ln",
    "deg": "°", "partial": "∂"
};

const SUPERSCRIPTS = {
    "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "x": "ˣ", "y": "ʸ", "i": "ⁱ", "j": "ʲ"
};

const SUBSCRIPTS = {
    "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
    "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "i": "ᵢ", "j": "ⱼ"
};

// Baseline-aligned 2D Text Box Model for ASCII Math Layout
function TextBox(lines, baseline) {
    this.lines = lines || [];
    this.height = this.lines.length;
    this.baseline = baseline || 0;
    this.width = 0;
    for (var i = 0; i < this.height; i++) {
        if (this.lines[i].length > this.width) {
            this.width = this.lines[i].length;
        }
    }
}

function padString(str, width, align) {
    if (str.length >= width) return str;
    var diff = width - str.length;
    if (align === "center") {
        var left = Math.floor(diff / 2);
        var right = diff - left;
        return " ".repeat(left) + str + " ".repeat(right);
    } else if (align === "right") {
        return " ".repeat(diff) + str;
    } else {
        return str + " ".repeat(diff);
    }
}

function hConcat(boxes) {
    if (boxes.length === 0) return new TextBox([""], 0);
    if (boxes.length === 1) return boxes[0];

    var maxBaseline = 0;
    var i;
    for (i = 0; i < boxes.length; i++) {
        if (boxes[i].baseline > maxBaseline) {
            maxBaseline = boxes[i].baseline;
        }
    }

    var maxBelow = 0;
    for (i = 0; i < boxes.length; i++) {
        var below = boxes[i].height - 1 - boxes[i].baseline;
        if (below > maxBelow) {
            maxBelow = below;
        }
    }

    var totalHeight = maxBaseline + 1 + maxBelow;
    var mergedLines = [];
    for (var r = 0; r < totalHeight; r++) {
        mergedLines.push("");
    }

    for (i = 0; i < boxes.length; i++) {
        var box = boxes[i];
        var topOffset = maxBaseline - box.baseline;
        
        for (var r = 0; r < totalHeight; r++) {
            var boxRow = r - topOffset;
            if (boxRow >= 0 && boxRow < box.height) {
                var line = box.lines[boxRow];
                if (line.length < box.width) {
                    line = line + " ".repeat(box.width - line.length);
                }
                mergedLines[r] += line;
            } else {
                mergedLines[r] += " ".repeat(box.width);
            }
        }
    }

    return new TextBox(mergedLines, maxBaseline);
}

function vConcat(numBox, denBox) {
    var width = Math.max(numBox.width, denBox.width) + 2;
    var dashes = "-".repeat(width);

    var lines = [];
    var i;
    for (i = 0; i < numBox.height; i++) {
        lines.push(padString(numBox.lines[i], width, "center"));
    }
    var baselineIndex = lines.length;
    lines.push(dashes);
    for (i = 0; i < denBox.height; i++) {
        lines.push(padString(denBox.lines[i], width, "center"));
    }

    return new TextBox(lines, baselineIndex);
}

function sqrtBox(innerBox) {
    var lines = [];
    if (innerBox.height === 1) {
        var overline = " " + "_".repeat(innerBox.width);
        var content = "√" + innerBox.lines[0];
        return new TextBox([overline, content], 1);
    }
    
    var overline = "   " + "_".repeat(innerBox.width);
    lines.push(overline);
    
    for (var i = 0; i < innerBox.height; i++) {
        var prefix = "   ";
        if (i === innerBox.baseline - 1) {
            prefix = " / ";
        } else if (i === innerBox.baseline) {
            prefix = "√  ";
        }
        lines.push(prefix + innerBox.lines[i]);
    }
    
    return new TextBox(lines, innerBox.baseline + 1);
}

function parseLatexToBox(str) {
    str = str.trim();
    var pos = 0;
    
    function parseExpression() {
        var boxes = [];
        while (pos < str.length) {
            var char = str[pos];
            
            if (char === ' ' || char === '\t' || char === '\n' || char === '\r') {
                pos++;
                continue;
            }
            if (char === '}') {
                break;
            }
            
            if (char === '\\') {
                pos++;
                var cmd = "";
                while (pos < str.length && /[a-zA-Z]/.test(str[pos])) {
                    cmd += str[pos];
                    pos++;
                }
                
                if (cmd === "frac") {
                    var numBox = parseGroup();
                    var denBox = parseGroup();
                    boxes.push(vConcat(numBox, denBox));
                } else if (cmd === "sqrt") {
                    var innerBox = parseGroup();
                    boxes.push(sqrtBox(innerBox));
                } else if (cmd === "pm") {
                    boxes.push(new TextBox(["±"], 0));
                } else {
                    var symbol = "";
                    if (GREEK_LOWER.hasOwnProperty(cmd)) symbol = GREEK_LOWER[cmd];
                    else if (GREEK_UPPER.hasOwnProperty(cmd)) symbol = GREEK_UPPER[cmd];
                    else if (MATH_SYMBOLS.hasOwnProperty(cmd)) symbol = MATH_SYMBOLS[cmd];
                    else symbol = cmd;
                    
                    boxes.push(new TextBox([symbol], 0));
                }
            } else if (char === '^') {
                pos++;
                var superBox = parseGroupOrChar();
                var lastBox = boxes.pop();
                if (!lastBox) lastBox = new TextBox([""], 0);
                
                var flatSuperText = "";
                for (var j = 0; j < superBox.lines.length; j++) {
                    flatSuperText += superBox.lines[j].trim();
                }
                var replacedSuper = "";
                for (var k = 0; k < flatSuperText.length; k++) {
                    replacedSuper += SUPERSCRIPTS[flatSuperText[k]] || flatSuperText[k];
                }
                
                var newLast = hConcat([lastBox, new TextBox([replacedSuper], 0)]);
                boxes.push(newLast);
            } else if (char === '_') {
                pos++;
                var subBox = parseGroupOrChar();
                var lastBox = boxes.pop();
                if (!lastBox) lastBox = new TextBox([""], 0);
                
                var flatSubText = "";
                for (var j = 0; j < subBox.lines.length; j++) {
                    flatSubText += subBox.lines[j].trim();
                }
                var replacedSub = "";
                for (var k = 0; k < flatSubText.length; k++) {
                    replacedSub += SUBSCRIPTS[flatSubText[k]] || flatSubText[k];
                }
                
                var newLast = hConcat([lastBox, new TextBox([replacedSub], 0)]);
                boxes.push(newLast);
            } else {
                boxes.push(new TextBox([char], 0));
                pos++;
            }
        }
        
        return hConcat(boxes);
    }
    
    function parseGroup() {
        while (pos < str.length && str[pos] !== '{') {
            pos++;
        }
        if (pos >= str.length) return new TextBox([""], 0);
        pos++;
        
        var start = pos;
        var braceCount = 1;
        while (pos < str.length && braceCount > 0) {
            if (str[pos] === '{') braceCount++;
            else if (str[pos] === '}') braceCount--;
            pos++;
        }
        
        var content = str.substring(start, pos - 1);
        return parseLatexToBox(content);
    }
    
    function parseGroupOrChar() {
        if (pos < str.length && str[pos] === '{') {
            return parseGroup();
        }
        if (pos < str.length) {
            var char = str[pos];
            pos++;
            return new TextBox([char], 0);
        }
        return new TextBox([""], 0);
    }
    
    return parseExpression();
}

function replaceSymbolsInFormulaFlat(formula) {
    // 1. Fractions: \frac{num}{den} -> (num)/(den)
    var fractionRegex = /\\frac\s*\{([^}]*)\}\s*\{([^}]*)\}/g;
    while (fractionRegex.test(formula)) {
        formula = formula.replace(fractionRegex, "($1)/($2)");
    }

    // 2. Superscripts: ^{12} -> ¹² or ^2 -> ²
    formula = formula.replace(/\^\{([^}]*)\}/g, function(match, p1) {
        var res = "";
        for (var i = 0; i < p1.length; i++) {
            res += SUPERSCRIPTS[p1[i]] || p1[i];
        }
        return res;
    });
    formula = formula.replace(/\^([0-9a-zA-Z\+\-\(\)])/g, function(match, p1) {
        return SUPERSCRIPTS[p1] || ("^" + p1);
    });

    // 3. Subscripts: _{ij} -> ᵢⱼ or _1 -> ₁
    formula = formula.replace(/_\{([^}]*)\}/g, function(match, p1) {
        var res = "";
        for (var i = 0; i < p1.length; i++) {
            res += SUBSCRIPTS[p1[i]] || p1[i];
        }
        return res;
    });
    formula = formula.replace(/_([0-9a-zA-Z\+\-\(\)])/g, function(match, p1) {
        return SUBSCRIPTS[p1] || ("_" + p1);
    });

    // 4. Commands: \alpha -> α, etc.
    formula = formula.replace(/\\([a-zA-Z]+)/g, function(match, p1) {
        if (GREEK_LOWER.hasOwnProperty(p1)) return GREEK_LOWER[p1];
        if (GREEK_UPPER.hasOwnProperty(p1)) return GREEK_UPPER[p1];
        if (MATH_SYMBOLS.hasOwnProperty(p1)) return MATH_SYMBOLS[p1];
        return p1;
    });

    // Clean up curly braces and any double backslashes
    formula = formula.replace(/[\{\}]/g, "")
                     .replace(/\\/g, "");

    return formula.trim();
}

function replaceLatexSymbols(text) {
    if (!text) return "";
    
    // Temporarily replace escaped dollar and other delimiters
    text = text.replace(/\\(\$)/g, "__ESCAPED_DOLLAR__");
    text = text.replace(/\\([\\\[\]\(\)])/g, function(match, p1) {
        return "__ESCAPED_" + p1.charCodeAt(0) + "__";
    });

    // Parse block math: $$ formula $$ or \[ formula \]
    var blockRegex1 = /\$\$([\s\S]*?)\$\$/g;
    text = text.replace(blockRegex1, function(match, p1) {
        if (p1.indexOf("\\frac") !== -1 || p1.indexOf("\\sqrt") !== -1) {
            var box = parseLatexToBox(p1);
            return "\n\n```text\n" + box.lines.join("\n") + "\n```\n\n";
        }
        return "\n\n```text\n" + replaceSymbolsInFormulaFlat(p1) + "\n```\n\n";
    });
    
    var blockRegex2 = /\\\[([\s\S]*?)\\\]/g;
    text = text.replace(blockRegex2, function(match, p1) {
        if (p1.indexOf("\\frac") !== -1 || p1.indexOf("\\sqrt") !== -1) {
            var box = parseLatexToBox(p1);
            return "\n\n```text\n" + box.lines.join("\n") + "\n```\n\n";
        }
        return "\n\n```text\n" + replaceSymbolsInFormulaFlat(p1) + "\n```\n\n";
    });

    // Parse inline math: $ formula $ or \( formula \)
    var inlineRegex1 = /\$([^\s\$](?:[^\$]*?[^\s\$])?)\$/g;
    text = text.replace(inlineRegex1, function(match, p1) {
        if (p1.indexOf("\\frac") !== -1 || p1.indexOf("\\sqrt") !== -1) {
            var box = parseLatexToBox(p1);
            return "\n\n```text\n" + box.lines.join("\n") + "\n```\n\n";
        }
        return " `" + replaceSymbolsInFormulaFlat(p1) + "` ";
    });

    var inlineRegex2 = /\\\(([\s\S]*?)\\\)/g;
    text = text.replace(inlineRegex2, function(match, p1) {
        if (p1.indexOf("\\frac") !== -1 || p1.indexOf("\\sqrt") !== -1) {
            var box = parseLatexToBox(p1);
            return "\n\n```text\n" + box.lines.join("\n") + "\n```\n\n";
        }
        return " `" + replaceSymbolsInFormulaFlat(p1) + "` ";
    });

    // Restore escaped characters
    text = text.replace(/__ESCAPED_DOLLAR__/g, "$");
    text = text.replace(/__ESCAPED_(\d+)__/g, function(match, p1) {
        return String.fromCharCode(parseInt(p1, 10));
    });

    return text;
}

function base64Encode(str) {
    if (!str) return "";
    var utf8Bytes = [];
    for (var i = 0; i < str.length; i++) {
        var charcode = str.charCodeAt(i);
        if (charcode < 0x80) utf8Bytes.push(charcode);
        else if (charcode < 0x800) {
            utf8Bytes.push(0xc0 | (charcode >> 6), 
                           0x80 | (charcode & 0x3f));
        }
        else if (charcode < 0xd800 || charcode >= 0xe000) {
            utf8Bytes.push(0xe0 | (charcode >> 12), 
                           0x80 | ((charcode >> 6) & 0x3f), 
                           0x80 | (charcode & 0x3f));
        }
        else {
            i++;
            charcode = 0x10000 + (((charcode & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff));
            utf8Bytes.push(0xf0 | (charcode >> 18), 
                           0x80 | ((charcode >> 12) & 0x3f), 
                           0x80 | ((charcode >> 6) & 0x3f), 
                           0x80 | (charcode & 0x3f));
        }
    }
    
    var keyStr = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
    var output = "";
    var chr1, chr2, chr3, enc1, enc2, enc3, enc4;
    var idx = 0;
    while (idx < utf8Bytes.length) {
        chr1 = utf8Bytes[idx++];
        chr2 = idx < utf8Bytes.length ? utf8Bytes[idx++] : NaN;
        chr3 = idx < utf8Bytes.length ? utf8Bytes[idx++] : NaN;
        
        enc1 = chr1 >> 2;
        enc2 = ((chr1 & 3) << 4) | (chr2 >> 4);
        enc3 = ((chr2 & 15) << 2) | (chr3 >> 6);
        enc4 = chr3 & 63;
        
        if (isNaN(chr2)) {
            enc3 = enc4 = 64;
        } else if (isNaN(chr3)) {
            enc4 = 64;
        }
        
        output += keyStr.charAt(enc1) + keyStr.charAt(enc2) + keyStr.charAt(enc3) + keyStr.charAt(enc4);
    }
    return output;
}
