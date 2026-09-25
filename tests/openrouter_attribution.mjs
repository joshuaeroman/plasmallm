#!/usr/bin/env node
/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// Unit tests for OpenRouter app-attribution headers (HTTP-Referer /
// X-OpenRouter-Title) in the OpenAI-compatible adapter strategies
// (openai_chat.js, openai_responses.js) and the decisions transport
// (commandValidator.js). Strips `.import` lines and injects a stubbed
// XMLHttpRequest so request headers can be inspected.
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a !== e) {
        failed++;
        console.error("FAIL", msg, "\n  expected:", e, "\n  actual:  ", a);
    }
}
function ok(cond, msg) {
    if (!cond) {
        failed++;
        console.error("FAIL", msg);
    }
}
function i18n() {
    let s = String(arguments[0]);
    for (let i = 1; i < arguments.length; i++) {
        s = s.split("%" + i).join(String(arguments[i]));
    }
    return s;
}

const REFERRER = "https://github.com/joshuaeroman/plasmallm";
const APP_TITLE = "PlasmaLLM";

function loadStrategy(file) {
    const raw = fs.readFileSync(
        path.join(__dirname, "../package/contents/ui/adapters/", file),
        "utf8"
    );
    const src = raw.replace(/^\.import .*$/gm, "");
    const sandbox = {
        console: { log() {}, warn() {}, error() {} },
        i18n,
        XMLHttpRequest: null
    };
    vm.createContext(sandbox);
    // Strategies import utils.js (stripped above); wire the real helpers in.
    vm.runInContext(
        fs.readFileSync(path.join(__dirname, "../package/contents/ui/utils.js"), "utf8"),
        sandbox
    );
    sandbox.Utils = {
        hostOf: sandbox.hostOf,
        isOpenRouterHost: sandbox.isOpenRouterHost,
        isOpenRouterEndpoint: sandbox.isOpenRouterEndpoint,
        isOpenRouterProvider: sandbox.isOpenRouterProvider,
    applyOpenRouterAttribution: sandbox.applyOpenRouterAttribution
    };
    vm.runInContext(src, sandbox);
    return sandbox;
}

const Chat = loadStrategy("openai_chat.js");
const Responses = loadStrategy("openai_responses.js");

// --- utils.js matcher semantics ------------------------------------------------
{
    const U = Chat.Utils;
    eq(U.hostOf("https://OpenRouter.AI/api/v1"), "openrouter.ai", "hostOf lowercases");
    eq(U.hostOf("not a url"), "", "hostOf empty on garbage");
    eq(U.isOpenRouterHost("openrouter.ai"), true, "host: bare domain");
    eq(U.isOpenRouterHost("www.openrouter.ai"), true, "host: www subdomain");
    eq(U.isOpenRouterHost("api.openrouter.ai"), true, "host: api subdomain");
    eq(U.isOpenRouterHost("notopenrouter.ai"), false, "host: suffix must be a dot");
    eq(U.isOpenRouterHost("openrouter.ai.evil.com"), false, "host: no trailing match");
    eq(U.isOpenRouterHost(""), false, "host: empty");
    eq(U.isOpenRouterEndpoint("https://www.openrouter.ai/api/v1"), true, "endpoint: subdomain");
    eq(U.isOpenRouterEndpoint("http://openrouter.ai/api/v1"), true, "endpoint: bare");
    eq(U.isOpenRouterEndpoint("https://api.openai.com/v1"), false, "endpoint: openai");
    eq(U.isOpenRouterProvider("OpenRouter", "https://gw.example/v1"), true, "provider: name match");
    eq(U.isOpenRouterProvider("openrouter", ""), true, "provider: case-insensitive name");
    eq(U.isOpenRouterProvider("Groq", "https://api.groq.com/v1"), false, "provider: no match");
    eq(U.isOpenRouterProvider("", "https://openrouter.ai/api/v1"), true, "provider: endpoint fallback");
}

function makeXhr() {
    return {
        requestHeaders: {},
        setRequestHeader(k, v) { this.requestHeaders[k] = String(v); }
    };
}

// --- utils.js applyOpenRouterAttribution ----------------------------------------
{
    const U = Chat.Utils;
    const xhr = makeXhr();
    U.applyOpenRouterAttribution(xhr, { attribution: true, providerName: "OpenRouter" }, "https://gw.example/v1");
    eq(xhr.requestHeaders["HTTP-Referer"], REFERRER, "helper: name-based apply");
    eq(xhr.requestHeaders["X-OpenRouter-Title"], APP_TITLE, "helper: title apply");

    const xhr2 = makeXhr();
    U.applyOpenRouterAttribution(xhr2, { attribution: true }, "https://openrouter.ai/api/v1");
    eq(xhr2.requestHeaders["HTTP-Referer"], REFERRER, "helper: endpoint-based apply");

    const xhr3 = makeXhr();
    U.applyOpenRouterAttribution(xhr3, null, "https://openrouter.ai/api/v1");
    ok(!("HTTP-Referer" in xhr3.requestHeaders), "helper: null opts stays off");

    const xhr4 = makeXhr();
    U.applyOpenRouterAttribution(xhr4, { attribution: true }, "https://api.openai.com/v1");
    ok(!("HTTP-Referer" in xhr4.requestHeaders), "helper: non-OpenRouter stays off");
}

// --- chat strategy: setHeaders ------------------------------------------------
{
    const xhr = makeXhr();
    Chat.setHeaders(xhr, "k", "https://openrouter.ai/api/v1",
        { sessionId: "s1", attribution: true });
    eq(xhr.requestHeaders["HTTP-Referer"], REFERRER, "chat: referer on openrouter endpoint");
    eq(xhr.requestHeaders["X-OpenRouter-Title"], APP_TITLE, "chat: title on openrouter endpoint");
    eq(xhr.requestHeaders["x-session-id"], "s1", "chat: session affinity kept");
}

{
    const xhr = makeXhr();
    Chat.setHeaders(xhr, "k", "https://openrouter.ai/api/v1",
        { sessionId: "s1", attribution: false });
    ok(!("HTTP-Referer" in xhr.requestHeaders), "chat: opt-out skips referer");
    ok(!("X-OpenRouter-Title" in xhr.requestHeaders), "chat: opt-out skips title");
}

{
    // A missing attribution key must not enable headers: a call site that
    // forgets to wire the setting stays header-free (opt-out safety).
    const xhr = makeXhr();
    Chat.setHeaders(xhr, "k", "https://openrouter.ai/api/v1", { sessionId: "s1" });
    ok(!("HTTP-Referer" in xhr.requestHeaders), "chat: missing attribution key stays off");
    eq(xhr.requestHeaders["x-session-id"], "s1", "chat: session affinity unaffected");
}

{
    // Legacy callers with no opts object cannot carry the preference —
    // headers stay off.
    const xhr = makeXhr();
    Chat.setHeaders(xhr, "k", "https://openrouter.ai/api/v1", null);
    ok(!("HTTP-Referer" in xhr.requestHeaders), "chat: null opts (legacy) sends nothing");
}

{
    // Provider name detection even when endpoint is a gateway URL.
    const xhr = makeXhr();
    Chat.setHeaders(xhr, "k", "https://gw.example/v1",
        { providerName: "OpenRouter", attribution: true });
    eq(xhr.requestHeaders["HTTP-Referer"], REFERRER, "chat: provider-based detection");
}

{
    // Case-insensitive provider match.
    const xhr = makeXhr();
    Chat.setHeaders(xhr, "k", "https://gw.example/v1",
        { providerName: "openrouter", attribution: true });
    eq(xhr.requestHeaders["HTTP-Referer"], REFERRER, "chat: case-insensitive provider");
}

{
    // Subdomain endpoints attributed when opted in.
    const xhr = makeXhr();
    Chat.setHeaders(xhr, "k", "https://www.openrouter.ai/api/v1", { attribution: true });
    eq(xhr.requestHeaders["HTTP-Referer"], REFERRER, "chat: subdomain attributed");
}

{
    const xhr = makeXhr();
    Chat.setHeaders(xhr, "k", "https://api.openai.com/v1",
        { sessionId: "s1", attribution: true });
    ok(!("HTTP-Referer" in xhr.requestHeaders), "chat: no attribution on OpenAI");
    ok(!("X-OpenRouter-Title" in xhr.requestHeaders), "chat: no title on OpenAI");
}

{
    const xhr = makeXhr();
    Chat.setHeaders(xhr, "k", "http://localhost:11434/v1", { attribution: true });
    ok(!("HTTP-Referer" in xhr.requestHeaders), "chat: no attribution on Ollama");
}

// --- responses strategy: setHeaders -------------------------------------------
{
    const xhr = makeXhr();
    Responses.setHeaders(xhr, "k", "https://openrouter.ai/api/v1",
        { sessionId: "s2", attribution: true });
    eq(xhr.requestHeaders["HTTP-Referer"], REFERRER, "responses: referer on openrouter");
    eq(xhr.requestHeaders["X-OpenRouter-Title"], APP_TITLE, "responses: title on openrouter");
    eq(xhr.requestHeaders["x-session-id"], "s2", "responses: session affinity kept");
}

{
    const xhr = makeXhr();
    Responses.setHeaders(xhr, "k", "https://openrouter.ai/api/v1", { attribution: false });
    ok(!("HTTP-Referer" in xhr.requestHeaders), "responses: opt-out skips referer");
    ok(!("X-OpenRouter-Title" in xhr.requestHeaders), "responses: opt-out skips title");
}

{
    // Missing key stays off, matching the chat strategy.
    const xhr = makeXhr();
    Responses.setHeaders(xhr, "k", "https://openrouter.ai/api/v1", { providerName: "OpenRouter" });
    ok(!("HTTP-Referer" in xhr.requestHeaders), "responses: missing attribution key stays off");
}

{
    const xhr = makeXhr();
    Responses.setHeaders(xhr, "k", "https://api.groq.com/openai/v1",
        { providerName: "Groq", attribution: true });
    ok(!("HTTP-Referer" in xhr.requestHeaders), "responses: no attribution on Groq");
}

// --- chat strategy: fetchModels (GET /models) ----------------------------------
// The adapter constructs its own XMLHttpRequest inside the vm, so use a
// module-level responder shared by every instance (decisions_adapter pattern)
// and track the most recent instance.
let responder = null;
function HarnessXHR() {
    const self = this;
    HarnessXHR.lastInstance = this;
    this.readyState = 0;
    this.status = 0;
    this.responseText = "";
    this.timeout = 0;
    this.requestHeaders = {};
    this.url = "";
    this.method = "";
    this.open = function (method, url) { self.method = method; self.url = url; };
    this.setRequestHeader = function (k, v) { self.requestHeaders[k] = String(v); };
    this.abort = function () {};
    this.send = function () { if (responder) responder(self); };
}
HarnessXHR.DONE = 4;
Chat.XMLHttpRequest = HarnessXHR;

function chatFetchOnce(endpoint, opts) {
    let out = null;
    responder = function (xhr) {
        xhr.status = 200;
        xhr.responseText = JSON.stringify({ data: [{ id: "m1" }] });
        xhr.readyState = 4;
        if (xhr.onreadystatechange) xhr.onreadystatechange();
    };
    Chat.fetchModels(endpoint, "k", opts, function (err, models) {
        out = { err: err, models: models };
    });
    return { out: out, xhr: HarnessXHR.lastInstance };
}

{
    const r = chatFetchOnce("https://openrouter.ai/api/v1",
        { providerName: "OpenRouter", attribution: true });
    eq(r.out.models, ["m1"], "chat fetchModels parses list");
    eq(r.xhr.url, "https://openrouter.ai/api/v1/models", "chat fetchModels url");
    eq(r.xhr.requestHeaders["HTTP-Referer"], REFERRER, "chat fetchModels: referer sent");
    eq(r.xhr.requestHeaders["X-OpenRouter-Title"], APP_TITLE, "chat fetchModels: title sent");
}

{
    // Missing attribution key stays off, even on OpenRouter.
    const r = chatFetchOnce("https://openrouter.ai/api/v1", { providerName: "OpenRouter" });
    ok(!("HTTP-Referer" in r.xhr.requestHeaders), "chat fetchModels: missing key stays off");
}

{
    const r = chatFetchOnce("https://openrouter.ai/api/v1", { attribution: false });
    ok(!("HTTP-Referer" in r.xhr.requestHeaders), "chat fetchModels: opt-out respected");
}

{
    const r = chatFetchOnce("https://api.openai.com/v1", { providerName: "OpenAI" });
    ok(!("HTTP-Referer" in r.xhr.requestHeaders), "chat fetchModels: no attribution on OpenAI");
}

// --- responses strategy: fetchModels (GET /models) ------------------------------
let responsesResponder = null;
function ResponsesXML() {
    const self = this;
    ResponsesXML.lastInstance = this;
    this.readyState = 0;
    this.status = 0;
    this.responseText = "";
    this.timeout = 0;
    this.requestHeaders = {};
    this.url = "";
    this.method = "";
    this.open = function (method, url) { self.method = method; self.url = url; };
    this.setRequestHeader = function (k, v) { self.requestHeaders[k] = String(v); };
    this.abort = function () {};
    this.send = function () { if (responsesResponder) responsesResponder(self); };
}
ResponsesXML.DONE = 4;
Responses.XMLHttpRequest = ResponsesXML;

function responsesFetchOnce(endpoint, opts) {
    let out = null;
    responsesResponder = function (xhr) {
        xhr.status = 200;
        xhr.responseText = JSON.stringify({ data: [{ id: "r1" }] });
        xhr.readyState = 4;
        if (xhr.onreadystatechange) xhr.onreadystatechange();
    };
    Responses.fetchModels(endpoint, "k", opts, function (err, models) {
        out = { err: err, models: models };
    });
    return { out: out, xhr: ResponsesXML.lastInstance };
}
ResponsesXML.lastInstance = null;

{
    const r = responsesFetchOnce("https://openrouter.ai/api/v1",
        { providerName: "OpenRouter", attribution: true });
    eq(r.out.models, ["r1"], "responses fetchModels parses list");
    eq(r.xhr.requestHeaders["HTTP-Referer"], REFERRER, "responses fetchModels: referer sent");
    eq(r.xhr.requestHeaders["X-OpenRouter-Title"], APP_TITLE, "responses fetchModels: title sent");
}

{
    const r = responsesFetchOnce("https://openrouter.ai/api/v1", { attribution: false });
    ok(!("HTTP-Referer" in r.xhr.requestHeaders), "responses fetchModels: opt-out respected");
}

// --- openai.js dispatcher: opts forwarded to strategies -------------------------
{
    const raw = fs.readFileSync(
        path.join(__dirname, "../package/contents/ui/adapters/openai.js"),
        "utf8"
    );
    const sandbox = { console: { log() {}, warn() {}, error() {} } };
    vm.createContext(sandbox);
    const calls = { chat: [], responses: [] };
    sandbox.Chat = {
        fetchModels: function (endpoint, apiKey, opts, cb) {
            calls.chat.push({ endpoint: endpoint, opts: opts });
            cb(null, ["chat-model"], 200);
        }
    };
    sandbox.Responses = {
        fetchModels: function (endpoint, apiKey, opts, cb) {
            calls.responses.push({ endpoint: endpoint, opts: opts });
            cb(null, ["responses-model"], 200);
        }
    };
    vm.runInContext(raw.replace(/^\.import .*$/gm, ""), sandbox);
    const AD = sandbox;

    let out = null;
    AD.fetchModels("https://openrouter.ai/api/v1", "k", true, { attribution: true }, function (e, m) { out = m; });
    eq(out, ["responses-model"], "dispatcher: responses path");
    eq(calls.responses[0].opts.attribution, true, "dispatcher: opts forwarded to Responses");

    out = null;
    AD.fetchModels("https://openrouter.ai/api/v1", "k", false, { attribution: true }, function (e, m) { out = m; });
    eq(out, ["chat-model"], "dispatcher: chat path");
    eq(calls.chat[0].opts.attribution, true, "dispatcher: opts forwarded to Chat");

    // Legacy 4-arg form (opts era callers): no opts, callback as 4th arg.
    out = null;
    AD.fetchModels("https://api.openai.com/v1", "k", false, function (e, m) { out = m; });
    eq(out, ["chat-model"], "dispatcher: legacy form");
    eq(calls.chat[1].opts, null, "dispatcher: legacy form has null opts");
}

// --- decisions transport: commandValidator.js postJson -------------------------
// commandValidator.js imports utils.js; strip `.import` lines and wire the
// real utils.js helpers in.
const validatorSandbox = {
    console: { log() {}, warn() {}, error() {} },
    i18n,
    XMLHttpRequest: null
};
vm.createContext(validatorSandbox);
vm.runInContext(
    fs.readFileSync(path.join(__dirname, "../package/contents/ui/utils.js"), "utf8"),
    validatorSandbox
);
validatorSandbox.Utils = {
    hostOf: validatorSandbox.hostOf,
    isOpenRouterHost: validatorSandbox.isOpenRouterHost,
    isOpenRouterEndpoint: validatorSandbox.isOpenRouterEndpoint,
    isOpenRouterProvider: validatorSandbox.isOpenRouterProvider,
    applyOpenRouterAttribution: validatorSandbox.applyOpenRouterAttribution
};
vm.runInContext(
    fs.readFileSync(path.join(__dirname, "../package/contents/ui/commandValidator.js"), "utf8")
        .replace(/^\.import .*$/gm, ""),
    validatorSandbox
);
const CV = validatorSandbox;
let validatorResponder = null;
function ValidatorXHR() {
    const self = this;
    ValidatorXHR.lastInstance = this;
    this.readyState = 0;
    this.status = 0;
    this.responseText = "";
    this.timeout = 0;
    this.requestHeaders = {};
    this.url = "";
    this.method = "";
    this.open = function (method, url) { self.method = method; self.url = url; };
    this.setRequestHeader = function (k, v) { self.requestHeaders[k] = String(v); };
    this.abort = function () {};
    this.send = function (body) {
        self.sentBody = body;
        if (validatorResponder) validatorResponder(self);
    };
}
ValidatorXHR.DONE = 4;
validatorSandbox.XMLHttpRequest = ValidatorXHR;

function postJsonOnce(url, opts) {
    let out = null;
    validatorResponder = function (xhr) {
        xhr.status = 200;
        xhr.responseText = JSON.stringify({});
        xhr.readyState = 4;
        if (xhr.onreadystatechange) xhr.onreadystatechange();
    };
    if (opts === undefined) {
        // Legacy 4-arg form: postJson(url, key, payload, callback).
        CV.postJson(url, "k", {}, function (err) { out = err; });
    } else {
        CV.postJson(url, "k", {}, opts, function (err) { out = err; });
    }
    return { out: out, xhr: ValidatorXHR.lastInstance };
}

{
    // Unified story: a caller without an opts object cannot carry the
    // preference, so headers stay off (same as the chat/responses setHeaders).
    const r = postJsonOnce("https://openrouter.ai/api/alpha/decisions");
    eq(r.out, null, "postJson legacy form succeeds");
    ok(!("HTTP-Referer" in r.xhr.requestHeaders), "postJson: legacy form sends no referer");
    ok(!("X-OpenRouter-Title" in r.xhr.requestHeaders), "postJson: legacy form sends no title");
}

{
    // Strict rule: attribution requires an explicit true.
    const r = postJsonOnce("https://openrouter.ai/api/alpha/decisions", { attribution: undefined });
    ok(!("HTTP-Referer" in r.xhr.requestHeaders), "postJson: missing key stays off");
}

{
    const r = postJsonOnce("https://openrouter.ai/api/alpha/decisions", { attribution: true });
    eq(r.xhr.requestHeaders["HTTP-Referer"], REFERRER, "postJson: attribution on when true");
    eq(r.xhr.requestHeaders["X-OpenRouter-Title"], APP_TITLE, "postJson: title when true");
}

// --- STT: sttAdapters/openai_transcriptions.js setHeaders ----------------------
{
    const raw = fs.readFileSync(
        path.join(__dirname, "../package/contents/ui/sttAdapters/openai_transcriptions.js"),
        "utf8"
    );
    const sandbox = {
        console: { log() {}, warn() {}, error() {} },
        i18n,
        XMLHttpRequest: null
    };
    vm.createContext(sandbox);
    vm.runInContext(
        fs.readFileSync(path.join(__dirname, "../package/contents/ui/utils.js"), "utf8"),
        sandbox
    );
    sandbox.Utils = {
        hostOf: sandbox.hostOf,
        isOpenRouterHost: sandbox.isOpenRouterHost,
        isOpenRouterEndpoint: sandbox.isOpenRouterEndpoint,
        isOpenRouterProvider: sandbox.isOpenRouterProvider,
    applyOpenRouterAttribution: sandbox.applyOpenRouterAttribution
    };
    vm.runInContext(raw.replace(/^\.import .*$/gm, ""), sandbox);
    const STT = sandbox;

    const xhr = makeXhr();
    STT.setHeaders(xhr, "k", "https://openrouter.ai/api/v1", { attribution: true });
    eq(xhr.requestHeaders["HTTP-Referer"], REFERRER, "stt: referer on openrouter");
    eq(xhr.requestHeaders["X-OpenRouter-Title"], APP_TITLE, "stt: title on openrouter");

    const xhr2 = makeXhr();
    STT.setHeaders(xhr2, "k", "https://openrouter.ai/api/v1", { attribution: false });
    ok(!("HTTP-Referer" in xhr2.requestHeaders), "stt: opt-out skips referer");

    const xhr3 = makeXhr();
    STT.setHeaders(xhr3, "k", "https://openrouter.ai/api/v1");
    ok(!("HTTP-Referer" in xhr3.requestHeaders), "stt: null opts sends nothing (model listing)");

    const xhr4 = makeXhr();
    STT.setHeaders(xhr4, "k", "https://api.openai.com/v1", { attribution: true });
    ok(!("HTTP-Referer" in xhr4.requestHeaders), "stt: no attribution on OpenAI");

    // Provider name detection: custom gateway + sttProviderName "OpenRouter".
    const xhr5 = makeXhr();
    STT.setHeaders(xhr5, "k", "https://gw.example/v1",
        { providerName: "OpenRouter", attribution: true });
    eq(xhr5.requestHeaders["HTTP-Referer"], REFERRER, "stt: provider-name detection");

    const xhr6 = makeXhr();
    STT.setHeaders(xhr6, "k", "https://gw.example/v1", { attribution: true });
    ok(!("HTTP-Referer" in xhr6.requestHeaders), "stt: custom gateway without name stays off");

    const xhr7 = makeXhr();
    STT.setHeaders(xhr7, "k", "https://openrouter.ai/api/v1", { attribution: false });
    ok(!("X-OpenRouter-Title" in xhr7.requestHeaders), "stt: opt-out skips title");
}

{
    const r = postJsonOnce("https://openrouter.ai/api/alpha/decisions", { attribution: false });
    ok(!("HTTP-Referer" in r.xhr.requestHeaders), "postJson: opt-out skips referer");
    ok(!("X-OpenRouter-Title" in r.xhr.requestHeaders), "postJson: opt-out skips title");
}

{
    const r = postJsonOnce("https://api.typesafe.ai/v1/systemone");
    ok(!("HTTP-Referer" in r.xhr.requestHeaders), "postJson: no attribution on TypeSafe");
    ok(!("X-OpenRouter-Title" in r.xhr.requestHeaders), "postJson: no title on TypeSafe");
}

if (failed > 0) {
    console.error(`openrouter_attribution: ${failed} failure(s)`);
    process.exit(1);
}
console.log("openrouter_attribution: ok");
