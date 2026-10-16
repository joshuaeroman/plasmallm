/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Pure generic helpers (no QML / shell / imports). QML imports this via
// main.qml / adapters; Node tests load it with vm.runInContext.

// RFC 4122 v4 UUID from Math.random. QML's JS engine has no crypto API, so
// this is the best available; used for stable per-conversation request
// identifiers (e.g. the x-opencode-session header), not for security.
function uuidv4() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
        var r = Math.random() * 16 | 0;
        var v = c === "x" ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

// Host of an http(s) URL, lowercase ("" when unparseable).
function hostOf(endpoint) {
    var m = String(endpoint || "").match(/^https?:\/\/([^\/:?#]+)/i);
    return m ? m[1].toLowerCase() : "";
}

// OpenRouter app host: openrouter.ai, www.openrouter.ai, or *.openrouter.ai.
function isOpenRouterHost(host) {
    host = String(host || "").toLowerCase();
    return host === "openrouter.ai" || host === "www.openrouter.ai" ||
           (host.length > 14 && host.slice(-14) === ".openrouter.ai");
}

function isOpenRouterEndpoint(endpoint) {
    return isOpenRouterHost(hostOf(endpoint));
}

// OpenRouter by provider preset name (e.g. "OpenRouter", "openrouter") or by
// endpoint host. Used by the OpenAI-compatible strategies (where a custom
// gateway URL may carry the provider name) and by the settings UI.
function isOpenRouterProvider(providerName, endpoint) {
    return String(providerName || "").toLowerCase().indexOf("openrouter") !== -1 ||
           isOpenRouterEndpoint(endpoint);
}

// App-attribution headers for OpenRouter (public rankings/analytics): the
// app URL and display name only, never message content. Applied only when
// opts.attribution === true (so a call site that forgets to wire the setting
// stays header-free) and the request targets OpenRouter by provider name
// (opts.providerName) or endpoint host. Single source of the header literals.
function applyOpenRouterAttribution(xhr, opts, endpoint) {
    if (opts && opts.attribution === true &&
        isOpenRouterProvider(opts.providerName, endpoint)) {
        xhr.setRequestHeader("HTTP-Referer", "https://github.com/joshuaeroman/plasmallm");
        xhr.setRequestHeader("X-OpenRouter-Title", "PlasmaLLM");
    }
}

// Chat history placement: "sidebar" or "button". "auto" picks the sidebar
// when the view fits both a minimum-width sidebar and a minimum-width chat;
// unknown modes keep the header button.
function historyLayoutFor(mode, width, minSidebarWidth, minChatWidth) {
    if (mode === "sidebar") return "sidebar";
    if (mode !== "auto") return "button";
    return (width >= minSidebarWidth + minChatWidth) ? "sidebar" : "button";
}

// One-line snippet from a raw JSON string fragment, as the history list's
// shell extraction yields it: escapes are still encoded and the text stops
// at the first quote, so an escaped \" leaves a dangling backslash.
function cleanHistoryPreview(raw) {
    var s = String(raw || "");
    var tail = s.match(/\\+$/);
    if (tail && tail[0].length % 2 === 1) s = s.slice(0, -1);
    s = s.replace(/\\(u[0-9a-fA-F]{4}|.)/g, function(m, e) {
        if (e.length === 5) return String.fromCharCode(parseInt(e.slice(1), 16));
        return (e === "n" || e === "r" || e === "t") ? " " : e;
    });
    // head -c can split a multibyte character at the cut.
    s = s.replace(/\uFFFD+$/, "");
    return s.replace(/\s+/g, " ").trim();
}

// Chat summarizer (titles shown in chat history). mode is "off", "initial"
// (summarize the first message only) or "every" (again after every
// `interval` user messages). A chat without a title is always summarized,
// so a failed or never-run summary is retried on the next message.
function shouldSummarizeChat(mode, userCount, interval, hasTitle) {
    if (mode !== "initial" && mode !== "every") return false;
    if (userCount < 1) return false;
    if (!hasTitle) return true;
    if (mode !== "every") return false;
    var n = Math.max(1, Math.floor(interval) || 1);
    return (userCount - 1) % n === 0;
}

var CHAT_SUMMARY_INSTRUCTION = "Summarize this conversation as a title in 5 words or less. Reply with only the title, without quotes or trailing punctuation.";

// User message for the summarizer: the first prompt (capped) plus the first
// 50 characters of up to three of the most recent later messages.
function buildChatSummaryPrompt(userTexts) {
    var texts = (userTexts || []).map(function(t) {
        return String(t || "").replace(/\s+/g, " ").trim();
    });
    if (texts.length === 0) return "";
    var initial = texts[0];
    if (initial.length > 2000) initial = initial.substring(0, 2000) + "…";
    var out = "First user message:\n" + initial;
    var recent = texts.slice(1).slice(-3);
    if (recent.length > 0) {
        out += "\n\nMost recent user messages (truncated):\n" + recent.map(function(t) {
            return "- " + t.substring(0, 50);
        }).join("\n");
    }
    return out + "\n\n" + CHAT_SUMMARY_INSTRUCTION;
}

// First meaningful line of the model's reply, without markdown, quotes,
// a "Title:"/"Summary:" label or trailing punctuation.
function cleanChatSummary(raw) {
    var lines = String(raw || "").split("\n");
    var s = "";
    for (var i = 0; i < lines.length; i++) {
        s = lines[i].replace(/[*_`#>]+/g, " ").replace(/\s+/g, " ").trim();
        if (s) break;
    }
    s = s.replace(/^(title|summary)\s*:\s*/i, "");
    s = s.replace(/^["'“”‘’]+|["'“”‘’]+$/g, "").trim();
    s = s.replace(/[.!?;:,]+$/, "").trim();
    if (s.length > 80) s = s.substring(0, 80).trim() + "…";
    return s;
}

// Chat history day group for a file mtime (seconds), by local calendar day:
// "today", "yesterday", "week" (the five days before that) or "older".
function historyDayGroup(mtimeSec, now) {
    if (!(mtimeSec > 0)) return "older";
    var t = mtimeSec * 1000;
    function dayStart(daysAgo) {
        return new Date(now.getFullYear(), now.getMonth(), now.getDate() - daysAgo).getTime();
    }
    if (t >= dayStart(0)) return "today";
    if (t >= dayStart(1)) return "yesterday";
    if (t >= dayStart(6)) return "week";
    return "older";
}
