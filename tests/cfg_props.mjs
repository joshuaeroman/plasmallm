#!/usr/bin/env node
/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// Guards the invariant that lets the settings pages survive dev-time QML
// errors: every cfg_ identifier referenced in any page must be declared as a
// property in BaseConfigPage.qml. Plasma injects declared main.xml keys onto
// pages dynamically; an undeclared reference throws a ReferenceError that can
// abort reconcileConfig before loadWalletKey runs (the API key then looks
// "gone" in settings). See the try/catch in configGeneral.qml
// syncModelParamControls for the runtime safety net this test complements.
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const UI_DIR = path.join(__dirname, "../package/contents/ui");

function listQmlFiles(dir) {
    const out = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) out.push(...listQmlFiles(full));
        else if (entry.name.endsWith(".qml")) out.push(full);
    }
    return out;
}

// Remove block comments and line comments, keeping `//` that belongs to a
// URL scheme (https://...) so endpoints in strings don't truncate the line.
function stripComments(src) {
    const noBlock = src.replace(/\/\*[\s\S]*?\*\//g, " ");
    return noBlock.split("\n").map((line) => {
        let idx = line.indexOf("//");
        while (idx >= 0) {
            if (idx > 0 && line[idx - 1] === ":") {
                idx = line.indexOf("//", idx + 2);
                continue;
            }
            return line.slice(0, idx);
        }
        return line;
    }).join("\n");
}

const baseSrc = fs.readFileSync(path.join(UI_DIR, "BaseConfigPage.qml"), "utf8");
const declared = new Set();
const declRe = /property\s+\w+\s+(cfg_[A-Za-z0-9_]+)/g;
let m;
while ((m = declRe.exec(baseSrc))) declared.add(m[1]);

const useRe = /\bcfg_[A-Za-z0-9_]+\b/g;
let failed = 0;
let files = 0;
let refs = 0;

for (const file of listQmlFiles(UI_DIR)) {
    const rel = path.relative(path.dirname(UI_DIR), file);
    const used = stripComments(fs.readFileSync(file, "utf8")).match(useRe) || [];
    if (used.length === 0) continue;
    files++;
    refs += used.length;
    for (const name of new Set(used)) {
        if (!declared.has(name)) {
            failed++;
            console.error(`FAIL ${rel}: uses ${name} but BaseConfigPage.qml does not declare it`);
        }
    }
}

if (refs === 0) {
    console.error("FAIL scan matched no cfg_ references — scanner broken?");
    failed++;
}

if (failed > 0) {
    console.error(failed + " test(s) failed");
    process.exit(1);
}

console.log(`cfg_props.mjs: all tests passed (${refs} cfg_ references across ${files} files)`);
