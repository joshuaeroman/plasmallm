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
// Future adapters (gemini, anthropic) translate to/from the OpenAI-shaped
// neutral form used internally for messages and tool_calls.

.import "openai.js" as OpenAI

function getAdapter(apiType) {
    switch (apiType) {
    case "openai":
    default:
        return OpenAI;
    }
}
