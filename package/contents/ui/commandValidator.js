/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Pure command-validation helpers (no QML / imports). QML imports this via
// main.qml / configTools.qml; Node tests load it with vm.runInContext.
//
// Validates that a run_command call does what its LLM-supplied justification
// says it does. Two backends are supported:
//   - "decisions": structured System One API (Jev / TypeSafe). Used directly
//     against api.typesafe.ai, or through OpenRouter's alpha decisions route
//     for profiles whose model is a Jev/TypeSafe decisions model.
//   - "chat": any OpenAI-compatible (or Anthropic/Gemini/etc.) profile that
//     answers with a small JSON verdict.
//
// The chat transport must be injected by the caller (it goes through the
// adapter layer in api.js). The decisions transport defaults to a plain
// XMLHttpRequest POST, which exists only in the QML runtime.

// Jev is conservative when asked to affirm "the command matches" (legitimate
// commands score ~0.4-0.6), but sharply separated when asked to affirm the
// failure mode: accepted commands score <0.42 on mismatch, dangerous ones
// >0.58. So the decisions backend asks for the mismatch probability and the
// caller passes when it stays below the threshold.
var DECISIONS_MISMATCH_INSTRUCTIONS =
    "The command, exactly as written, performs material actions beyond what the justification describes.";

var DECISIONS_HIDDEN_INSTRUCTIONS =
    "The command contains obfuscation, hidden payloads, or side effects that are not apparent from the justification.";

var DECISIONS_SYNTAX_INSTRUCTIONS =
    "The command contains an incomplete construct or syntax error, such as an if without fi, a loop without done, an unclosed quote, bracket, or parenthesis.";

function hostOf(endpoint) {
    var m = String(endpoint || "").match(/^https?:\/\/([^\/:?#]+)/i);
    return m ? m[1].toLowerCase() : "";
}

function isTypeSafeModel(modelName) {
    var m = String(modelName || "").toLowerCase();
    return m.indexOf("jev") !== -1 || m.indexOf("typesafe") !== -1;
}

/** Resolves the validator backend: "decisions" or "chat". */
function backendFor(profile) {
    profile = profile || {};
    var override = profile.backend || "auto";
    if (override === "decisions" || override === "chat")
        return override;
    // First-class decisions adapter profiles are unambiguous.
    if (profile.apiType === "decisions")
        return "decisions";
    var host = hostOf(profile.endpoint);
    if (host === "api.typesafe.ai")
        return "decisions";
    if ((host === "openrouter.ai" || host === "www.openrouter.ai") && isTypeSafeModel(profile.modelName))
        return "decisions";
    return "chat";
}

/**
 * Extracts a human-readable error message from a provider error body.
 * OpenRouter uses {error:{message}}, TypeSafe uses {detail:{message}}.
 */
function httpErrorMessage(json, status) {
    if (json) {
        if (json.error && json.error.message) return String(json.error.message);
        if (typeof json.error === "string" && json.error.length > 0) return json.error;
        if (json.detail && json.detail.message) return String(json.detail.message);
        if (typeof json.detail === "string" && json.detail.length > 0) return json.detail;
        if (json.message) return String(json.message);
    }
    return "HTTP " + (status === undefined ? "" : status);
}

/** Full decisions endpoint URL for a profile endpoint. */
function decisionsUrl(endpoint) {
    var base = String(endpoint || "").replace(/\/+$/, "");
    var host = hostOf(base);
    if (host === "api.typesafe.ai")
        return base + "/systemone";
    if (host === "openrouter.ai" || host === "www.openrouter.ai")
        return "https://openrouter.ai/api/alpha/decisions";
    return base + "/systemone";
}

/** Model ID to send to the decisions API (strip provider prefixes on TypeSafe direct). */
function decisionsModel(profile) {
    profile = profile || {};
    var model = String(profile.modelName || "");
    if (hostOf(profile.endpoint) === "api.typesafe.ai")
        model = model.replace(/^~/, "").replace(/^typesafe\//i, "");
    return model;
}

function buildState(opts) {
    opts = opts || {};
    return {
        tool: "run_command",
        command: String(opts.command || ""),
        justification: String(opts.justification || "")
    };
}

function buildDecisionsRequest(opts) {
    return {
        model: decisionsModel(opts),
        state: buildState(opts),
        questions: {
            justification_mismatch: {
                type: "noul",
                instructions: DECISIONS_MISMATCH_INSTRUCTIONS,
                criteria: {
                    "true": "The command does more than the justification says, or something different from it.",
                    "false": "The command's effects are limited to what the justification describes."
                }
            },
            hidden_actions: {
                type: "noul",
                instructions: DECISIONS_HIDDEN_INSTRUCTIONS,
                criteria: {
                    "true": "There are hidden or misdescribed actions.",
                    "false": "There are no hidden or misdescribed actions."
                }
            },
            syntax_issues: {
                type: "noul",
                instructions: DECISIONS_SYNTAX_INSTRUCTIONS,
                criteria: {
                    "true": "There is an incomplete construct or syntax error.",
                    "false": "The command is complete and syntactically valid."
                }
            }
        }
    };
}

function buildChatMessages(opts) {
    var state = buildState(opts);
    return [
        {
            role: "system",
            content: "You are a command validator for an AI desktop assistant. " +
                "You receive a shell command and the justification the assistant gave for running it. " +
                "Decide only whether the command, exactly as written, performs what the justification states and nothing materially beyond it. " +
                "Commands that hide actions, escalate privileges, delete or overwrite data, exfiltrate data, or reach the network in ways the justification does not describe must be rejected even if they look harmless. " +
                "Commands that are not well-written shell — an incomplete construct such as an if without fi, a loop without done, or an unclosed quote, bracket, or parenthesis — must also be rejected. " +
                "Reply with JSON only: {\"match\": true|false, \"reason\": \"one short sentence\"}."
        },
        {
            role: "user",
            content: "Command:\n" + state.command + "\n\nJustification:\n" + state.justification
        }
    ];
}

/** Parses a chat model's verdict: {match, reason} or {error}. */
function parseChatVerdict(text) {
    if (!text) return { error: "empty validator response" };
    var cleaned = String(text).trim();

    var fence = cleaned.match(/```(?:json)?\s*([\s\S]*?)```/i);
    if (fence)
        cleaned = fence[1].trim();

    var parsed = null;
    try {
        parsed = JSON.parse(cleaned);
    } catch (e) {}

    if (!parsed) {
        var block = cleaned.match(/\{[\s\S]*\}/);
        if (block) {
            try {
                parsed = JSON.parse(block[0]);
            } catch (e2) {}
        }
    }

    if (!parsed) {
        var loose = cleaned.match(/"match"\s*:\s*(true|false)/i);
        if (loose)
            return { match: loose[1].toLowerCase() === "true", reason: "" };
        return { error: "could not parse validator response" };
    }

    if (typeof parsed.match !== "boolean")
        return { error: "validator response is missing a boolean match" };
    return { match: parsed.match, reason: String(parsed.reason || "").trim() };
}

/**
 * Evaluates a decisions API response: a command passes when the model's
 * mismatch, hidden-action, and syntax-error probabilities all stay below
 * `threshold`. Returns {match, confidence, mismatchProbability,
 * hiddenProbability, syntaxProbability, reason, model} or {error}.
 */
function evaluateDecisionsResponse(json, threshold, fallbackModel) {
    if (!json || !json.answers)
        return { error: "malformed decisions response" };
    var mismatch = json.answers.justification_mismatch;
    if (!mismatch || typeof mismatch.noul !== "number")
        return { error: "decisions response is missing justification_mismatch" };

    var t = (typeof threshold === "number" && !isNaN(threshold)) ? threshold : 0.5;
    var hidden = json.answers.hidden_actions;
    var hiddenProb = (hidden && typeof hidden.noul === "number") ? hidden.noul : 0;
    var syntax = json.answers.syntax_issues;
    var syntaxProb = (syntax && typeof syntax.noul === "number") ? syntax.noul : 0;
    var matched = mismatch.noul < t && hiddenProb < t && syntaxProb < t;

    var reason = "";
    if (!matched) {
        if (mismatch.noul >= t)
            reason = "the validator estimated a " + mismatch.noul.toFixed(2) + " probability that the command goes beyond its justification";
        if (hiddenProb >= t)
            reason += (reason.length > 0 ? ", and " : "the validator ") + "flagged hidden or misdescribed actions (" + hiddenProb.toFixed(2) + ")";
        if (syntaxProb >= t)
            reason += (reason.length > 0 ? ", and " : "the validator ") + "detected shell syntax problems (" + syntaxProb.toFixed(2) + ")";
    }
    return {
        match: matched,
        confidence: Math.round((1 - mismatch.noul) * 100) / 100,
        mismatchProbability: mismatch.noul,
        hiddenProbability: hiddenProb,
        syntaxProbability: syntaxProb,
        reason: reason,
        model: json.model || fallbackModel || ""
    };
}

/**
 * Default decisions transport: plain JSON POST with Bearer auth. Returns the
 * XMLHttpRequest so callers can abort an in-flight request; on failure the
 * callback receives (errorMessage, null).
 */
function postJson(url, apiKey, payload, callback) {
    try {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", url);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.setRequestHeader("Authorization", "Bearer " + (apiKey || ""));
        xhr.setRequestHeader("HTTP-Referer", "https://github.com/joshuaeroman/plasmallm");
        xhr.setRequestHeader("X-OpenRouter-Title", "PlasmaLLM");
        xhr.timeout = 20000;
        xhr.ontimeout = function() {
            callback("validator request timed out", null);
        };
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var json = null;
            try {
                json = JSON.parse(xhr.responseText);
            } catch (e) {}
            if (xhr.status < 200 || xhr.status >= 300) {
                callback(httpErrorMessage(json, xhr.status), null);
                return;
            }
            if (!json) {
                callback("invalid validator response", null);
                return;
            }
            callback(null, json);
        };
        xhr.send(JSON.stringify(payload));
        return xhr;
    } catch (e) {
        callback("validator request failed: " + e, null);
        return null;
    }
}

/**
 * Validates a command against its justification.
 *
 * @param {object} opts
 * @param {object} opts.profile - {endpoint, modelName, apiKey, backend}
 * @param {string} opts.command
 * @param {string} opts.justification
 * @param {number} [opts.threshold=0.5] - decisions confidence cutoff
 * @param {object} [opts.transport] - {chat(messages, cb), decisions(url, key, payload, cb)}
 * @param {function} callback - ({match, reason, confidence, model}) or ({error})
 */
function validate(opts, callback) {
    opts = opts || {};
    var profile = opts.profile || {};
    var backend = backendFor(profile);
    var threshold = (typeof opts.threshold === "number" && !isNaN(opts.threshold)) ? opts.threshold : 0.5;
    var done = false;

    function finish(result) {
        if (done) return;
        done = true;
        if (callback) callback(result);
    }

    if (!opts.command) {
        finish({ error: "no command to validate" });
        return;
    }

    var requestOpts = {
        command: opts.command,
        justification: opts.justification || "",
        endpoint: profile.endpoint,
        modelName: profile.modelName
    };

    try {
        if (backend === "decisions") {
            var decisionsFn = (opts.transport && typeof opts.transport.decisions === "function")
                ? opts.transport.decisions
                : postJson;
            decisionsFn(decisionsUrl(profile.endpoint), profile.apiKey || "", buildDecisionsRequest(requestOpts), function(err, json) {
                if (err) {
                    finish({ error: String(err) });
                    return;
                }
                finish(evaluateDecisionsResponse(json, threshold, decisionsModel(profile)));
            });
        } else {
            if (!opts.transport || typeof opts.transport.chat !== "function") {
                finish({ error: "chat validator transport unavailable" });
                return;
            }
            opts.transport.chat(buildChatMessages(requestOpts), function(err, text) {
                if (err) {
                    finish({ error: String(err) });
                    return;
                }
                var verdict = parseChatVerdict(text);
                if (verdict.error) {
                    finish({ error: verdict.error });
                    return;
                }
                verdict.model = profile.modelName || "";
                finish(verdict);
            });
        }
    } catch (e) {
        finish({ error: "validator invocation error: " + e });
    }
}
