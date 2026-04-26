/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Adapter registry. Each adapter is a JS module exposing the same surface:
//   id, displayName,
//   fetchModels(endpoint, apiKey, callback),
//   buildTools(options),
//   buildContentArray(text, attachments),
//   sendStreaming({endpoint, apiKey, model, messages, temperature, maxTokens,
//                  tools, onChunk, onComplete}) -> handle.
//

.import "openai.js" as OpenAI
.import "anthropic.js" as Anthropic

function getAdapter(apiType) {
    switch (apiType) {
    case "anthropic":
        return Anthropic;
    case "openai":
    default:
        return OpenAI;
    }
}

// Flattened preset list across all adapters, with the apiType tagged on each
// entry so the UI can switch adapters when a preset is picked. The "Custom"
// sentinel is intentionally not included here — it's a UI affordance.
function getAllPresets() {
    var out = [];
    var adapters = [OpenAI, Anthropic];
    for (var a = 0; a < adapters.length; a++) {
        var ad = adapters[a];
        if (!ad.presets) continue;
        for (var i = 0; i < ad.presets.length; i++) {
            var p = ad.presets[i];
            out.push({ name: p.name, url: p.url, apiType: ad.id });
        }
    }
    return out;
}
