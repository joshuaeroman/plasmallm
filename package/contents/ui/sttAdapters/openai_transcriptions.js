/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// OpenAI-compatible / OpenRouter speech-to-text via POST /audio/transcriptions
// using JSON body with base64 input_audio (OpenRouter STT shape; also works
// with other gateways that accept the same wire format).

var id = "openai_transcriptions";
var displayName = "OpenAI-compatible transcriptions";

function setHeaders(xhr, apiKey) {
    xhr.setRequestHeader("Content-Type", "application/json");
    if (apiKey && apiKey.length > 0) {
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
    }
}

function hostOf(endpoint) {
    if (!endpoint || typeof endpoint !== "string") return "";
    var m = endpoint.match(/^https?:\/\/([^\/:?#]+)/i);
    return m ? m[1].toLowerCase() : "";
}

function isOpenRouter(endpoint) {
    var h = hostOf(endpoint);
    return h === "openrouter.ai" || h.indexOf("openrouter.ai") !== -1;
}

function isOpenAiHost(endpoint) {
    var h = hostOf(endpoint);
    return h === "api.openai.com" || h === "openai.com";
}

function parseModelIds(responseText) {
    var response = JSON.parse(responseText);
    var models = [];
    if (response && response.data) {
        for (var i = 0; i < response.data.length; i++) {
            if (response.data[i] && response.data[i].id)
                models.push(response.data[i].id);
        }
    }
    return models;
}

function knownOpenAiSttModels() {
    return [
        "gpt-transcribe",
        "gpt-4o-transcribe",
        "gpt-4o-mini-transcribe",
        "whisper-1"
    ];
}

/**
 * List STT models. OpenRouter requires output_modalities=transcription;
 * default GET /models omits whisper/gpt-transcribe entirely.
 *
 * Strategy:
 *  1) Try /models?output_modalities=transcription (OpenRouter and any host that supports it)
 *  2) Fall back to plain /models
 *  3) Seed known OpenAI STT ids if still empty and host is OpenAI
 */
function fetchModels(endpoint, apiKey, callback) {
    callback = callback || function() {};
    var base = (endpoint || "").replace(/\/+$/, "");
    if (!base) {
        callback(i18n("STT endpoint is not configured"), null);
        return;
    }

    function getJson(url, onDone) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.timeout = 30000;
        setHeaders(xhr, apiKey);
        xhr.ontimeout = function() { onDone(i18n("Request timed out after 30 seconds"), null, 0); };
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    onDone(null, parseModelIds(xhr.responseText), xhr.status);
                } catch (e) {
                    onDone(i18n("Failed to parse models: %1", e.message || String(e)), null, xhr.status);
                }
            } else {
                onDone(i18n("Failed to fetch models: HTTP %1", xhr.status), null, xhr.status);
            }
        };
        try {
            xhr.send();
        } catch (sendErr) {
            onDone(i18n("Model list request failed: %1", sendErr.message || String(sendErr)), null, 0);
        }
    }

    var transcriptionUrl = base + "/models?output_modalities=transcription";
    var plainUrl = base + "/models";

    getJson(transcriptionUrl, function(err, models, status) {
        if (!err && models && models.length > 0) {
            callback(null, models, status);
            return;
        }
        // OpenRouter: empty/error on plain list still won't include STT; try plain anyway for other hosts.
        getJson(plainUrl, function(err2, models2, status2) {
            if (!err2 && models2 && models2.length > 0) {
                callback(null, models2, status2);
                return;
            }
            if (isOpenAiHost(endpoint)) {
                callback(null, knownOpenAiSttModels(), 200);
                return;
            }
            // Prefer the transcription-query error if both failed.
            if (err && (!models2 || models2.length === 0))
                callback(err, null, status || status2);
            else if (err2)
                callback(err2, null, status2);
            else
                callback(i18n("No STT models returned"), null, status2 || status);
        });
    });
}

/**
 * Transcribe base64-encoded audio.
 * @param {object} opts
 * @param {string} opts.endpoint  Base URL ending in /v1 (or provider root)
 * @param {string} opts.apiKey
 * @param {string} opts.model
 * @param {string} opts.audioBase64  Raw base64 (no data: URI prefix)
 * @param {string} opts.format       e.g. wav, mp3, ogg, webm, m4a, flac
 * @param {string} [opts.language]   Optional ISO-639-1 code
 * @param {function} opts.callback   function(err, result) result = { text }
 */
function transcribe(opts) {
    var callback = opts.callback || function() {};
    var endpoint = (opts.endpoint || "").replace(/\/+$/, "");
    if (!endpoint) {
        callback(i18n("STT endpoint is not configured"), null);
        return;
    }
    if (!opts.audioBase64 || opts.audioBase64.length === 0) {
        callback(i18n("No audio data to transcribe"), null);
        return;
    }
    if (!opts.model || String(opts.model).length === 0) {
        callback(i18n("STT model is not configured"), null);
        return;
    }

    var xhr = new XMLHttpRequest();
    var url = endpoint + "/audio/transcriptions";
    xhr.open("POST", url);
    xhr.timeout = 90000;
    setHeaders(xhr, opts.apiKey);

    var body = {
        model: opts.model,
        input_audio: {
            data: opts.audioBase64,
            format: opts.format || "wav"
        }
    };
    if (opts.language && String(opts.language).trim().length > 0) {
        body.language = String(opts.language).trim();
    }

    xhr.ontimeout = function() {
        callback(i18n("Speech-to-text request timed out"), null);
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        if (xhr.status >= 200 && xhr.status < 300) {
            try {
                var response = JSON.parse(xhr.responseText);
                var text = (response && typeof response.text === "string") ? response.text : "";
                callback(null, { text: text });
            } catch (e) {
                callback(i18n("Failed to parse STT response: %1", e.message || String(e)), null);
            }
            return;
        }
        var detail = "";
        try {
            var errObj = JSON.parse(xhr.responseText);
            if (errObj && errObj.error) {
                if (typeof errObj.error === "string")
                    detail = errObj.error;
                else if (errObj.error.message)
                    detail = errObj.error.message;
            } else if (errObj && errObj.message) {
                detail = errObj.message;
            }
        } catch (e2) {
            detail = (xhr.responseText || "").substring(0, 240);
        }
        if (detail)
            callback(i18n("STT failed (HTTP %1): %2", xhr.status, detail), null);
        else
            callback(i18n("STT failed (HTTP %1)", xhr.status), null);
    };

    try {
        xhr.send(JSON.stringify(body));
    } catch (sendErr) {
        callback(i18n("STT request failed: %1", sendErr.message || String(sendErr)), null);
    }
}
