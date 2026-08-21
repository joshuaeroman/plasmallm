/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Pure helpers for Gemini generateContent thinkingConfig.
// Node tests load this with vm.runInContext (no QML imports).
//
// Platform differences (confirmed via curl):
//   AI Studio (generativelanguage):
//     gemini-flash-lite-latest / gemini-3.5-flash-lite reject thinkingBudget:0
//       → use thinkingLevel instead when disabling thinking
//     gemini-flash-latest accepts budget:0, rejects thinkingLevel MINIMAL
//   Agent Platform / Vertex (aiplatform):
//     gemini-2.5-* reject thinkingLevel entirely ("not supported by this model")
//     gemini-2.5-* and gemini-3-* accept thinkingBudget (including 0)
//     → always use thinkingBudget on Agent Platform

function isAgentPlatform(authMethod) {
    return authMethod === "agentplatform";
}

// AI Studio models that 400 on thinkingBudget:0.
function rejectsBudgetZeroOnAiStudio(model) {
    var m = String(model || "").toLowerCase();
    if (!m)
        return false;
    if (m === "gemini-flash-lite-latest")
        return true;
    // 3.5 / 3.6 flash-lite on AI Studio rejected budget 0 in testing.
    if (m.indexOf("3.5-flash-lite") !== -1 || m.indexOf("3.6-flash-lite") !== -1)
        return true;
    // Rolling lite aliases that currently map to the above.
    if (m.indexOf("flash-lite-latest") !== -1)
        return true;
    return false;
}

// gemini-flash-latest rejects MINIMAL; use LOW as the "off/cheap" floor.
function supportsMinimalThinkingLevel(model) {
    var m = String(model || "").toLowerCase();
    if (m === "gemini-flash-latest")
        return false;
    return true;
}

function budgetToThinkingLevel(budget, model) {
    var b = budget | 0;
    if (b <= 0) {
        if (supportsMinimalThinkingLevel(model))
            return "MINIMAL";
        return "LOW";
    }
    if (b <= 1024)
        return "LOW";
    if (b <= 8192)
        return "MEDIUM";
    return "HIGH";
}

// Build generationConfig.thinkingConfig for streamGenerateContent / generateContent.
// Never send both thinkingBudget and thinkingLevel (API 400).
// authMethod: "aistudio" | "agentplatform" | other/empty treated as aistudio.
function buildThinkingConfig(model, thinkingBudget, showThoughts, authMethod) {
    var budget = thinkingBudget | 0;
    if (budget < 0)
        budget = 0;

    var cfg = {};
    if (showThoughts)
        cfg.includeThoughts = true;

    // Vertex / Agent Platform: never send thinkingLevel (2.5 rejects it; 3 accepts budget).
    if (isAgentPlatform(authMethod)) {
        cfg.thinkingBudget = budget;
        return cfg;
    }

    // AI Studio: only switch to thinkingLevel when budget:0 is known-invalid.
    if (budget === 0 && rejectsBudgetZeroOnAiStudio(model)) {
        cfg.thinkingLevel = budgetToThinkingLevel(0, model);
        return cfg;
    }

    cfg.thinkingBudget = budget;
    return cfg;
}
