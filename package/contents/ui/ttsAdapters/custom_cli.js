/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Custom CLI adapter for Piper, espeak-ng, mimic, etc.

var id = "custom_cli";
var displayName = "Custom CLI command";
var transport = "cli";

function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function trimStr(value) {
    return String(value || "").replace(/^\s+|\s+$/g, "");
}

function isConfigured(conn) {
    if (!conn || !conn.enabled)
        return false;
    var tpl = trimStr(conn.cliTemplate);
    var bin = trimStr(conn.cliBinary);
    return tpl.length > 0 || bin.length > 0;
}

/**
 * Build CLI command from template.
 * Supported tokens: {text}, {voice}, {rate}
 *
 * @param {object} opts
 * @param {string} opts.text
 * @param {string} [opts.cliTemplate]
 * @param {string} [opts.cliBinary]
 * @param {string} [opts.voice]
 * @param {number} [opts.rate]
 * @param {string} [opts.extraArgs]
 * @returns {string} shell command
 */
function buildCommand(opts) {
    opts = opts || {};
    var text = String(opts.text || "");
    if (!text.trim().length)
        throw new Error("No text to speak");

    var tpl = trimStr(opts.cliTemplate);
    var binary = trimStr(opts.cliBinary) || "espeak-ng";
    var quotedText = shellQuote(text);
    var voice = trimStr(opts.voice);
    var rate = opts.rate !== undefined ? String(opts.rate) : "0";

    if (tpl.length > 0) {
        var cmd = tpl;
        if (cmd.indexOf("{text}") >= 0) {
            cmd = cmd.replace(/\{text\}/g, quotedText);
        } else {
            cmd = cmd + " " + quotedText;
        }
        if (cmd.indexOf("{voice}") >= 0) {
            cmd = cmd.replace(/\{voice\}/g, voice.length ? shellQuote(voice) : "");
        }
        if (cmd.indexOf("{rate}") >= 0) {
            cmd = cmd.replace(/\{rate\}/g, rate);
        }
        var extra = trimStr(opts.extraArgs);
        if (extra.length)
            cmd += " " + extra;
        return "echo TTS_READY; " + cmd;
    }

    // Default fallback to invoking binary with text
    var parts = [binary];
    if (voice.length) {
        parts.push("-v");
        parts.push(shellQuote(voice));
    }
    var extraArgs = trimStr(opts.extraArgs);
    if (extraArgs.length)
        parts.push(extraArgs);
    parts.push(quotedText);
    return "echo TTS_READY; " + parts.join(" ");
}

/**
 * Build the command to stop speech playback immediately.
 * @returns {string}
 */
function buildStopCommand() {
    return "pkill -f '/tmp/plasmallm_tts' 2>/dev/null; spd-say -S 2>/dev/null";
}

function parseResult(stdout, stderr, exitCode) {
    if (exitCode !== 0 && exitCode !== "0") {
        var errDetail = trimStr(stderr) || trimStr(stdout) || ("Exit code " + exitCode);
        return { err: "Custom TTS command failed: " + errDetail, result: null };
    }
    return { err: null, result: { success: true } };
}
