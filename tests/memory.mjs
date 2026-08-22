#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/memory.js"),
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

const M = sandbox;

// --- parseStored ------------------------------------------------------------
eq(M.parseStored('["a","b"]'), ["a", "b"], "parseStored: JSON string");
eq(M.parseStored(["a", 1, null, "b"]), ["a", "b"], "parseStored: filters non-strings");
eq(M.parseStored(["a", "", "   ", "b"]), ["a", "b"], "parseStored: drops blank strings");
eq(M.parseStored(""), [], "parseStored: empty string");
eq(M.parseStored("not json"), [], "parseStored: invalid JSON");
eq(M.parseStored('{"a":1}'), [], "parseStored: non-array JSON");
eq(M.parseStored(undefined), [], "parseStored: undefined");
eq(M.parseStored(null), [], "parseStored: null");
eq(M.parseStored(["a"]), ["a"], "parseStored: array passthrough");
ok(M.parseStored('["a"]') !== null && M.parseStored('["a"]')[0] === "a", "parseStored: roundtrip");

// --- serialize ----------------------------------------------------------------
eq(M.serialize(["a", "b"]), '["a","b"]', "serialize: basic");
eq(M.serialize([]), "", "serialize: empty -> empty string");
eq(M.serialize("not json"), "", "serialize: junk input");
eq(M.serialize([" a ", "b\tc"]), '[" a ","b\\tc"]', "serialize: entries kept verbatim");
eq(M.serialize(['["x"]']), '["[\\"x\\"]"]', "serialize: phrase containing brackets survives");

// --- normalizePhrase ----------------------------------------------------------
eq(M.normalizePhrase("  likes   pizza  "), "likes pizza", "normalizePhrase: trims and collapses");
eq(M.normalizePhrase(""), "", "normalizePhrase: empty");
eq(M.normalizePhrase(null), "", "normalizePhrase: null");
eq(M.normalizePhrase(42), "42", "normalizePhrase: coerces non-strings");
eq(M.normalizePhrase("x".repeat(M.MAX_PHRASE_LENGTH + 50)), "x".repeat(M.MAX_PHRASE_LENGTH), "normalizePhrase: caps at MAX_PHRASE_LENGTH");
eq(M.normalizePhrase("  " + "y".repeat(M.MAX_PHRASE_LENGTH + 1) + " "), "y".repeat(M.MAX_PHRASE_LENGTH), "normalizePhrase: cap then trim");

// --- addPhrase ------------------------------------------------------------------
let r = M.addPhrase([], "likes pizza");
ok(r.added === true && r.reason === "ok" && r.phrase === "likes pizza", "addPhrase: appends");
eq(r.list, ["likes pizza"], "addPhrase: list contents");

r = M.addPhrase(["likes pizza"], "LIKES PIZZA");
ok(r.added === false && r.reason === "duplicate", "addPhrase: case-insensitive duplicate");
eq(r.list, ["likes pizza"], "addPhrase: duplicate leaves list untouched");
eq(r.phrase, "likes pizza", "addPhrase: duplicate reports stored wording");

r = M.addPhrase(["  multi  word\tphrase "], "multi word phrase");
ok(r.added === false && r.reason === "duplicate", "addPhrase: whitespace-normalized duplicate");

r = M.addPhrase([], "");
ok(r.added === false && r.reason === "empty", "addPhrase: empty text rejected");

r = M.addPhrase(["   "], "real");
eq(r.list, ["real"], "addPhrase: skips blank stored entries");

const FULL = Array.from({ length: M.MAX_PHRASES }, (_, i) => "p" + i);
r = M.addPhrase(FULL, "p49");
ok(r.added === false && r.reason === "duplicate", "addPhrase: last-slot duplicate detected");
r = M.addPhrase(FULL, "new one");
ok(r.added === false && r.reason === "full", "addPhrase: full at MAX_PHRASES");
eq(r.list.length, M.MAX_PHRASES, "addPhrase: full does not grow list");
r = M.addPhrase(FULL.slice(0, M.MAX_PHRASES - 1), "new one");
ok(r.added === true && r.list.length === M.MAX_PHRASES, "addPhrase: accepts up to MAX_PHRASES");

// --- removePhrase -----------------------------------------------------------------
r = M.removePhrase(["a", "b", "c"], "2");
ok(r.removed === "b" && r.reason === "ok", "removePhrase: by number");
eq(r.list, ["a", "c"], "removePhrase: by number list contents");

r = M.removePhrase(["a", "b"], "3");
ok(r.removed === null && r.reason === "not_found", "removePhrase: out-of-range number");
r = M.removePhrase(["a", "b"], "0");
ok(r.removed === null && r.reason === "not_found", "removePhrase: zero is not an index");

r = M.removePhrase(["Likes Pizza"], "likes pizza");
ok(r.removed === "Likes Pizza" && r.reason === "ok", "removePhrase: case-insensitive exact text");
eq(r.list, [], "removePhrase: exact text list contents");

r = M.removePhrase(["uses neovim nightly"], "  Uses   Neovim Nightly ");
ok(r.removed !== null, "removePhrase: normalized whitespace match");

r = M.removePhrase(["prefers dark themes", "prefers light themes"], "dark themes");
ok(r.removed === "prefers dark themes" && r.reason === "ok", "removePhrase: unique substring match");

r = M.removePhrase(["prefers dark themes", "hates dark themes"], "dark themes");
ok(r.removed === null && r.reason === "ambiguous", "removePhrase: ambiguous substring rejected");
eq(r.matches.length, 2, "removePhrase: ambiguity lists both candidates");

r = M.removePhrase(["alpha"], "omega");
ok(r.removed === null && r.reason === "not_found", "removePhrase: no match");
eq(r.list, ["alpha"], "removePhrase: no match leaves list intact");

r = M.removePhrase([], "anything");
ok(r.reason === "empty", "removePhrase: empty memory");
r = M.removePhrase(["a"], "");
ok(r.removed === null && r.reason === "not_found", "removePhrase: blank target");

// number-like phrase falls back to text when out of range but matches text
r = M.removePhrase(["call 911 now"], "911");
ok(r.removed === "call 911 now", "removePhrase: numeric substring after number miss");

// --- renderSection ------------------------------------------------------------------
eq(M.renderSection([]), "", "renderSection: empty -> empty string");
eq(M.renderSection("not json"), "", "renderSection: junk -> empty string");
r = M.renderSection(["likes pizza", "uses neovim"]);
ok(r.indexOf("## Persistent Memory") === 0, "renderSection: header first line");
ok(r.indexOf("1. likes pizza") !== -1 && r.indexOf("2. uses neovim") !== -1, "renderSection: numbered entries");
ok(r.indexOf("edit_memory") !== -1, "renderSection: mentions edit_memory tool");
eq(M.renderSection('["a"]'), M.renderSection(["a"]), "renderSection: accepts raw storage string");

// --- updatePhrase -----------------------------------------------------------------
r = M.updatePhrase(["a", "b", "c"], "2", "B2");
ok(r.reason === "ok" && r.removed === "b" && r.phrase === "B2", "updatePhrase: by number");
eq(r.list, ["a", "B2", "c"], "updatePhrase: by number list contents");

r = M.updatePhrase(["Likes Pizza"], "likes pizza", "loves pineapple pizza");
ok(r.reason === "ok" && r.removed === "Likes Pizza" && r.phrase === "loves pineapple pizza", "updatePhrase: by case-insensitive text");

r = M.updatePhrase(["prefers dark themes"], "dark", "prefers very dark themes");
ok(r.reason === "ok" && r.list[0] === "prefers very dark themes", "updatePhrase: by unique substring");

r = M.updatePhrase(["likes PIZZA"], "1", "likes pizza");
ok(r.reason === "unchanged" && r.phrase === "likes pizza", "updatePhrase: same wording (case-insensitive) is a no-op");
eq(r.list, ["likes PIZZA"], "updatePhrase: unchanged leaves stored wording intact");

r = M.updatePhrase(["alpha", "beta"], "alpha", "BETA");
ok(r.reason === "duplicate" && r.dupIndex === 2, "updatePhrase: duplicate of another entry rejected with its number");
eq(r.list, ["alpha", "beta"], "updatePhrase: duplicate leaves list untouched");

r = M.updatePhrase(["dark theme a", "dark theme b"], "theme", "new");
ok(r.reason === "ambiguous" && r.matches.length === 2, "updatePhrase: ambiguous target rejected");

r = M.updatePhrase(["alpha"], "omega", "x");
ok(r.reason === "not_found", "updatePhrase: missing target");

r = M.updatePhrase([], "1", "x");
ok(r.reason === "empty", "updatePhrase: empty memory");
r = M.updatePhrase(["a"], "1", "   ");
ok(r.reason === "empty", "updatePhrase: blank text rejected");

r = M.updatePhrase(["call 911 now"], "911", "call emergency services");
ok(r.reason === "ok" && r.list[0] === "call emergency services", "updatePhrase: numeric target falls back to text match");

r = M.updatePhrase(["a", "b"], "2", "  lots   of   spaces ");
eq(r.list, ["a", "lots of spaces"], "updatePhrase: normalizes new text");

// --- formatEntryList -------------------------------------------------------------------
eq(M.formatEntryList([]), "(memory is empty)", "formatEntryList: empty marker");
eq(M.formatEntryList(["x", "y"]), "\n1. x\n2. y", "formatEntryList: numbered listing");

// --- serialize/parse roundtrip with real-world phrases -------------------------------------
const phrases = [
    "Prefers dark themes",
    "Uses Neovim; hates mouse-driven workflows",
    'Quotes need "escaping" & symbols: <ok>',
    "Unicode: café ☕ 日本語"
];
eq(M.parseStored(M.serialize(phrases)), phrases, "roundtrip: special characters survive");

// --- buildSystemPrompt integration (regression: {{memories}} vs sysinfo {{memory}} clobber) --
// api.js can't be .import-ed under node, so strip the QML import directives and
// provide the same namespace objects the QML engine would inject.
const apiSrc = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/api.js"),
    "utf8"
).replace(/^\.import .*$/gm, "");
const mainXml = fs.readFileSync(
    path.join(__dirname, "../package/contents/config/main.xml"),
    "utf8"
);
const tplMatch = mainXml.match(/<entry name="systemPrompt"[\s\S]*?<default>([\s\S]*?)<\/default>/);
ok(tplMatch, "integration: systemPrompt default found in main.xml");
const newDefault = tplMatch[1];
ok(newDefault.includes("{{memories}}"), "integration: default template carries {{memories}}");
ok(!newDefault.includes("{{memory}}"), "integration: no colliding bare {{memory}} placeholder");

const apiSb = { console };
vm.createContext(apiSb);
vm.runInContext(src, apiSb); // memory.js
apiSb.Memory = {
    parseStored: apiSb.parseStored, serialize: apiSb.serialize,
    normalizePhrase: apiSb.normalizePhrase, addPhrase: apiSb.addPhrase,
    removePhrase: apiSb.removePhrase, renderSection: apiSb.renderSection,
    formatEntryList: apiSb.formatEntryList, MAX_PHRASES: apiSb.MAX_PHRASES,
    MAX_PHRASE_LENGTH: apiSb.MAX_PHRASE_LENGTH
};
apiSb.ToolManager = { buildSystemPromptSection: () => "## Tools\n(stub)" };
apiSb.Skills = { buildSystemPromptSection: () => "" };
apiSb.DriverManager = { getDrivingInstructions: () => "" };
apiSb.WalletCore = { KEY_SLOT_SCHEME_VERSION: 3 };
vm.runInContext(apiSrc + "\nthis.__build = buildSystemPrompt;", apiSb);
const build = apiSb.__build;

const withPhrases = build({}, newDefault, {
    sysInfoDateTime: true,
    toolsConfig: { memoryPhrases: ["my favorite food is pizza"], skillsEnabled: false }
});
ok(withPhrases.includes("## Persistent Memory"), "integration: section rendered from default template");
ok(withPhrases.includes("my favorite food is pizza"), "integration: phrase visible to model");

const withoutPhrases = build({}, newDefault, {
    sysInfoDateTime: true,
    toolsConfig: { memoryPhrases: [], skillsEnabled: false }
});
ok(!withoutPhrases.includes("## Persistent Memory"), "integration: empty memory renders nothing");

// Respect-removal: a template without the placeholder must not force-append.
const customTpl = newDefault.replace("{{memories}}\n", "");
const customOut = build({}, customTpl, {
    sysInfoDateTime: true,
    toolsConfig: { memoryPhrases: ["my favorite food is pizza"], skillsEnabled: false }
});
ok(!customOut.includes("## Persistent Memory"), "integration: omitted placeholder means no memory section");

// Migration derivation: stripping the placeholder line yields the pre-feature template.
ok(!customTpl.includes("{{memories}}"), "integration: previous-template derivation is clean");

// Sysinfo RAM must never leak into the memories section (the original clobber bug).
const ramOut = build({ memory: "  total  used  free\nMem: 16Gi" }, newDefault, {
    sysInfoDateTime: true,
    toolsConfig: { memoryPhrases: ["likes pizza"], skillsEnabled: false }
});
ok(ramOut.includes("1. likes pizza"), "integration: phrase survives alongside sysinfo RAM");

if (failed > 0) {
    console.error(failed + " test(s) failed");
    process.exit(1);
}
console.log("memory.mjs: all tests passed");
