/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Pure skill-file helpers (no QML / shell / imports). QML imports this via
// main.qml / api.js. Node tests load it with vm.runInContext.
//
// Skills are standard Agent Skills: a folder per skill containing a
// SKILL.md with YAML frontmatter:
//
//     ---
//     name: weather-report
//     description: Fetch current conditions and forecasts.
//     ---
//     Full instructions shown to the model on demand...
//
// Discovery scans one or more root directories for <name>/SKILL.md files.
// Enabled skills are advertised to the model as an <available_skills> index;
// the model loads full instructions by calling the built-in "skill" tool.
// Once loaded in a session ("active"), bodies are re-injected in full into
// every system prompt rebuild so context compaction and message capping can
// never drop them.

var SKILL_FILE_NAME = "SKILL.md";
var MAX_NAME_LENGTH = 64;
var MAX_DESCRIPTION_LENGTH = 1024;
var NAME_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
var SCRIPT_NAME_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*\.sh$/;

// Marker used when replacing an already-delivered tool result with a stub.
var STUB_SENTINEL = "[[plasmallm-skill-stub]]";

function isValidSkillName(name) {
    if (!name || typeof name !== "string") return false;
    if (name.length < 1 || name.length > MAX_NAME_LENGTH) return false;
    return NAME_PATTERN.test(name);
}

function isValidSkillScriptName(name) {
    if (!name || typeof name !== "string") return false;
    return SCRIPT_NAME_PATTERN.test(name);
}

function _unquote(value) {
    var v = String(value === undefined ? "" : value).trim();
    if (v.length >= 2) {
        var first = v.charAt(0);
        var last = v.charAt(v.length - 1);
        if ((first === "\"" && last === "\"") || (first === "'" && last === "'")) {
            v = v.substring(1, v.length - 1);
        }
    }
    return v.trim();
}

/**
 * Minimal frontmatter parser: recognizes a leading --- block of "key: value"
 * lines plus one level of nesting (e.g. metadata sub-maps). Unknown fields are
 * preserved but ignored by callers. Returns { attrs, body, hasFrontmatter }.
 */
function parseFrontmatter(text) {
    var result = { attrs: {}, body: "", hasFrontmatter: false };
    if (text === undefined || text === null) return result;
    var normalized = String(text).replace(/\r\n/g, "\n");
    var lines = normalized.split("\n");
    if (lines.length === 0 || lines[0].trim() !== "---") return result;

    var end = -1;
    for (var i = 1; i < lines.length; i++) {
        var t = lines[i].trim();
        if (t === "---" || t === "...") { end = i; break; }
    }
    if (end === -1) return result;

    result.hasFrontmatter = true;
    var currentMapKey = null;
    for (var j = 1; j < end; j++) {
        var line = lines[j];
        if (!line.trim() || line.trim().indexOf("#") === 0) continue;
        var m = line.match(/^\s*([A-Za-z0-9_-]+)\s*:\s*(.*)$/);
        if (!m) continue;
        if (/^\s/.test(line) && currentMapKey) {
            if (result.attrs[currentMapKey] === undefined ||
                    typeof result.attrs[currentMapKey] !== "object" ||
                    result.attrs[currentMapKey] === null) {
                result.attrs[currentMapKey] = {};
            }
            result.attrs[currentMapKey][m[1]] = _unquote(m[2]);
        } else {
            currentMapKey = m[1];
            result.attrs[m[1]] = _unquote(m[2]);
        }
    }
    result.body = lines.slice(end + 1).join("\n").replace(/^\n+/, "");
    return result;
}

/**
 * Parses one skill file into a skill record. Two layouts are supported:
 *   - nested:  <root>/<name>/SKILL.md   (standard folder layout; name must match dir)
 *   - flat:    <root>/<name>.md          (self-contained; name falls back to
 *                                        the file stem when frontmatter omits
 *                                        it, and must match the stem when set)
 * Returns { name, description, body, path, dirName, source, valid, error } —
 * invalid records carry a human-readable error and valid=false.
 */
function parseSkillFile(path, text) {
    var parts = String(path === undefined ? "" : path).split("/");
    var base = parts[parts.length - 1] || "";
    var isFlat = base !== SKILL_FILE_NAME && /\.md$/i.test(base);
    var dirName = isFlat
        ? base.replace(/\.md$/i, "")
        : (parts.length >= 2 ? parts[parts.length - 2] : "");
    var fm = parseFrontmatter(text);
    var skill = {
        name: typeof fm.attrs.name === "string" ? fm.attrs.name.trim() : "",
        description: typeof fm.attrs.description === "string" ? fm.attrs.description.trim() : "",
        body: fm.body,
        path: String(path === undefined ? "" : path),
        dirName: dirName,
        source: "",
        scripts: [],
        valid: false,
        error: ""
    };
    // Self-contained convenience: <stem>.md without a name field names itself.
    if (!skill.name && isFlat) skill.name = dirName;
    if (!fm.hasFrontmatter) {
        skill.error = "missing '---' frontmatter block with name/description";
        return skill;
    }
    if (!skill.name) { skill.error = "frontmatter is missing required field 'name'"; return skill; }
    if (!skill.description) { skill.error = "frontmatter is missing required field 'description'"; return skill; }
    if (!isValidSkillName(skill.name)) {
        skill.error = "invalid name '" + skill.name + "' (lowercase alphanumeric words separated by single hyphens, max " + MAX_NAME_LENGTH + " chars)";
        return skill;
    }
    if (dirName && skill.name !== dirName) {
        skill.error = isFlat
            ? "frontmatter name '" + skill.name + "' must match the file name '" + dirName + ".md'"
            : "name '" + skill.name + "' must match its directory name '" + dirName + "'";
        return skill;
    }
    if (skill.description.length > MAX_DESCRIPTION_LENGTH) {
        skill.error = "description exceeds " + MAX_DESCRIPTION_LENGTH + " characters";
        return skill;
    }
    skill.valid = true;
    return skill;
}

function isNameListed(name, json) {
    var list = parseDisabledList(json);
    var wanted = String(name || "");
    for (var i = 0; i < list.length; i++) {
        if (list[i] === wanted) return true;
    }
    return false;
}

function isSkillScriptAutoRun(skillName, autoRunJson) {
    return isNameListed(skillName, autoRunJson);
}

/** Directory containing the skill file (folder for SKILL.md, parent for flat .md). */
function skillDirectory(skill) {
    var path = skill && skill.path ? String(skill.path) : "";
    var slash = path.lastIndexOf("/");
    if (slash <= 0) return "";
    return path.substring(0, slash);
}

function candidateScriptPaths(skill, scriptName) {
    var dir = skillDirectory(skill);
    if (!dir || !isValidSkillScriptName(scriptName)) return [];
    return [dir + "/scripts/" + scriptName, dir + "/" + scriptName];
}

function normalizeScriptArgs(raw) {
    if (raw === undefined || raw === null || raw === "") return [];
    if (Array.isArray(raw)) {
        var out = [];
        for (var i = 0; i < raw.length; i++) out.push(String(raw[i]));
        return out;
    }
    return [String(raw)];
}

/**
 * Resolves a run_skill_script call to a bash command, or { error }.
 * Prefers scripts/<name>.sh, then <name>.sh next to SKILL.md.
 */
function resolveSkillScript(args, skills, config) {
    var skillName = String(args && (args.skill || args.name) ? (args.skill || args.name) : "").trim();
    var scriptName = String(args && args.script ? args.script : "").trim();
    if (!skillName) return { error: "missing skill name" };
    if (!isValidSkillScriptName(scriptName)) {
        return { error: "invalid script name '" + scriptName + "' (lowercase-hyphen stem ending in .sh)" };
    }
    var list = Array.isArray(skills) ? skills : [];
    var found = null;
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].valid && list[i].name === skillName) {
            found = list[i];
            break;
        }
    }
    if (!found) return { error: "unknown or invalid skill '" + skillName + "'" };
    if (isNameListed(skillName, config && config.skillsDisabledList)) {
        return { error: "skill '" + skillName + "' is disabled" };
    }
    var cands = candidateScriptPaths(found, scriptName);
    if (cands.length === 0) return { error: "cannot resolve script path" };
    var argv = normalizeScriptArgs(args && args.args);
    var home = config && config.userHome ? toLocalPath(config.userHome) : "";
    var cd = home ? ("cd " + shellQuotePath(home) + " && ") : "cd \"$HOME\" && ";
    var cmd = cd + "if [ -f " + shellQuotePath(cands[0]) + " ]; then s=" + shellQuotePath(cands[0]) +
        "; elif [ -f " + shellQuotePath(cands[1]) + " ]; then s=" + shellQuotePath(cands[1]) +
        "; else echo 'Skill script not found' >&2; exit 1; fi; bash \"$s\"";
    for (var a = 0; a < argv.length; a++) {
        cmd += " " + shellQuotePath(argv[a]);
    }
    return { command: cmd, paths: cands, skill: found };
}

function _basename(path) {
    var p = String(path || "");
    var slash = p.lastIndexOf("/");
    return slash >= 0 ? p.substring(slash + 1) : p;
}

function attachSkillScripts(skills, scriptPaths) {
    var list = Array.isArray(skills) ? skills : [];
    for (var i = 0; i < list.length; i++) {
        if (!list[i].scripts) list[i].scripts = [];
    }
    var paths = Array.isArray(scriptPaths) ? scriptPaths : [];
    for (var p = 0; p < paths.length; p++) {
        var sp = toLocalPath(paths[p]);
        var base = _basename(sp);
        if (!isValidSkillScriptName(base)) continue;
        for (var s = 0; s < list.length; s++) {
            if (!list[s] || !list[s].valid) continue;
            var cands = candidateScriptPaths(list[s], base);
            if (sp === cands[0] || sp === cands[1]) {
                if (list[s].scripts.indexOf(base) === -1) list[s].scripts.push(base);
                break;
            }
        }
    }
}

/** Parses the disabled-skills JSON string into an array of names. */
function parseDisabledList(disabledJson) {
    if (!disabledJson) return [];
    try {
        var parsed = typeof disabledJson === "string" ? JSON.parse(disabledJson) : disabledJson;
        if (!Array.isArray(parsed)) return [];
        var out = [];
        for (var i = 0; i < parsed.length; i++) out.push(String(parsed[i]));
        return out;
    } catch (e) {
        return [];
    }
}

/** Returns the subset of skills that are valid and not individually disabled. */
function filterEnabledSkills(skills, disabledJson) {
    var disabled = parseDisabledList(disabledJson);
    var lookup = {};
    for (var d = 0; d < disabled.length; d++) lookup[disabled[d]] = true;
    var out = [];
    var list = Array.isArray(skills) ? skills : [];
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].valid && !lookup[list[i].name]) out.push(list[i]);
    }
    return out;
}

function escapeXml(s) {
    return String(s === undefined || s === null ? "" : s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
}

/**
 * Renders the <available_skills> XML index for an enabled skill list. This
 * lives inside the skill tool's schema description so models see the list at tool-selection time. Returns "" when empty.
 */
function buildAvailableSkillsIndex(enabledSkills) {
    var enabled = Array.isArray(enabledSkills) ? enabledSkills : [];
    if (enabled.length === 0) return "";
    var out = "<available_skills>\n";
    for (var i = 0; i < enabled.length; i++) {
        out += "  <skill>\n" +
            "    <name>" + escapeXml(enabled[i].name) + "</name>\n" +
            "    <description>" + escapeXml(enabled[i].description) + "</description>\n" +
            "  </skill>\n";
    }
    out += "</available_skills>";
    return out;
}

/** Appends the skills index to a tool description (no-op without skills). */
function embedSkillsIndex(description, enabledSkills) {
    var base = String(description === undefined || description === null ? "" : description);
    var index = buildAvailableSkillsIndex(enabledSkills);
    if (!index) return base;
    return base + "\n\n" + index;
}

/**
 * Renders the {{skills}} system prompt section: the routing instruction plus
 * full bodies of any active (loaded this session) skills. The index itself is
 * NOT rendered here — it rides in the skill tool's description instead.
 * Returns "" when there is nothing to say at all.
 */
function buildSystemPromptSection(skills, disabledJson, activeNames) {
    var enabled = filterEnabledSkills(skills, disabledJson);

    var activeLookup = {};
    var wanted = Array.isArray(activeNames) ? activeNames : [];
    for (var w = 0; w < wanted.length; w++) activeLookup[String(wanted[w])] = true;
    var active = [];
    for (var e = 0; e < enabled.length; e++) {
        if (activeLookup[enabled[e].name]) active.push(enabled[e]);
    }

    if (enabled.length === 0 && active.length === 0) return "";

    var out = "\n## Skills\n\n";
    if (enabled.length > 0) {
        out += "If a task matches an available skill, load it with the `skill` tool before using any other tools. " +
            "The list of available skills is included in the `skill` tool's description.\n";
    }
    if (active.length > 0) {
        out += "\n### Loaded Skill Instructions\n\n" +
            "Full instructions for skills already loaded this session. They remain available below even " +
            "if earlier conversation turns are compacted:\n";
        for (var a = 0; a < active.length; a++) {
            out += "\n#### Skill: " + escapeXml(active[a].name) + "\n\n" + active[a].body + "\n";
        }
    }
    return out.replace(/\n{3,}/g, "\n\n").replace(/\s+$/, "");
}

function stubText(skillName) {
    return STUB_SENTINEL + " Skill '" + skillName + "' was loaded earlier. Its full instructions are provided " +
        "in the Skills section of the system prompt.";
}

function _extractArgName(rawArgs) {
    var args = rawArgs;
    if (typeof args === "string") {
        try { args = JSON.parse(args); } catch (e) { return ""; }
    }
    if (!args || typeof args !== "object") return "";
    return args.name ? String(args.name) : "";
}

/**
 * Rewrites delivered `skill` tool results whose body is already injected in
 * the system prompt's Active Skills section, replacing them with short stubs
 * to avoid paying for the same content twice. Operates on the outgoing
 * request copy only — never mutates chat history. Returns the original array
 * when nothing changed.
 *
 * @param {Array} messages - outgoing [{role, content, tool_calls?, tool_call_id?}]
 * @param {Array} activeNames - skills activated this session
 */
function stubDeliveredSkillResults(messages, activeNames) {
    if (!Array.isArray(messages)) return messages;
    var wanted = Array.isArray(activeNames) ? activeNames : [];
    if (wanted.length === 0) return messages;

    var lookup = {};
    for (var w = 0; w < wanted.length; w++) lookup[String(wanted[w])] = true;

    var changed = false;
    var out = messages.slice();
    for (var i = 0; i < out.length; i++) {
        var msg = out[i];
        if (!msg || msg.role !== "assistant" || !msg.tool_calls) continue;
        var calls = Array.isArray(msg.tool_calls) ? msg.tool_calls : [];
        for (var c = 0; c < calls.length; c++) {
            var call = calls[c];
            var fn = call && call["function"] ? call["function"] : null;
            if (!fn || fn.name !== "skill") continue;
            var skillName = _extractArgName(fn.arguments);
            if (!skillName || !lookup[skillName]) continue;
            for (var t = i + 1; t < out.length; t++) {
                var tm = out[t];
                if (tm && tm.role === "tool" && tm.tool_call_id === call.id &&
                        String(tm.content || "").indexOf(STUB_SENTINEL) === -1) {
                    out[t] = { role: "tool", content: stubText(skillName), tool_call_id: call.id };
                    changed = true;
                    break;
                }
            }
        }
    }
    return changed ? out : messages;
}

/**
 * Parses the delimited output of the scan command emitted by main.qml's
 * loadSkills(). Each entry begins with a line "===PLASMALLM_SKILL <path>"
 * followed by the raw file contents; scanning stops at the END marker.
 *
 * @param {string} stdout - raw scan output
 * @param {Array} roots - [{dir: "/abs/dir", source: "plasmallm"}] in priority order
 * @returns {Array} parsed skill records; duplicate names keep the first
 *   (highest-priority) occurrence and later ones are marked invalid.
 */
function parseScanOutput(stdout, roots) {
    var MARK = "===PLASMALLM_SKILL ";
    var SCRIPT_MARK = "===PLASMALLM_SKILL_SCRIPT ";
    var END = "===PLASMALLM_SKILL_END";
    var found = [];
    var scriptPaths = [];
    var current = null;
    if (!stdout) return [];

    var lines = String(stdout).split("\n");
    function flush() {
        if (!current) return;
        found.push(parseSkillFile(current.path, current.chunks.join("\n")));
        current = null;
    }
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line.indexOf(SCRIPT_MARK) === 0) {
            flush();
            scriptPaths.push(line.substring(SCRIPT_MARK.length).trim());
        } else if (line.indexOf(MARK) === 0) {
            flush();
            current = { path: line.substring(MARK.length).trim(), chunks: [] };
        } else if (line.indexOf(END) === 0) {
            break;
        } else if (current) {
            current.chunks.push(line);
        }
    }
    flush();

    // Assign a source label based on which root directory contains the file.
    var list = Array.isArray(roots) ? roots : [];
    for (var f = 0; f < found.length; f++) {
        var best = null;
        for (var r = 0; r < list.length; r++) {
            var dir = list[r].dir ? String(list[r].dir).replace(/\/+$/, "") : "";
            if (dir && found[f].path.indexOf(dir + "/") === 0) {
                if (!best || dir.length > best.dir.length) best = { dir: dir, source: list[r].source };
            }
        }
        found[f].source = best ? best.source : "custom";
    }

    // Enforce unique names: first (highest-priority) wins.
    var seen = {};
    for (var s = 0; s < found.length; s++) {
        if (!found[s].valid) continue;
        if (seen[found[s].name]) {
            found[s].valid = false;
            found[s].error = "duplicate skill name '" + found[s].name + "' (first found at " + seen[found[s].name] + ")";
        } else {
            seen[found[s].name] = found[s].path;
        }
    }
    attachSkillScripts(found, scriptPaths);
    return found;
}

function shellQuotePath(p) {
    return "'" + String(p).replace(/'/g, "'\\''") + "'";
}

/**
 * StandardPaths.writableLocation in QML may return a file:// URL (or a
 * QUrl whose toString is one). Shell globs and xdg-open need a local path;
 * prepending another file:// makes QUrl treat "file" as a host (smb://file/...).
 */
function toLocalPath(p) {
    var s = String(p === undefined || p === null ? "" : p);
    if (s.indexOf("file://") === 0) {
        s = s.substring(7);
        if (s.indexOf("localhost/") === 0) s = s.substring(9);
    }
    return s;
}

function toFileUrl(p) {
    var local = toLocalPath(p);
    if (!local) return "";
    if (local.charAt(0) !== "/") local = "/" + local;
    return "file://" + local;
}

/**
 * Shell command used by main.qml and the Skills settings page to dump
 * SKILL.md / flat .md files from each root. Nested folders are listed
 * first so they win name conflicts against same-named flat files.
 */
function buildScanCommand(roots, prefixCmd) {
    var list = Array.isArray(roots) ? roots : [];
    var parts = [];
    if (prefixCmd) {
        parts.push(String(prefixCmd).replace(/[\s;&|]+$/, ""));
    }
    for (var i = 0; i < list.length; i++) {
        var dir = shellQuotePath(list[i].dir);
        parts.push("for f in " + dir + "/*/SKILL.md; do " +
            "if [ -f \"$f\" ]; then echo \"===PLASMALLM_SKILL $f\"; head -c 262144 \"$f\"; echo; fi; done");
        parts.push("for f in " + dir + "/*.md; do " +
            "if [ -f \"$f\" ]; then echo \"===PLASMALLM_SKILL $f\"; head -c 262144 \"$f\"; echo; fi; done");
        parts.push("for f in " + dir + "/*/scripts/*.sh; do " +
            "if [ -f \"$f\" ]; then echo \"===PLASMALLM_SKILL_SCRIPT $f\"; fi; done");
        parts.push("for f in " + dir + "/*/*.sh; do " +
            "if [ -f \"$f\" ]; then echo \"===PLASMALLM_SKILL_SCRIPT $f\"; fi; done");
        parts.push("for f in " + dir + "/*.sh; do " +
            "if [ -f \"$f\" ]; then echo \"===PLASMALLM_SKILL_SCRIPT $f\"; fi; done");
    }
    return parts.join("; ") + "; echo \"===PLASMALLM_SKILL_END\"";
}

/** Builds a compact metadata list (no bodies) safe to cache in KCFG for the settings dialog. */
function toCacheJson(skills) {
    var list = Array.isArray(skills) ? skills : [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        out.push({
            name: list[i].name,
            description: list[i].description,
            path: list[i].path,
            dirName: list[i].dirName,
            source: list[i].source,
            valid: list[i].valid,
            error: list[i].error,
            scripts: Array.isArray(list[i].scripts) ? list[i].scripts : [],
            bodyLength: list[i].body ? String(list[i].body).length : 0
        });
    }
    return JSON.stringify(out);
}

/**
 * Returns true if filePath is located inside any configured skill root directory.
 * Expands ~ and normalizes alternative home paths if homePaths {home, homeEnv} is provided.
 */
function isSkillPath(filePath, roots, homePaths) {
    if (!filePath) return false;
    var local = toLocalPath(filePath).trim();
    if (!local) return false;
    var expanded = local;
    if (homePaths) {
        var home = (homePaths.home || "").replace(/\/$/, "");
        var homeEnv = (homePaths.homeEnv || "").replace(/\/$/, "");
        if (expanded.indexOf("~") === 0) {
            expanded = (home || homeEnv || "$HOME") + expanded.substring(1);
        } else if (home && homeEnv && home !== homeEnv) {
            if (expanded === homeEnv || expanded.indexOf(homeEnv + "/") === 0) {
                expanded = home + expanded.substring(homeEnv.length);
            }
        }
    }
    expanded = expanded.replace(/\/+/g, "/").replace(/\/$/, "");
    var list = Array.isArray(roots) ? roots : [];
    for (var i = 0; i < list.length; i++) {
        var rootDir = toLocalPath(list[i].dir || "").trim();
        if (homePaths && homePaths.home && homePaths.homeEnv && homePaths.home !== homePaths.homeEnv) {
            if (rootDir === homePaths.homeEnv || rootDir.indexOf(homePaths.homeEnv + "/") === 0) {
                rootDir = homePaths.home + rootDir.substring(homePaths.homeEnv.length);
            }
        }
        rootDir = rootDir.replace(/\/+/g, "/").replace(/\/$/, "");
        if (rootDir && (expanded === rootDir || expanded.indexOf(rootDir + "/") === 0)) {
            return true;
        }
    }
    return false;
}

