#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Mock QML .import environment (same pattern as tests/tts.mjs).
function loadModule(relPath, extraScope = {}) {
    const filePath = path.join(__dirname, relPath);
    let code = fs.readFileSync(filePath, "utf8");
    code = code.replace(/^\s*\.(import|pragma)\s+.*$/gm, "");
    const sandbox = { console, ...extraScope };
    vm.createContext(sandbox);
    vm.runInContext(code, sandbox);
    return sandbox;
}

const DRIVER = { isSessionActive: false };
const ToolManager = loadModule("../package/contents/ui/toolManager.js", {
    ToolRegistry: { getTool: () => null, getToolConfigUI: () => "", getAllTools: () => [] },
    DriverManager: DRIVER,
    Skills: { isSkillScriptAutoRun: () => true },
    i18n: (s) => s
});

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

// Namespace helpers
eq(ToolManager.wireToolName("read_file"), "plm_read_file", "bare name gets prefixed");
eq(ToolManager.wireToolName("plm_read_file"), "plm_read_file", "prefixed name is unchanged");
eq(ToolManager.bareToolName("plm_read_file"), "read_file", "prefix stripped");
eq(ToolManager.bareToolName("read_file"), "read_file", "bare name unchanged");

// Chat-history migration
const legacyCalls = JSON.stringify([
    { id: "call_1", type: "function", function: { name: "read_file", arguments: "{\"path\":\"/tmp/x\"}" } },
    { id: "call_2", type: "function", function: { name: "browser_exec", arguments: "{}" } }
]);
const migrated = JSON.parse(ToolManager.normalizeToolCallsJson(legacyCalls));
eq(migrated.map(c => c.function.name), ["plm_read_file", "plm_browser_exec"],
    "every stored call name moves into the namespace");
eq(migrated[0].id, "call_1", "call id preserved");
eq(migrated[0].function.arguments, "{\"path\":\"/tmp/x\"}", "call arguments preserved");
eq(ToolManager.normalizeToolCallsJson(ToolManager.normalizeToolCallsJson(legacyCalls)),
    ToolManager.normalizeToolCallsJson(legacyCalls), "migration is idempotent");
const alreadyWired = JSON.stringify([{ id: "c", function: { name: "plm_read_file", arguments: "{}" } }]);
eq(ToolManager.normalizeToolCallsJson(alreadyWired), alreadyWired, "v3 tool_calls left byte-identical");
eq(ToolManager.normalizeToolCallsJson(""), "", "empty json preserved");
eq(ToolManager.normalizeToolCallsJson("not json"), "not json", "unparseable json returned as-is");
eq(ToolManager.normalizeToolCallsJson("{}"), "{}", "non-array json returned as-is");

// Display and icon lookups accept both namespaces
eq(ToolManager.toolIconName("run_command"), "utilities-terminal", "icon for legacy bare name");
eq(ToolManager.toolIconName("plm_run_command"), "utilities-terminal", "icon for wire name");
ok(ToolManager.resultLabel("plm_read_file", { path: "/tmp/x" }, "/home/u").indexOf("plm_") === -1,
    "result label shows the bare name");
eq(ToolManager.shouldCollapseResult("plm_web_search", "", ""), false, "web search stays expanded");

// Desktop automation tools are in the namespace too
DRIVER.isSessionActive = true;
const desktop = ToolManager.getEnabledTools({ enableTools: true, enableDesktopAutomation: true, useCommandTool: true });
ok(desktop.length > 0 && desktop.every(n => n.indexOf("plm_") === 0),
    "active desktop session advertises only namespaced tools: " + desktop.join(","));
ok(desktop.indexOf("plm_StartSession") === -1, "StartSession hidden while a session is active");
ok(ToolManager.isAutoRun("plm_DesktopClick", { sessionAutoMode: true }), "desktop tools auto-run in auto mode");
DRIVER.isSessionActive = false;
const beforeSession = ToolManager.getEnabledTools({ enableTools: true, enableDesktopAutomation: true });
ok(beforeSession.indexOf("plm_StartSession") >= 0, "StartSession advertised before a session starts");
ok(beforeSession.indexOf("plm_DesktopClick") === -1, "desktop click not advertised before a session");

// Custom script tools join the namespace while keeping their configured name
const customCfg = {
    enableTools: true,
    customTools: JSON.stringify([{ name: "deploy_service", description: "d", commandTemplate: "deploy {target}" }])
};
ok(ToolManager.isTool("plm_deploy_service", customCfg), "custom tool matches its wire name");
ok(!ToolManager.isTool("deploy_service", customCfg), "bare custom name is not advertised");
eq(ToolManager.getToolMetadata("plm_deploy_service", customCfg).displayName, "deploy_service",
    "custom tool display name stays bare");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("tool_names: ok");
