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

if (failed > 0) {
    console.error(failed + " test(s) failed");
    process.exit(1);
}

console.log("utils.mjs: all tests passed");
