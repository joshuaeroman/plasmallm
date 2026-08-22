/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Built-in "edit_memory" tool: add, update, or remove entries in persistent
// memory in a single call. Entries live in the widget's KConfig
// ("memoryPhrases", JSON array) and are rendered into the system prompt's
// {{memories}} section on every rebuild (see memory.js), so they persist
// across conversations and Plasma restarts. Existing entries are identified
// by their 1-based number in the rendered list or by matching text. Access
// to the store is provided by the tool context (getMemory/setMemory).

.pragma library

.import "../memory.js" as Memory

var name = "edit_memory";
var displayName = "Edit Memory";
var description = "Add, update, or remove an entry in persistent memory; entries appear in your system prompt in every future conversation. Never save anything transient or sensitive.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "Brief reason for this change." },
        operation: { type: "string", enum: ["add", "update", "remove"], description: "Add a new entry, update an existing one, or remove one." },
        text: { type: "string", description: "For add/update: a short phrase capturing the fact or preference (max 100 chars)." },
        target: { type: "string", description: "For update/remove: entry number from the Persistent Memory list, or matching text fragment." }
    },
    required: ["justification", "operation"]
};
var sandboxed = false;
var sideEffect = true;

function _requireTarget(args, context) {
    if (!String(args.target || "").trim()) {
        context.error("Provide the entry to " + args.operation + ": its number from the Persistent Memory list or matching text.");
        return false;
    }
    return true;
}

function execute(args, context) {
    if (typeof context.getMemory !== "function" || typeof context.setMemory !== "function") {
        context.error("Persistent memory is not accessible from tool context.");
        return;
    }

    var op = String(args.operation || "").trim().toLowerCase();
    if (op !== "add" && op !== "update" && op !== "remove") {
        context.error("Unknown operation \"" + String(args.operation) + "\". Use one of: add, update, remove.");
        return;
    }

    var memory = context.getMemory();

    if (op === "add") {
        var res = Memory.addPhrase(memory, args.text);
        if (res.reason === "empty") {
            context.error("Provide the text to remember.");
            return;
        }
        if (res.reason === "full") {
            context.error("Memory is full (" + Memory.MAX_PHRASES + " entries). Remove an outdated entry first.");
            return;
        }
        if (res.reason === "duplicate") {
            context.onDone("Already remembered: \"" + res.phrase + "\"", "", 0);
            return;
        }
        context.setMemory(res.list);
        context.onDone("Remembered: \"" + res.phrase + "\"", "", 0);
        return;
    }

    if (op === "update") {
        if (!_requireTarget(args, context)) return;
        var upd = Memory.updatePhrase(memory, args.target, args.text);
        if (upd.reason === "empty") {
            context.error("Provide the new text for the entry.");
            return;
        }
        if (upd.reason === "not_found") {
            context.error("No matching entry to update. Current memory:" + Memory.formatEntryList(memory));
            return;
        }
        if (upd.reason === "ambiguous") {
            context.error("Multiple entries match \"" + String(args.target).trim() + "\". Be more specific or use the entry number:" + Memory.formatEntryList(upd.matches));
            return;
        }
        if (upd.reason === "duplicate") {
            context.error("That wording is already remembered as entry " + upd.dupIndex + ": \"" + upd.phrase + "\"");
            return;
        }
        if (upd.reason === "unchanged") {
            context.onDone("Unchanged: \"" + upd.phrase + "\"", "", 0);
            return;
        }
        context.setMemory(upd.list);
        context.onDone("Updated: \"" + upd.removed + "\" is now \"" + upd.phrase + "\"", "", 0);
        return;
    }

    // remove
    if (!_requireTarget(args, context)) return;
    var rem = Memory.removePhrase(memory, args.target);
    if (rem.reason === "empty") {
        context.onDone("Persistent memory is already empty.", "", 0);
        return;
    }
    if (rem.reason === "not_found") {
        context.error("No matching entry. Current memory:" + Memory.formatEntryList(memory));
        return;
    }
    if (rem.reason === "ambiguous") {
        context.error("Multiple entries match \"" + String(args.target).trim() + "\". Be more specific or use the entry number:" + Memory.formatEntryList(rem.matches));
        return;
    }
    context.setMemory(rem.list);
    context.onDone("Forgot: \"" + rem.removed + "\"", "", 0);
}
