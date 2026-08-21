#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/walletCore.js"),
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

eq(C.keySlotSchemeVersion(), 3, "watermark after v2| copy is 3");
eq(C.KEY_SLOT_SCHEME_VERSION, 3, "KEY_SLOT_SCHEME_VERSION var");

eq(C.unwrapDbusValue(0), 0, "unwrap 0");
eq(C.unwrapDbusValue({ value: 0 }), 0, "unwrap {value:0}");
eq(C.unwrapDbusValue([0]), 0, "unwrap [0]");
eq(C.unwrapDbusValue({ value: { value: "0" } }), "0", "unwrap nested");
eq(C.coerceHandle({ value: 5 }), 5, "handle wrapped");
eq(C.coerceHandle("nope"), -1, "bad handle");
eq(C.isWriteSuccess(0), true, "write 0");
eq(C.isWriteSuccess({ value: 0 }), true, "write {value:0}");
eq(C.isWriteSuccess([0]), true, "write [0]");
eq(C.isWriteSuccess(1), false, "write 1 is fail");
eq(C.passwordText({ value: "  abc  " }), "abc", "password trim");

const geminiV2 = C.currentKeySlot("p_default", "gemini", "", "https://generativelanguage.googleapis.com", "aistudio");
eq(geminiV2, C.currentKeySlot("p_default", "gemini", "Google Gemini", "https://proxy.example/gemini", "aistudio"),
    "Gemini empty name / proxy URL / Google Gemini share one v2 slot");
eq(geminiV2, C.currentKeySlot("p_default", "gemini", "Custom", "https://generativelanguage.googleapis.com", "aistudio"),
    "Gemini Custom name still Google Gemini v2 slot");
eq(geminiV2, C.currentKeySlot("p_default", "gemini", "Google Gemini (Interactions API)", "https://aiplatform.googleapis.com", "aistudio"),
    "Gemini Vertex URL still same aistudio slot");
ok(!geminiV2.includes("/"), "v2 Gemini slot has no slash");
ok(geminiV2.indexOf("v2|chat|") === 0, "v2 chat prefix");
ok(geminiV2.indexOf("Google%20Gemini") !== -1, "encoded Google Gemini");

const agent = C.currentKeySlot("p_default", "gemini", "Google Gemini", "https://aiplatform.googleapis.com", "agentplatform");
ok(agent !== geminiV2, "agentplatform is a different apiType token");
ok(agent.indexOf("gemini_agentplatform") !== -1, "agentplatform token encoded in v2 slot");

const openaiCustom = C.currentKeySlot("p_default", "openai", "", "http://localhost:11434/v1", null);
ok(openaiCustom.indexOf("%5Bhttp") !== -1, "OpenAI unnamed still Custom+[url]");
ok(!openaiCustom.includes("/"), "v2 openai custom has no slash");

const legs = C.legacyKeySlots("p_default", "gemini", "Google Gemini", "https://generativelanguage.googleapis.com", "aistudio");
ok(legs.indexOf("v1/chat/p_default/gemini/Google Gemini") !== -1, "legacy includes v1 Gemini name");
ok(legs.indexOf("v1/chat/p_default/gemini/[https://generativelanguage.googleapis.com]") !== -1,
    "legacy includes v1 Custom-URL accident");
ok(legs.indexOf("apiKey:profile:p_default") !== -1, "legacy includes profile-only");
ok(legs.indexOf("apiKey") !== -1, "legacy includes bare apiKey");
ok(legs.indexOf(geminiV2) === -1, "legacy list does not include primary v2 slot");

eq(C.searchKeySlot("exa"), "v2|search|_|exa", "search v2");
ok(C.searchLegacyKeySlots("exa").indexOf("v1/search/_/exa") !== -1, "search legacy v1");
ok(C.searchLegacyKeySlots("exa").indexOf("exaApiKey") !== -1, "search legacy exaApiKey");

eq(C.sttKeySlot("OpenRouter", ""), "v2|stt|OpenRouter", "stt named");
ok(C.sttLegacyKeySlots("OpenRouter", "").indexOf("v1/stt/OpenRouter") !== -1, "stt v1 legacy");

const fb = C.parseFallbackMap('{"a":"1"}');
eq(C.lookupFallback(fb, ["x", "a"], ""), "1", "fallback walks extras");
eq(C.lookupFallback({}, ["a"], "cfg"), "cfg", "fallback cfg apiKey");

const copied = C.applyFallbackCopies({ "apiKey:profile:p_default": "OLD" }, [
    { from: "apiKey:profile:p_default", to: geminiV2 }
]);
ok(copied.changed, "fallback copy changed");
eq(copied.map[geminiV2], "OLD", "fallback copied to v2");
const noOverwrite = C.applyFallbackCopies({ dest: "KEEP", src: "NEW" }, [{ from: "src", to: "dest" }]);
eq(noOverwrite.changed, false, "do not overwrite non-empty dest");
eq(noOverwrite.map.dest, "KEEP", "dest preserved");

const removed = C.removeFallback({ a: "1", b: "2" }, "a");
eq(removed, { b: "2" }, "removeFallback deletes only target slot");
eq(C.removeFallback({}, "a"), {}, "removeFallback on empty map");
eq(C.removeFallback(null, "a"), {}, "removeFallback on null map");

const pairs = C.buildMigrationCopies({
    profiles: [{
        id: "p_default",
        apiType: "gemini",
        providerName: "Google Gemini",
        apiEndpoint: "https://generativelanguage.googleapis.com",
        geminiAuthMethod: "aistudio"
    }],
    activeProfileId: "p_default",
    entries: [
        "apiKey:profile:p_default",
        "v1/chat/p_default/gemini/Google Gemini",
        "v1/chat/p_default/gemini/[https://generativelanguage.googleapis.com]"
    ]
});
function hasPair(from, to) {
    return pairs.some(function (p) { return p.from === from && p.to === to; });
}
ok(hasPair("apiKey:profile:p_default", geminiV2), "migrate profile-only → v2 Gemini");
ok(hasPair("v1/chat/p_default/gemini/Google Gemini", geminiV2), "migrate v1 name → v2");
ok(hasPair("v1/chat/p_default/gemini/[https://generativelanguage.googleapis.com]", geminiV2),
    "migrate v1 URL accident → v2");

// Express Mode (Agent Platform + API key) forces generateContent, not Interactions.
eq(C.clampGeminiApiVariant("interactions", "agentplatform", "apikey"), "legacy",
    "Express Mode clamps interactions → legacy");
eq(C.clampGeminiApiVariant("interactions", "agentplatform", "gcloud"), "interactions",
    "gcloud Agent Platform may keep interactions");
eq(C.clampGeminiApiVariant("interactions", "aistudio", "apikey"), "interactions",
    "AI Studio keeps interactions");
eq(C.resolvedApiType("gemini", "interactions", "agentplatform", "apikey"), "gemini",
    "Express Mode resolvedApiType is gemini not interactions");
eq(C.resolvedApiType("gemini", "interactions", "aistudio", "apikey"), "gemini_interactions",
    "AI Studio interactions resolves to gemini_interactions");

// Sibling Gemini auth slots are read fallbacks so AI Studio ↔ Agent Platform can share a key.
const agentLegs = C.legacyKeySlots("p_default", "gemini", "Google Gemini",
    "https://aiplatform.googleapis.com", "agentplatform");
ok(agentLegs.indexOf(geminiV2) !== -1, "agentplatform legacy includes aistudio v2 sibling");
ok(agentLegs.indexOf(agent) === -1, "legacy list excludes primary agentplatform slot");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("wallet_core: ok");
