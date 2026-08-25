#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/toolManager.js"),
    "utf8"
);
const start = src.indexOf("function expandPath");
const end = src.indexOf("// Catalog strings");
if (start < 0 || end < 0 || end <= start) {
    console.error("FAIL could not extract path helpers from toolManager.js");
    process.exit(1);
}
const sandbox = { console };
vm.createContext(sandbox);
vm.runInContext(src.slice(start, end), sandbox);

let failed = 0;
function eq(actual, expected, msg) {
    if (actual !== expected) {
        failed++;
        console.error("FAIL", msg, "\n  expected:", expected, "\n  actual:  ", actual);
    }
}
function ok(cond, msg) {
    if (!cond) {
        failed++;
        console.error("FAIL", msg);
    }
}

const T = sandbox;
const ostree = {
    home: "/var/home/joshuaroman",
    homeEnv: "/home/joshuaroman"
};
const whitelist = '["$HOME","/tmp/plasmallm"]';

ok(T.isPathAllowed("~/x", whitelist, ostree), "tilde under $HOME allowed");
ok(T.isPathAllowed("/var/home/joshuaroman/.local/share/plasmallm/skills/a/SKILL.md", whitelist, ostree),
    "realpath home allowed");
ok(T.isPathAllowed("/home/joshuaroman/.local/share/plasmallm/skills/a/SKILL.md", whitelist, ostree),
    "logical $HOME (symlink) allowed when $HOME is whitelisted");
ok(T.isPathAllowed("/tmp/plasmallm/download-youtube/SKILL.md", whitelist, ostree),
    "explicit extra dir allowed");
ok(!T.isPathAllowed("/etc/passwd", whitelist, ostree), "outside whitelist rejected");
ok(!T.isPathAllowed("/home/other/.bashrc", whitelist, ostree), "other user's home rejected");

eq(T.resolveHomePath("/home/joshuaroman/.local/foo", ostree),
    "/var/home/joshuaroman/.local/foo",
    "logical home rewritten to realpath for execution");
eq(T.resolveHomePath("~/.local/foo", ostree),
    "/var/home/joshuaroman/.local/foo",
    "tilde expands via realpath home");
eq(T.contractPath("/home/joshuaroman/.local/foo", ostree.home, ostree.homeEnv),
    "~/.local/foo",
    "logical home contracted to tilde");

const same = { home: "/home/user", homeEnv: "/home/user" };
ok(T.isPathAllowed("/home/user/a", '["$HOME"]', same), "identical homeEnv is a no-op");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("path_sandbox: ok");
