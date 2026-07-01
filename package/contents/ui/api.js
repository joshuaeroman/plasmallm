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

    var drivingInstructions = DriverManager.getDrivingInstructions();
    var responseLengthInstruction = "Keep responses short (~1 paragraph) unless more detail is needed to properly answer. Be concise and conversational.";
    if (drivingInstructions && drivingInstructions.trim().length > 0) {
        responseLengthInstruction = "Be concise and conversational in standard chat. However, when automating the desktop, prioritizing thorough visual analysis and planning is essential; explain your observations in detail.";
    }

    prompt += "\nGeneral-purpose assistant. " + responseLengthInstruction + " " +
        "Don't assume queries are system-related or reference specs unless relevant. " +
        "Always use the `~` alias instead of absolute paths when referring to the user's home directory in tool calls or text.\n\n";


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

    if (drivingInstructions) {
        prompt += drivingInstructions + "\n";
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
