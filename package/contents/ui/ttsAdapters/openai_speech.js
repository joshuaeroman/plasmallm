/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// OpenRouter and OpenAI-compatible speech endpoint adapter.
// Supports OpenRouter (google/gemini-3.8-flash-lite-tts with raw PCM)
// and OpenAI (tts-1, tts-1-hd with MP3), as well as custom endpoints.

var id = "openai_speech";
var displayName = "OpenRouter / OpenAI speech endpoint";
var transport = "endpoint";

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

function defaultVoiceForModel(model) {
    var m = String(model || "").toLowerCase();
    if (m.indexOf("gemini") >= 0)
        return "Zephyr";
    return "alloy";
}

function defaultFormatForModel(model) {
    var m = String(model || "").toLowerCase();
    if (m.indexOf("gemini") >= 0)
        return "pcm";
    return "mp3";
}

/**
 * Build shell command to synthesize speech from endpoint and play it.
 *
 * @param {object} opts
 * @param {string} opts.endpoint
 * @param {string} opts.apiKey
 * @param {string} opts.model
 * @param {string} opts.text
 * @param {string} [opts.voice]
 * @param {string} [opts.responseFormat]  pcm | mp3
 * @param {string} [opts.tempDir]
 * @returns {string} shell command
 */
function buildCommand(opts) {
    opts = opts || {};
    var text = String(opts.text || "");
    if (!text.trim().length)
        throw new Error("No text to speak");

    var endpoint = trimStr(opts.endpoint).replace(/\/+$/, "");
    if (!endpoint.length)
        throw new Error("TTS endpoint is not configured");

    var model = trimStr(opts.model);
    if (!model.length)
        throw new Error("TTS model is not configured");

    var url = endpoint + "/audio/speech";
    var voice = trimStr(opts.voice) || defaultVoiceForModel(model);
    var format = trimStr(opts.responseFormat) || defaultFormatForModel(model);
    var apiKey = trimStr(opts.apiKey);

    var tempDir = opts.tempDir || "/tmp/plasmallm_tts";
    var stamp = Date.now().toString(36) + "_" + Math.random().toString(36).substring(2, 8);

    var jsonFile = tempDir + "/req_" + stamp + ".json";
    var audioFile = tempDir + "/speech_" + stamp + "." + (format === "pcm" ? "pcm" : "mp3");
    var wavFile = tempDir + "/speech_" + stamp + ".wav";

    var payload = {
        model: model,
        input: text,
        voice: voice,
        response_format: format
    };

    var payloadStr = JSON.stringify(payload);

    var scriptParts = [
        "mkdir -p " + shellQuote(tempDir),
        "printf '%s' " + shellQuote(payloadStr) + " > " + shellQuote(jsonFile),
        "CODE=$(curl -s -X POST " + shellQuote(url)
            + " -H 'Content-Type: application/json'"
            + (apiKey.length ? (" -H 'Authorization: Bearer " + apiKey.replace(/'/g, "'\\''") + "'") : "")
            + " -d @" + shellQuote(jsonFile)
            + " -o " + shellQuote(audioFile)
            + " -w '%{http_code}')",
        'if [ "$CODE" -lt 200 ] || [ "$CODE" -ge 300 ]; then '
            + 'cat ' + shellQuote(audioFile) + ' 1>&2; '
            + 'rm -f ' + shellQuote(jsonFile) + ' ' + shellQuote(audioFile) + '; '
            + 'exit 1; '
            + 'fi'
    ];

    var playParts = [];

    if (format === "pcm") {
        // Convert raw 24kHz 16-bit mono PCM into standard WAV
        var pcmToWav = "python3 -c \"import wave, sys; "
            + "d=open('" + audioFile.replace(/'/g, "'\\''") + "','rb').read(); "
            + "w=wave.open('" + wavFile.replace(/'/g, "'\\''") + "','wb'); "
            + "w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); "
            + "w.writeframes(d); w.close()\"";
        scriptParts.push(pcmToWav);
        playParts.push("(pw-play " + shellQuote(wavFile) + " 2>/dev/null || paplay " + shellQuote(wavFile) + " 2>/dev/null || aplay " + shellQuote(wavFile) + " 2>/dev/null)");
        playParts.push("rm -f " + shellQuote(jsonFile) + " " + shellQuote(audioFile) + " " + shellQuote(wavFile));
    } else {
        playParts.push("(pw-play " + shellQuote(audioFile) + " 2>/dev/null || paplay " + shellQuote(audioFile) + " 2>/dev/null || ffplay -nodisp -autoexit " + shellQuote(audioFile) + " 2>/dev/null)");
        playParts.push("rm -f " + shellQuote(jsonFile) + " " + shellQuote(audioFile));
    }

    scriptParts.push("echo TTS_READY");

    var synthCmd = scriptParts.join(" && ");
    var playCmd = playParts.join("; ");
    var fullCmd = synthCmd + " && " + playCmd;

    var res = new String(fullCmd);
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
            } else if (errObj && errObj.message) {
                detail = errObj.message;
            }
        } catch (e) {
            if (detail.length > 250)
                detail = detail.substring(0, 250);
        }
        return { err: "Text-to-speech request failed: " + detail, result: null };
    }
    return { err: null, result: { success: true } };
}

var DEFAULT_TTS_MODELS = [
    "google/gemini-3.8-flash-lite-tts",
    "openai/tts-1",
    "openai/tts-1-hd",
    "tts-1",
    "tts-1-hd"
];

function defaultKnownModels() {
    return DEFAULT_TTS_MODELS.slice();
}

/**
 * Fetch available TTS models from the endpoint, seeded with known TTS models.
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

    var defaultModels = defaultKnownModels();

    function setHeaders(xhr, key) {
        xhr.setRequestHeader("Accept", "application/json");
        var k = trimStr(key);
        if (k.length > 0) {
            xhr.setRequestHeader("Authorization", "Bearer " + k);
        }
    }

    var xhr = new XMLHttpRequest();
    xhr.open("GET", base + "/models");
    xhr.timeout = 25000;
    setHeaders(xhr, apiKey);
    xhr.ontimeout = function() {
        callback(null, defaultModels);
    };
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        if (xhr.status >= 200 && xhr.status < 300) {
            try {
                var json = JSON.parse(xhr.responseText);
                var data = Array.isArray(json) ? json : (json && Array.isArray(json.data) ? json.data : []);
                var found = [];
                for (var i = 0; i < data.length; i++) {
                    var id = typeof data[i] === "string" ? data[i] : (data[i] && data[i].id ? data[i].id : "");
                    if (!id) continue;
                    var lower = id.toLowerCase();
                    if (lower.indexOf("tts") >= 0 || lower.indexOf("speech") >= 0 || lower.indexOf("audio") >= 0) {
                        found.push(id);
                    }
                }
                var combined = defaultModels.slice();
                for (var j = 0; j < found.length; j++) {
                    if (combined.indexOf(found[j]) === -1)
                        combined.push(found[j]);
                }
                callback(null, combined);
            } catch (e) {
                callback(null, defaultModels);
            }
        } else {
            callback(null, defaultModels);
        }
    };
    try {
        xhr.send();
    } catch (e) {
        callback(null, defaultModels);
    }
}
