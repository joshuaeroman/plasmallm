#!/usr/bin/env node
// Unit tests for the decisions adapter (package/contents/ui/adapters/decisions.js).
// Loads commandValidator.js for its pure helpers, strips the adapter's `.import`
// line, and injects a stubbed Validator + XMLHttpRequest.
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

// Pure validator helpers first, so the adapter can delegate to them.
const validatorSandbox = { console };
vm.createContext(validatorSandbox);
vm.runInContext(
    fs.readFileSync(path.join(__dirname, "../package/contents/ui/commandValidator.js"), "utf8"),
    validatorSandbox
);
const V = validatorSandbox;

// --- decisions adapter sandbox ---------------------------------------------
const raw = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/adapters/decisions.js"),
    "utf8"
);
const src = raw.replace(/^\.import .*$/gm, "");

const sandbox = {
    console: { log() {}, warn() {}, error() {} },
    i18n,
    Validator: {
        hostOf: V.hostOf,
        decisionsUrl: V.decisionsUrl,
        decisionsModel: V.decisionsModel,
        httpErrorMessage: V.httpErrorMessage,
        postJson: null
    }
};

let responder = null;
sandbox.XMLHttpRequest = function () {
    const self = this;
    sandbox.XMLHttpRequest.instances.push(this);
    this.readyState = 0;
    this.status = 0;
    this.responseText = "";
    this.timeout = 0;
    this.requestHeaders = {};
    this.url = "";
    this.method = "";
    this.open = function (method, url) { self.method = method; self.url = url; };
    this.setRequestHeader = function (k, v) { self.requestHeaders[k] = v; };
    this.abort = function () {};
    this.send = function () {
        if (responder) responder(self);
    };
};
sandbox.XMLHttpRequest.instances = [];
sandbox.XMLHttpRequest.DONE = 4;

vm.createContext(sandbox);
vm.runInContext(src, sandbox);
const D = sandbox;

function respondJson(body, status) {
    return function (xhr) {
        xhr.status = status === undefined ? 200 : status;
        xhr.responseText = JSON.stringify(body);
        xhr.readyState = 4;
        if (xhr.onreadystatechange) xhr.onreadystatechange();
    };
}

// --- metadata ---------------------------------------------------------------
eq(D.id, "decisions", "adapter id");
eq(D.capabilities.chatMode, "decisions", "chatMode capability");
eq(D.capabilities.fetchModels, true, "fetchModels capability");
eq(D.capabilities.reasoningEffort, false, "no reasoning effort");
eq(D.presets.length, 2, "two presets");
eq(D.buildTools({}), [], "no tools");

// --- fetchModels ------------------------------------------------------------
function fetchOnce(endpoint, key, body, status) {
    let out = null;
    responder = respondJson(body, status);
    D.fetchModels(endpoint, key, function (err, models) {
        out = { err: err, models: models };
    });
    return { out: out, xhr: sandbox.XMLHttpRequest.instances.pop() };
}

{
    const r = fetchOnce("https://api.typesafe.ai/v1", "k", {
        models: [{ name: "jev-latest" }, { name: "jev-1.13.0" }]
    });
    eq(r.out.models, ["jev-latest", "jev-1.13.0"], "typesafe models parsed");
    eq(r.xhr.url, "https://api.typesafe.ai/v1/models", "typesafe models url");
    eq(r.xhr.requestHeaders["Authorization"], "Bearer k", "bearer header");
}
{
    const r = fetchOnce("https://openrouter.ai/api/v1", "k", {
        data: [{ id: "~typesafe/jev-latest" }, { id: "typesafe/jev-1.13" }]
    });
    eq(r.out.models, ["~typesafe/jev-latest", "typesafe/jev-1.13"], "openrouter decisions models parsed");
    ok(r.xhr.url.indexOf("output_modalities=decisions") !== -1, "openrouter decisions query");
}
{
    const r = fetchOnce("https://proxy.example/v1", "", { data: [{ id: "decisions-model" }] });
    eq(r.out.models, ["decisions-model"], "custom endpoint openai shape");
}
{
    const r = fetchOnce("https://api.typesafe.ai/v1", "k", { detail: { message: "nope" } }, 403);
    eq(r.out.err, null, "fallback keeps error null");
    eq(r.out.models, ["jev-latest"], "fallback list on error");
}
{
    const r = fetchOnce("https://openrouter.ai/api/v1", "k", { data: [] });
    eq(r.out.models, ["jev-latest"], "fallback list on empty response");
}

// --- chat decision request ---------------------------------------------------
{
    const req = D.buildChatDecision("Is the sky blue?");
    eq(req.state, "Is the sky blue?", "state preserved");
    eq(req.model, "", "model filled by sender");
    eq(req.questions.answer.type, "choice", "choice question");
    eq(Object.keys(req.questions.answer.criteria), ["yes", "no", "uncertain"], "verdict options");
}

// --- sendDecisionChat --------------------------------------------------------
const postCalls = [];
sandbox.Validator.postJson = function (url, key, payload, callback) {
    postCalls.push({ url: url, key: key, payload: payload });
    callback(null, {
        model: "typesafe/jev-1.13-20260917",
        answers: {
            answer: {
                type: "choice",
                choice: "yes",
                confidence: 0.98,
                probabilities: { yes: 0.98, no: 0.01, uncertain: 0.01 }
            }
        }
    });
};
{
    let out = null;
    D.sendDecisionChat({ endpoint: "https://openrouter.ai/api/v1", apiKey: "k", model: "~typesafe/jev-latest", state: "Is the sky blue?" }, function (err, v) {
        out = { err: err, v: v };
    });
    eq(postCalls[0].url, "https://openrouter.ai/api/alpha/decisions", "openrouter decisions url");
    eq(postCalls[0].payload.model, "~typesafe/jev-latest", "model prefix kept for openrouter");
    eq(out.err, null, "no error");
    eq(out.v.choice, "yes", "choice surfaced");
    eq(out.v.confidence, 0.98, "confidence surfaced");
    eq(out.v.model, "typesafe/jev-1.13-20260917", "versioned model surfaced");
}
{
    let out = null;
    D.sendDecisionChat({ endpoint: "https://api.typesafe.ai/v1", apiKey: "k", model: "~typesafe/jev-latest", state: "x" }, function (err, v) {
        out = { err: err, v: v };
    });
    eq(postCalls[1].url, "https://api.typesafe.ai/v1/systemone", "typesafe decisions url");
    eq(postCalls[1].payload.model, "jev-latest", "typesafe model prefix stripped");
    eq(out.err, null, "typesafe no error");
}
{
    sandbox.Validator.postJson = function (url, key, payload, callback) {
        callback(null, { answers: {} });
    };
    let errText = null;
    D.sendDecisionChat({ endpoint: "https://api.typesafe.ai/v1", apiKey: "k", model: "jev-latest", state: "x" }, function (err) {
        errText = err;
    });
    ok(!!errText, "missing answer errors");
}

// --- sendStreaming refusal ---------------------------------------------------
{
    let errText = null;
    D.sendStreaming({ onComplete: function (text, err) { errText = err; } });
    ok(!!errText && errText.indexOf("Decisions") !== -1, "streaming refused");
}

if (failed > 0) {
    console.error(`decisions_adapter: ${failed} failure(s)`);
    process.exit(1);
}
console.log("decisions_adapter: ok");
