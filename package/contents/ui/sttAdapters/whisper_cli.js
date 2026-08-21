/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Local OpenAI Whisper CLI (the official `whisper` Python package).
// Host (main.qml) executes the command via the Plasma executable engine.

var id = "whisper_cli";
var displayName = "OpenAI Whisper (local CLI)";
var transport = "cli";

var KNOWN_MODELS = [
    "tiny",
    "tiny.en",
    "base",
    "base.en",
    "small",
    "small.en",
    "medium",
    "medium.en",
    "large",
    "large-v1",
    "large-v2",
    "large-v3",
    "turbo"
];

var KNOWN_TASKS = ["transcribe", "translate"];
var KNOWN_DEVICES = ["cpu", "cuda"];

// Official openai-whisper cache: ${XDG_CACHE_HOME:-$HOME/.cache}/whisper/{file}
var CACHE_FILES = {
    "tiny": "tiny.pt",
    "tiny.en": "tiny.en.pt",
    "base": "base.pt",
    "base.en": "base.en.pt",
    "small": "small.pt",
    "small.en": "small.en.pt",
    "medium": "medium.pt",
    "medium.en": "medium.en.pt",
    "large-v1": "large-v1.pt",
    "large-v2": "large-v2.pt",
    "large-v3": "large-v3.pt",
    "large": "large-v3.pt",
    "large-v3-turbo": "large-v3-turbo.pt",
    "turbo": "large-v3-turbo.pt"
};

var SIZE_HINTS = {
    "tiny": "~75 MB",
    "tiny.en": "~75 MB",
    "base": "~142 MB",
    "base.en": "~142 MB",
    "small": "~466 MB",
    "small.en": "~466 MB",
    "medium": "~1.5 GB",
    "medium.en": "~1.5 GB",
    "large-v1": "~2.9 GB",
    "large-v2": "~2.9 GB",
    "large-v3": "~2.9 GB",
    "large": "~2.9 GB",
    "large-v3-turbo": "~809 MB",
    "turbo": "~809 MB"
};

function cacheFileName(model) {
    return CACHE_FILES[trimStr(model)] || "";
}

function downloadSizeHint(model) {
    return SIZE_HINTS[trimStr(model)] || "";
}

function buildCacheCheckCommand(model) {
    var file = cacheFileName(model);
    if (!file.length || !/^[A-Za-z0-9._-]+\.pt$/.test(file))
        return "";
    return 'f="${XDG_CACHE_HOME:-$HOME/.cache}/whisper/' + file + '"; '
        + 'if [ -f "$f" ] && [ "$(wc -c < "$f" | tr -d \' \')" -gt 1048576 ]; then echo DOWNLOADED; else echo MISSING; fi';
}

/**
 * Map a Whisper command prefix to a python3 launcher in the same environment.
 * "whisper" / "/path/to/whisper" → "python3"
 * "python3 -m whisper" → "python3"
 * "toolbox run whisper" → "toolbox run python3"
 */
function pythonLauncherFromPrefix(cliBinary) {
    var p = trimStr(cliBinary) || defaultPrefix();
    var parts = p.split(/\s+/);
    var n = parts.length;
    if (n >= 3 && /^python3?$/.test(parts[n - 3])
            && parts[n - 2] === "-m"
            && /whisper$/i.test(parts[n - 1])) {
        parts = parts.slice(0, n - 3);
        parts.push("python3");
        return parts.filter(function(t) { return t.length > 0; }).join(" ") || "python3";
    }
    if (n >= 1 && /(^|\/)whisper$/i.test(parts[n - 1])) {
        parts = parts.slice(0, n - 1);
        parts.push("python3");
        return parts.filter(function(t) { return t.length > 0; }).join(" ") || "python3";
    }
    return "python3";
}

function buildCudaCheckCommand(cliBinary) {
    var launcher = pythonLauncherFromPrefix(cliBinary);
    return launcher + " -c 'import sys; sys.stdout.write(\"1\" if __import__(\"torch\").cuda.is_available() else \"0\")'";
}

function knownModels() {
    return KNOWN_MODELS.slice();
}

function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function isSafeToken(value) {
    return /^[A-Za-z0-9._-]+$/.test(String(value || ""));
}

function trimStr(value) {
    return String(value || "").replace(/^\s+|\s+$/g, "");
}

function dirnameOf(path) {
    var p = String(path || "");
    var i = p.lastIndexOf("/");
    if (i <= 0)
        return ".";
    return p.substring(0, i);
}

function sidecarTxt(path) {
    var p = String(path || "");
    var slash = p.lastIndexOf("/");
    var dot = p.lastIndexOf(".");
    if (dot > slash)
        return p.substring(0, dot) + ".txt";
    return p + ".txt";
}

function defaultPrefix() {
    return "whisper";
}

function isConfigured(conn) {
    if (!conn || !conn.enabled)
        return false;
    if (!conn.model || String(conn.model).length === 0)
        return false;
    return true;
}

function fetchModels(endpoint, apiKey, callback) {
    callback = callback || function() {};
    callback(null, knownModels(), 200);
}

/**
 * @param {object} opts
 * @param {string} opts.filePath
 * @param {string} opts.model
 * @param {string} [opts.language]
 * @param {string} [opts.cliBinary]  Verbatim command prefix (e.g. "toolbox run whisper")
 * @param {string} [opts.cliTask]    transcribe | translate
 * @param {string} [opts.cliDevice]  cpu | cuda | empty
 * @param {boolean} [opts.cliFp16]
 * @param {number} [opts.cliThreads]
 * @param {string} [opts.cliInitialPrompt]
 * @param {string} [opts.cliExtraArgs]
 * @returns {string} shell command
 */
function buildCommand(opts) {
    opts = opts || {};
    var filePath = String(opts.filePath || "");
    if (!filePath.length)
        throw new Error(i18n("No audio file to transcribe"));

    var model = trimStr(opts.model);
    if (!model.length)
        throw new Error(i18n("STT model is not configured"));
    if (!isSafeToken(model))
        throw new Error(i18n("Invalid Whisper model id"));

    var prefix = trimStr(opts.cliBinary) || defaultPrefix();
    var outDir = dirnameOf(filePath);
    var txtPath = sidecarTxt(filePath);

    var parts = [];
    parts.push(prefix);
    parts.push(shellQuote(filePath));
    parts.push("--model");
    parts.push(model);
    parts.push("--output_format");
    parts.push("txt");
    parts.push("--output_dir");
    parts.push(shellQuote(outDir));
    parts.push("--verbose");
    parts.push("False");

    var language = trimStr(opts.language);
    if (language.length) {
        parts.push("--language");
        parts.push(isSafeToken(language) ? language : shellQuote(language));
    }

    var task = trimStr(opts.cliTask);
    if (task.length && task !== "transcribe") {
        if (KNOWN_TASKS.indexOf(task) < 0)
            throw new Error(i18n("Invalid Whisper task"));
        parts.push("--task");
        parts.push(task);
    }

    var device = trimStr(opts.cliDevice);
    if (device.length) {
        if (KNOWN_DEVICES.indexOf(device) < 0)
            throw new Error(i18n("Invalid Whisper device"));
        parts.push("--device");
        parts.push(device);
    }

    parts.push("--fp16");
    parts.push(opts.cliFp16 ? "True" : "False");

    var threads = parseInt(opts.cliThreads, 10);
    if (!isNaN(threads) && threads > 0) {
        parts.push("--threads");
        parts.push(String(threads));
    }

    var prompt = String(opts.cliInitialPrompt || "");
    if (trimStr(prompt).length) {
        parts.push("--initial_prompt");
        parts.push(shellQuote(prompt));
    }

    var extra = trimStr(opts.cliExtraArgs);
    if (extra.length)
        parts.push(extra);

    return parts.join(" ") + " 1>/dev/null && cat " + shellQuote(txtPath);
}

function truncateDetail(text) {
    var s = trimStr(text);
    var max = 500;
    if (s.length > max)
        s = s.substring(s.length - max);
    return s;
}

function looksLikeCudaError(text) {
    var s = String(text || "").toLowerCase();
    return s.indexOf("cuda") >= 0
        || s.indexOf("cublas") >= 0
        || s.indexOf("cudnn") >= 0
        || s.indexOf("no kernel image") >= 0
        || (s.indexOf("gpu") >= 0 && s.indexOf("not compiled") >= 0);
}

function parseResult(stdout, stderr, exitCode, opts) {
    if (exitCode !== 0 && exitCode !== "0") {
        var raw = trimStr(stderr) || trimStr(stdout);
        var detail = truncateDetail(raw);
        var err;
        if (detail)
            err = i18n("Whisper CLI failed (exit %1): %2", exitCode, detail);
        else
            err = i18n("Whisper CLI failed (exit %1)", exitCode);
        if (looksLikeCudaError(raw))
            err += "\n" + i18n("Try Device: cpu or Default in Speech to Text settings.");
        return { err: err, result: null };
    }
    var text = String(stdout || "").replace(/^\s+|\s+$/g, "");
    return { err: null, result: { text: text } };
}
