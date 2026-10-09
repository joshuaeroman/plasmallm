/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Built-in "set_tts_style" tool: dynamically adjust text-to-speech style,
// tone, or emotion hints for speech synthesis. Supports three scopes:
// - "turn": applies only to the upcoming assistant response in this turn.
// - "session": applies to the current chat conversation until reset/cleared.
// - "persistent": writes to widget settings (Plasmoid.configuration.ttsStyleHint).

.pragma library

var name = "set_tts_style";
var displayName = "Set Speech Tone / Style";
var description = "Dynamically set or adjust the text-to-speech style, emotion, or voice tone directive for speech synthesis (e.g. '<sarcastic>', '[whispering]', '<excited>', or '' to reset to default). Use 'turn' for only the upcoming response, 'session' for this conversation, or 'persistent' to save in settings.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "Brief explanation of why the speech style is being changed." },
        style: { type: "string", description: "The style or tone hint to set, e.g. '<sarcastic>', '[whispering]', '<excited>', or empty string to reset." },
        scope: {
            type: "string",
            enum: ["turn", "session", "persistent"],
            description: "Scope of the tone directive: 'turn' for only the upcoming assistant response, 'session' for the ongoing conversation, or 'persistent' to save in widget settings permanently."
        }
    },
    required: ["justification", "style"]
};
var sandboxed = false;
var sideEffect = true;

function execute(args, context) {
    if (!context || typeof context.setTtsStyle !== "function") {
        if (context && typeof context.error === "function") {
            context.error("TTS style control is not available in tool context.");
        }
        return;
    }

    if (context.config && context.config.ttsAllowAgentStyleControl === false) {
        context.error("Agent speech style control is disabled in widget settings.");
        return;
    }

    var scope = String(args.scope || "turn").toLowerCase();
    if (scope !== "turn" && scope !== "session" && scope !== "persistent") {
        scope = "turn";
    }

    var res = context.setTtsStyle(args.style, scope);
    var label = (res && res.style && res.style.length > 0) ? ("'" + res.style + "'") : "default";
    var msg = "Speech style set to " + label + " (" + scope + "). Your response will use this style.";
    context.onDone(msg, "", 0);
}
