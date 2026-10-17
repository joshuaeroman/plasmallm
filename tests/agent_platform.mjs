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

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("agent_platform: ok");
