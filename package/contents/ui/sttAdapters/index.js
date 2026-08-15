/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Registry of STT backends (mirrors adapters/index.js style).
// Imported from stt.js (.pragma library).

.import "openai_transcriptions.js" as OpenaiTranscriptions

var backends = {
    "openai_transcriptions": OpenaiTranscriptions
};

function get(backendId) {
    var id = backendId || "openai_transcriptions";
    return backends[id] || backends["openai_transcriptions"];
}

function list() {
    return [
        { id: OpenaiTranscriptions.id, name: OpenaiTranscriptions.displayName }
    ];
}
