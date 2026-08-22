#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const src = fs.readFileSync(
    path.join(__dirname, "../package/contents/ui/skills.js"),
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

const S = sandbox;

// --- name validation -------------------------------------------------------
ok(S.isValidSkillName("weather"), "plain name");
ok(S.isValidSkillName("git-release"), "hyphenated name");
ok(S.isValidSkillName("a"), "single char");
ok(S.isValidSkillName("a".repeat(64)), "64 chars ok");
ok(!S.isValidSkillName("a".repeat(65)), "65 chars rejected");
ok(!S.isValidSkillName("Weather"), "uppercase rejected");
ok(!S.isValidSkillName("-lead"), "leading hyphen rejected");
ok(!S.isValidSkillName("trail-"), "trailing hyphen rejected");
ok(!S.isValidSkillName("dou--ble"), "double hyphen rejected");
ok(!S.isValidSkillName(""), "empty rejected");
ok(!S.isValidSkillName(null), "null rejected");
ok(!S.isValidSkillName("has_underscore"), "underscore rejected");

// --- frontmatter parsing ---------------------------------------------------
{
    const r = S.parseFrontmatter("---\nname: weather\ndescription: Does weather\n---\n\n# Body\nline2");
    ok(r.hasFrontmatter, "frontmatter detected");
    eq(r.attrs.name, "weather", "name attr");
    eq(r.attrs.description, "Does weather", "description attr");
    eq(r.body, "# Body\nline2", "body after frontmatter, leading blank stripped");
}
{
    const r = S.parseFrontmatter("---\nname: 'quoted'\ndescription: \"dquoted\"\nlicense: MIT\nmetadata:\n  audience: all\n  workflow: demo\n---\nbody");
    eq(r.attrs.name, "quoted", "single quotes stripped");
    eq(r.attrs.description, "dquoted", "double quotes stripped");
    eq(r.attrs.license, "MIT", "unknown field preserved");
    eq(r.attrs.metadata.audience, "all", "nested metadata map");
    eq(r.attrs.metadata.workflow, "demo", "nested metadata second key");
}
{
    const r = S.parseFrontmatter("no frontmatter here\n---\nx: y");
    ok(!r.hasFrontmatter, "missing leading marker");
    const r2 = S.parseFrontmatter("---\nname: x\n");
    ok(!r2.hasFrontmatter, "unterminated block");
    const r3 = S.parseFrontmatter("");
    ok(!r3.hasFrontmatter && r3.body === "", "empty text");
    const r4 = S.parseFrontmatter("---\r\nname: win\r\n---\r\nbody\r\nlines");
    eq(r4.attrs.name, "win", "CRLF normalized");
}

// --- parseSkillFile --------------------------------------------------------
{
    const s = S.parseSkillFile("/data/plasmallm/skills/weather/SKILL.md",
        "---\nname: weather\ndescription: Weather lookups\n---\nDo weather things.");
    ok(s.valid, "valid skill parses");
    eq(s.name, "weather", "skill name");
    eq(s.dirName, "weather", "dir name extracted");
    eq(s.body, "Do weather things.", "skill body");
}
{
    const mismatch = S.parseSkillFile("/skills/not-weather/SKILL.md",
        "---\nname: weather\ndescription: x\n---\nb");
    ok(!mismatch.valid, "name/dir mismatch invalid");
    ok(mismatch.error.indexOf("must match") !== -1, "mismatch error message");
    const noDesc = S.parseSkillFile("/s/w/SKILL.md", "---\nname: w\n---\nb");
    ok(!noDesc.valid && noDesc.error.indexOf("description") !== -1, "missing description invalid");
    const badName = S.parseSkillFile("/s/Bad_Name/SKILL.md", "---\nname: Bad_Name\ndescription: x\n---\nb");
    ok(!badName.valid, "invalid name invalid");
    const longDesc = S.parseSkillFile("/s/w/SKILL.md", "---\nname: w\ndescription: " + "x".repeat(1025) + "\n---\nb");
    ok(!longDesc.valid && longDesc.error.indexOf("1024") !== -1, "overlong description invalid");
    const noFm = S.parseSkillFile("/s/w/SKILL.md", "just text");
    ok(!noFm.valid && noFm.error.indexOf("frontmatter") !== -1, "no frontmatter invalid");
}

// --- flat self-contained <name>.md files ------------------------------------
{
    const flat = S.parseSkillFile("/skills/notes.md",
        "---\nname: notes\ndescription: Note taking\n---\nBody here.");
    ok(flat.valid, "flat file with matching name valid");
    eq(flat.name, "notes", "flat name from frontmatter");
    eq(flat.dirName, "notes", "flat stem extracted");

    const auto = S.parseSkillFile("/skills/weather.md",
        "---\ndescription: Weather lookups\n---\nFetch weather.");
    ok(auto.valid, "flat file without name field falls back to stem");
    eq(auto.name, "weather", "stem fallback name");

    const mismatch = S.parseSkillFile("/skills/other.md",
        "---\nname: notes\ndescription: x\n---\nb");
    ok(!mismatch.valid && mismatch.error.indexOf("other.md") !== -1,
        "flat frontmatter name must match file stem");

    const bare = S.parseSkillFile("/skills/bare.md", "no frontmatter at all");
    ok(!bare.valid, "flat file without frontmatter invalid");

    const noDesc = S.parseSkillFile("/skills/x.md",
        "---\nsummary: hi\n---\nb");
    ok(!noDesc.valid, "flat file without description invalid");

    // Case-insensitive extension; stem must still be a valid skill name.
    const upperExt = S.parseSkillFile("/skills/deploy-notes.MD",
        "---\ndescription: d\n---\nb");
    ok(upperExt.valid && upperExt.name === "deploy-notes", "uppercase .MD extension handled");

    const badStem = S.parseSkillFile("/skills/Bad_Stem.md",
        "---\ndescription: d\n---\nb");
    ok(!badStem.valid && badStem.error.indexOf("invalid name") !== -1,
        "stem that fails name rules rejected");

    // Nested layout still takes SKILL.md's sibling dir as its name source.
    const nested = S.parseSkillFile("/skills/pair/SKILL.md",
        "---\nname: pair\ndescription: d\n---\nb");
    ok(nested.valid, "nested layout unaffected by flat support");
}

// --- disabled list + filtering --------------------------------------------
{
    const skills = [
        { name: "a", valid: true },
        { name: "b", valid: true },
        { name: "c", valid: false }
    ];
    eq(S.filterEnabledSkills(skills, '["b"]').map(s => s.name), ["a"], "disabled and invalid filtered");
    eq(S.filterEnabledSkills(skills, "").length, 2, "empty disabled list keeps valid");
    eq(S.filterEnabledSkills(skills, "not json").length, 2, "bad json tolerated");
}

// --- prompt section rendering ----------------------------------------------
{
    eq(S.buildSystemPromptSection([], "", []), "", "no skills -> empty section");
    const skills = [
        { name: "weather", description: "Weather <lookups> & forecasts", body: "WEATHER BODY", valid: true },
        { name: "git-release", description: "Release flow", body: "GIT BODY", valid: true }
    ];
    const idxOnly = S.buildSystemPromptSection(skills, '["git-release"]', []);
    ok(idxOnly.indexOf("<available_skills>") === -1, "index no longer rendered into prompt");
    ok(idxOnly.indexOf("before using any other tools") !== -1, "ordering rule present");
    ok(idxOnly.indexOf("git-release") === -1, "disabled skill absent");
    ok(idxOnly.indexOf("WEATHER BODY") === -1, "inactive body not inlined");

    const withActive = S.buildSystemPromptSection(skills, "", ["weather"]);
    ok(withActive.indexOf("#### Skill: weather") !== -1, "active header");
    ok(withActive.indexOf("WEATHER BODY") !== -1, "active body inlined");
    ok(withActive.indexOf("GIT BODY") === -1, "non-active body excluded");

    // Active skill that gets disabled disappears from active section too.
    const disabledActive = S.buildSystemPromptSection(skills, '["weather"]', ["weather"]);
    ok(disabledActive.indexOf("WEATHER BODY") === -1, "disabling removes active body");
    ok(disabledActive.indexOf("before using any other tools") !== -1,
        "instruction kept while other skills remain enabled");

    // Compaction-safety wording only appears when something is active.
    ok(idxOnly.indexOf("compacted") === -1, "no compaction note when none active");
}

// --- index builder + schema embedding ----------------------------------------
{
    eq(S.buildAvailableSkillsIndex([]), "", "empty list -> empty index");
    const skills = [
        { name: "weather", description: "Weather <lookups> & forecasts" },
        { name: "git-release", description: "Release flow" }
    ];
    const idx = S.buildAvailableSkillsIndex(skills);
    ok(idx.indexOf("<available_skills>") === 0, "index xml opens");
    ok(idx.indexOf("<name>weather</name>") !== -1, "index name entry");
    ok(idx.indexOf("&lt;lookups&gt; &amp; forecasts") !== -1, "XML escaped description");
    ok(idx.trim().endsWith("</available_skills>"), "index xml closes");
    ok(S.buildAvailableSkillsIndex(null) === "", "null tolerated");

    const base = "Load the full instructions of an available skill by name.";
    const embedded = S.embedSkillsIndex(base, skills);
    ok(embedded.indexOf(base) === 0, "embed keeps base description first");
    ok(embedded.indexOf("<available_skills>") > base.length, "embed appends index after description");
    eq(S.embedSkillsIndex(base, []), base, "embed no-op without skills");
    eq(S.embedSkillsIndex(base, null), base, "embed no-op with null skills");

    const input = [{ name: "x", description: "y" }];
    S.embedSkillsIndex(base, input);
    eq(input[0].name, "x", "embed does not mutate input");
}

// --- stubbing delivered tool results ---------------------------------------
{
    const messages = [
        { role: "system", content: "sys" },
        { role: "user", content: "check the weather" },
        { role: "assistant", content: "", tool_calls: [{ id: "call_1", "function": { name: "skill", arguments: "{\"name\":\"weather\"}" } }] },
        { role: "tool", tool_call_id: "call_1", content: "WEATHER BODY (long)" },
        { role: "assistant", content: "It is sunny." }
    ];
    const out = S.stubDeliveredSkillResults(messages, ["weather"]);
    ok(out !== messages, "returns new array when changed");
    eq(out[3].content.indexOf("[[plasmallm-skill-stub]]") === 0, true, "tool result stubbed");
    eq(out[3].tool_call_id, "call_1", "tool_call_id preserved");
    eq(out[4].content, "It is sunny.", "other messages untouched");
    eq(messages[3].content, "WEATHER BODY (long)", "input array not mutated");

    const untouched = S.stubDeliveredSkillResults(messages, []);
    ok(untouched === messages, "no active names -> original returned");

    const notActive = S.stubDeliveredSkillResults(messages, ["other"]);
    ok(notActive === messages, "non-active skill results untouched");

    // Object-form arguments and non-skill tools are handled.
    const objArgs = [
        { role: "assistant", tool_calls: [{ id: "c2", "function": { name: "skill", arguments: { name: "weather" } } }] },
        { role: "tool", tool_call_id: "c2", content: "BODY" }
    ];
    eq(S.stubDeliveredSkillResults(objArgs, ["weather"])[1].content.indexOf("[[plasmallm-skill-stub]]") === 0, true,
        "object-form arguments stubbed");

    const mixedTools = [
        { role: "assistant", tool_calls: [{ id: "c3", "function": { name: "run_command", arguments: "{}" } }] },
        { role: "tool", tool_call_id: "c3", content: "ls output" }
    ];
    ok(S.stubDeliveredSkillResults(mixedTools, ["weather"]) === mixedTools, "non-skill calls untouched");

    // Already-stubbed content is not double-replaced.
    const twice = S.stubDeliveredSkillResults(out, ["weather"]);
    eq(twice[3].content, out[3].content, "idempotent re-stub");
}

// --- scan output parsing ----------------------------------------------------
{
    const stdout = [
        "===PLASMALLM_SKILL /data/plasmallm/skills/weather/SKILL.md",
        "---",
        "name: weather",
        "description: Weather lookups",
        "---",
        "Fetch weather via wttr.in.",
        "===PLASMALLM_SKILL /home/u/.claude/skills/git-release/SKILL.md",
        "---",
        "name: git-release",
        "description: Release helper",
        "---",
        "Draft releases.",
        "===PLASMALLM_SKILL /data/plasmallm/skills/broken/SKILL.md",
        "no frontmatter",
        "===PLASMALLM_SKILL_END"
    ].join("\n");
    const roots = [
        { dir: "/data/plasmallm/skills", source: "plasmallm" },
        { dir: "/home/u/.claude/skills", source: "claude" }
    ];
    const parsed = S.parseScanOutput(stdout, roots);
    eq(parsed.length, 3, "three files parsed");
    eq(parsed[0].name, "weather", "first skill");
    eq(parsed[0].source, "plasmallm", "primary source assigned");
    eq(parsed[0].body, "Fetch weather via wttr.in.", "body captured");
    eq(parsed[1].source, "claude", "compat source assigned by longest root match");
    ok(parsed[1].valid, "compat skill valid");
    ok(!parsed[2].valid, "broken file invalid");
    eq(parsed[2].source, "plasmallm", "broken file still source-tagged");

    // Duplicate names: first wins, later flagged.
    const dupStdout = [
        "===PLASMALLM_SKILL /a/one/weather/SKILL.md",
        "---",
        "name: weather",
        "description: first",
        "---",
        "A",
        "===PLASMALLM_SKILL /b/two/weather/SKILL.md",
        "---",
        "name: weather",
        "description: second",
        "---",
        "B",
        "===PLASMALLM_SKILL_END"
    ].join("\n");
    const dups = S.parseScanOutput(dupStdout, [
        { dir: "/a/one", source: "plasmallm" },
        { dir: "/b/two", source: "agents" }
    ]);
    eq(dups[0].valid, true, "first duplicate wins");
    ok(!dups[1].valid && dups[1].error.indexOf("duplicate") !== -1, "later duplicate marked invalid");

    // Mixed layout: nested folder beats same-named flat file (scan order).
    const mixedStdout = [
        "===PLASMALLM_SKILL /skills/weather/SKILL.md",
        "---",
        "name: weather",
        "description: nested version",
        "---",
        "A",
        "===PLASMALLM_SKILL /skills/weather.md",
        "---",
        "description: flat version",
        "---",
        "B",
        "===PLASMALLM_SKILL_END"
    ].join("\n");
    const mixed = S.parseScanOutput(mixedStdout, [{ dir: "/skills", source: "plasmallm" }]);
    eq(mixed.length, 2, "both files parsed");
    eq(mixed[0].valid, true, "nested wins name conflict");
    ok(!mixed[1].valid && mixed[1].error.indexOf("duplicate") !== -1, "flat loser flagged");
}

// --- cache serialization -----------------------------------------------------
{
    const cache = S.toCacheJson([
        { name: "weather", description: "d", path: "/p", dirName: "weather", source: "plasmallm", valid: true, error: "", body: "12345" }
    ]);
    const arr = JSON.parse(cache);
    eq(arr.length, 1, "cache has one entry");
    ok(arr[0].body === undefined, "body not cached");
    eq(arr[0].bodyLength, 5, "bodyLength cached");
}

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("skills: ok");
