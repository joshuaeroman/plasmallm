/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Speech Dispatcher (spd-say) local CLI adapter.
// Standard across Linux/KDE desktops, completely offline, zero configuration.

var id = "spd_say";
var displayName = "Speech Dispatcher (local CLI)";
var transport = "cli";

function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function trimStr(value) {
    return String(value || "").replace(/^\s+|\s+$/g, "");
}

function isSafeToken(value) {
    return /^[A-Za-z0-9._-]+$/.test(String(value || ""));
}

function isConfigured(conn) {
    if (!conn || !conn.enabled)
        return false;
    return true;
}

/**
 * Build the CLI command to speak text using spd-say.
 * Uses pipe mode (-e) with printf to safely stream multi-line text without shell escaping limits.
 *
 * @param {object} opts
 * @param {string} opts.text
 * @param {number} [opts.rate]       -100 to 100 (default: 0)
 * @param {number} [opts.pitch]      -100 to 100 (default: 0)
 * @param {string} [opts.voice]      synthesis voice name
 * @param {string} [opts.language]   ISO language code
 * @param {string} [opts.cliBinary]  spd-say command/prefix
 * @param {string} [opts.extraArgs]  additional CLI args
 * @returns {string} shell command
 */
function buildCommand(opts) {
    opts = opts || {};
    var text = String(opts.text || "");
    if (!text.trim().length)
        throw new Error("No text to speak");

    var binary = trimStr(opts.cliBinary) || "spd-say";
    var args = [];

    // Rate (-100 to 100)
    var rate = parseInt(opts.rate, 10);
    if (!isNaN(rate) && rate !== 0 && rate >= -100 && rate <= 100) {
        args.push("-r");
        args.push(String(rate));
    }

    // Pitch (-100 to 100)
    var pitch = parseInt(opts.pitch, 10);
    if (!isNaN(pitch) && pitch !== 0 && pitch >= -100 && pitch <= 100) {
        args.push("-p");
        args.push(String(pitch));
    }

    // Voice
    var voice = trimStr(opts.voice);
    if (voice.length) {
        args.push("-y");
        args.push(isSafeToken(voice) ? voice : shellQuote(voice));
    }

    // Language
    var lang = trimStr(opts.language);
    if (lang.length) {
        args.push("-l");
        args.push(isSafeToken(lang) ? lang : shellQuote(lang));
    }

    // Check if text looks like SSML
    if (text.indexOf("<speak>") >= 0 || text.indexOf("</speak>") >= 0) {
        args.push("-x");
    }

    var extra = trimStr(opts.extraArgs);
    if (extra.length) {
        args.push(extra);
    }

    args.push("-e");

    var cmd = "echo TTS_READY; printf '%s' " + shellQuote(text) + " | " + binary + " " + args.join(" ") + " 1>/dev/null";
    return cmd;
}

/**
 * Build the command to stop speech playback immediately.
 * @returns {string}
 */
function buildStopCommand() {
    return "spd-say -S 2>/dev/null || spd-say -C 2>/dev/null";
}

function parseResult(stdout, stderr, exitCode) {
    if (exitCode !== 0 && exitCode !== "0") {
        var errDetail = trimStr(stderr) || trimStr(stdout) || ("Exit code " + exitCode);
        return { err: "Speech Dispatcher failed: " + errDetail, result: null };
    }
    return { err: null, result: { success: true } };
}
