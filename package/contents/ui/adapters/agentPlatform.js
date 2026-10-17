/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Shared helpers for the Gemini adapters (generateContent and Interactions).
// Node tests load this with vm.runInContext (no QML imports).

// Model IDs that are not chat models. They answer generateContent but
// return images/audio (or need websockets), so they don't belong in the chat
// model picker. "nano-banana" is the Gemini image model's public name.
var NON_CHAT_MARKERS = [
    "-tts", "embedding", "image", "nano-banana", "live", "native-audio",
    "lyria", "veo"
];

function isChatModel(modelId) {
    var lower = String(modelId || "").toLowerCase();
    for (var i = 0; i < NON_CHAT_MARKERS.length; i++) {
        if (lower.indexOf(NON_CHAT_MARKERS[i]) !== -1)
            return false;
    }
    return true;
}
