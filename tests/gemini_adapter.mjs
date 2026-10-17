#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Minimal XMLHttpRequest stand-in: each request is queued and answered by
// the test with respond(status, body).
const requests = [];
class FakeXHR {
    static DONE = 4;
    constructor() { this.headers = {}; this.readyState = 0; this.aborted = false; }
    open(method, url) {
        this.method = method; this.url = url; this.readyState = 1;
        if (this.onreadystatechange) this.onreadystatechange();
    }
    setRequestHeader(k, v) { this.headers[k] = v; }
    send(body) { this.body = body; requests.push(this); }
    abort() { this.aborted = true; this.respond(0, ""); }
    respond(status, body) {
        this.status = status;
        this.responseText = body;
        this.readyState = 4;
        if (this.onreadystatechange) this.onreadystatechange();
    }
}

function loadModule(relPath, extraScope = {}) {
    let code = fs.readFileSync(path.join(__dirname, relPath), "utf8");
    code = code.replace(/^\s*\.(import|pragma)\s+.*$/gm, "");
    const sandbox = { console, XMLHttpRequest: FakeXHR, ...extraScope };
    vm.createContext(sandbox);
    vm.runInContext(code, sandbox);
    return sandbox;
}

const AgentPlatform = loadModule("../package/contents/ui/adapters/agentPlatform.js");
const Gemini = loadModule("../package/contents/ui/adapters/gemini.js", {
    AgentPlatform,
    GeminiThinking: { buildThinkingConfig: function() { return {}; } },
    ToolManager: {},
    // The adapter logs failed completions; the failure cases below are expected.
    console: Object.assign({}, console, { error: function() {} }),
    i18n: function(s) {
        const args = Array.prototype.slice.call(arguments, 1);
        return s.replace(/%(\d)/g, function(m, n) { return String(args[n - 1]); });
    }
});

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

const AP = "https://aiplatform.googleapis.com";
const SSE = 'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"OK"}]}}]}\n\n';
const NOT_FOUND = JSON.stringify({ error: { code: 404, message:
    "Publisher model `projects/42/locations/us-east4/publishers/google/models/x` was not found" } });

function send(extra) {
    const result = {};
    const handle = Gemini.sendStreaming(Object.assign({
        endpoint: AP,
        apiKey: "AQ.key",
        model: "gemini-4-argon",
        temperature: 70,
        maxTokens: 100,
        messages: [{ role: "user", content: "hi" }],
        geminiAuthMethod: "agentplatform",
        geminiVertexAuthType: "apikey",
        onChunk: function() {},
        onComplete: function(text, err) { result.text = text; result.err = err; }
    }, extra || {}));
    return { handle, result };
}

// First express-key request: project lookup, then the chat request on the
// project URL.
let { handle, result } = send();
eq(requests.length, 1, "only the lookup is in flight");
let lookup = requests.shift();
ok(/\/v1\/publishers\/google\/models\/[^/]+:countTokens$/.test(lookup.url), "lookup uses express countTokens");
ok(handle.xhr !== null && typeof handle.xhr.abort === "function", "handle is abortable during lookup");
lookup.respond(404, NOT_FOUND);
eq(requests.length, 1, "chat request sent after lookup");
let chat = requests.shift();
eq(chat.url, AP + "/v1/projects/42/locations/global/publishers/google/models/gemini-4-argon:streamGenerateContent?alt=sse",
    "chat request uses discovered project");
eq(chat.headers["x-goog-api-key"], "AQ.key", "chat request keeps key header");
ok(handle.xhr === chat, "handle.xhr now points at the chat request");
chat.respond(200, SSE);
eq(result, { text: "OK", err: null }, "stream completes");

// Same key again: cached project, no lookup.
({ handle, result } = send());
eq(requests.length, 1, "cached project skips the lookup");
chat = requests.shift();
ok(chat.url.indexOf("/v1/projects/42/locations/global/") !== -1, "cached project used");
chat.respond(200, SSE);

// Cancel during lookup: chat request never starts.
({ handle, result } = send({ apiKey: "AQ.cancel" }));
lookup = requests.shift();
handle.xhr.abort();
eq(requests.length, 0, "cancelled lookup sends no chat request");
ok(lookup.aborted, "lookup request aborted");

// Lookup fails: fall back to the express URL.
({ handle, result } = send({ apiKey: "AQ.bad" }));
requests.shift().respond(400, '{"error":{"message":"API key not valid"}}');
chat = requests.shift();
eq(chat.url, AP + "/v1/publishers/google/models/gemini-4-argon:streamGenerateContent?alt=sse",
    "failed lookup falls back to express URL");
chat.respond(400, '{"error":{"message":"API key not valid"}}');
ok(result.err && result.err.indexOf("API key not valid") !== -1, "auth error still surfaces");

// Explicit project (gcloud): unchanged, no lookup.
({ handle, result } = send({ apiKey: "ya29.tok", geminiVertexAuthType: "gcloud", geminiProjectId: "my-proj", geminiLocation: "us-central1" }));
chat = requests.shift();
eq(chat.url, "https://us-central1-aiplatform.googleapis.com/v1/projects/my-proj/locations/us-central1/publishers/google/models/gemini-4-argon:streamGenerateContent?alt=sse",
    "gcloud project URL unchanged");
eq(chat.headers["Authorization"], "Bearer ya29.tok", "gcloud bearer auth unchanged");

// AI Studio: unchanged.
({ handle, result } = send({ endpoint: "https://generativelanguage.googleapis.com", apiKey: "AIza", geminiAuthMethod: "aistudio" }));
chat = requests.shift();
eq(chat.url, "https://generativelanguage.googleapis.com/v1beta/models/gemini-4-argon:streamGenerateContent?alt=sse",
    "AI Studio URL unchanged");
eq(requests.length, 0, "no stray requests");

// --- fetchModels (express key): models.dev candidates, verified ---
const MODELS_DEV = JSON.stringify({ "google-vertex": { models: {
    "gemini-3.8-flash": {}, "gemini-4-argon": {}, "gemini-retired-1": {},
    "gemini-3.1-flash-image": {}, "gemini-2.5-flash-tts": {}
} } });
function fetchModels(apiKey) {
    const out = {};
    Gemini.fetchModels(AP, apiKey, { geminiAuthMethod: "agentplatform", geminiVertexAuthType: "apikey" },
        function(err, models) { out.err = err; out.models = models; });
    return out;
}
let fm = fetchModels("AQ.key");
requests.shift().respond(200, MODELS_DEV);
eq(requests.map(function(r) { return r.url.split("/models/")[1]; }),
    ["gemini-3.8-flash:countTokens", "gemini-4-argon:countTokens", "gemini-retired-1:countTokens"],
    "probes only chat candidates (image/TTS filtered first)");
ok(requests.every(function(r) { return r.url.indexOf("/v1/projects/42/") !== -1; }), "probes use cached project");
requests[0].respond(200, "{}");
requests[1].respond(200, "{}");
requests[2].respond(404, NOT_FOUND);
requests.length = 0;
eq(fm, { err: null, models: ["gemini-3.8-flash", "gemini-4-argon"] }, "unreachable models dropped");

fm = fetchModels("AQ.key");
requests.shift().respond(200, MODELS_DEV);
while (requests.length) requests.shift().respond(0, "");
eq(fm.models, ["gemini-3.8-flash", "gemini-4-argon", "gemini-retired-1"], "all probes failing keeps the unverified list");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("gemini_adapter: ok");
