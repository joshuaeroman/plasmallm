#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

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

const Chat = loadModule("../package/contents/ui/adapters/openai_chat.js", {
    ToolManager: {},
    Utils: { isOpenRouterProvider: () => false, applyOpenRouterAttribution: () => {} },
    i18n: (s) => s
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

const CLIENT_TOOLS = [{
    type: "function",
    "function": { name: "plm_read_file", description: "read a file", parameters: { type: "object", properties: {} } }
}];

function send(extra) {
    const result = {};
    Chat.sendStreaming(Object.assign({
        endpoint: "https://api.example.com/v1",
        apiKey: "test-key",
        model: "test-model",
        messages: [{ role: "user", content: "hi" }],
        tools: CLIENT_TOOLS,
        onChunk: function() {},
        onComplete: function(text, err, toolCalls, assistantMsg) {
            result.text = text;
            result.err = err;
            result.toolCalls = toolCalls;
            result.assistantMsg = assistantMsg;
        }
    }, extra || {}));
    return result;
}

function sse(delta) {
    return "data: " + JSON.stringify({ choices: [{ delta: delta }] }) + "\n\n" +
        "data: [DONE]\n\n";
}

// A call the model addressed to an advertised tool is reported to the host.
let result = send();
requests.shift().respond(200, sse({
    tool_calls: [{ index: 0, id: "call_client", type: "function",
        "function": { name: "plm_read_file", arguments: "{}" } }]
}));
eq(result.toolCalls && result.toolCalls.length, 1, "client tool call reported");
eq(result.toolCalls && result.toolCalls[0]["function"].name, "plm_read_file", "client name kept");

// A call to a name the host never advertised came from the server side of the
// gateway (or is a hallucination); running it locally would be wrong.
result = send();
requests.shift().respond(200, sse({
    tool_calls: [{ index: 0, id: "call_srv", type: "function",
        "function": { name: "browser_exec", arguments: "{}" } }]
}));
eq(result.toolCalls, null, "unadvertised streamed call dropped");

// Non-streaming fallback: same rule applies to message.tool_calls.
result = send();
requests.shift().respond(200, JSON.stringify({
    choices: [{ message: {
        role: "assistant",
        content: "Gateway says hi",
        tool_calls: [{ id: "call_srv2", type: "function", "function": { name: "browser_exec", arguments: "{}" } }]
    } }]
}));
eq(result.toolCalls, null, "unadvertised fallback call dropped");
eq(result.text, "Gateway says hi", "fallback text kept");

result = send();
requests.shift().respond(200, JSON.stringify({
    choices: [{ message: {
        role: "assistant",
        content: "",
        tool_calls: [{ id: "call_client2", type: "function", "function": { name: "plm_read_file", arguments: "{}" } }]
    } }]
}));
eq(result.toolCalls && result.toolCalls.length, 1, "advertised fallback call reported");
eq(result.assistantMsg && result.assistantMsg.tool_calls.length, 1, "assistant message carries the call");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("openai_chat_adapter: ok");
