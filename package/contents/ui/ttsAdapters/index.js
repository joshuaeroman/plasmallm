/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Registry of TTS backends.
// Imported from tts.js (.pragma library).

.import "spd_say.js" as SpdSay
.import "openai_speech.js" as OpenaiSpeech
.import "custom_cli.js" as CustomCli

var backends = {
    "spd_say": SpdSay,
    "openai_speech": OpenaiSpeech,
    "custom_cli": CustomCli
};

function get(backendId) {
    var id = backendId || "spd_say";
    return backends[id] || backends["spd_say"];
}

function list() {
    return [
        { id: SpdSay.id, name: SpdSay.displayName },
        { id: OpenaiSpeech.id, name: OpenaiSpeech.displayName },
        { id: CustomCli.id, name: CustomCli.displayName }
    ];
}
