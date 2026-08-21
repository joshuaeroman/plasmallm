#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/adapters/geminiThinking.js"),
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

const C = sandbox;

// --- AI Studio ---
eq(
    C.buildThinkingConfig("gemini-flash-lite-latest", 0, false, "aistudio"),
    { thinkingLevel: "MINIMAL" },
    "AI Studio lite-latest budget0 → MINIMAL (not budget 0)"
);
eq(
    C.buildThinkingConfig("gemini-flash-lite-latest", 4096, false, "aistudio"),
    { thinkingBudget: 4096 },
    "AI Studio lite-latest 4096 stays budget"
);
eq(
    C.buildThinkingConfig("gemini-3.5-flash-lite", 0, true, "aistudio"),
    { includeThoughts: true, thinkingLevel: "MINIMAL" },
    "AI Studio 3.5-flash-lite budget0 + thoughts"
);
eq(
    C.buildThinkingConfig("gemini-flash-latest", 0, false, "aistudio"),
    { thinkingBudget: 0 },
    "AI Studio flash-latest budget0 stays budget"
);
eq(
    C.buildThinkingConfig("gemini-2.5-flash", 0, false, "aistudio"),
    { thinkingBudget: 0 },
    "AI Studio 2.5-flash budget0 stays budget"
);
eq(
    C.buildThinkingConfig("gemini-3-flash-preview", 4096, false, "aistudio"),
    { thinkingBudget: 4096 },
    "AI Studio 3-flash positive budget stays budget"
);

// --- Agent Platform / Vertex ---
eq(
    C.buildThinkingConfig("gemini-2.5-flash", 0, false, "agentplatform"),
    { thinkingBudget: 0 },
    "Vertex 2.5 budget0 stays budget (level would 400)"
);
eq(
    C.buildThinkingConfig("gemini-2.5-flash", 4096, false, "agentplatform"),
    { thinkingBudget: 4096 },
    "Vertex 2.5 4096 budget"
);
eq(
    C.buildThinkingConfig("gemini-2.5-flash-lite", 4096, false, "agentplatform"),
    { thinkingBudget: 4096 },
    "Vertex 2.5-lite never gets thinkingLevel"
);
eq(
    C.buildThinkingConfig("gemini-flash-lite-latest", 0, false, "agentplatform"),
    { thinkingBudget: 0 },
    "Vertex: even lite-latest name uses budget (no level)"
);
eq(
    C.buildThinkingConfig("gemini-3-flash-preview", 4096, true, "agentplatform"),
    { includeThoughts: true, thinkingBudget: 4096 },
    "Vertex 3-flash uses budget not level"
);
eq(
    C.buildThinkingConfig("gemini-3.5-flash-lite", 0, false, "agentplatform"),
    { thinkingBudget: 0 },
    "Vertex 3.5-flash-lite budget0 ok"
);

// Never both keys
function hasOnlyOne(cfg) {
    const hasB = cfg.thinkingBudget !== undefined;
    const hasL = cfg.thinkingLevel !== undefined;
    return (hasB && !hasL) || (hasL && !hasB);
}
ok(hasOnlyOne(C.buildThinkingConfig("gemini-flash-lite-latest", 0, false, "aistudio")),
    "aistudio lite0 only one field");
ok(hasOnlyOne(C.buildThinkingConfig("gemini-2.5-flash", 4096, false, "agentplatform")),
    "vertex only one field");

eq(C.budgetToThinkingLevel(0, "gemini-flash-lite-latest"), "MINIMAL", "map 0");
eq(C.budgetToThinkingLevel(500, "x"), "LOW", "map low");
eq(C.budgetToThinkingLevel(4096, "x"), "MEDIUM", "map mid");
eq(C.budgetToThinkingLevel(16000, "x"), "HIGH", "map high");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("gemini_thinking: ok");
