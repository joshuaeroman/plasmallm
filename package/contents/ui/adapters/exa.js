/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.import "openai_chat.js" as Chat

var id = "exa";
var displayName = "Exa";

var presets = [
    { name: "Exa API", url: "https://api.exa.ai" }
];

var capabilities = {
    providerPresets: false,
    customEndpoint: false,
    reasoningEffort: false,
    thinkingBudget: false,
    fetchModels: true,
    // Shown in config even without thinking knobs (see configGeneral.qml).
    reasoningHelp: i18n("Exa performs real-time neural search and synthesizes grounded answers with live web citations.")
};

function fetchModels(endpoint, apiKey, opts, callback) {
    if (typeof opts === "function") {
        callback = opts;
        opts = null;
    }
    // OpenAI-compat chat model per Exa docs.
    var models = ["exa"];
    if (callback) callback(null, models, 200);
    return models;
}

function buildTools(options) {
    return [];
}

function buildContentArray(text, attachments) {
    return Chat.buildContentArray(text, attachments);
}

function sendStreaming(opts) {
    // Shallow copy — avoid Object.assign for broader QJSEngine consistency.
    var options = {};
    if (opts) {
        for (var k in opts) {
            if (opts.hasOwnProperty(k)) options[k] = opts[k];
        }
    }
    // Always normalize endpoint to https://api.exa.ai for Exa adapter
    options.endpoint = "https://api.exa.ai";

    // Fallback to exaApiKey if main apiKey is missing
    if ((!options.apiKey || options.apiKey.trim() === "") && options.exaApiKey) {
        options.apiKey = options.exaApiKey;
    }

    // Ensure model is valid for Exa chat completions endpoint
    if (!options.model || options.model !== "exa") {
        options.model = "exa";
    }

    return Chat.sendStreaming(options);
}
