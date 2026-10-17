#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/adapters/agentPlatform.js"),
    "utf8"
);
// Minimal XMLHttpRequest stand-in: each request is queued and answered by
// the test with respond(status, body).
const requests = [];
class FakeXHR {
    static DONE = 4;
    constructor() { this.headers = {}; this.readyState = 0; this.aborted = false; }
    open(method, url) { this.method = method; this.url = url; this.readyState = 1; }
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
const sandbox = { console, XMLHttpRequest: FakeXHR };
vm.createContext(sandbox);
vm.runInContext(src, sandbox);

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

const A = sandbox;

// --- isChatModel ---
for (const id of [
    "gemini-2.5-flash", "gemini-2.5-pro", "gemini-3.1-pro-preview",
    "gemini-3.1-pro-preview-customtools", "gemini-3.8-flash", "gemini-4-argon",
    "gemma-3-27b-it"
]) {
    eq(A.isChatModel(id), true, "chat model: " + id);
}
for (const id of [
    "gemini-2.5-flash-tts", "gemini-2.5-flash-preview-tts", "gemini-3.8-flash-lite-tts",
    "gemini-embedding-001", "gemini-2.5-flash-image", "gemini-3.1-flash-lite-image",
    "gemini-3-pro-image-preview", "gemini-2.0-flash-exp-image-generation",
    "gemini-nano-banana-2.1", "gemini-3.8-live", "gemini-live-2.5-flash-native-audio",
    "lyria-3-pro-preview", "veo-3.1-generate-001", "imagen-4.0-generate-001"
]) {
    eq(A.isChatModel(id), false, "non-chat model: " + id);
}
eq(A.isChatModel(""), true, "empty id is not filtered here (callers skip empties)");

// --- projectFromError ---
const notFound = JSON.stringify({ error: { code: 404, message:
    "Publisher model `projects/387126880676/locations/us-east4/publishers/google/models/x` was not found" } });
eq(A.projectFromError(notFound), "387126880676", "project number from express 404");
eq(A.projectFromError('{"error":{"code":400,"message":"API key not valid"}}'), "", "no project in auth error");
eq(A.projectFromError(undefined), "", "undefined text");

// --- usesExpressKey ---
const AP = "https://aiplatform.googleapis.com";
const express = { geminiAuthMethod: "agentplatform", geminiVertexAuthType: "apikey" };
eq(A.usesExpressKey(express, "AQ.key", AP), true, "express key, no project");
eq(A.usesExpressKey({ geminiAuthMethod: "agentplatform" }, "AQ.key", AP), true, "auth type unset defaults to API key");
eq(A.usesExpressKey({ ...express, geminiProjectId: "my-proj" }, "AQ.key", AP), false, "explicit project wins");
eq(A.usesExpressKey({ ...express, geminiProjectId: "  " }, "AQ.key", AP), true, "blank project ignored");
eq(A.usesExpressKey({ ...express, geminiVertexAuthType: "gcloud" }, "ya29.tok", AP), false, "gcloud auth");
eq(A.usesExpressKey(express, "ya29.tok", AP), false, "bearer token pasted as key");
eq(A.usesExpressKey(express, "", AP), false, "no key");
eq(A.usesExpressKey({ geminiAuthMethod: "aistudio" }, "AIza", "https://generativelanguage.googleapis.com"), false, "AI Studio");
eq(A.usesExpressKey(express, "AQ.key", "https://us-central1-aiplatform.googleapis.com"), false, "regional host");
eq(A.usesExpressKey(express, "AQ.key", "https://proxy.example"), false, "custom proxy");

// --- modelUrl ---
eq(A.modelUrl(AP, "", "global", "gemini-3.8-flash", "streamGenerateContent?alt=sse"),
    AP + "/v1/publishers/google/models/gemini-3.8-flash:streamGenerateContent?alt=sse", "express URL");
eq(A.modelUrl(AP, "123", "global", "gemini-3.8-flash", "countTokens"),
    AP + "/v1/projects/123/locations/global/publishers/google/models/gemini-3.8-flash:countTokens", "project URL");
eq(A.modelUrl(AP, "123", "", "m", "countTokens"),
    AP + "/v1/projects/123/locations/global/publishers/google/models/m:countTokens", "empty location -> global");

// --- discoverProject ---
let got = null;
A.discoverProject(AP, "AQ.one", function(p) { got = p; });
let req = requests.pop();
eq(req.headers["x-goog-api-key"], "AQ.one", "lookup sends key as header");
ok(req.url.indexOf("/v1/publishers/google/models/") !== -1 && /:countTokens$/.test(req.url), "lookup hits express countTokens");
req.respond(404, notFound);
eq(got, "387126880676", "lookup returns project");
eq(A.cachedProject("AQ.one"), "387126880676", "project cached per key");
eq(A.cachedProject("AQ.other"), "", "other keys not cached");

got = "unset";
A.discoverProject(AP, "AQ.bad", function(p) { got = p; });
requests.pop().respond(400, '{"error":{"message":"API key not valid"}}');
eq(got, "", "lookup failure returns empty project");
eq(A.cachedProject("AQ.bad"), "", "failures not cached");

got = "unset";
const h = A.discoverProject(AP, "AQ.cancel", function(p) { got = p; });
req = requests.pop();
h.abort();
ok(req.aborted, "abort() aborts the lookup request");
eq(got, "unset", "cancelled lookup never calls back");

// --- verifyModels ---
let verified = null;
A.verifyModels(AP, "AQ.one", "global", ["a", "b", "c"], function(list) { verified = list; });
eq(requests.length, 3, "one countTokens per candidate (project already cached)");
ok(requests.every(function(r) { return r.url.indexOf("/v1/projects/387126880676/locations/global/") !== -1; }),
    "candidates probed on the project URL");
// Answer out of order; result keeps candidate order.
requests[2].respond(200, "{}");
requests[0].respond(200, "{}");
eq(verified, null, "waits for every probe");
requests[1].respond(404, notFound);
requests.length = 0;
eq(verified, ["a", "c"], "keeps reachable models in original order");

verified = null;
A.verifyModels(AP, "AQ.fresh", "global", ["x"], function(list) { verified = list; });
eq(requests.length, 1, "uncached key looks up the project first");
requests.shift().respond(404, notFound.replace("387126880676", "777"));
eq(requests.length, 1, "then probes");
ok(requests[0].url.indexOf("/v1/projects/777/") !== -1, "probe uses the looked-up project");
requests[0].ontimeout();
requests.length = 0;
eq(verified, [], "timed-out probe counts as unreachable");

verified = null;
A.verifyModels(AP, "AQ.one", "global", [], function(list) { verified = list; });
eq(verified, [], "empty candidate list calls back immediately");
eq(requests.length, 0, "no requests for empty list");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("agent_platform: ok");
