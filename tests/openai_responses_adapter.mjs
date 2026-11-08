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

const Responses = loadModule("../package/contents/ui/adapters/openai_responses.js", {
    ToolManager: { getEnabledToolsMetadata: function() { return []; } },
    Utils: {
        isOpenRouterProvider: function() { return false; },
        applyOpenRouterAttribution: function() {}
    },
    i18n: function(s) { return s; }
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
    name: "plm_read_file",
    description: "read a file",
    parameters: { type: "object", properties: {} }
}];

function sse(events) {
    return events.map(function(e) { return "data: " + JSON.stringify(e) + "\n"; }).join("\n");
}

function send(extra) {
    const result = {};
    const handle = Responses.sendStreaming(Object.assign({
        endpoint: "https://gateway.example/v1",
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
    return { handle, result };
}

// Gateway executes its own tool server-side and streams both the call and its
// output. The call must not be reported to the host, otherwise the follow-up
// request ends in a tool item and strict gateways reject it.
let { result } = send();
requests.shift().respond(200, sse([
    { type: "response.output_item.added", item: {
        type: "function_call", id: "fc_1", call_id: "call_srv", name: "browser_exec", arguments: "{}" } },
    { type: "response.output_item.added", item: {
        type: "function_call_output", id: "fco_1", call_id: "call_srv",
        output: [{ type: "input_text", text: "page text" }] } },
    { type: "response.output_text.delta", delta: "Here is the answer." },
    { type: "response.completed" }
]));
eq(result.err, null, "server-executed turn: no error");
eq(result.text, "Here is the answer.", "server-executed turn: text kept");
eq(result.toolCalls, null, "server-executed turn: no tool calls reported");
ok(result.assistantMsg && result.assistantMsg.content === "Here is the answer.",
    "server-executed turn: assistant message kept");

// Same stream, but the output arrives as output_item.done instead of added.
({ result } = send());
requests.shift().respond(200, sse([
    { type: "response.output_item.added", item: {
        type: "function_call", id: "fc_2", call_id: "call_srv2", name: "browser_exec", arguments: "{}" } },
    { type: "response.output_item.done", item: {
        type: "function_call_output", id: "fco_2", call_id: "call_srv2",
        output: [{ type: "input_text", text: "page text" }] } },
    { type: "response.output_text.delta", delta: "Done." },
    { type: "response.completed" }
]));
eq(result.toolCalls, null, "answered via item_done: no tool calls reported");

// Standard Responses provider: a call with no output is the model asking the
// client to run one of the tools we advertised.
({ result } = send());
requests.shift().respond(200, sse([
    { type: "response.output_item.added", item: {
        type: "function_call", id: "fc_3", call_id: "call_client", name: "plm_read_file",
        arguments: "{\"path\":\"/tmp/x\"}" } },
    { type: "response.completed" }
]));
eq(result.toolCalls && result.toolCalls.length, 1, "client call: one tool call reported");
eq(result.toolCalls && result.toolCalls[0].id, "call_client", "client call: call id kept");
eq(result.toolCalls && result.toolCalls[0]["function"].name, "plm_read_file",
    "client call: name kept");

// Server aborted before emitting the output: the name was never advertised, so
// the call cannot be ours and must not be re-posted.
({ result } = send());
requests.shift().respond(200, sse([
    { type: "response.output_item.added", item: {
        type: "function_call", id: "fc_4", call_id: "call_abandoned", name: "read_file",
        arguments: "{}" } },
    { type: "response.output_text.delta", delta: "Partial answer." },
    { type: "response.completed" }
]));
eq(result.toolCalls, null, "abandoned server call: dropped");
eq(result.text, "Partial answer.", "abandoned server call: text kept");

// Reasoning items still round-trip when every call is dropped.
({ result } = send());
requests.shift().respond(200, sse([
    { type: "response.reasoning_summary_text.delta", delta: "thinking..." },
    { type: "response.output_item.done", item: {
        type: "reasoning", id: "rs_1", summary: [{ type: "summary_text", text: "thinking..." }] } },
    { type: "response.output_item.added", item: {
        type: "function_call", id: "fc_5", call_id: "call_srv3", name: "browser_exec", arguments: "{}" } },
    { type: "response.output_item.added", item: {
        type: "function_call_output", id: "fco_3", call_id: "call_srv3",
        output: [{ type: "input_text", text: "ok" }] } },
    { type: "response.output_text.delta", delta: "Answer." },
    { type: "response.completed" }
]));
eq(result.toolCalls, null, "thinking turn: no tool calls reported");
ok(result.assistantMsg && result.assistantMsg.thinkingBlocks
    && result.assistantMsg.thinkingBlocks.length === 1,
    "thinking turn: reasoning block kept");
eq(result.assistantMsg && result.assistantMsg.thinkingBlocks[0].id, "rs_1",
    "thinking turn: reasoning id kept");

// Non-streaming fallback: a completed Response object whose output mixes an
// answered server-side call with a client call.
({ result } = send());
requests.shift().respond(200, JSON.stringify({
    output: [
        { type: "function_call", id: "fc_6", call_id: "call_a", name: "browser_exec", arguments: "{}" },
        { type: "function_call_output", id: "fco_4", call_id: "call_a", output: "ok" },
        { type: "message", content: [{ type: "output_text", text: "Fallback answer." }] }
    ]
}));
eq(result.text, "Fallback answer.", "fallback: text parsed");
eq(result.toolCalls, null, "fallback: answered server call dropped");

({ result } = send());
requests.shift().respond(200, JSON.stringify({
    output: [
        { type: "function_call", id: "fc_7", call_id: "call_b", name: "plm_read_file", arguments: "{}" },
        { type: "message", content: [{ type: "output_text", text: "Calling a tool." }] }
    ]
}));
eq(result.toolCalls && result.toolCalls.length, 1, "fallback: client call reported");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("openai_responses_adapter: ok");
