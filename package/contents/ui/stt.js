/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.import "sttAdapters/index.js" as SttAdapters

function getSttConnection(config) {
    if (!config)
        return null;
    return {
        enabled: !!config.sttEnabled,
        providerName: config.sttProviderName || "",
        endpoint: config.sttApiEndpoint || "",
        model: config.sttModelName || "",
        backend: config.sttBackend || "openai_transcriptions",
        language: config.sttLanguage || ""
    };
}

function isSttConfigured(config) {
    var c = getSttConnection(config);
    if (!c || !c.enabled)
        return false;
    if (!c.endpoint || String(c.endpoint).length === 0)
        return false;
    if (!c.model || String(c.model).length === 0)
        return false;
    return true;
}

function formatFromPath(filePath) {
    if (!filePath)
        return "wav";
    var path = String(filePath);
    path = path.replace(/^file:\/\//, "");
    var dot = path.lastIndexOf(".");
    if (dot < 0)
        return "wav";
    var ext = path.substring(dot + 1).toLowerCase();
    if (ext === "wave")
        return "wav";
    if (ext === "mpeg" || ext === "mpga")
        return "mp3";
    if (ext === "mp4")
        return "m4a";
    if (["wav", "mp3", "flac", "m4a", "ogg", "webm", "aac", "opus"].indexOf(ext) >= 0)
        return ext;
    return "wav";
}

/**
 * Transcribe using dedicated STT settings (not chat profiles).
 * @param {object} opts
 * @param {object} opts.config
 * @param {string} opts.apiKey
 * @param {string} opts.audioBase64
 * @param {string} [opts.format]
 * @param {string} [opts.filePath]
 * @param {function} opts.callback  function(err, { text })
 */
function transcribe(opts) {
    var callback = (opts && opts.callback) || function() {};
    var config = opts.config;
    var conn = getSttConnection(config);
    if (!conn || !isSttConfigured(config)) {
        callback(i18n("Speech-to-text is not configured"), null);
        return;
    }

    var adapter = SttAdapters.get(conn.backend);
    if (!adapter || typeof adapter.transcribe !== "function") {
        callback(i18n("Unknown STT backend: %1", conn.backend), null);
        return;
    }

    var format = opts.format || formatFromPath(opts.filePath);

    adapter.transcribe({
        endpoint: conn.endpoint,
        apiKey: opts.apiKey || "",
        model: conn.model,
        audioBase64: opts.audioBase64,
        format: format,
        language: conn.language,
        callback: callback
    });
}

function fetchModels(endpoint, apiKey, backendId, callback) {
    var adapter = SttAdapters.get(backendId || "openai_transcriptions");
    if (!adapter || typeof adapter.fetchModels !== "function") {
        callback(i18n("STT backend does not support model listing"), null);
        return;
    }
    adapter.fetchModels(endpoint, apiKey, callback);
}

function backendChoices() {
    return SttAdapters.list();
}

function providerPresets() {
    return [
        { name: "OpenRouter", url: "https://openrouter.ai/api/v1" },
        { name: "OpenAI",     url: "https://api.openai.com/v1" },
        { name: "Groq",       url: "https://api.groq.com/openai/v1" },
        { name: "Custom",     url: "" }
    ];
}
