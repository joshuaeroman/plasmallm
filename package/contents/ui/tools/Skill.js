/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Built-in "skill" tool: loads the full instructions of an available skill.
// The model discovers skills via the <available_skills> index rendered into
// the {{skills}} system prompt section (see skills.js) and calls this tool
// with the skill's name. Bodies come from the in-memory skill cache built by
// main.qml's directory scan, so no shell or filesystem access is needed.

var name = "skill";
var description = "Load the full instructions of an available skill by name. " +
    "Check this tool BEFORE using other tools when a task matches an available skill. " +
    "Only use names listed in <available_skills>.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        name: { type: "string", description: "The skill name from <available_skills>" }
    },
    required: ["justification", "name"]
};
var sandboxed = false;
var sideEffect = false;

// Matches main.qml's scan cap (head -c on SKILL.md files).
var MAX_BODY_CHARS = 262144;

function _isDisabled(skillName, config) {
    if (!config || !config.skillsDisabledList) return false;
    try {
        var parsed = typeof config.skillsDisabledList === "string"
            ? JSON.parse(config.skillsDisabledList)
            : config.skillsDisabledList;
        if (!Array.isArray(parsed)) return false;
        for (var i = 0; i < parsed.length; i++) {
            if (String(parsed[i]) === skillName) return true;
        }
    } catch (e) {}
    return false;
}

function execute(args, context) {
    var wanted = String(args.name || "").trim();
    var skills = (typeof context.getSkills === "function") ? (context.getSkills() || []) : [];

    var found = null;
    for (var i = 0; i < skills.length; i++) {
        if (skills[i] && skills[i].valid && skills[i].name === wanted) {
            found = skills[i];
            break;
        }
    }
    if (!found) {
        context.error("Unknown or invalid skill '" + wanted + "'. Use a name listed in <available_skills>.");
        return;
    }
    if (_isDisabled(wanted, context.config)) {
        context.error("Skill '" + wanted + "' is disabled by the user in PlasmaLLM settings.");
        return;
    }

    var body = String(found.body || "");
    if (body.length > MAX_BODY_CHARS) {
        body = body.substring(0, MAX_BODY_CHARS) + "\n;;; (skill truncated at " + MAX_BODY_CHARS + " characters)";
    }
    context.onDone(body, "", 0);
}
