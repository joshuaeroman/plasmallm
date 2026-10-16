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
