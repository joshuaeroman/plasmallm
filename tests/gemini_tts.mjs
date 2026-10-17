#!/usr/bin/env node
import fs from "fs";
import os from "os";
import path from "path";
import vm from "vm";
import { spawnSync } from "child_process";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Minimal XMLHttpRequest stand-in: each request is queued and answered by
// the test with respond(status, body).
const requests = [];
class FakeXHR {
    static DONE = 4;
    constructor() { this.headers = {}; this.readyState = 0; }
    open(method, url) { this.method = method; this.url = url; this.readyState = 1; }
    setRequestHeader(k, v) { this.headers[k] = v; }
    send(body) { this.body = body; requests.push(this); }
    abort() {}
    respond(status, body) {
        this.status = status;
        this.responseText = typeof body === "string" ? body : JSON.stringify(body);
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
const G = loadModule("../package/contents/ui/ttsAdapters/gemini_tts.js", { AgentPlatform });

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
const STUDIO = "https://generativelanguage.googleapis.com";

// --- request shape ---
eq(G.requestUrl(AP, "gemini-3.8-flash-lite-tts"),
    AP + "/v1/publishers/google/models/gemini-3.8-flash-lite-tts:generateContent", "Agent Platform URL");
eq(G.requestUrl(STUDIO + "/", "gemini-2.5-flash-preview-tts"),
    STUDIO + "/v1beta/models/gemini-2.5-flash-preview-tts:generateContent", "AI Studio URL");
eq(G.voiceConfig("Kore"), { prebuiltVoiceConfig: { voiceName: "Kore" } }, "prebuilt voice");
eq(G.voiceConfig("voice_abc123"), { voice: "voice_abc123" }, "designed voice id");
eq(G.voiceConfig("en-US-narrator-4"), { voice: "en-US-narrator-4" }, "library voice id");
eq(G.promptText("Hello.", ""), "Hello.", "no direction: plain text");
eq(G.promptText("Hello.", "warm and unhurried."),
    "Read the following text aloud. Delivery: warm and unhurried.\n\nHello.", "direction prompt");
eq(G.buildRequest({ text: "Hi", voice: "" }).generationConfig,
    { responseModalities: ["AUDIO"], speechConfig: {} }, "no voice: model default");

// --- buildCommand ---
const cmd = G.buildCommand({ endpoint: AP, apiKey: "AQ.key", model: "gemini-3.8-flash-lite-tts",
    text: "It's fine.", voice: "Puck", styleDirection: "cheerful" });
ok(cmd.synthesizeCmd && cmd.playCmd, "two-phase command");
ok(cmd.synthesizeCmd.indexOf("x-goog-api-key: AQ.key") !== -1, "key sent as x-goog-api-key");
ok(cmd.synthesizeCmd.indexOf(":generateContent") !== -1, "posts to generateContent");
ok(cmd.synthesizeCmd.indexOf("Delivery: cheerful") !== -1, "style direction in payload");
ok(/echo TTS_READY$/.test(cmd.synthesizeCmd), "synthesis ends with TTS_READY");
ok(cmd.playCmd.indexOf("pw-play") === 1, "plays with pw-play first");
const bearer = G.buildCommand({ endpoint: AP, apiKey: "ya29.tok", model: "m", text: "x" });
ok(bearer.synthesizeCmd.indexOf("Authorization: Bearer ya29.tok") !== -1, "gcloud token sent as bearer");
let threw = false;
try { G.buildCommand({ endpoint: AP, model: "m", text: "  " }); } catch (e) { threw = true; }
ok(threw, "empty text rejected");

// --- decode script, run for real ---
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "plasmallm-gemini-tts-"));
function decode(response) {
    const resp = path.join(tmp, "resp.json"), out = path.join(tmp, "out.wav");
    fs.rmSync(out, { force: true });
    fs.writeFileSync(resp, JSON.stringify(response));
    const r = spawnSync("python3", ["-c", G.DECODE_SCRIPT, resp, out], { encoding: "utf8" });
    return { code: r.status, stderr: r.stderr, out: fs.existsSync(out) ? fs.readFileSync(out) : null };
}
function audioResponse(mime, bytes) {
    return { candidates: [{ content: { parts: [{ inlineData: { mimeType: mime, data: bytes.toString("base64") } }] } }] };
}
const pcm = Buffer.alloc(4800 * 2);
let r = decode(audioResponse("audio/L16;codec=pcm;rate=24000", pcm));
eq(r.code, 0, "PCM decodes");
ok(r.out && r.out.toString("ascii", 0, 4) === "RIFF", "PCM wrapped as WAV");
ok(r.out && r.out.readUInt32LE(24) === 24000, "WAV sample rate from mime");
const wav = Buffer.concat([Buffer.from("RIFF"), Buffer.alloc(40)]);
r = decode(audioResponse("audio/wav", wav));
ok(r.code === 0 && r.out && r.out.equals(wav), "WAV passed through unchanged");
r = decode({ candidates: [{ finishReason: "SAFETY", content: { parts: [] } }] });
eq(r.code, 1, "no audio fails");
eq(G.parseResult("", r.stderr, 1).err, "Text-to-speech request failed: No audio returned (SAFETY)", "no-audio reason surfaced");
fs.rmSync(tmp, { recursive: true, force: true });

// --- parseResult ---
eq(G.parseResult("TTS_READY", "", 0), { err: null, result: { success: true } }, "success");
eq(G.parseResult("", '{"error":{"code":403,"message":"Permission denied"}}', 1).err,
    "Text-to-speech request failed: Permission denied", "API error message");

// --- fetchModels: AI Studio lists directly ---
let got = null;
G.fetchModels(STUDIO, "AIza", function(err, models) { got = models; });
let req = requests.shift();
eq(req.url, STUDIO + "/v1beta/models?pageSize=1000", "AI Studio list URL");
eq(req.headers["x-goog-api-key"], "AIza", "AI Studio key header");
req.respond(200, { models: [{ name: "models/gemini-2.5-flash-preview-tts" }, { name: "models/gemini-old-tts" }, { name: "models/gemini-2.5-flash" }] });
eq(requests.map(function(x) { return x.url; }), [
    STUDIO + "/v1beta/models/gemini-2.5-flash-preview-tts:countTokens",
    STUDIO + "/v1beta/models/gemini-old-tts:countTokens"
], "AI Studio: TTS models probed");
requests.shift().respond(200, "{}");
requests.shift().respond(404, "{}");
eq(got, ["gemini-2.5-flash-preview-tts"], "AI Studio: usable TTS models only");

// --- fetchModels: Agent Platform verifies models.dev candidates ---
got = null;
G.fetchModels(AP, "AQ.key", function(err, models) { got = models; });
req = requests.shift();
eq(req.url, "https://models.dev/api.json", "Agent Platform candidates from models.dev");
req.respond(200, { "google-vertex": { models: { "gemini-2.5-flash-tts": {}, "gemini-2.5-flash": {} } },
                   "google": { models: { "gemini-9-tts-retired": {} } } });
const lookup = requests.shift();
ok(/:countTokens$/.test(lookup.url), "project lookup first");
lookup.respond(404, '{"error":{"message":"Publisher model `projects/5/locations/x/publishers/google/models/y` was not found"}}');
const probed = requests.map(function(x) { return x.url.split("/models/")[1].replace(":countTokens", ""); });
eq(probed, ["gemini-3.8-flash-lite-tts", "gemini-3.8-flash-tts", "gemini-2.5-flash-tts", "gemini-2.5-pro-tts", "gemini-9-tts-retired"],
    "defaults plus discovered TTS candidates probed");
while (requests.length) {
    const x = requests.shift();
    x.respond(x.url.indexOf("retired") !== -1 ? 404 : 200, "{}");
}
eq(got, ["gemini-3.8-flash-lite-tts", "gemini-3.8-flash-tts", "gemini-2.5-flash-tts", "gemini-2.5-pro-tts"],
    "unreachable TTS model dropped");

got = null;
G.fetchModels(AP, "AQ.key", function(err, models) { got = models; });
requests.shift().respond(503, "down");
eq(got, G.defaultKnownModels(), "models.dev failure falls back to defaults");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("gemini_tts: ok");
