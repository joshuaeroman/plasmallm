#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/opencodeRoute.js"),
    "utf8"
);
const sandbox = { console };
vm.createContext(sandbox);
vm.runInContext(src, sandbox);

let failed = 0;
function eq(actual, expected, msg) {
    if (actual !== expected) {
        failed++;
        console.error("FAIL", msg, "\n  expected:", expected, "\n  actual:  ", actual);
    }
}

const R = sandbox;

eq(R.productFromEndpoint("https://opencode.ai/zen/v1", "OpenCode Zen"), "zen", "zen endpoint");
eq(R.productFromEndpoint("https://opencode.ai/zen/go/v1", ""), "go", "go endpoint");
eq(R.productFromEndpoint("https://proxy.example/v1", "OpenCode Go"), "go", "go by provider name");
eq(R.productFromEndpoint("", ""), "zen", "empty defaults zen");

eq(R.npmToProtocol("@ai-sdk/openai"), "responses", "npm openai");
eq(R.npmToProtocol("@ai-sdk/anthropic"), "anthropic", "npm anthropic");
eq(R.npmToProtocol("@ai-sdk/google"), "gemini", "npm google");
eq(R.npmToProtocol("@ai-sdk/openai-compatible"), "chat", "npm compat");
eq(R.npmToProtocol(undefined), "chat", "npm missing");

function proto(product, model, overlay) {
    return R.resolveProtocol(product, model, overlay);
}

eq(proto("zen", "gpt-5.5"), "responses", "zen gpt-5.5");
eq(proto("zen", "grok-4.6"), "responses", "zen grok-4.6");
eq(proto("zen", "muse-spark-1.2"), "responses", "zen muse");
eq(proto("zen", "claude-sonnet-4-5"), "anthropic", "zen claude");
eq(proto("zen", "qwen3.7-plus"), "anthropic", "zen qwen dotted");
eq(proto("zen", "gemini-3.1-pro"), "gemini", "zen gemini");
eq(proto("zen", "glm-5.2"), "chat", "zen glm");
eq(proto("zen", "kimi-k3"), "chat", "zen kimi");
eq(proto("zen", "big-pickle"), "chat", "zen big-pickle");
eq(proto("zen", "minimax-m3"), "chat", "zen minimax is chat");
eq(proto("zen", "qwen3-coder"), "chat", "zen qwen3-coder stays chat");

eq(proto("go", "gpt-5.6-luna"), "responses", "go luna");
eq(proto("go", "grok-4.6"), "responses", "go grok");
eq(proto("go", "minimax-m3"), "anthropic", "go minimax");
eq(proto("go", "qwen3.8-flash"), "anthropic", "go qwen flash");
eq(proto("go", "qwen3.7-max"), "anthropic", "go qwen max");
eq(proto("go", "glm-5.3-flash"), "chat", "go glm");
eq(proto("go", "deepseek-v4-pro"), "chat", "go deepseek");
eq(proto("go", "gemini-3.1-pro"), "gemini", "go gemini prefix still gemini");

eq(proto("zen", ""), "chat", "empty model");
eq(proto("zen", "totally-unknown-model"), "chat", "unknown");
eq(proto("zen", "GPT-5.5"), "responses", "case insensitive");

eq(proto("zen", "glm-5.2", { "glm-5.2": "responses" }), "responses", "overlay wins");
eq(proto("go", "minimax-m3", { "minimax-m3": "chat" }), "chat", "overlay wins over go minimax");

if (failed) {
    console.error(failed + " failed");
    process.exit(1);
}
console.log("ok");
