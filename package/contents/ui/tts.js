/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.import "ttsAdapters/index.js" as TtsAdapters

function _i18n(str, arg1, arg2) {
    if (typeof i18n === "function") {
        if (arg2 !== undefined)
            return i18n(str, arg1, arg2);
        if (arg1 !== undefined)
            return i18n(str, arg1);
        return i18n(str);
    }
    var res = str;
    if (arg1 !== undefined)
        res = res.replace(/%1/g, String(arg1));
    if (arg2 !== undefined)
        res = res.replace(/%2/g, String(arg2));
    return res;
}

function getTtsConnection(config) {
    if (!config)
        return null;
    return {
        enabled: !!config.ttsEnabled,
        autoRead: !!config.ttsAutoRead,
        autoReadOnlyVoicePrompted: !!config.ttsAutoReadOnlyVoicePrompted,
        styleHint: config.ttsStyleHint || "",
        backend: config.ttsBackend || "spd_say",
        providerName: config.ttsProviderName || "",
        endpoint: config.ttsApiEndpoint || "",
        model: config.ttsModelName || "",
        voice: config.ttsVoice || "",
        responseFormat: config.ttsResponseFormat || "",
        rate: config.ttsRate || 0,
        pitch: config.ttsPitch || 0,
        language: config.ttsLanguage || "",
        cliBinary: config.ttsCliBinary || "spd-say",
        cliTemplate: config.ttsCliTemplate || "",
        cliExtraArgs: config.ttsCliExtraArgs || ""
    };
}

function isTtsConfigured(config) {
    var c = getTtsConnection(config);
    if (!c)
        return false;
    var adapter = TtsAdapters.get(c.backend);
    if (adapter && typeof adapter.isConfigured === "function")
        return adapter.isConfigured(c);
    if (!c.enabled)
        return false;
    return true;
}

var KNOWN_GEMINI_VOICES = [
    "Zephyr", "Puck", "Charon", "Kore", "Fenrir", "Leda", "Orus", "Aoede",
    "Callirrhoe", "Autonoe", "Enceladus", "Iapetus", "Umbriel", "Algieba",
    "Despina", "Erinome", "Algenib", "Rasalgethi", "Laomedeia", "Achernar",
    "Alnilam", "Schedar", "Gacrux", "Pulcherrima", "Achird", "Zubenelgenubi",
    "Vindemiatrix", "Sadachbia", "Sadaltager", "Sulafat"
];

var KNOWN_OPENAI_VOICES = [
    "alloy", "echo", "fable", "onyx", "nova", "shimmer"
];

function knownGeminiVoices() {
    return KNOWN_GEMINI_VOICES.slice();
}

function knownOpenAiVoices() {
    return KNOWN_OPENAI_VOICES.slice();
}

function providerPresets() {
    return [
        {
            name: "OpenRouter",
            url: "https://openrouter.ai/api/v1",
            model: "google/gemini-3.8-flash-lite-tts",
            voice: "Zephyr",
            responseFormat: "pcm"
        },
        {
            name: "OpenAI",
            url: "https://api.openai.com/v1",
            model: "tts-1",
            voice: "alloy",
            responseFormat: "mp3"
        },
        {
            name: "Custom",
            url: "",
            model: "",
            voice: "",
            responseFormat: "mp3"
        }
    ];
}

function backendChoices() {
    return TtsAdapters.list();
}

function defaultKnownModels() {
    return [
        "google/gemini-3.8-flash-lite-tts",
        "openai/tts-1",
        "openai/tts-1-hd",
        "tts-1",
        "tts-1-hd"
    ];
}

function fetchModels(endpoint, apiKey, backendId, callback) {
    var adapter = TtsAdapters.get(backendId || "openai_speech");
    if (!adapter || typeof adapter.fetchModels !== "function") {
        callback(_i18n("TTS backend does not support model listing"), null);
        return;
    }
    adapter.fetchModels(endpoint, apiKey, callback);
}

/**
 * Sanitize and prepare markdown text for speech synthesis.
 * Strips thought blocks, converts links, and summarizes large code blocks
 * while preserving short code snippets (<= 3 lines, <= 80 chars).
 *
 * @param {string} text
 * @returns {string} cleaned plain text
 */
function cleanTextForSpeech(text) {
    if (!text || typeof text !== "string")
        return "";

    var s = text;

    // Strip thought / thinking blocks completely (preserve line boundary)
    s = s.replace(/<thought[\s\S]*?<\/thought>/gi, "\n");
    s = s.replace(/<think[\s\S]*?<\/think>/gi, "\n");

    // Handle code blocks (```lang\n...\n```)
    s = s.replace(/```(?:[a-zA-Z0-9_-]*)\n([\s\S]*?)```/g, function(match, code) {
        var trimmed = (code || "").trim();
        if (!trimmed.length)
            return " ";
        var lines = trimmed.split("\n");
        // Allow short snippets (<= 3 lines and <= 80 characters) to be read
        if (lines.length <= 3 && trimmed.length <= 80)
            return " " + trimmed + " ";
        return " [code block] ";
    });

    // Remove images: ![alt](url)
    s = s.replace(/!\[[^\]]*\]\([^)]+\)/g, " ");

    // Convert links: [text](url) -> text
    s = s.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");

    // Inline code: `code` -> code
    s = s.replace(/`([^`]+)`/g, "$1");

    // Headers: # Header -> Header. (allow leading spaces)
    s = s.replace(/^[ \t]*#{1,6}\s+(.+)$/gm, "$1. ");

    // Blockquotes: > quote -> quote
    s = s.replace(/^[ \t]*>\s*(.+)$/gm, "$1 ");

    // Bold / italic / strikethrough
    s = s.replace(/\*\*([^*]+)\*\*/g, "$1");
    s = s.replace(/\*([^*]+)\*/g, "$1");
    s = s.replace(/__([^_]+)__/g, "$1");
    s = s.replace(/_([^_]+)_/g, "$1");
    s = s.replace(/~~([^~]+)~~/g, "$1");

    // Strip HTML tags (except style hints, which are applied after this step)
    s = s.replace(/<[^>]+>/g, " ");

    // Decode basic HTML entities
    s = s.replace(/&amp;/g, "&")
         .replace(/&lt;/g, "<")
         .replace(/&gt;/g, ">")
         .replace(/&quot;/g, '"')
         .replace(/&#39;/g, "'")
         .replace(/&nbsp;/g, " ");

    // Collapse multiple spaces and newlines
    s = s.replace(/[ \t\r\n]+/g, " ").trim();

    return s;
}

/**
 * Apply speech style/tone hints to the cleaned text.
 * E.g. `<sarcastic>`, `[whispering]`, `<speak><prosody pitch="+10%">{text}</prosody></speak>`
 *
 * @param {string} cleanedText
 * @param {string} styleHint
 * @returns {string} styled text
 */
function applyStyleHint(cleanedText, styleHint) {
    if (!cleanedText || !cleanedText.length)
        return "";

    var hint = String(styleHint || "").trim();
    if (!hint.length)
        return cleanedText;

    // Explicit placeholder: {text}
    if (hint.indexOf("{text}") >= 0)
        return hint.replace(/\{text\}/g, cleanedText);

    // Single opening XML tag: <sarcastic> -> <sarcastic>text</sarcastic>
    var tagMatch = hint.match(/^<([a-zA-Z0-9_-]+)>$/);
    if (tagMatch) {
        var tag = tagMatch[1];
        return "<" + tag + ">" + cleanedText + "</" + tag + ">";
    }

    // Bracketed speech tag: [whispering] -> [whispering] text
    if (/^\[[a-zA-Z0-9_\s-]+\]$/.test(hint)) {
        return hint + " " + cleanedText;
    }

    // Single identifier token without tags: sarcastic -> <sarcastic>text</sarcastic>
    if (/^[a-zA-Z0-9_-]+$/.test(hint)) {
        return "<" + hint + ">" + cleanedText + "</" + hint + ">";
    }

    // Full XML/SSML structure, e.g. <speak>...</speak>
    if (/^<[a-zA-Z0-9_-]+[\s\S]*>$/.test(hint)) {
        return hint + " " + cleanedText;
    }

    // Natural language style hints (e.g. "fake russian voice") steer the LLM's text
    // generation via the system prompt rather than prepending literal words to audio synthesis.
    return cleanedText;
}

/**
 * Full preparation pipeline: cleans text and applies style hint.
 *
 * @param {string} rawText
 * @param {string} [styleHint]
 * @returns {string} prepared text
 */
function prepareTextForSpeech(rawText, styleHint) {
    var cleaned = cleanTextForSpeech(rawText);
    if (!cleaned.length)
        return "";
    return applyStyleHint(cleaned, styleHint);
}

/**
 * Build the command to stop speech playback immediately.
 * @param {string} [backendId]
 * @returns {string}
 */
function buildStopCommand(backendId) {
    var adapter = TtsAdapters.get(backendId);
    if (adapter && typeof adapter.buildStopCommand === "function")
        return adapter.buildStopCommand();
    return "pkill -f '/tmp/plasmallm_tts' 2>/dev/null; spd-say -S 2>/dev/null";
}

/**
 * Speak text using the configured TTS backend.
 *
 * @param {object} opts
 * @param {object} opts.config
 * @param {string} opts.text
 * @param {string} [opts.apiKey]
 * @param {function} opts.runCommand  function(cmd, callback)
 * @param {function} opts.callback    function(err, result)
 */
function speak(opts) {
    var callback = (opts && opts.callback) || function() {};
    var onReady = (opts && opts.onReady) || null;
    function notifyReady() {
        if (typeof onReady === "function") {
            try { onReady(); } catch (e) {}
            onReady = null;
        }
    }

    var config = opts && opts.config;
    var conn = getTtsConnection(config);

    if (!conn || !isTtsConfigured(config)) {
        notifyReady();
        callback(_i18n("Text-to-speech is not configured"), null);
        return;
    }

    var adapter = TtsAdapters.get(conn.backend);
    if (!adapter) {
        notifyReady();
        callback(_i18n("Unknown TTS backend: %1", conn.backend), null);
        return;
    }

    var preparedText = prepareTextForSpeech(opts.text, conn.styleHint);
    if (!preparedText.length) {
        notifyReady();
        callback(_i18n("No speech content to read aloud"), null);
        return;
    }

    if (typeof opts.runCommand !== "function") {
        notifyReady();
        callback(_i18n("TTS command runner is not available"), null);
        return;
    }

    var cmd;
    try {
        cmd = adapter.buildCommand({
            text: preparedText,
            endpoint: conn.endpoint,
            apiKey: opts.apiKey || "",
            model: conn.model,
            voice: conn.voice,
            responseFormat: conn.responseFormat,
            rate: conn.rate,
            pitch: conn.pitch,
            language: conn.language,
            cliBinary: conn.cliBinary,
            cliTemplate: conn.cliTemplate,
            extraArgs: conn.cliExtraArgs
        });
    } catch (buildErr) {
        notifyReady();
        callback(buildErr.message || String(buildErr), null);
        return;
    }

    if (!cmd || !cmd.length) {
        notifyReady();
        callback(_i18n("Could not build TTS command"), null);
        return;
    }

    // Two-phase execution (synthesize -> onReady -> playback) for endpoint backends
    if (cmd && cmd.synthesizeCmd && cmd.playCmd) {
        opts.runCommand(cmd.synthesizeCmd, function(synErr, synProc) {
            if (synErr) {
                notifyReady();
                callback(synErr, null);
                return;
            }
            synProc = synProc || {};
            if (typeof adapter.parseResult === "function") {
                var synParsed = adapter.parseResult(synProc.stdout, synProc.stderr, synProc.exitCode);
                if (synParsed && synParsed.err) {
                    notifyReady();
                    callback(synParsed.err, null);
                    return;
                }
            }

            if (typeof opts.isCancelled === "function" && opts.isCancelled()) {
                notifyReady();
                return;
            }

            // Audio has returned from endpoint and is ready on disk!
            // Signal ready NOW so chat bubble displays at the exact moment playback starts.
            notifyReady();

            opts.runCommand(cmd.playCmd, function(playErr, playProc) {
                if (playErr) {
                    callback(playErr, null);
                    return;
                }
                playProc = playProc || {};
                callback(null, { success: true });
            });
        }, notifyReady);
        return;
    }

    opts.runCommand(cmd, function(runErr, proc) {
        if (runErr) {
            notifyReady();
            callback(runErr, null);
            return;
        }
        proc = proc || {};
        if (typeof adapter.parseResult === "function") {
            var parsed = adapter.parseResult(proc.stdout, proc.stderr, proc.exitCode);
            if (parsed && parsed.err) {
                notifyReady();
                callback(parsed.err, null);
                return;
            }
        }
        notifyReady();
        callback(null, { success: true });
    }, notifyReady);
}
