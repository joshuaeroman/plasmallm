/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// OpenAI-compatible adapter dispatcher. Routes calls to one of two strategy
// modules depending on the active provider's API:
//   - openai_chat.js — /v1/chat/completions (default; broad ecosystem)
//   - openai_responses.js — /v1/responses (OpenAI native, Poe, OpenRouter,
//     Azure; required to surface reasoning content and round-trip reasoning
//     items across turns).
//
// The strategy is selected via opts.usesResponsesAPI (forwarded by main.qml
// from Plasmoid.configuration.usesResponsesAPI). Each preset annotates whether
// it speaks Responses; the configGeneral page auto-syncs the flag on preset
// change but the user can override it manually.

.import "openai_chat.js" as Chat
.import "openai_responses.js" as Responses

var id = "openai";
var displayName = "OpenAI-compatible";

// Which optional settings the configGeneral UI should expose for this adapter.
// Both strategies support reasoning effort; the thinking budget knob is only
// meaningful on Anthropic/Gemini.
var capabilities = {
    providerPresets: true,
    customEndpoint: true,
    reasoningEffort: true,
    thinkingBudget: false,
    fetchModels: true,
    reasoningHelp: i18n("Reasoning effort (low / medium / high) gates extended thinking. To see thoughts on OpenAI / Poe / OpenRouter / Azure, enable Use Responses API; chat-completions providers (DeepSeek, Qwen) surface reasoning via reasoning_content.")
};

// Provider presets shown in the settings UI. usesResponsesAPI:true marks
// providers that need /v1/responses for reasoning. Providers without the flag
// stay on chat-completions (the default and current behavior).
var presets = [
    { name: "Custom",                        url: "" },
    // Local / self-hosted (chat-completions only)
    { name: "Ollama (local)",                url: "http://localhost:11434/v1" },
    { name: "LM Studio (local)",             url: "http://localhost:1234/v1" },
    { name: "LocalAI (local)",               url: "http://localhost:8080/v1" },
    { name: "vLLM (local)",                  url: "http://localhost:8000/v1" },
    { name: "KoboldCpp (local)",             url: "http://localhost:5001/v1" },
    { name: "text-generation-webui (local)", url: "http://localhost:5000/v1" },
    // Cloud — Responses API
    { name: "OpenAI",                        url: "https://api.openai.com/v1",       usesResponsesAPI: true },
    { name: "Poe",                           url: "https://api.poe.com/v1",          usesResponsesAPI: true },
    { name: "OpenRouter",                    url: "https://openrouter.ai/api/v1",    usesResponsesAPI: true },
    { name: "Azure OpenAI",                  url: "",                                usesResponsesAPI: true },
    // Cloud — Chat Completions only
    { name: "Anthropic (OpenAI-compat)",     url: "https://api.anthropic.com/v1" },
    { name: "Google Gemini",                 url: "https://generativelanguage.googleapis.com/v1beta/openai" },
    { name: "Groq",                          url: "https://api.groq.com/openai/v1" },
    { name: "Together AI",                   url: "https://api.together.xyz/v1" },
    { name: "Mistral",                       url: "https://api.mistral.ai/v1" },
    { name: "Perplexity",                    url: "https://api.perplexity.ai" },
    { name: "DeepSeek",                      url: "https://api.deepseek.com/v1" },
    { name: "xAI (Grok)",                    url: "https://api.x.ai/v1" },
    { name: "Fireworks AI",                  url: "https://api.fireworks.ai/inference/v1" },
    { name: "Cerebras",                      url: "https://api.cerebras.ai/v1" },
    { name: "DeepInfra",                     url: "https://api.deepinfra.com/v1/openai" },
    { name: "Cohere",                        url: "https://api.cohere.ai/compatibility/v1" },
    { name: "SambaNova",                     url: "https://api.sambanova.ai/v1" },
    { name: "Novita AI",                     url: "https://api.novita.ai/v3/openai" },
    // Russian providers
    { name: "RouterAI (RU)",                 url: "https://routerai.ru/api/v1" },
    { name: "AITunnel (RU)",                 url: "https://api.aitunnel.ru/v1" }
];

function fetchModels(endpoint, apiKey, usesResponsesAPI, callback) {
    return usesResponsesAPI
        ? Responses.fetchModels(endpoint, apiKey, callback)
        : Chat.fetchModels(endpoint, apiKey, callback);
}

function buildTools(options) {
    return (options && options.usesResponsesAPI)
        ? Responses.buildTools(options)
        : Chat.buildTools(options);
}

function buildContentArray(text, attachments, usesResponsesAPI) {
    return usesResponsesAPI
        ? Responses.buildContentArray(text, attachments)
        : Chat.buildContentArray(text, attachments);
}

function sendStreaming(opts) {
    return (opts && opts.usesResponsesAPI)
        ? Responses.sendStreaming(opts)
        : Chat.sendStreaming(opts);
}
