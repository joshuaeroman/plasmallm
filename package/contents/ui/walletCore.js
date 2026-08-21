/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Pure wallet helpers (no QML / D-Bus). QML imports this via wallet.js / api.js.
// Node tests load it with vm.runInContext.

// Wallet *entry prefixes* are v1/ (2.6–2.7.0) then v2| (this refactor).
// apiKeySlotSchemeVersion is a migration watermark, not that prefix:
//   2 = copied onto v1/ names
//   3 = copied onto v2| names
function keySlotSchemeVersion() { return 3; }
var KEY_SLOT_SCHEME_VERSION = 3;

var WALLET_FOLDER = "PlasmaLLM";
var WALLET_APPID = "PlasmaLLM";
var WALLET_NAME = "kdewallet";
var GEMINI_PROVIDER = "Google Gemini";

var LEGACY_SEARCH_KEY_MAP = {
    "exaApiKey": "exa",
    "ollamaSearchApiKey": "ollama",
    "ollamaApiKey": "ollama",
    "searxngApiKey": "searxng"
};

function normalizeEndpoint(endpoint) {
    if (!endpoint) return "";
    return String(endpoint).replace(/\/+$/, "");
}

function enc(s) {
    return encodeURIComponent(String(s == null ? "" : s));
}

function dec(s) {
    try { return decodeURIComponent(String(s == null ? "" : s)); }
    catch (e) { return String(s == null ? "" : s); }
}

function unwrapDbusValue(val, depth) {
    if (depth === undefined) depth = 0;
    if (depth > 4 || val === null || val === undefined)
        return val;
    if (typeof val === "object") {
        if (Object.prototype.hasOwnProperty.call(val, "value"))
            return unwrapDbusValue(val.value, depth + 1);
        if (typeof val.length === "number" && val.length === 1 && typeof val !== "string")
            return unwrapDbusValue(val[0], depth + 1);
    }
    return val;
}

function coerceHandle(val) {
    var v = unwrapDbusValue(val);
    if (typeof v === "number")
        return v === v ? v : -1;
    var n = parseInt(v, 10);
    return n === n ? n : -1;
}

function isWriteSuccess(result) {
    var v = unwrapDbusValue(result);
    return v === 0 || v === "0";
}

function isTruthyFlag(val) {
    var v = unwrapDbusValue(val);
    return v === true || v === 1 || v === "1";
}

function passwordText(val) {
    var v = unwrapDbusValue(val);
    if (v === null || v === undefined)
        return "";
    return String(v).replace(/^\s+|\s+$/g, "");
}

function normalizeStringList(val) {
    var v = unwrapDbusValue(val);
    if (!v)
        return [];
    if (typeof v === "string")
        return [v];
    if (typeof v.length === "number") {
        var out = [];
        for (var i = 0; i < v.length; i++)
            out.push(String(unwrapDbusValue(v[i])));
        return out;
    }
    return [];
}

function parseFallbackMap(raw) {
    if (!raw || String(raw).length === 0)
        return {};
    try {
        var m = JSON.parse(raw);
        return (m && typeof m === "object" && !Array.isArray(m)) ? m : {};
    } catch (e) {
        return {};
    }
}

function lookupFallback(map, slots, cfgApiKey) {
    if (!map)
        map = {};
    slots = slots || [];
    for (var i = 0; i < slots.length; i++) {
        var s = slots[i];
        if (s && Object.prototype.hasOwnProperty.call(map, s) && map[s])
            return String(map[s]);
    }
    return cfgApiKey ? String(cfgApiKey) : "";
}

function putFallback(map, slot, key) {
    var next = {};
    var m = map || {};
    for (var k in m) {
        if (Object.prototype.hasOwnProperty.call(m, k))
            next[k] = m[k];
    }
    if (slot)
        next[slot] = key;
    return next;
}

// Copy-on-write delete so a successful KWallet write can scrub the
// plaintext fallback copy for that slot.
function removeFallback(map, slot) {
    var next = {};
    var m = map || {};
    for (var k in m) {
        if (Object.prototype.hasOwnProperty.call(m, k) && k !== slot)
            next[k] = m[k];
    }
    return next;
}

function stringifyFallbackMap(map) {
    try { return JSON.stringify(map || {}); }
    catch (e) { return "{}"; }
}

function uniqueSlots(list) {
    var seen = {};
    var out = [];
    for (var i = 0; i < (list || []).length; i++) {
        var s = list[i];
        if (!s || seen[s])
            continue;
        seen[s] = true;
        out.push(s);
    }
    return out;
}

function uniquePairs(pairs) {
    var seen = {};
    var out = [];
    for (var i = 0; i < (pairs || []).length; i++) {
        var p = pairs[i];
        if (!p || !p.from || !p.to || p.from === p.to)
            continue;
        var k = p.from + "\0" + p.to;
        if (seen[k])
            continue;
        seen[k] = true;
        out.push({ from: p.from, to: p.to });
    }
    return out;
}

function applyFallbackCopies(map, pairs) {
    var m = map || {};
    var changed = false;
    for (var i = 0; i < (pairs || []).length; i++) {
        var from = pairs[i].from;
        var to = pairs[i].to;
        if (!from || !to || from === to)
            continue;
        if (!m[from] || String(m[from]).length === 0)
            continue;
        if (m[to] && String(m[to]).length > 0)
            continue;
        m = putFallback(m, to, m[from]);
        changed = true;
    }
    return { map: m, changed: changed };
}

function slotApiType(apiType, geminiAuthMethod) {
    var t = apiType || "openai";
    if (t === "gemini_interactions")
        t = "gemini";
    if (t === "gemini" && geminiAuthMethod === "agentplatform")
        return "gemini_agentplatform";
    if (t === "gemini:agentplatform" || t === "gemini_agentplatform")
        return "gemini_agentplatform";
    return t;
}

function isGeminiSlotType(apiType, geminiAuthMethod) {
    var t = slotApiType(apiType, geminiAuthMethod);
    return t === "gemini" || t === "gemini_agentplatform";
}

// Express Mode (Agent Platform + API key) only supports generateContent, not Interactions.
function clampGeminiApiVariant(variant, geminiAuthMethod, vertexAuthType) {
    var authType = vertexAuthType || "apikey";
    if (geminiAuthMethod === "agentplatform" && authType === "apikey")
        return "legacy";
    return variant || "legacy";
}

function resolvedApiType(apiType, geminiApiVariant, geminiAuthMethod, vertexAuthType) {
    var t = apiType || "openai";
    var v = clampGeminiApiVariant(geminiApiVariant, geminiAuthMethod, vertexAuthType);
    if (t === "gemini" && v === "interactions")
        return "gemini_interactions";
    return t;
}

function siblingGeminiAuthMethod(geminiAuthMethod) {
    return geminiAuthMethod === "agentplatform" ? "aistudio" : "agentplatform";
}

// Historical v1/ last-segment: empty name → Custom+[url]. Used only when *reading* 2.7.0 names.
function slotProviderPartRaw(providerName, endpoint) {
    var p = (providerName && String(providerName).length > 0) ? String(providerName) : "Custom";
    if (p === "Custom")
        return "[" + normalizeEndpoint(endpoint) + "]";
    return p;
}

// v2 writes: Gemini is always "Google Gemini". Other adapters keep Custom+[url] for unnamed/custom.
function slotProviderPart(providerName, endpoint, apiType, geminiAuthMethod) {
    if (isGeminiSlotType(apiType, geminiAuthMethod))
        return GEMINI_PROVIDER;
    return slotProviderPartRaw(providerName, endpoint);
}

function profileToken(profileId) {
    return (profileId && String(profileId).length > 0) ? String(profileId) : "_";
}

function v1ChatKeySlot(profileId, apiType, providerName, endpoint, geminiAuthMethod) {
    return "v1/chat/" + profileToken(profileId) + "/"
        + slotApiType(apiType, geminiAuthMethod) + "/"
        + slotProviderPartRaw(providerName, endpoint);
}

function chatKeySlot(profileId, apiType, providerName, endpoint, geminiAuthMethod) {
    return "v2|chat|" + enc(profileToken(profileId)) + "|"
        + enc(slotApiType(apiType, geminiAuthMethod)) + "|"
        + enc(slotProviderPart(providerName, endpoint, apiType, geminiAuthMethod));
}

function currentKeySlot(activeProfileId, apiType, providerName, endpoint, geminiAuthMethod) {
    return chatKeySlot(activeProfileId, apiType, providerName, endpoint, geminiAuthMethod);
}

function v1SearchKeySlot(searchProvider) {
    return "v1/search/_/" + (searchProvider || "ollama");
}

function searchKeySlot(searchProvider) {
    return "v2|search|_|" + enc(searchProvider || "ollama");
}

function v1SttKeySlot(providerName, endpoint) {
    return "v1/stt/" + slotProviderPartRaw(providerName, endpoint);
}

function sttKeySlot(providerName, endpoint) {
    return "v2|stt|" + enc(slotProviderPartRaw(providerName, endpoint));
}

function searchLegacyKeySlots(searchProvider) {
    var p = searchProvider || "ollama";
    var out = [v1SearchKeySlot(p)];
    for (var k in LEGACY_SEARCH_KEY_MAP) {
        if (Object.prototype.hasOwnProperty.call(LEGACY_SEARCH_KEY_MAP, k) && LEGACY_SEARCH_KEY_MAP[k] === p)
            out.push(k);
    }
    return uniqueSlots(out);
}

function sttLegacyKeySlots(providerName, endpoint) {
    return uniqueSlots([v1SttKeySlot(providerName, endpoint)]);
}

function legacyProviderKeySlot(apiType, providerName, endpoint, geminiAuthMethod) {
    var t = apiType || "openai";
    if (t === "gemini_interactions")
        t = "gemini";
    if (t === "gemini" && geminiAuthMethod === "agentplatform")
        t = "gemini:agentplatform";
    var p = (providerName && String(providerName).length > 0) ? providerName : "Custom";
    if (isGeminiSlotType(apiType, geminiAuthMethod) && (!providerName || p === "Custom"))
        p = GEMINI_PROVIDER;
    if (p === "Custom" && endpoint && String(endpoint).length > 0)
        p = "Custom:" + normalizeEndpoint(endpoint);
    return "apiKey:" + t + ":" + p;
}

function legacyProfileKeySlot(profileId) {
    return "apiKey:profile:" + profileId;
}

function pushGeminiV1Accidents(out, profileId, apiType, endpoint, geminiAuthMethod) {
    var urls = [
        normalizeEndpoint(endpoint),
        "https://generativelanguage.googleapis.com",
        "https://aiplatform.googleapis.com"
    ];
    out.push(v1ChatKeySlot(profileId, apiType, GEMINI_PROVIDER, endpoint, geminiAuthMethod));
    for (var i = 0; i < urls.length; i++) {
        if (!urls[i])
            continue;
        out.push(v1ChatKeySlot(profileId, apiType, "", urls[i], geminiAuthMethod));
        out.push(v1ChatKeySlot(profileId, apiType, "Custom", urls[i], geminiAuthMethod));
        out.push(legacyProviderKeySlot(apiType, "Custom", urls[i], geminiAuthMethod));
    }
    out.push(legacyProviderKeySlot(apiType, GEMINI_PROVIDER, endpoint, geminiAuthMethod));
}

function legacyKeySlots(activeProfileId, apiType, providerName, endpoint, geminiAuthMethod) {
    var out = [];
    out.push(v1ChatKeySlot(activeProfileId, apiType, providerName, endpoint, geminiAuthMethod));
    if (isGeminiSlotType(apiType, geminiAuthMethod)) {
        pushGeminiV1Accidents(out, activeProfileId, apiType, endpoint, geminiAuthMethod);
        var sib = siblingGeminiAuthMethod(geminiAuthMethod);
        out.push(chatKeySlot(activeProfileId, apiType, providerName, endpoint, sib));
        pushGeminiV1Accidents(out, activeProfileId, apiType, endpoint, sib);
        out.push(legacyProviderKeySlot(apiType, providerName, endpoint, sib));
    }
    out.push(legacyProviderKeySlot(apiType, providerName, endpoint, geminiAuthMethod));
    if (activeProfileId && String(activeProfileId).length > 0)
        out.push(legacyProfileKeySlot(activeProfileId));
    out.push("apiKey");
    return uniqueSlots(out);
}

function apiKeySlot(apiType, providerName) {
    return legacyProviderKeySlot(apiType, providerName, "", null);
}

function profileKeySlot(profileId) {
    return legacyProfileKeySlot(profileId);
}

function providerKeySlot(apiType, providerName, endpoint, geminiAuthMethod) {
    return legacyProviderKeySlot(apiType, providerName, endpoint, geminiAuthMethod);
}

function compositeKeySlot(profileId, apiType, providerPart) {
    var providerName = providerPart;
    var endpoint = "";
    if (providerPart && providerPart.indexOf("Custom:") === 0) {
        providerName = "Custom";
        endpoint = providerPart.substring(7);
    }
    var geminiAuth = null;
    var t = apiType || "openai";
    if (t === "gemini:agentplatform") {
        t = "gemini";
        geminiAuth = "agentplatform";
    }
    return chatKeySlot(profileId, t, providerName, endpoint, geminiAuth);
}

function isLegacyProfileOnlySlot(name) {
    return /^apiKey:profile:[^:]+$/.test(name || "");
}

function isProviderOnlyChatSlot(name) {
    if (!name || name.indexOf("apiKey:") !== 0) return false;
    if (name === "apiKey") return false;
    if (name.indexOf("apiKey:profile:") === 0) return false;
    return name.substring(7).indexOf(":") !== -1;
}

function parseProviderOnlySlot(name) {
    if (!isProviderOnlyChatSlot(name)) return null;
    var rest = name.substring(7);
    if (rest.indexOf("gemini:agentplatform:") === 0) {
        return {
            apiType: "gemini",
            geminiAuthMethod: "agentplatform",
            providerName: rest.substring("gemini:agentplatform:".length),
            endpoint: ""
        };
    }
    var colon = rest.indexOf(":");
    if (colon < 0) return null;
    var type = rest.substring(0, colon);
    var prov = rest.substring(colon + 1);
    var endpoint = "";
    var providerName = prov;
    if (prov.indexOf("Custom:") === 0) {
        providerName = "Custom";
        endpoint = prov.substring(7);
    }
    return {
        apiType: type,
        geminiAuthMethod: null,
        providerName: providerName,
        endpoint: endpoint
    };
}

function parseLegacyProfileOnlySlot(name) {
    if (!isLegacyProfileOnlySlot(name)) return null;
    return name.substring("apiKey:profile:".length);
}

function parseV1ChatSlot(name) {
    var prefix = "v1/chat/";
    if (!name || name.indexOf(prefix) !== 0) return null;
    var rest = name.substring(prefix.length);
    var i1 = rest.indexOf("/");
    if (i1 < 0) return null;
    var pid = rest.substring(0, i1);
    var rest2 = rest.substring(i1 + 1);
    var i2 = rest2.indexOf("/");
    if (i2 < 0) return null;
    var type = rest2.substring(0, i2);
    var prov = rest2.substring(i2 + 1);
    var geminiAuth = null;
    var apiType = type;
    if (type === "gemini_agentplatform") {
        apiType = "gemini";
        geminiAuth = "agentplatform";
    }
    var providerName = prov;
    var endpoint = "";
    if (prov && prov.charAt(0) === "[") {
        providerName = "Custom";
        if (prov.charAt(prov.length - 1) === "]")
            endpoint = prov.substring(1, prov.length - 1);
        else
            endpoint = prov.substring(1);
    }
    return {
        profileId: pid,
        apiType: apiType,
        providerName: providerName,
        endpoint: endpoint,
        geminiAuthMethod: geminiAuth
    };
}

function modelCacheSlot(apiType, providerName, endpoint, activeProfileId, geminiAuthMethod) {
    var type = slotApiType(apiType, geminiAuthMethod);
    var prov = slotProviderPart(providerName, endpoint, apiType, geminiAuthMethod);
    var base = "models:" + type + ":" + prov;
    if (activeProfileId && String(activeProfileId).length > 0)
        return "models:" + activeProfileId + ":" + type + ":" + prov;
    return base;
}

function addPair(pairs, from, to) {
    pairs.push({ from: from, to: to });
}

function buildMigrationCopies(opts) {
    opts = opts || {};
    var profiles = opts.profiles || [];
    var entries = opts.entries || [];
    var pairs = [];
    var i, j, p, legs, to;

    for (i = 0; i < profiles.length; i++) {
        p = profiles[i];
        to = currentKeySlot(p.id, p.apiType, p.providerName, p.apiEndpoint, p.geminiAuthMethod);
        legs = legacyKeySlots(p.id, p.apiType, p.providerName, p.apiEndpoint, p.geminiAuthMethod);
        for (j = 0; j < legs.length; j++)
            addPair(pairs, legs[j], to);
    }

    for (i = 0; i < entries.length; i++) {
        var name = entries[i];
        var parsedProv = parseProviderOnlySlot(name);
        if (parsedProv) {
            for (j = 0; j < profiles.length; j++) {
                addPair(pairs, name, currentKeySlot(
                    profiles[j].id, parsedProv.apiType, parsedProv.providerName,
                    parsedProv.endpoint, parsedProv.geminiAuthMethod));
            }
        }
        if (LEGACY_SEARCH_KEY_MAP[name])
            addPair(pairs, name, searchKeySlot(LEGACY_SEARCH_KEY_MAP[name]));
        if (name && name.indexOf("v1/search/_/") === 0)
            addPair(pairs, name, searchKeySlot(name.substring("v1/search/_/".length)));
        var parsedV1 = parseV1ChatSlot(name);
        if (parsedV1) {
            addPair(pairs, name, currentKeySlot(
                parsedV1.profileId, parsedV1.apiType, parsedV1.providerName,
                parsedV1.endpoint, parsedV1.geminiAuthMethod));
        }
        if (name && name.indexOf("v1/stt/") === 0) {
            var sttPart = name.substring("v1/stt/".length);
            var sttName = sttPart;
            var sttEp = "";
            if (sttPart && sttPart.charAt(0) === "[") {
                sttName = "Custom";
                sttEp = sttPart.charAt(sttPart.length - 1) === "]"
                    ? sttPart.substring(1, sttPart.length - 1)
                    : sttPart.substring(1);
            }
            addPair(pairs, name, sttKeySlot(sttName, sttEp));
        }
    }

    var searchProviders = ["ollama", "exa", "searxng"];
    for (i = 0; i < searchProviders.length; i++) {
        var sp = searchProviders[i];
        var searchTo = searchKeySlot(sp);
        var slegs = searchLegacyKeySlots(sp);
        for (j = 0; j < slegs.length; j++)
            addPair(pairs, slegs[j], searchTo);
    }

    if (opts.sttProviderName || opts.sttApiEndpoint) {
        addPair(pairs,
            v1SttKeySlot(opts.sttProviderName, opts.sttApiEndpoint),
            sttKeySlot(opts.sttProviderName, opts.sttApiEndpoint));
    }

    if (profiles.length > 0) {
        var act = null;
        for (i = 0; i < profiles.length; i++) {
            if (profiles[i].id === opts.activeProfileId) {
                act = profiles[i];
                break;
            }
        }
        if (!act)
            act = profiles[0];
        addPair(pairs, "apiKey", currentKeySlot(
            act.id, act.apiType, act.providerName, act.apiEndpoint, act.geminiAuthMethod));
    }

    return uniquePairs(pairs);
}
