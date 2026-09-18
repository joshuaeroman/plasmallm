#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/commandValidator.js"),
    "utf8"
);
const sandbox = { console };
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

const V = sandbox;

// --- backend detection ------------------------------------------------------
eq(V.backendFor({ endpoint: "https://api.typesafe.ai/v1", modelName: "jev-latest" }), "decisions", "typesafe direct");
eq(V.backendFor({ endpoint: "https://openrouter.ai/api/v1", modelName: "~typesafe/jev-latest" }), "decisions", "openrouter jev");
eq(V.backendFor({ endpoint: "https://openrouter.ai/api/v1", modelName: "typesafe/jev-1.13" }), "decisions", "openrouter typesafe versioned");
eq(V.backendFor({ endpoint: "https://openrouter.ai/api/v1", modelName: "openai/gpt-4o" }), "chat", "openrouter chat model");
eq(V.backendFor({ endpoint: "https://api.openai.com/v1", modelName: "gpt-4o" }), "chat", "openai chat");
eq(V.backendFor({ endpoint: "http://localhost:11434/v1", modelName: "qwen" }), "chat", "local chat");
eq(V.backendFor({ endpoint: "https://openrouter.ai/api/v1", modelName: "openai/gpt-4o", backend: "decisions" }), "decisions", "override decisions");
eq(V.backendFor({ endpoint: "https://api.typesafe.ai/v1", modelName: "jev-latest", backend: "chat" }), "chat", "override chat");
eq(V.backendFor({ apiType: "decisions", endpoint: "https://openrouter.ai/api/v1", modelName: "~typesafe/jev-latest" }), "decisions", "decisions adapter");
eq(V.backendFor({ apiType: "decisions", endpoint: "https://proxy.example/v1", modelName: "custom" }), "decisions", "decisions adapter custom endpoint");

// --- http error message extraction ------------------------------------------
eq(V.httpErrorMessage({ error: { message: "Model not found" } }, 404), "Model not found", "openrouter error shape");
eq(V.httpErrorMessage({ detail: { error_type: "authentication_error", message: "Must supply an API key!" } }, 403), "Must supply an API key!", "typesafe error shape");
eq(V.httpErrorMessage({ detail: "Bad request" }, 422), "Bad request", "string detail");
eq(V.httpErrorMessage({ message: "Nope" }, 400), "Nope", "top-level message");
eq(V.httpErrorMessage(null, 500), "HTTP 500", "status fallback");
eq(V.httpErrorMessage({}, 401), "HTTP 401", "empty body fallback");

// --- endpoint/model resolution ---------------------------------------------
eq(V.decisionsUrl("https://api.typesafe.ai/v1"), "https://api.typesafe.ai/v1/systemone", "typesafe url");
eq(V.decisionsUrl("https://api.typesafe.ai/v1/"), "https://api.typesafe.ai/v1/systemone", "typesafe url trailing slash");
eq(V.decisionsUrl("https://openrouter.ai/api/v1"), "https://openrouter.ai/api/alpha/decisions", "openrouter decisions url");

eq(V.decisionsModel({ endpoint: "https://api.typesafe.ai/v1", modelName: "~typesafe/jev-latest" }), "jev-latest", "strip prefix typesafe");
eq(V.decisionsModel({ endpoint: "https://api.typesafe.ai/v1", modelName: "typesafe/jev-1.13" }), "jev-1.13", "strip typesafe slash");
eq(V.decisionsModel({ endpoint: "https://api.typesafe.ai/v1", modelName: "jev-latest" }), "jev-latest", "plain jev");
eq(V.decisionsModel({ endpoint: "https://openrouter.ai/api/v1", modelName: "~typesafe/jev-latest" }), "~typesafe/jev-latest", "openrouter keeps prefix");

// --- decisions request shape ------------------------------------------------
{
    const req = V.buildDecisionsRequest({
        command: "rm -rf ~/tmp/x",
        justification: "Clean up temporary files"
    });
    eq(req.state.tool, "run_command", "state tool");
    eq(req.state.command, "rm -rf ~/tmp/x", "state command");
    eq(req.state.justification, "Clean up temporary files", "state justification");
    eq(req.questions.justification_mismatch.type, "noul", "mismatch question type");
    eq(req.questions.hidden_actions.type, "noul", "hidden question type");
    eq(req.questions.syntax_issues.type, "noul", "syntax question type");
    ok(typeof req.questions.justification_mismatch.instructions === "string" && req.questions.justification_mismatch.instructions.length > 0, "mismatch instructions");
    ok(req.questions.syntax_issues.instructions.indexOf("syntax") !== -1, "syntax instructions");
}

// --- chat messages ----------------------------------------------------------
{
    const msgs = V.buildChatMessages({
        command: "systemctl restart nginx",
        justification: "Apply the new nginx config"
    });
    eq(msgs.length, 2, "two chat messages");
    eq(msgs[0].role, "system", "system first");
    eq(msgs[1].role, "user", "user second");
    ok(msgs[1].content.indexOf("systemctl restart nginx") !== -1, "user message has command");
    ok(msgs[1].content.indexOf("Apply the new nginx config") !== -1, "user message has justification");
    ok(msgs[0].content.indexOf("unclosed quote") !== -1, "system prompt asks for syntax check");
}

// --- chat verdict parsing ---------------------------------------------------
eq(V.parseChatVerdict('{"match": true, "reason": "fits"}'), { match: true, reason: "fits" }, "clean json true");
eq(V.parseChatVerdict('{"match": false, "reason": "unrelated"}'), { match: false, reason: "unrelated" }, "clean json false");
eq(V.parseChatVerdict('```json\n{"match": true, "reason": "fits"}\n```'), { match: true, reason: "fits" }, "fenced json");
eq(V.parseChatVerdict('Sure! {"match": false, "reason": "nope"} done.'), { match: false, reason: "nope" }, "json embedded in prose");
eq(V.parseChatVerdict('"match": true'), { match: true, reason: "" }, "loose match true");
eq(V.parseChatVerdict('"match": false'), { match: false, reason: "" }, "loose match false");
ok(!!V.parseChatVerdict("I cannot answer").error, "garbage rejected");
ok(!!V.parseChatVerdict('{"match": "yes"}').error, "non-boolean match rejected");
ok(!!V.parseChatVerdict("").error, "empty rejected");

// --- decisions evaluation ---------------------------------------------------
{
    const r = V.evaluateDecisionsResponse({ answers: { justification_mismatch: { noul: 0.07 }, hidden_actions: { noul: 0.02 }, syntax_issues: { noul: 0.03 } } }, 0.5, "jev-latest");
    eq(r.match, true, "low mismatch passes");
    eq(r.confidence, 0.93, "confidence inverted from mismatch");
    eq(r.mismatchProbability, 0.07, "mismatch probability surfaced");
    eq(r.syntaxProbability, 0.03, "syntax probability surfaced");
    eq(r.model, "jev-latest", "fallback model surfaced");
}
{
    const r = V.evaluateDecisionsResponse({ answers: { justification_mismatch: { noul: 0.4 }, hidden_actions: { noul: 0.49 }, syntax_issues: { noul: 0.49 } } }, 0.5);
    eq(r.match, true, "below threshold passes");
}
{
    const r = V.evaluateDecisionsResponse({ answers: { justification_mismatch: { noul: 0.5 }, hidden_actions: { noul: 0.1 }, syntax_issues: { noul: 0.1 } } }, 0.5);
    eq(r.match, false, "exactly at threshold fails (strict)");
}
{
    const r = V.evaluateDecisionsResponse({ answers: { justification_mismatch: { noul: 0.7 }, hidden_actions: { noul: 0.1 }, syntax_issues: { noul: 0.1 } } }, 0.5);
    eq(r.match, false, "high mismatch fails");
    ok(r.reason.indexOf("0.70") !== -1, "reason includes probability");
}
{
    const r = V.evaluateDecisionsResponse({ answers: { justification_mismatch: { noul: 0.1 }, hidden_actions: { noul: 0.8 }, syntax_issues: { noul: 0.1 } } }, 0.5);
    eq(r.match, false, "hidden actions fail");
    ok(r.reason.indexOf("hidden") !== -1, "hidden reason mentioned");
}
{
    const r = V.evaluateDecisionsResponse({ answers: { justification_mismatch: { noul: 0.1 }, hidden_actions: { noul: 0.1 }, syntax_issues: { noul: 0.85 } } }, 0.5);
    eq(r.match, false, "syntax problems fail");
    ok(r.reason.indexOf("syntax") !== -1, "syntax reason mentioned");
}
{
    const r = V.evaluateDecisionsResponse({ answers: { justification_mismatch: { noul: 0.1 }, hidden_actions: { noul: 0.1 } } }, 0.5);
    eq(r.match, true, "missing syntax answer treated as no syntax issues");
}
ok(!!V.evaluateDecisionsResponse(null, 0.5).error, "malformed decisions rejected");
ok(!!V.evaluateDecisionsResponse({ answers: {} }, 0.5).error, "missing answer rejected");

// --- validate with injected transports --------------------------------------
function validate(opts, cb) { V.validate(opts, cb); }

{
    let calledUrl = "";
    let calledKey = "";
    validate({
        profile: { endpoint: "https://openrouter.ai/api/v1", modelName: "~typesafe/jev-latest", apiKey: "k" },
        command: "ls",
        justification: "List files",
        threshold: 0.5,
        transport: {
            decisions: function(url, key, payload, cb) {
                calledUrl = url;
                calledKey = key;
                cb(null, {
                    model: "typesafe/jev-1.13",
                    answers: { justification_mismatch: { noul: 0.01 }, hidden_actions: { noul: 0.01 }, syntax_issues: { noul: 0.01 } }
                });
            }
        }
    }, function(result) {
        eq(result.match, true, "decisions validate passes");
        eq(result.model, "typesafe/jev-1.13", "response model used");
        eq(calledUrl, "https://openrouter.ai/api/alpha/decisions", "decisions url used");
        eq(calledKey, "k", "api key forwarded");
    });
}

{
    validate({
        profile: { endpoint: "https://api.openai.com/v1", modelName: "gpt-4o" },
        command: "ls",
        justification: "List files",
        transport: {
            chat: function(messages, cb) {
                cb(null, '```json\n{"match": false, "reason": "not related"}\n```');
            }
        }
    }, function(result) {
        eq(result.match, false, "chat validate fails");
        eq(result.reason, "not related", "chat reason surfaced");
        eq(result.model, "gpt-4o", "chat model surfaced");
    });
}

{
    validate({
        profile: { endpoint: "https://api.openai.com/v1", modelName: "gpt-4o" },
        command: "ls",
        justification: "List files",
        transport: { chat: function(messages, cb) { cb("HTTP 500", null); } }
    }, function(result) {
        ok(!!result.error, "chat transport error surfaced");
    });
}

{
    validate({
        profile: { endpoint: "https://api.openai.com/v1", modelName: "gpt-4o" },
        command: "ls",
        justification: "List files"
    }, function(result) {
        ok(!!result.error, "missing chat transport errors");
    });
}

{
    validate({
        profile: { endpoint: "https://api.typesafe.ai/v1", modelName: "jev-latest" },
        command: "ls",
        justification: "List files",
        transport: { decisions: function(url, key, payload, cb) { cb("401 unauthorized", null); } }
    }, function(result) {
        ok(!!result.error, "decisions transport error surfaced");
    });
}

{
    validate({
        profile: { endpoint: "https://api.openai.com/v1", modelName: "gpt-4o" },
        command: "",
        justification: "nothing"
    }, function(result) {
        ok(!!result.error, "empty command rejected before transport");
    });
}

if (failed > 0) {
    console.error(`command_validation: ${failed} failure(s)`);
    process.exit(1);
}
console.log("command_validation: ok");
