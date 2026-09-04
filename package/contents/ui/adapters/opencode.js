/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// OpenCode Zen / Go gateway adapter. One apiType, two presets. Each model
// speaks a native protocol (Responses, chat completions, Anthropic messages,
// or Gemini generateContent); this module routes to the existing adapters
// after rewriting URLs/headers via opts.opencodeAuth.

.import "openai_chat.js" as Chat
.import "openai_responses.js" as Responses
.import "anthropic.js" as Anthropic
.import "gemini.js" as Gemini
.import "../opencodeRoute.js" as Route
.import "../utils.js" as Utils

var id = "opencode";
var displayName = "OpenCode";

// The gateway wants an x-opencode-session header on every request: one
// stable ID per conversation when the caller supplies one (opts.sessionId,
// maintained by main.qml), otherwise a per-call ID (models fetch, one-offs).
// Delivered to the protocol adapters via the generic opts.extraHeaders path.
function sessionHeaders(opts) {
    var h = {};
    var k;
    if (opts && opts.extraHeaders) {
        for (k in opts.extraHeaders) {
            if (opts.extraHeaders.hasOwnProperty(k))
                h[k] = opts.extraHeaders[k];
        }
    }
    h["x-opencode-session"] = (opts && opts.sessionId) ? opts.sessionId : Utils.uuidv4();
    return h;
}

var presets = [
    { name: "OpenCode Zen", url: "https://opencode.ai/zen/v1" },
    { name: "OpenCode Go",  url: "https://opencode.ai/zen/go/v1" }
];

var capabilities = {
    providerPresets: true,
    customEndpoint: true,
    reasoningEffort: true,
    thinkingBudget: true,
    fetchModels: true,
    reasoningHelp: "OpenCode routes each model to its native API (Responses, chat completions, Anthropic, or Gemini). Reasoning effort and thinking budget apply when the selected model supports them."
};

function productFromOpts(opts) {
    return Route.productFromEndpoint(
        opts && opts.endpoint,
        opts && opts.providerName
    );
}

function protocolFor(opts, model) {
    var mid = model;
    if (mid === undefined || mid === null)
        mid = opts && opts.model;
    return Route.resolveProtocol(productFromOpts(opts), mid);
}

function copyOpts(opts, extra) {
    var o = {};
    var k;
    if (opts) {
        for (k in opts) {
            if (opts.hasOwnProperty(k))
                o[k] = opts[k];
        }
    }
    o.opencodeAuth = true;
    o.extraHeaders = sessionHeaders(o);
    if (extra) {
        for (k in extra) {
            if (extra.hasOwnProperty(k))
                o[k] = extra[k];
        }
    }
    return o;
}

function fetchModels(endpoint, apiKey, opts, callback) {
    if (typeof opts === "function") {
        callback = opts;
        opts = null;
    }
    return Chat.fetchModels(endpoint, apiKey, { extraHeaders: sessionHeaders(opts) }, callback);
}

function buildTools(options) {
    var p = protocolFor(options);
    var o = copyOpts(options);
    if (p === "responses") {
        o.usesResponsesAPI = true;
        return Responses.buildTools(o);
    }
    if (p === "anthropic")
        return Anthropic.buildTools(o);
    if (p === "gemini")
        return Gemini.buildTools(o);
    return Chat.buildTools(o);
}

function buildContentArray(text, attachments, extra) {
    var model = extra;
    var product = "zen";
    if (extra && typeof extra === "object") {
        model = extra.model;
        product = Route.productFromEndpoint(extra.endpoint, extra.providerName);
    }
    var p = Route.resolveProtocol(product, model);
    if (p === "responses")
        return Responses.buildContentArray(text, attachments);
    if (p === "anthropic")
        return Anthropic.buildContentArray(text, attachments);
    if (p === "gemini")
        return Gemini.buildContentArray(text, attachments);
    return Chat.buildContentArray(text, attachments);
}

function sendStreaming(opts) {
    var p = protocolFor(opts);
    var o = copyOpts(opts);
    if (p === "responses") {
        o.usesResponsesAPI = true;
        return Responses.sendStreaming(o);
    }
    if (p === "anthropic")
        return Anthropic.sendStreaming(o);
    if (p === "gemini")
        return Gemini.sendStreaming(o);
    return Chat.sendStreaming(o);
}
