/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Decisions adapter for TypeSafe System One models (Jev). Decisions models
// cannot generate text: they evaluate a `state` against typed questions and
// return calibrated probabilities. As an active profile each user message is
// sent as state and rendered as a single-shot verdict bubble (see
// chatMode:"decisions" consumed by main.qml); as a command-validator profile
// the validator sends its own question set to the same endpoint.

.import "../commandValidator.js" as Validator
.import "../utils.js" as Utils

var id = "decisions";
var displayName = "Decisions (TypeSafe / Jev)";

var presets = [
    { name: "TypeSafe",              url: "https://api.typesafe.ai/v1" },
    { name: "OpenRouter (decisions)", url: "https://openrouter.ai/api/v1" }
];

// chatMode "decisions": no text generation, no tools. main.qml branches to the
// single-shot evaluation path instead of the streaming chat pipeline.
var capabilities = {
    providerPresets: true,
    customEndpoint: true,
    reasoningEffort: false,
    thinkingBudget: false,
    fetchModels: true,
    chatMode: "decisions",
    reasoningHelp: "Decisions models (Jev) return typed answers with calibrated probabilities instead of generated text. Each message is evaluated once; there is no conversation memory."
};

function hostOf(endpoint) {
    return Validator.hostOf(endpoint);
}

function parseTypeSafeModels(json) {
    var out = [];
    if (json && json.models && json.models.length) {
        for (var i = 0; i < json.models.length; i++) {
            if (json.models[i] && json.models[i].name)
                out.push(json.models[i].name);
        }
    }
    return out;
}

function parseOpenRouterModels(json) {
    var out = [];
    if (json && json.data) {
        for (var i = 0; i < json.data.length; i++) {
            if (json.data[i] && json.data[i].id)
                out.push(json.data[i].id);
        }
    }
    return out;
}

function _getModels(url, apiKey, attribution, callback) {
    try {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.timeout = 30000;
        xhr.setRequestHeader("Authorization", "Bearer " + (apiKey || ""));
        // OpenRouter app attribution (see applyOpenRouterAttribution in
        // utils.js for the explicit-true opt-out rule).
        Utils.applyOpenRouterAttribution(xhr, { attribution: attribution }, url);
        xhr.ontimeout = function() {
            callback("Request timed out after 30 seconds", null);
        };
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var json = null;
            try {
                json = JSON.parse(xhr.responseText);
            } catch (e) {}
            if (xhr.status < 200 || xhr.status >= 300) {
                callback(Validator.httpErrorMessage(json, xhr.status), null);
                return;
            }
            var models = parseTypeSafeModels(json);
            if (models.length === 0)
                models = parseOpenRouterModels(json);
            if (models.length === 0) {
                callback("No decisions models returned", null);
                return;
            }
            callback(null, models);
        };
        xhr.send();
    } catch (e) {
        callback("Model fetch failed: " + e, null);
    }
}

function fetchModels(endpoint, apiKey, opts, callback) {
    if (typeof opts === "function") {
        callback = opts;
        opts = null;
    }
    var ep = String(endpoint || "").replace(/\/+$/, "");
    var host = hostOf(ep);
    var attribution = opts && opts.attribution;
    if (!callback) callback = function() {};

    function fallback() {
        callback(null, ["jev-latest"], 200);
    }

    // TypeSafe direct: GET /v1/models → { models: [{name, ...}] }
    if (host === "api.typesafe.ai") {
        _getModels(ep + "/models", apiKey, attribution, function(err, models) {
            if (err) fallback();
            else callback(null, models, 200);
        });
        return;
    }
    // OpenRouter hides decisions models from the default list; ask for them.
    if (Utils.isOpenRouterHost(host)) {
        _getModels(ep + "/models?output_modalities=decisions", apiKey, attribution, function(err, models) {
            if (err) fallback();
            else callback(null, models, 200);
        });
        return;
    }
    // Custom endpoint: try the standard models shapes.
    _getModels(ep + "/models", apiKey, attribution, function(err, models) {
        if (err) fallback();
        else callback(null, models, 200);
    });
}

function buildTools(options) {
    return [];
}

function buildContentArray(text, attachments) {
    return text;
}

/**
 * Single-shot chat evaluation: the user's message becomes the state and one
 * choice question produces a verdict.
 */
function buildChatDecision(state) {
    return {
        model: "",
        state: String(state || ""),
        questions: {
            answer: {
                type: "choice",
                instructions: "Evaluate the user's message. If it asks a yes/no question, decide whether the answer is yes or no. If it makes a factual claim, decide whether the claim is true. If it is an open-ended question, a request to perform an action, subjective, ambiguous, or cannot be decided from general knowledge, choose uncertain.",
                criteria: {
                    yes: "The yes/no question's answer is yes, or the factual claim is true.",
                    no: "The yes/no question's answer is no, or the factual claim is false.",
                    uncertain: "Open-ended questions, action requests, subjective or ambiguous messages, or anything that cannot be decided as true or false."
                }
            }
        }
    };
}

/**
 * Sends a single-shot decision for `state`. Callback receives
 * (error, {choice, confidence, probabilities, model}). Returns the underlying
 * XMLHttpRequest so the caller can abort.
 */
function sendDecisionChat(opts, callback) {
    opts = opts || {};
    var payload = buildChatDecision(opts.state);
    payload.model = Validator.decisionsModel({
        endpoint: opts.endpoint,
        modelName: opts.model
    });
    var url = Validator.decisionsUrl(opts.endpoint);
    if (!url) {
        if (callback) callback("Decisions endpoint is not configured", null);
        return null;
    }
    return Validator.postJson(url, opts.apiKey || "", payload, { attribution: opts.attribution }, function(err, json) {
        if (err) {
            if (callback) callback(String(err), null);
            return;
        }
        var a = json && json.answers && json.answers.answer;
        if (!a || a.type !== "choice" || !a.choice) {
            if (callback) callback("Decisions response is missing an answer", null);
            return;
        }
        if (callback) callback(null, {
            choice: String(a.choice),
            confidence: (typeof a.confidence === "number") ? a.confidence : null,
            probabilities: a.probabilities || {},
            model: json.model || opts.model || ""
        });
    });
}

/**
 * Decisions models cannot generate text. main.qml routes decisions profiles
 * to sendDecisionChat, so this is a guard for any path that still asks for a
 * text stream (e.g. compaction).
 */
function sendStreaming(opts) {
    if (opts && typeof opts.onComplete === "function") {
        opts.onComplete("", i18n("Decisions models cannot generate chat text. Use it as your active profile for single-shot evaluations, or select it as the Command Validator profile in Tools settings."));
    }
}
