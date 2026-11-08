#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const requests = [];
class FakeXHR {
    static DONE = 4;
    constructor() { this.headers = {}; this.readyState = 0; }
    open(method, url) { this.method = method; this.url = url; this.readyState = 1; }
    setRequestHeader(k, v) { this.headers[k] = v; }
    send(body) { this.body = body; requests.push(this); }
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

const calls = { tools: [], skills: [], memoryHints: [] };
const Api = loadModule("../package/contents/ui/api.js", {
    Adapters: {
        getAdapter: function() {
            return {
                capabilities: {},
                buildTools: function() { return [{ type: "function", name: "plm_read_file" }]; },
                fetchModels: function() { return null; }
            };
        }
    },
    ToolManager: {
        buildSystemPromptSection: function() { calls.tools.push(1); return "## Tools\n- plm_run_command"; }
    },
    DriverManager: { getDrivingInstructions: function() { return ""; } },
    WalletCore: {},
    Skills: {
        buildSystemPromptSection: function() { calls.skills.push(1); return "## Skills\n..."; }
    },
    Memory: {
        renderSection: function(list, hint) { calls.memoryHints.push(hint); return "## Persistent Memory"; }
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

const AGENT_CAPS = JSON.stringify({
    object: "hermes.api_server.capabilities",
    runtime: { mode: "server_agent", tool_execution: "server", split_runtime: false }
});
const PLAIN_CAPS = JSON.stringify({ object: "openai.capabilities", runtime: { mode: "completions" } });

// Pure payload parsing
ok(Api.parseServerAgentCapabilities(AGENT_CAPS), "server_agent mode detected");
ok(Api.parseServerAgentCapabilities(JSON.stringify({
    runtime: { mode: "x", tool_execution: "server", split_runtime: false } })),
    "server tool execution without split runtime detected");
ok(!Api.parseServerAgentCapabilities(PLAIN_CAPS), "plain runtime not treated as agent");
ok(!Api.parseServerAgentCapabilities("not json"), "unparseable payload is not an agent");
ok(!Api.parseServerAgentCapabilities("{}"), "missing runtime is not an agent");

// Capability detection rides on the model-list fetch, which holds the key.
const cfg = { endpoint: "https://gateway.example/v1", providerName: "Hermes" };
let tools = Api.buildTools("openai", { toolsConfig: {}, endpoint: cfg.endpoint, providerName: cfg.providerName });
eq(tools.length, 1, "chat turns never probe: unknown endpoint advertises");
eq(requests.length, 0, "buildTools issues no request");

Api.fetchModels("openai", cfg.endpoint, "k", true, { providerName: cfg.providerName }, function() {});
eq(requests.length, 1, "fetchModels probes /capabilities");
const probe = requests.shift();
eq(probe.url, "https://gateway.example/v1/capabilities", "probe hits /capabilities");
eq(probe.headers["Authorization"], "Bearer k", "probe carries the API key");

probe.respond(200, AGENT_CAPS);
ok(Api.isServerAgentEndpoint("openai", cfg.endpoint, cfg.providerName), "agent endpoint cached");

tools = Api.buildTools("openai", { toolsConfig: {}, endpoint: cfg.endpoint, providerName: cfg.providerName });
eq(tools, [], "agent endpoint suppresses tool advertisement");
eq(requests.length, 0, "known endpoint is not probed again");

// A plain API (404 on /capabilities) keeps advertising and is not re-probed.
const plain = { endpoint: "https://api.example.com/v1", providerName: "OpenAI" };
Api.fetchModels("openai", plain.endpoint, "k", true, { providerName: plain.providerName }, function() {});
requests.shift().respond(404, "no such route");
ok(!Api.isServerAgentEndpoint("openai", plain.endpoint, plain.providerName), "404 marks the endpoint as non-agent");
tools = Api.buildTools("openai", { toolsConfig: {}, endpoint: plain.endpoint, providerName: plain.providerName });
eq(tools.length, 1, "non-agent endpoint keeps advertising");
Api.fetchModels("openai", plain.endpoint, "k", true, { providerName: plain.providerName }, function() {});
eq(requests.length, 0, "non-agent endpoint is not probed again");

// Authentication failures are not conclusive: retry on the next fetch.
const authFail = { endpoint: "https://auth.example.com/v1", providerName: "Gateway" };
Api.fetchModels("openai", authFail.endpoint, "k", true, { providerName: authFail.providerName }, function() {});
requests.shift().respond(401, "unauthorized");
ok(!Api.isServerAgentEndpoint("openai", authFail.endpoint, authFail.providerName), "401 is not treated as an agent");
Api.fetchModels("openai", authFail.endpoint, "k", true, { providerName: authFail.providerName }, function() {});
eq(requests.length, 1, "401 endpoints are probed again");
requests.shift().respond(200, PLAIN_CAPS);

// System prompt: tool/skill sections and the memory tool hint disappear only
// for server-agent endpoints; memories themselves stay.
calls.tools.length = 0;
calls.skills.length = 0;
calls.memoryHints.length = 0;
const promptOpts = { toolsConfig: { skillsEnabled: true, memoryPhrases: "[]" }, i18n: function(s) { return s; } };

let prompt = Api.buildSystemPrompt({}, "{{tools}}{{skills}}{{memories}}", Object.assign({ serverAgentEndpoint: true }, promptOpts));
eq(prompt.indexOf("## Tools"), -1, "agent endpoint: no tool section");
eq(prompt.indexOf("## Skills"), -1, "agent endpoint: no skill-index section");
eq(prompt.indexOf("## Persistent Memory"), 0, "agent endpoint: memories still rendered");
eq(calls.memoryHints[0], false, "agent endpoint: memory tool hint omitted");

calls.tools.length = 0;
calls.skills.length = 0;
calls.memoryHints.length = 0;
prompt = Api.buildSystemPrompt({}, "{{tools}}{{skills}}{{memories}}", Object.assign({ serverAgentEndpoint: false }, promptOpts));
ok(prompt.indexOf("## Tools") !== -1, "normal endpoint: tool section kept");
ok(prompt.indexOf("## Skills") !== -1, "normal endpoint: skill section kept");
eq(calls.memoryHints[0], true, "normal endpoint: memory tool hint kept");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("server_agent_capability: ok");
