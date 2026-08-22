/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Pure persistent-memory helpers (no QML / shell / imports). QML imports this
// via main.qml / api.js / tools; Node tests load it with vm.runInContext.
//
// Memory is a flat list of short phrases stored in the widget's KConfig as a
// JSON array string (config key "memoryPhrases"). The phrases are rendered
// into the system prompt's {{memories}} section on every rebuild, so context
// compaction and message capping can never drop them mid-session. Entries are
// managed via the edit_memory tool and matched by the 1-based number shown in
// that rendered list or by text.

var MAX_PHRASES = 100;
var MAX_PHRASE_LENGTH = 100;

// Accepts a JSON string, an array, or junk; returns a clean array of strings.
function parseStored(raw) {
    var list = null;
    if (Array.isArray(raw)) {
        list = raw;
    } else if (typeof raw === "string" && raw.trim().length > 0) {
        try {
            var parsed = JSON.parse(raw);
            if (Array.isArray(parsed)) list = parsed;
        } catch (e) {}
    }
    if (!list) return [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        if (typeof list[i] === "string" && list[i].trim().length > 0) out.push(list[i]);
    }
    return out;
}

// Inverse of parseStored: canonical storage form ("" when empty).
function serialize(list) {
    var clean = parseStored(list);
    return clean.length > 0 ? JSON.stringify(clean) : "";
}

// Collapses whitespace, trims, and caps length. Returns "" for empty input.
function normalizePhrase(text) {
    var s = String(text === undefined || text === null ? "" : text)
        .replace(/\s+/g, " ")
        .trim();
    if (s.length > MAX_PHRASE_LENGTH) {
        s = s.substring(0, MAX_PHRASE_LENGTH).trim();
    }
    return s;
}

function _key(text) {
    return normalizePhrase(text).toLowerCase();
}

// Adds a phrase to a copy of `list` (deduped case-insensitively, capped).
// Returns { list, added, phrase, reason } with reason "ok", "duplicate",
// "empty", or "full". On duplicate, `phrase` is the already-stored wording.
function addPhrase(list, text) {
    var phrase = normalizePhrase(text);
    var out = parseStored(list);
    if (!phrase) return { list: out, added: false, phrase: "", reason: "empty" };
    var key = phrase.toLowerCase();
    for (var i = 0; i < out.length; i++) {
        if (_key(out[i]) === key) {
            return { list: out, added: false, phrase: out[i], reason: "duplicate" };
        }
    }
    if (out.length >= MAX_PHRASES) {
        return { list: out, added: false, phrase: phrase, reason: "full" };
    }
    out.push(phrase);
    return { list: out, added: true, phrase: phrase, reason: "ok" };
}

// Resolves an entry reference within `items`: a 1-based number from the
// rendered list, case-insensitive exact text, or a unique substring match.
// Returns { idx, candidates, reason } with reason "ok", "not_found", or
// "ambiguous"; `candidates` holds the conflicting phrases for ambiguity
// errors. Out-of-range numbers fall through to text matching.
function _resolveTarget(items, target) {
    var t = String(target === undefined || target === null ? "" : target).trim();
    if (!t) return { idx: -1, candidates: [], reason: "not_found" };

    if (/^\d+$/.test(t)) {
        var idx = parseInt(t, 10) - 1;
        if (idx >= 0 && idx < items.length) {
            return { idx: idx, candidates: [items[idx]], reason: "ok" };
        }
    }

    var key = _key(t);
    for (var i = 0; i < items.length; i++) {
        if (_key(items[i]) === key) {
            return { idx: i, candidates: [items[i]], reason: "ok" };
        }
    }

    var hitIdx = [];
    for (var j = 0; j < items.length; j++) {
        if (_key(items[j]).indexOf(key) !== -1) hitIdx.push(j);
    }
    if (hitIdx.length === 1) {
        return { idx: hitIdx[0], candidates: [items[hitIdx[0]]], reason: "ok" };
    }
    if (hitIdx.length > 1) {
        var candidates = [];
        for (var k = 0; k < hitIdx.length; k++) {
            candidates.push(items[hitIdx[k]]);
        }
        return { idx: -1, candidates: candidates, reason: "ambiguous" };
    }
    return { idx: -1, candidates: [], reason: "not_found" };
}

// Removes an entry identified by _resolveTarget. Returns
// { list, removed, matches, reason } with reason "ok", "empty",
// "not_found", or "ambiguous".
function removePhrase(list, target) {
    var items = parseStored(list);
    if (items.length === 0) return { list: items, removed: null, matches: [], reason: "empty" };
    var res = _resolveTarget(items, target);
    if (res.reason !== "ok") {
        return { list: items, removed: null, matches: res.candidates, reason: res.reason };
    }
    var removed = items.splice(res.idx, 1)[0];
    return { list: items, removed: removed, matches: [removed], reason: "ok" };
}

// Replaces an entry identified like removePhrase with new text. Returns
// { list, removed, phrase, dupIndex, matches, reason } with reason "ok",
// "unchanged", "duplicate", "empty", "not_found", or "ambiguous". `removed`
// carries the old wording on success; `dupIndex` is the 1-based number of a
// conflicting entry when reason is "duplicate".
function updatePhrase(list, target, text) {
    var items = parseStored(list);
    var phrase = normalizePhrase(text);
    if (items.length === 0 || !phrase) {
        return { list: items, removed: null, phrase: phrase, dupIndex: -1, matches: [], reason: "empty" };
    }
    var res = _resolveTarget(items, target);
    if (res.reason !== "ok") {
        return { list: items, removed: null, phrase: phrase, dupIndex: -1, matches: res.candidates, reason: res.reason };
    }
    var key = phrase.toLowerCase();
    if (_key(items[res.idx]) === key) {
        return { list: items, removed: items[res.idx], phrase: phrase, dupIndex: -1, matches: [], reason: "unchanged" };
    }
    for (var i = 0; i < items.length; i++) {
        if (i !== res.idx && _key(items[i]) === key) {
            return { list: items, removed: null, phrase: phrase, dupIndex: i + 1, matches: [], reason: "duplicate" };
        }
    }
    var old = items[res.idx];
    items[res.idx] = phrase;
    return { list: items, removed: old, phrase: phrase, dupIndex: -1, matches: [], reason: "ok" };
}

// Renders the {{memories}} system-prompt section; "" when there are no phrases.
function renderSection(list) {
    var items = parseStored(list);
    if (items.length === 0) return "";
    var lines = [
        "## Persistent Memory",
        "Long-term notes the user asked you to remember across conversations. Add, update, or remove entries with the `edit_memory` tool, citing an entry's number or text.",
        ""
    ];
    for (var i = 0; i < items.length; i++) {
        lines.push((i + 1) + ". " + items[i]);
    }
    return lines.join("\n");
}

// Numbered listing for tool error messages ("Current memory:\n1. ...").
function formatEntryList(list) {
    var items = parseStored(list);
    if (items.length === 0) return "(memory is empty)";
    var lines = [];
    for (var i = 0; i < items.length; i++) {
        lines.push((i + 1) + ". " + items[i]);
    }
    return "\n" + lines.join("\n");
}
