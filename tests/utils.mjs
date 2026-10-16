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

// shouldSummarizeChat: off never; untitled always; "every" on 1, 1+n, 1+2n...
ok(!U.shouldSummarizeChat("off", 1, 5, false), "off never summarizes");
ok(U.shouldSummarizeChat("initial", 1, 5, false), "initial summarizes first message");
ok(!U.shouldSummarizeChat("initial", 6, 5, true), "initial does not resummarize");
ok(U.shouldSummarizeChat("initial", 4, 5, false), "untitled chat is retried");
ok(!U.shouldSummarizeChat("every", 0, 5, false), "no user messages, no summary");
ok(!U.shouldSummarizeChat("every", 5, 5, true), "every 5: not at message 5");
ok(U.shouldSummarizeChat("every", 6, 5, true), "every 5: resummarize at message 6");
ok(U.shouldSummarizeChat("every", 11, 5, true), "every 5: resummarize at message 11");
ok(U.shouldSummarizeChat("every", 2, 1, true), "every 1: each message");
ok(U.shouldSummarizeChat("every", 3, 0, true), "bad interval treated as 1");

// buildChatSummaryPrompt: initial in full, last three later messages at 50 chars.
const one = U.buildChatSummaryPrompt(["How do I  resize\na btrfs partition?"]);
ok(one.startsWith("First user message:\nHow do I resize a btrfs partition?"), "initial whitespace collapsed");
ok(one.indexOf("Most recent") === -1, "no recent section with one message");
ok(one.endsWith(U.CHAT_SUMMARY_INSTRUCTION), "ends with the instruction");
const many = U.buildChatSummaryPrompt(["first", "second", "third", "fourth", "x".repeat(80)]);
ok(many.indexOf("- second") === -1, "only the three most recent later messages");
ok(many.indexOf("- third") !== -1 && many.indexOf("- fourth") !== -1, "recent messages included");
ok(many.indexOf("- " + "x".repeat(50) + "\n") !== -1 && many.indexOf("x".repeat(51)) === -1, "recent messages cut at 50 chars");
ok(U.buildChatSummaryPrompt(["y".repeat(3000)]).indexOf("y".repeat(2001)) === -1, "initial capped at 2000 chars");
ok(U.buildChatSummaryPrompt([]) === "", "no messages, empty prompt");

// cleanChatSummary: strips decoration around a short title.
ok(U.cleanChatSummary("Resizing btrfs partitions") === "Resizing btrfs partitions", "plain title unchanged");
ok(U.cleanChatSummary("\n**\"Btrfs Partition Resize.\"**\nExtra line") === "Btrfs Partition Resize", "markdown, quotes, period, extra lines removed");
ok(U.cleanChatSummary("Title: Nginx timeout tuning!") === "Nginx timeout tuning", "label prefix removed");
ok(U.cleanChatSummary("   ") === "", "blank reply is empty");
ok(U.cleanChatSummary("z".repeat(100)).length === 81, "long reply capped at 80 chars plus ellipsis");

// historyDayGroup: local calendar days, independent of time of day.
const noon = new Date(2026, 9, 16, 12, 0);
const at = (d) => d.getTime() / 1000;
ok(U.historyDayGroup(at(new Date(2026, 9, 16, 0, 0, 1)), noon) === "today", "just after midnight is today");
ok(U.historyDayGroup(at(new Date(2026, 9, 15, 23, 59)), noon) === "yesterday", "late last night is yesterday");
ok(U.historyDayGroup(at(new Date(2026, 9, 15, 0, 0)), noon) === "yesterday", "start of yesterday");
ok(U.historyDayGroup(at(new Date(2026, 9, 14, 23, 59)), noon) === "week", "two days ago is previous week");
ok(U.historyDayGroup(at(new Date(2026, 9, 10, 0, 0)), noon) === "week", "six days ago is previous week");
ok(U.historyDayGroup(at(new Date(2026, 9, 9, 23, 59)), noon) === "older", "seven days ago is older");
ok(U.historyDayGroup(at(new Date(2026, 9, 1, 12, 0)), new Date(2026, 9, 2, 0, 30)) === "yesterday", "across a month boundary");
ok(U.historyDayGroup(0, noon) === "older", "unknown mtime is older");

if (failed > 0) {
    console.error(failed + " test(s) failed");
    process.exit(1);
}

console.log("utils.mjs: all tests passed");
