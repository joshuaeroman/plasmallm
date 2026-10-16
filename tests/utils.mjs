#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/utils.js"),
    "utf8"
);
const sandbox = { console, Math };
vm.createContext(sandbox);
vm.runInContext(src, sandbox);

let failed = 0;
function ok(cond, msg) {
    if (!cond) {
        failed++;
        console.error("FAIL", msg);
    }
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

const U = sandbox;

const first = U.uuidv4();
ok(typeof first === "string", "returns a string");
ok(UUID_RE.test(first), "matches RFC 4122 v4 shape: " + first);

let allUnique = true;
for (let i = 0; i < 2000; i++) {
    const id = U.uuidv4();
    if (!UUID_RE.test(id)) {
        allUnique = false;
        console.error("FAIL malformed after", i, "iterations:", id);
        break;
    }
    if (id === first) {
        allUnique = false;
        console.error("FAIL duplicate id:", id);
        break;
    }
}
ok(allUnique, "2000 ids well-formed and unique");

// historyLayoutFor: forced modes, auto shows the sidebar only when both fit.
ok(U.historyLayoutFor("sidebar", 100, 250, 360) === "sidebar", "forced sidebar ignores size");
ok(U.historyLayoutFor("button", 2000, 250, 360) === "button", "forced button ignores size");
ok(U.historyLayoutFor("bogus", 2000, 250, 360) === "button", "unknown mode keeps button");
ok(U.historyLayoutFor("auto", 610, 250, 360) === "sidebar", "exact fit shows sidebar");
ok(U.historyLayoutFor("auto", 609, 250, 360) === "button", "one pixel short keeps button");
ok(U.historyLayoutFor("auto", 0, 250, 360) === "button", "zero width keeps button");

// cleanHistoryPreview: decodes escapes, drops a dangling backslash.
ok(U.cleanHistoryPreview("hello") === "hello", "plain text unchanged");
ok(U.cleanHistoryPreview("line one\\nline two") === "line one line two", "\\n becomes a space");
ok(U.cleanHistoryPreview("say \\") === "say", "dangling backslash from \\\" dropped");
ok(U.cleanHistoryPreview("C:\\\\dir") === "C:\\dir", "escaped backslash kept");
ok(U.cleanHistoryPreview("a\\\\nb") === "a\\nb", "escaped backslash before n is not a newline");
ok(U.cleanHistoryPreview("caf\\u00e9") === "caf\u00e9", "unicode escape decoded");
ok(U.cleanHistoryPreview("  \\t x  \\r\\n ") === "x", "whitespace collapsed and trimmed");
ok(U.cleanHistoryPreview(undefined) === "", "undefined is empty");

if (failed > 0) {
    console.error(failed + " test(s) failed");
    process.exit(1);
}

console.log("utils.mjs: all tests passed");
