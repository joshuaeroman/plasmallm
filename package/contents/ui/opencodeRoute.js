/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Pure OpenCode Zen/Go protocol routing (no QML / network / imports).
// Node tests load this with vm.runInContext.
//
// OpenCode gateways speak a native protocol per model. GET /models does not
// include that metadata, so we map from the official endpoint tables:
//   https://opencode.ai/docs/zen/
//   https://opencode.ai/docs/go
// models.dev `provider.npm` mostly agrees; Go Qwen is `/messages` in the
// official table but openai-compatible on models.dev — this file follows
// the official table. Prefix fallbacks cover newly listed siblings.

function productFromEndpoint(endpoint, providerName) {
    var name = String(providerName || "").toLowerCase();
    if (name.indexOf("opencode") !== -1 && name.indexOf("go") !== -1)
        return "go";
    var ep = String(endpoint || "").toLowerCase();
    if (ep.indexOf("/zen/go") !== -1)
        return "go";
    return "zen";
}

function npmToProtocol(npm) {
    if (npm === "@ai-sdk/openai")
        return "responses";
    if (npm === "@ai-sdk/anthropic")
        return "anthropic";
    if (npm === "@ai-sdk/google")
        return "gemini";
    return "chat";
}

// overlay: optional { modelId: protocol } map (e.g. from models.dev).
function resolveProtocol(product, modelId, overlay) {
    var id = String(modelId || "").toLowerCase();
    var prod = product === "go" ? "go" : "zen";
    if (!id)
        return "chat";
    if (overlay) {
        if (overlay[id])
            return overlay[id];
        if (modelId && overlay[modelId])
            return overlay[modelId];
    }
    if (id.indexOf("gpt-") === 0 || id.indexOf("grok-") === 0 || id.indexOf("muse-spark-") === 0)
        return "responses";
    if (id.indexOf("gemini-") === 0)
        return "gemini";
    if (id.indexOf("claude-") === 0)
        return "anthropic";
    // Official tables list qwen3.N-* on /messages. Do not use a bare "qwen3"
    // prefix — Zen also serves qwen3-coder on chat completions.
    if (id.indexOf("qwen3.") === 0)
        return "anthropic";
    if (prod === "go" && id.indexOf("minimax-") === 0)
        return "anthropic";
    return "chat";
}
