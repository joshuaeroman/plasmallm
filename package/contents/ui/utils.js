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
