/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Shared helpers for the Gemini adapters (generateContent and Interactions).
// Node tests load this with vm.runInContext (no QML imports).

// Model IDs that are not chat models. They answer generateContent but
// return images/audio (or need websockets), so they don't belong in the chat
// model picker. "nano-banana" is the Gemini image model's public name.
var NON_CHAT_MARKERS = [
    "-tts", "embedding", "image", "nano-banana", "live", "native-audio",
    "lyria", "veo"
];

function isChatModel(modelId) {
    var lower = String(modelId || "").toLowerCase();
    for (var i = 0; i < NON_CHAT_MARKERS.length; i++) {
        if (lower.indexOf(NON_CHAT_MARKERS[i]) !== -1)
            return false;
    }
    return true;
}

// Agent Platform express-mode keys belong to one project, but the short
// express URL (/v1/publishers/google/models/...) is served from a single
// region and 404s for models that region doesn't host. Any 404 from the
// express endpoint names the key's project, so read it from there and use
// the project + location URL instead.
var EXPRESS_HOST = "://aiplatform.googleapis.com";
var PROJECT_PROBE_MODEL = "plasmallm-project-probe";
var COUNT_TOKENS_BODY = JSON.stringify({ contents: [{ role: "user", parts: [{ text: "hi" }] }] });
var projectByKey = {};

function projectFromError(text) {
    var m = /projects\/(\d+)\//.exec(String(text || ""));
    return m ? m[1] : "";
}

// True when requests go out with an express-mode API key and no project ID,
// i.e. when looking up the key's project is both possible and useful.
function usesExpressKey(opts, apiKey, baseUrl) {
    if (!opts || opts.geminiAuthMethod !== "agentplatform" || opts.geminiVertexAuthType === "gcloud")
        return false;
    if (!apiKey || apiKey.indexOf("ya29.") === 0)
        return false;
    if (opts.geminiProjectId && String(opts.geminiProjectId).trim().length > 0)
        return false;
    return String(baseUrl || "").indexOf(EXPRESS_HOST) !== -1;
}

function cachedProject(apiKey) {
    return projectByKey[apiKey] || "";
}

function modelUrl(baseUrl, projectId, location, model, method) {
    if (projectId && projectId.length > 0) {
        return baseUrl +
               "/v1/projects/" + encodeURIComponent(projectId) +
               "/locations/" + encodeURIComponent(location || "global") +
               "/publishers/google/models/" + encodeURIComponent(model) +
               ":" + method;
    }
    return baseUrl + "/v1/publishers/google/models/" + encodeURIComponent(model) + ":" + method;
}

// Calls back with the key's project number ("" if it can't be found). The
// returned handle's abort() cancels the lookup without calling back.
function discoverProject(baseUrl, apiKey, callback) {
    var cancelled = false;
    var xhr = new XMLHttpRequest();
    xhr.open("POST", modelUrl(baseUrl, "", "", PROJECT_PROBE_MODEL, "countTokens"));
    xhr.timeout = 15000;
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("x-goog-api-key", apiKey);
    function done() {
        if (cancelled) return;
        cancelled = true;
        var project = projectFromError(xhr.responseText);
        if (project) projectByKey[apiKey] = project;
        callback(project);
    }
    xhr.ontimeout = done;
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) done();
    };
    xhr.send(COUNT_TOKENS_BODY);
    return {
        abort: function() {
            cancelled = true;
            xhr.abort();
        }
    };
}
