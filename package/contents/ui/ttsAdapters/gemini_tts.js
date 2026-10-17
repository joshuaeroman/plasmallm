/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.import "../adapters/agentPlatform.js" as AgentPlatform

// Native Gemini TTS adapter (generateContent with responseModalities AUDIO).
// Works with Agent Platform express-mode keys and AI Studio keys. Newer
// models return audio/wav; older ones return raw 24 kHz PCM (audio/L16),
// which is wrapped into WAV before playback.

var id = "gemini_tts";
var displayName = "Google Gemini TTS (Agent Platform / AI Studio)";
var transport = "endpoint";

var AGENT_PLATFORM_URL = "https://aiplatform.googleapis.com";
var AI_STUDIO_URL = "https://generativelanguage.googleapis.com";

var presets = [
    {
        name: "Google Agent Platform",
        url: AGENT_PLATFORM_URL,
        model: "gemini-3.8-flash-lite-tts",
        voice: "Zephyr"
    },
    {
        name: "Google AI Studio",
        url: AI_STUDIO_URL,
        model: "gemini-3.8-flash-lite-tts",
        voice: "Zephyr"
    }
];

var DEFAULT_TTS_MODELS = [
    "gemini-3.8-flash-lite-tts",
    "gemini-3.8-flash-tts",
    "gemini-2.5-flash-tts",
    "gemini-2.5-pro-tts"
];

function defaultKnownModels() {
    return DEFAULT_TTS_MODELS.slice();
}

function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function trimStr(value) {
    return String(value || "").replace(/^\s+|\s+$/g, "");
}

function isConfigured(conn) {
    if (!conn || !conn.enabled)
        return false;
    if (!conn.endpoint || String(conn.endpoint).length === 0)
        return false;
    if (!conn.model || String(conn.model).length === 0)
        return false;
    return true;
}

function isAgentPlatform(endpoint) {
    return String(endpoint || "").indexOf("aiplatform.googleapis.com") !== -1;
}

function requestUrl(endpoint, model) {
    var base = trimStr(endpoint).replace(/\/+$/, "");
    if (isAgentPlatform(base))
        return AgentPlatform.modelUrl(base, "", "", model, "generateContent");
    return base + "/v1beta/models/" + encodeURIComponent(model) + ":generateContent";
}

// Prebuilt voices (single capitalized names like "Kore") use
// prebuiltVoiceConfig, which every Gemini TTS model accepts. Anything else
// is a voice library or designed-voice ID, which only the newer `voice`
// field takes.
function voiceConfig(voice) {
    if (/^[A-Z][a-z]+$/.test(voice))
        return { prebuiltVoiceConfig: { voiceName: voice } };
    return { voice: voice };
}

// Natural-language delivery directions go in the prompt. "Say <style>:
// <text>" gets read aloud verbatim by the 3.8 models; this form doesn't.
function promptText(text, styleDirection) {
    var direction = trimStr(styleDirection);
    if (!direction.length)
        return text;
    return "Read the following text aloud. Delivery: " + direction.replace(/[.\s]+$/, "") + ".\n\n" + text;
}

function buildRequest(opts) {
    var speechConfig = {};
    var voice = trimStr(opts.voice);
    if (voice.length)
        speechConfig.voiceConfig = voiceConfig(voice);
    return {
        contents: [{ role: "user", parts: [{ text: promptText(String(opts.text || ""), opts.styleDirection) }] }],
        generationConfig: {
            responseModalities: ["AUDIO"],
            speechConfig: speechConfig
        }
    };
}

// Reads the generateContent response, writes the first audio part to a WAV
// file (wrapping raw PCM), or reports why there was none.
var DECODE_SCRIPT = [
    "import base64, json, re, sys, wave",
    "resp = json.load(open(sys.argv[1]))",
    "cands = resp.get('candidates') or []",
    "parts = (cands[0].get('content') or {}).get('parts', []) if cands else []",
    "audio = [p['inlineData'] for p in parts if 'inlineData' in p]",
    "if not audio:",
    "    reason = cands[0].get('finishReason') if cands else resp.get('promptFeedback')",
    "    sys.stderr.write(json.dumps({'error': {'message': 'No audio returned (%s)' % reason}}))",
    "    sys.exit(1)",
    "mime = audio[0].get('mimeType', '')",
    "data = base64.b64decode(audio[0]['data'])",
    "if mime.startswith('audio/L16') or mime.startswith('audio/pcm'):",
    "    rate = re.search(r'rate=(\\d+)', mime)",
    "    w = wave.open(sys.argv[2], 'wb')",
    "    w.setnchannels(1); w.setsampwidth(2); w.setframerate(int(rate.group(1)) if rate else 24000)",
    "    w.writeframes(data); w.close()",
    "else:",
    "    open(sys.argv[2], 'wb').write(data)"
].join("\n");

/**
 * Build shell command to synthesize speech with Gemini TTS and play it.
 *
 * @param {object} opts
 * @param {string} opts.endpoint
 * @param {string} opts.apiKey
 * @param {string} opts.model
 * @param {string} opts.text
 * @param {string} [opts.voice]
 * @param {string} [opts.styleDirection]  natural-language delivery direction
 * @param {string} [opts.tempDir]
 * @returns {string} shell command
 */
function buildCommand(opts) {
    opts = opts || {};
    var text = String(opts.text || "");
    if (!text.trim().length)
        throw new Error("No text to speak");

    var endpoint = trimStr(opts.endpoint);
    if (!endpoint.length)
        throw new Error("TTS endpoint is not configured");

    var model = trimStr(opts.model);
    if (!model.length)
        throw new Error("TTS model is not configured");

    var apiKey = trimStr(opts.apiKey);
    var authHeader = apiKey.indexOf("ya29.") === 0
        ? "Authorization: Bearer " + apiKey
        : "x-goog-api-key: " + apiKey;

    var tempDir = opts.tempDir || "/tmp/plasmallm_tts";
    var stamp = Date.now().toString(36) + "_" + Math.random().toString(36).substring(2, 8);
    var jsonFile = tempDir + "/req_" + stamp + ".json";
    var respFile = tempDir + "/resp_" + stamp + ".json";
    var wavFile = tempDir + "/speech_" + stamp + ".wav";

    var payloadStr = JSON.stringify(buildRequest(opts));

    var scriptParts = [
        "mkdir -p " + shellQuote(tempDir),
        "printf '%s' " + shellQuote(payloadStr) + " > " + shellQuote(jsonFile),
        "CODE=$(curl -s -X POST " + shellQuote(requestUrl(endpoint, model))
            + " -H 'Content-Type: application/json'"
            + (apiKey.length ? " -H " + shellQuote(authHeader) : "")
            + " -d @" + shellQuote(jsonFile)
            + " -o " + shellQuote(respFile)
            + " -w '%{http_code}')",
        'if [ "$CODE" -lt 200 ] || [ "$CODE" -ge 300 ]; then '
            + 'cat ' + shellQuote(respFile) + ' 1>&2; '
            + 'rm -f ' + shellQuote(jsonFile) + ' ' + shellQuote(respFile) + '; '
            + 'exit 1; '
            + 'fi',
        "python3 -c " + shellQuote(DECODE_SCRIPT) + " " + shellQuote(respFile) + " " + shellQuote(wavFile)
            + " || { rm -f " + shellQuote(jsonFile) + " " + shellQuote(respFile) + "; exit 1; }",
        "rm -f " + shellQuote(jsonFile) + " " + shellQuote(respFile),
        "echo TTS_READY"
    ];

    var playParts = [
        "(pw-play " + shellQuote(wavFile) + " 2>/dev/null || paplay " + shellQuote(wavFile) + " 2>/dev/null || aplay " + shellQuote(wavFile) + " 2>/dev/null)",
        "rm -f " + shellQuote(wavFile)
    ];

    var synthCmd = scriptParts.join(" && ");
    var playCmd = playParts.join("; ");

    var res = new String(synthCmd + " && " + playCmd);
    res.synthesizeCmd = synthCmd;
    res.playCmd = playCmd;
    return res;
}

/**
 * Build the command to stop speech playback immediately.
 * @returns {string}
 */
function buildStopCommand() {
    return "pkill -f '/tmp/plasmallm_tts' 2>/dev/null; pkill -f 'pw-play.*/tmp/plasmallm_tts' 2>/dev/null; pkill -f 'paplay.*/tmp/plasmallm_tts' 2>/dev/null";
}

function parseResult(stdout, stderr, exitCode) {
    if (exitCode !== 0 && exitCode !== "0") {
        var raw = trimStr(stderr) || trimStr(stdout) || ("Exit code " + exitCode);
        var detail = raw;
        try {
            var errObj = JSON.parse(raw);
            if (errObj && errObj.error) {
                if (typeof errObj.error === "string")
                    detail = errObj.error;
                else if (errObj.error.message)
                    detail = errObj.error.message;
            }
        } catch (e) {
            if (detail.length > 250)
                detail = detail.substring(0, 250);
        }
        return { err: "Text-to-speech request failed: " + detail, result: null };
    }
    return { err: null, result: { success: true } };
}

function isTtsModel(modelId) {
    return String(modelId || "").toLowerCase().indexOf("tts") !== -1;
}

function mergeWithDefaults(found) {
    var combined = defaultKnownModels();
    for (var i = 0; i < found.length; i++) {
        if (combined.indexOf(found[i]) === -1)
            combined.push(found[i]);
    }
    return combined;
}

/**
 * Fetch TTS models. AI Studio lists them directly; Agent Platform express
 * keys can't list models, so candidates come from models.dev. Either way
 * each one is checked with countTokens and unusable ones are dropped.
 *
 * @param {string} endpoint
 * @param {string} apiKey
 * @param {function} callback function(err, models)
 */
function fetchModels(endpoint, apiKey, callback) {
    callback = callback || function() {};
    var base = trimStr(endpoint).replace(/\/+$/, "");
    if (!base.length) {
        callback("TTS endpoint is not configured", null);
        return;
    }
    var key = trimStr(apiKey);
    var defaults = defaultKnownModels();

    var xhr = new XMLHttpRequest();
    if (isAgentPlatform(base)) {
        xhr.open("GET", "https://models.dev/api.json");
    } else {
        xhr.open("GET", base + "/v1beta/models?pageSize=1000");
        if (key.length)
            xhr.setRequestHeader("x-goog-api-key", key);
    }
    xhr.timeout = 25000;
    xhr.ontimeout = function() {
        callback(null, defaults);
    };
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        if (xhr.status < 200 || xhr.status >= 300) {
            callback(null, defaults);
            return;
        }
        var found = [];
        try {
            var json = JSON.parse(xhr.responseText);
            if (isAgentPlatform(base)) {
                var providers = ["google-vertex", "google"];
                for (var p = 0; p < providers.length; p++) {
                    var entry = json[providers[p]];
                    var ids = entry && entry.models ? Object.keys(entry.models) : [];
                    for (var i = 0; i < ids.length; i++) {
                        if (isTtsModel(ids[i]) && found.indexOf(ids[i]) === -1)
                            found.push(ids[i]);
                    }
                }
            } else {
                var models = json.models || [];
                for (var j = 0; j < models.length; j++) {
                    var name = String(models[j].name || "").replace(/^models\//, "");
                    if (isTtsModel(name))
                        found.push(name);
                }
            }
        } catch (e) {
            callback(null, defaults);
            return;
        }
        if (!isAgentPlatform(base)) {
            if (!found.length || !key.length || key.indexOf("ya29.") === 0) {
                callback(null, found.length ? found : defaults);
                return;
            }
            AgentPlatform.verifyStudioModels(base, key, found, function(usable) {
                callback(null, usable.length > 0 ? usable : found);
            });
            return;
        }
        if (!key.length) {
            callback(null, mergeWithDefaults(found));
            return;
        }
        AgentPlatform.verifyModels(base, key, "global", mergeWithDefaults(found), function(reachable) {
            callback(null, reachable.length > 0 ? reachable : defaults);
        });
    };
    try {
        xhr.send();
    } catch (e) {
        callback(null, defaults);
    }
}
