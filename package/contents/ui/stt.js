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
        language: config.sttLanguage || "",
        cliBinary: config.sttCliBinary || "whisper",
        cliTask: config.sttCliTask || "transcribe",
        cliDevice: config.sttCliDevice || "",
        cliFp16: !!config.sttCliFp16,
        cliThreads: config.sttCliThreads || 0,
        cliInitialPrompt: config.sttCliInitialPrompt || "",
        cliExtraArgs: config.sttCliExtraArgs || ""
    };
}

function isSttConfigured(config) {
    var c = getSttConnection(config);
    if (!c)
        return false;
    var adapter = SttAdapters.get(c.backend);
    if (adapter && typeof adapter.isConfigured === "function")
        return adapter.isConfigured(c);
    if (!c.enabled)
        return false;
    if (!c.endpoint || String(c.endpoint).length === 0)
        return false;
    if (!c.model || String(c.model).length === 0)
        return false;
    return true;
}

function isCliTransport(config) {
    var c = getSttConnection(config);
    var adapter = SttAdapters.get(c && c.backend);
    return !!(adapter && adapter.transport === "cli");
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
    if (!adapter) {
        callback(i18n("Unknown STT backend: %1", conn.backend), null);
        return;
    }

    var format = opts.format || formatFromPath(opts.filePath);

    if (adapter.transport === "cli") {
        if (!opts.filePath || String(opts.filePath).length === 0) {
            callback(i18n("No audio file to transcribe"), null);
            return;
        }
        if (typeof opts.runCommand !== "function") {
            callback(i18n("Whisper CLI runner is not available"), null);
            return;
        }
        if (typeof adapter.buildCommand !== "function" || typeof adapter.parseResult !== "function") {
            callback(i18n("Unknown STT backend: %1", conn.backend), null);
            return;
        }
        var cmd;
        try {
            cmd = adapter.buildCommand({
                filePath: opts.filePath,
                model: conn.model,
                language: conn.language,
                cliBinary: conn.cliBinary,
                cliTask: conn.cliTask,
                cliDevice: conn.cliDevice,
                cliFp16: conn.cliFp16,
                cliThreads: conn.cliThreads,
                cliInitialPrompt: conn.cliInitialPrompt,
                cliExtraArgs: conn.cliExtraArgs
            });
        } catch (buildErr) {
            callback(buildErr.message || String(buildErr), null);
            return;
        }
        if (!cmd) {
            callback(i18n("Could not build Whisper command"), null);
            return;
        }
        opts.runCommand(cmd, function(runErr, proc) {
            if (runErr) {
                callback(runErr, null);
                return;
            }
            proc = proc || {};
            var parsed = adapter.parseResult(proc.stdout, proc.stderr, proc.exitCode, opts);
            if (parsed && parsed.err)
                callback(parsed.err, null);
            else
                callback(null, (parsed && parsed.result) || { text: "" });
        });
        return;
    }

    if (typeof adapter.transcribe !== "function") {
        callback(i18n("Unknown STT backend: %1", conn.backend), null);
        return;
    }

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

function whisperCacheCheckCommand(model) {
    var adapter = SttAdapters.get("whisper_cli");
    if (!adapter || typeof adapter.buildCacheCheckCommand !== "function")
        return "";
    return adapter.buildCacheCheckCommand(model);
}

function whisperDownloadSizeHint(model) {
    var adapter = SttAdapters.get("whisper_cli");
    if (!adapter || typeof adapter.downloadSizeHint !== "function")
        return "";
    return adapter.downloadSizeHint(model);
}

function whisperCudaCheckCommand(cliBinary) {
    var adapter = SttAdapters.get("whisper_cli");
    if (!adapter || typeof adapter.buildCudaCheckCommand !== "function")
        return "";
    return adapter.buildCudaCheckCommand(cliBinary);
}

function providerPresets() {
    return [
        { name: "OpenRouter", url: "https://openrouter.ai/api/v1" },
        { name: "OpenAI",     url: "https://api.openai.com/v1" },
        { name: "Groq",       url: "https://api.groq.com/openai/v1" },
        { name: "Custom",     url: "" }
    ];
}
