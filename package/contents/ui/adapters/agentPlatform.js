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

// Calls back with the ids whose countTokens probe (POST urlFor(id)) didn't
// return 404, in their original order. countTokens is free; Google answers
// 404 for models a key can't use (retired, allowlisted, or "no longer
// available to new users"). Only a 404 drops a model, so rate limits or
// timeouts while probing many models at once don't hide usable ones.
function probeModels(ids, urlFor, apiKey, callback) {
    if (!ids || ids.length === 0) {
        callback([]);
        return;
    }
    var reachable = [];
    var pending = ids.length;
    function settle(index, ok) {
        reachable[index] = ok;
        pending--;
        if (pending === 0) {
            callback(ids.filter(function(id, i) { return reachable[i]; }));
        }
    }
    for (var i = 0; i < ids.length; i++) {
        (function(index) {
            var xhr = new XMLHttpRequest();
            var settled = false;
            function done() {
                if (settled) return;
                settled = true;
                settle(index, xhr.status !== 404);
            }
            xhr.open("POST", urlFor(ids[index]));
            xhr.timeout = 15000;
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("x-goog-api-key", apiKey);
            xhr.ontimeout = done;
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) done();
            };
            xhr.send(COUNT_TOKENS_BODY);
        })(i);
    }
}

// Express keys can't call ListModels, so model lists come from models.dev
// unverified. Probe each candidate on the key's project URL (like chat
// requests) and keep the ones the key can use.
function verifyModels(baseUrl, apiKey, location, ids, callback) {
    if (!ids || ids.length === 0) {
        callback([]);
        return;
    }
    function probeAll(projectId) {
        probeModels(ids, function(id) {
            return modelUrl(baseUrl, projectId, location, id, "countTokens");
        }, apiKey, callback);
    }
    var cached = cachedProject(apiKey);
    if (cached) {
        probeAll(cached);
    } else {
        discoverProject(baseUrl, apiKey, probeAll);
    }
}

// AI Studio's ListModels includes models a key can't call (e.g. ones "no
// longer available to new users"); probe them the same way.
function verifyStudioModels(baseUrl, apiKey, ids, callback) {
    probeModels(ids, function(id) {
        return baseUrl + "/v1beta/models/" + encodeURIComponent(id) + ":countTokens";
    }, apiKey, callback);
}
