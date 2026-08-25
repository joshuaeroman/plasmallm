/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "run_skill_script";
var displayName = "Run Skill Script";
var description = "Run a .sh file that belongs to an available skill (scripts/<name>.sh or <name>.sh next to SKILL.md). " +
    "Pass the skill name, script basename, and an args array. Do not use run_command for that work. " +
    "The script's working directory is the user's home. " +
    "The user may enable auto-run for that skill in Settings → Skills.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        skill: { type: "string", description: "Skill name from <available_skills>" },
        script: { type: "string", description: "Script basename, e.g. download.sh" },
        args: {
            type: "array",
            items: { type: "string" },
            description: "Positional arguments passed to the script"
        }
    },
    required: ["justification", "skill", "script"]
};
var sandboxed = false;
var sideEffect = true;
var outputScheme = "console style";

function execute(args, context) {
    if (typeof context.resolveSkillScript !== "function") {
        context.error("Skill script resolver is unavailable.");
        return;
    }
    var resolved = context.resolveSkillScript(args || {});
    if (!resolved || resolved.error) {
        context.error((resolved && resolved.error) ? resolved.error : "could not resolve skill script");
        return;
    }
    context.exec(resolved.command, name, args);
}
