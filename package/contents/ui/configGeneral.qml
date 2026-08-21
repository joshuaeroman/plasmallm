/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.plasma5support as P5Support

import "api.js" as Api
import "wallet.js" as Wallet
import "walletCore.js" as WalletCore
import "profiles.js" as Profiles

BaseConfigPage {
    id: configPage

    property var profilesList: []

    onCfg_profilesChanged: {
        profilesList = Profiles.loadProfilesRaw(cfg_profiles);
    }

    property bool hasGcloud: false
    property string gcloudToken: ""
    property bool tokenFetchInProgress: false
    property var pendingModelsFetch: null

    P5Support.DataSource {
        id: gcloudChecker
        engine: "executable"
        connectedSources: ["command -v gcloud"]
        onNewData: function(source, data) {
            hasGcloud = (data["exit code"] === 0);
            disconnectSource(source);
        }
    }

    P5Support.DataSource {
        id: gcloudTokenSource
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var token = data["stdout"] ? data["stdout"].trim() : "";
            var exitCode = data["exit code"];
            tokenFetchInProgress = false;
            disconnectSource(source);
            if (exitCode === 0 && token.length > 0) {
                gcloudToken = token;
                if (pendingModelsFetch) {
                    var cb = pendingModelsFetch;
                    pendingModelsFetch = null;
                    cb(token);
                }
            } else {
                fetchInProgress = false;
                fetchStatusLabel.text = i18n("Failed to fetch gcloud token (exit %1): %2", exitCode, data["stderr"] || "");
                fetchStatusLabel.visible = true;
                pendingModelsFetch = null;
            }
        }
    }

    P5Support.DataSource {
        id: openFolderSource
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source);
        }
    }

    property var modelCache: ({})
    property var availableModels: []
    property bool fetchInProgress: false
    property string walletApiKey: ""
    property bool walletKeyLoaded: false
    property bool walletAvailable: false
    property bool walletKeyDirty: false
    property bool walletSaveInProgress: false
    // Slot that the currently displayed key belongs to. Used to flush dirty
    // (typed-but-unsaved) keys when the active slot changes.
    property string lastKeySlot: ""
    // Set when adapter/provider selection intentionally clears modelName so the
    // next model-list settle may pick a default. Opening settings must never
    // treat an empty/missing name as license to overwrite a saved selection.
    property bool _allowModelAutoSelect: false

    function currentSlot() {
        return Api.currentKeySlot(cfg_activeProfileId, cfg_apiType, cfg_providerName,
                                  cfg_apiEndpoint, cfg_geminiAuthMethod);
    }

    // Model cache slot always includes adapter+provider so each adapter's
    // model list is stored separately, even when a profile is active.
    function currentModelCacheSlot() {
        return Api.modelCacheSlot(cfg_apiType, cfg_providerName, cfg_apiEndpoint,
                                  cfg_activeProfileId, cfg_geminiAuthMethod);
    }

    function legacyProviderSlot() {
        return Api.providerKeySlot(cfg_apiType, cfg_providerName, cfg_apiEndpoint,
                                   cfg_geminiAuthMethod);
    }

    function readFallbackMap() {
        if (!cfg_apiKeysFallback || cfg_apiKeysFallback.length === 0) return {};
        try { return JSON.parse(cfg_apiKeysFallback) || {}; } catch(e) { return {}; }
    }

    function fallbackKeyFor(slot) {
        var m = readFallbackMap();
        if (m.hasOwnProperty(slot)) return m[slot];

        // Walk legacy identity slots (profile-only, then provider-only).
        var legacies = Api.legacyKeySlots(cfg_activeProfileId, cfg_apiType, cfg_providerName,
                                          cfg_apiEndpoint, cfg_geminiAuthMethod);
        for (var i = 0; i < legacies.length; i++) {
            if (legacies[i] === slot) continue;
            if (m.hasOwnProperty(legacies[i]) && m[legacies[i]])
                return m[legacies[i]];
        }

        return cfg_apiKey || "";
    }

    function writeFallbackKey(slot, key) {
        cfg_apiKeysFallback = WalletCore.stringifyFallbackMap(
            WalletCore.putFallback(readFallbackMap(), slot, key));
    }

    function removeFallbackKey(slot) {
        cfg_apiKeysFallback = WalletCore.stringifyFallbackMap(
            WalletCore.removeFallback(readFallbackMap(), slot));
    }

    // Persist an unsaved key to a specific slot (used when the active slot is
    // about to change so typed-but-not-saved keys are not discarded).
    function flushDirtyKeyToSlot(slot) {
        if (!walletKeyDirty || !apiKeyField) return;
        var key = apiKeyField.text.replace(/^\s+|\s+$/g, "");
        walletApiKey = key;
        walletKeyDirty = false;
        // Fire-and-forget; the next load targets a different slot.
        // The plaintext config copy is written only when KWallet could not
        // store the key, and scrubbed when it could.
        Wallet.writeKey(DBus, slot, key, function(res) {
            if (res && res.available) {
                walletAvailable = true;
                if (res.success) {
                    removeFallbackKey(slot);
                    cfg_apiKeyVersion++;
                    return;
                }
            }
            writeFallbackKey(slot, key);
        });
    }

    // loadWalletKey(copyKey, gen, onReady)
    // gen: config generation; stale callbacks no-op when gen !== _configGen
    // onReady: optional callback after key is applied for this gen
    function loadWalletKey(copyKey, gen, onReady) {
        var myGen = (gen !== undefined && gen !== null) ? gen : _configGen;
        var slot = currentSlot();
        var isCopy = copyKey !== undefined && copyKey !== null && copyKey !== "";

        function done() {
            if (myGen !== _configGen) return;
            if (typeof onReady === "function") onReady();
        }

        // If the user typed a key without saving:
        //  - different slot → flush to the previous slot, then load the new one
        //  - same slot (e.g. re-reconcile without identity change) → keep the
        //    typed value in the field; do not clobber it with a wallet re-read
        if (!isCopy && walletKeyDirty && lastKeySlot.length > 0) {
            if (lastKeySlot === slot) {
                walletKeyLoaded = true;
                done();
                return;
            }
            flushDirtyKeyToSlot(lastKeySlot);
        }

        lastKeySlot = slot;
        walletKeyLoaded = false;
        function isCurrent() {
            return myGen === _configGen && slot === currentSlot();
        }
        function applyKey(key) {
            if (!isCurrent()) return;
            walletApiKey = key || "";
            walletKeyLoaded = true;
            if (apiKeyField) apiKeyField.text = walletApiKey;
            walletKeyDirty = false;
            lastKeySlot = slot;
            done();
        }

        if (isCopy) {
            if (apiKeyField) apiKeyField.text = copyKey;
            walletKeyDirty = true;
            saveWalletKey(); // writes to the new slot and sets walletApiKey
            // saveWalletKey is async; mark loaded so models can proceed with the
            // typed key immediately.
            walletApiKey = String(copyKey).replace(/^\s+|\s+$/g, "");
            walletKeyLoaded = true;
            lastKeySlot = slot;
            done();
            return;
        }

        Wallet.readKey(DBus, slot,
            Api.legacyKeySlots(cfg_activeProfileId, cfg_apiType, cfg_providerName,
                cfg_apiEndpoint, cfg_geminiAuthMethod),
            readFallbackMap(), cfg_apiKey,
            function(res) {
                if (!isCurrent()) return;
                walletAvailable = !!(res && res.available);
                applyKey(res ? res.key : fallbackKeyFor(slot));
            }
        );
    }

    function saveWalletKey() {
        var key = apiKeyField.text.replace(/^\s+|\s+$/g, "");
        var slot = currentSlot();
        lastKeySlot = slot;
        walletApiKey = key;
        walletKeyDirty = false;
        walletSaveInProgress = true;
        Wallet.writeKey(DBus, slot, key, function(res) {
            if (res && res.available)
                walletAvailable = true;
            if (res && res.success) {
                // Scrub any stale plaintext copy now that KWallet holds the key.
                removeFallbackKey(slot);
                cfg_apiKeyVersion++;
            } else {
                // Plaintext fallback only when KWallet could not store the key.
                writeFallbackKey(slot, key);
            }
            walletSaveInProgress = false;
            ensureModelsLoaded(false);
        });
    }

    // Resolve a model list for the current identity, accepting legacy cache keys
    // written by older slot schemes so opening settings does not look "empty"
    // and re-fetch/race the combo onto index 0.
    function modelListForCurrentSlot() {
        var slot = currentModelCacheSlot();
        var list = modelCache[slot];
        if (Array.isArray(list) && list.length > 0)
            return list;

        // Intermediate scheme: models:<profile>:apiKey:<type>:<provider>
        var t = cfg_apiType || "openai";
        if (t === "gemini" && cfg_geminiAuthMethod === "agentplatform")
            t = "gemini:agentplatform";
        var p = cfg_providerName || "Custom";
        if (p === "Custom" && cfg_apiEndpoint)
            p = "Custom:" + String(cfg_apiEndpoint).replace(/\/+$/, "");
        var legacyBase = "apiKey:" + t + ":" + p;
        var candidates = [];
        if (cfg_activeProfileId && cfg_activeProfileId.length > 0) {
            candidates.push("models:" + cfg_activeProfileId + ":" + legacyBase);
            candidates.push(legacyBase);
            candidates.push("apiKey:profile:" + cfg_activeProfileId);
        } else {
            candidates.push(legacyBase);
        }
        for (var i = 0; i < candidates.length; i++) {
            var legacy = modelCache[candidates[i]];
            if (Array.isArray(legacy) && legacy.length > 0) {
                // Promote into the current slot so later reads are stable.
                var next = {};
                for (var k in modelCache) {
                    if (modelCache.hasOwnProperty(k))
                        next[k] = modelCache[k];
                }
                next[slot] = legacy;
                modelCache = next;
                // Persist promotion so the next settings open hits the new key.
                try {
                    cfg_availableModels = JSON.stringify(next);
                } catch (e) {}
                return legacy;
            }
        }
        return Array.isArray(list) ? list : [];
    }

    function refreshAvailableModels() {
        availableModels = modelListForCurrentSlot();
        syncModelComboIndex();
    }

    // Keep the model combo on the persisted selection. ComboBox resets
    // currentIndex to 0 when its model is replaced; defer so we win that race.
    function syncModelComboIndex() {
        if (modelPicker)
            modelPicker.syncIndex();
    }

    function loadModelCache() {
        var parsed = {};
        if (cfg_availableModels && cfg_availableModels.length > 0) {
            try {
                var v = JSON.parse(cfg_availableModels);
                // Discard the legacy flat-array shape; keep only the new map shape.
                if (v && typeof v === "object" && !Array.isArray(v)) parsed = v;
            } catch(e) {}
        }
        modelCache = parsed;
        refreshAvailableModels();
    }

    function ensureModelsLoaded(force, gen) {
        var myGen = (gen !== undefined && gen !== null) ? gen : _configGen;
        var slot = currentModelCacheSlot();
        var have = Array.isArray(modelCache[slot]) && modelCache[slot].length > 0;
        // Legacy cache keys still count as a hit after promotion.
        if (!have) {
            var promoted = modelListForCurrentSlot();
            have = Array.isArray(promoted) && promoted.length > 0;
        }
        if (!force && have) {
            // Cache hit: still restore combo selection (open settings path).
            syncModelComboIndex();
            // Only after an intentional provider/adapter clear may we default.
            if (_allowModelAutoSelect
                    && (!cfg_modelName || cfg_modelName.length === 0)
                    && !inConfigTxn && _initialized) {
                var cached = modelListForCurrentSlot();
                if (cached.length > 0) {
                    cfg_modelName = cached[0];
                    _allowModelAutoSelect = false;
                    rootItem.triggerCapture();
                    syncModelComboIndex();
                }
            }
            return;
        }
        if (fetchInProgress) return;
        // Wallet load is async; reconcile only calls us after key is ready.
        if (!walletKeyLoaded) return;
        var key = walletApiKey;
        // Skip automatic fetches when no key is set — some endpoints (e.g. local
        // LM Studio) don't need one, but we shouldn't hammer remote providers
        // with guaranteed-401 requests. The manual refresh button bypasses this.
        // Exception: Exa exposes a static model list that does not require a key.
        var endpointText = apiEndpointField ? apiEndpointField.text : (cfg_apiEndpoint || "");
        var isExaStatic = (cfg_apiType === "exa") || (function(ep) {
            if (!ep) return false;
            var m = String(ep).match(/^https?:\/\/([^\/:?#]+)/i);
            if (!m) return false;
            var host = m[1].toLowerCase();
            return host === "api.exa.ai" || host === "exa.ai" || (host.length > 7 && host.slice(-7) === ".exa.ai");
        })(endpointText);
        if (!force && (!key || key.length === 0) && !isExaStatic) return;
        fetchInProgress = true;
        fetchStatusLabel.visible = false;

        var opts = {
            geminiApiVariant: cfg_geminiApiVariant,
            geminiAuthMethod: cfg_geminiAuthMethod,
            geminiVertexAuthType: cfg_geminiVertexAuthType,
            geminiProjectId: cfg_geminiProjectId,
            geminiLocation: cfg_geminiLocation
        };
        var endpointForFetch = endpointText;

        var fetchAction = function(effectiveKey) {
            Api.fetchModels(effectiveApiType, endpointForFetch, effectiveKey, cfg_usesResponsesAPI, opts, function(error, models, status) {
                fetchInProgress = false;
                // Stale gen: a newer reconcile wanted models while we were in
                // flight and bailed on fetchInProgress — re-arm for latest.
                if (myGen !== _configGen) {
                    ensureModelsLoaded(false, _configGen);
                    return;
                }
                if (error) {
                    if (status && status >= 400) {
                        fetchStatusLabel.text = error;
                        fetchStatusLabel.visible = true;
                    } else {
                        fetchStatusLabel.visible = false;
                    }
                } else if (!models || models.length === 0) {
                    fetchStatusLabel.visible = false;
                } else {
                    fetchStatusLabel.visible = false;
                    var next = {};
                    for (var k in modelCache) if (modelCache.hasOwnProperty(k)) next[k] = modelCache[k];
                    next[slot] = models;
                    modelCache = next;
                    cfg_availableModels = JSON.stringify(next);
                    refreshAvailableModels();
                    // Auto-select first model only after intentional clear
                    // (provider/adapter switch), never when merely opening settings.
                    if (_allowModelAutoSelect
                            && (!cfg_modelName || cfg_modelName.length === 0)
                            && models.length > 0
                            && !inConfigTxn && _initialized) {
                        cfg_modelName = models[0];
                        _allowModelAutoSelect = false;
                        rootItem.triggerCapture();
                    }
                    syncModelComboIndex();
                }
            });
        };

        if (cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform" && cfg_geminiVertexAuthType === "gcloud") {
            pendingModelsFetch = fetchAction;
            gcloudTokenSource.connectSource("gcloud auth print-access-token");
        } else {
            fetchAction(key);
        }
    }

    onCfg_availableModelsChanged: loadModelCache()

    Component.onCompleted: {
        profilesList = Profiles.loadProfilesRaw(cfg_profiles);
        loadModelCache();
        // Initial reconcile: load key then models then capture.
        _configGen++;
        reconcileConfig({}, _configGen);
    }

    // OpenAI-compatible presets only (Anthropic/Gemini each have a single fixed
    // endpoint, so they don't need a preset dropdown). The "Custom" sentinel at
    // index 0 lets users pick a non-preset endpoint without a separate toggle.
    readonly property var presetEndpoints: {
        var raw = Api.getPresets(effectiveApiType) || [];
        var list = [];
        var hasCustom = false;
        for (var i = 0; i < raw.length; i++) {
            if (raw[i].url === "") { hasCustom = true; }
            list.push({ name: raw[i].name, url: raw[i].url, usesResponsesAPI: !!raw[i].usesResponsesAPI });
        }
        if (!hasCustom) list.unshift({ name: "Custom", url: "", usesResponsesAPI: false });
        return list;
    }

    readonly property var adapterChoices: Api.getAdapterChoices()
    readonly property string effectiveApiType: Api.resolvedApiType(cfg_apiType, cfg_geminiApiVariant, cfg_geminiAuthMethod, cfg_geminiVertexAuthType)
    readonly property var caps: Api.getCapabilities(effectiveApiType) || {}
    // Dedicated Exa adapter, or OpenAI-compatible preset/endpoint pointed at Exa.
    readonly property bool usingExaChat: {
        if (cfg_apiType === "exa")
            return true;
        if (cfg_apiType !== "openai")
            return false;
        if ((cfg_providerName || "") === "Exa")
            return true;
        var ep = cfg_apiEndpoint || "";
        var m = String(ep).match(/^https?:\/\/([^\/:?#]+)/i);
        if (!m)
            return false;
        var host = m[1].toLowerCase();
        return host === "api.exa.ai" || host === "exa.ai" || (host.length > 7 && host.slice(-7) === ".exa.ai");
    }

    // Out-of-band cfg changes (KCM reload, other pages): coalesce into one reconcile.
    // Intentional multi-field paths use begin/endConfigTxn and skip these.
    onCfg_apiTypeChanged: { if (!inConfigTxn && _initialized) scheduleFallbackReconcile(); }
    onCfg_geminiApiVariantChanged: { if (!inConfigTxn && _initialized) scheduleFallbackReconcile(); }
    onCfg_geminiAuthMethodChanged: { if (!inConfigTxn && _initialized) scheduleFallbackReconcile(); }
    onCfg_geminiVertexAuthTypeChanged: { if (!inConfigTxn && _initialized) scheduleFallbackReconcile(); }
    onCfg_providerNameChanged: { if (!inConfigTxn && _initialized) scheduleFallbackReconcile(); }

    // Single post-txn pipeline: UI sync → wallet → models → capture.
    function reconcileConfig(opts, gen) {
        opts = opts || {};
        var myGen = (gen !== undefined && gen !== null) ? gen : _configGen;
        if (myGen !== _configGen) return;

        if (cfg_apiType === "gemini" && cfg_providerName !== "Google Gemini") {
            cfg_providerName = "Google Gemini";
            opts.needsCapture = true;
        }

        // Express Mode (Agent Platform + API key) cannot use Interactions.
        if (cfg_apiType === "gemini") {
            var clampedVariant = Api.clampGeminiApiVariant(
                cfg_geminiApiVariant, cfg_geminiAuthMethod, cfg_geminiVertexAuthType);
            if (clampedVariant !== cfg_geminiApiVariant) {
                cfg_geminiApiVariant = clampedVariant;
                opts.needsCapture = true;
            }
        }

        syncModelParamControls();

        // Flush dirty key to the previous slot when identity changed.
        if (opts.prevKeySlot && opts.prevKeySlot.length > 0
                && opts.prevKeySlot !== currentSlot() && walletKeyDirty) {
            flushDirtyKeyToSlot(opts.prevKeySlot);
        }

        loadWalletKey(opts.copyKey, myGen, function() {
            if (myGen !== _configGen) return;
            refreshAvailableModels();
            ensureModelsLoaded(!!opts.forceModels, myGen);
            if (opts.needsCapture) {
                rootItem.triggerCapture();
            }
        });
    }

    // Sync the Provider combo currentIndex from cfg_providerName / cfg_apiEndpoint.
    function syncEndpointPresetIndex() {
        if (!endpointPreset || !presetEndpoints) return;
        var i;
        if (cfg_providerName && cfg_providerName.length > 0) {
            for (i = 0; i < presetEndpoints.length; i++) {
                if (presetEndpoints[i].name === cfg_providerName) {
                    endpointPreset.currentIndex = i;
                    return;
                }
            }
        }
        if (cfg_apiEndpoint && cfg_apiEndpoint.length > 0) {
            for (i = 1; i < presetEndpoints.length; i++) {
                if (presetEndpoints[i].url === cfg_apiEndpoint) {
                    endpointPreset.currentIndex = i;
                    return;
                }
            }
        }
        endpointPreset.currentIndex = 0;
    }

    // Push cfg_* model-parameter values back into controls whose QML bindings
    // may have been broken by prior user interaction.
    function syncModelParamControls() {
        if (adapterCombo && adapterChoices) {
            for (var ai = 0; ai < adapterChoices.length; ai++) {
                if (adapterChoices[ai].id === cfg_apiType) {
                    adapterCombo.currentIndex = ai;
                    break;
                }
            }
        }
        if (temperatureSlider) temperatureSlider.value = cfg_temperature;
        if (maxTokensSpinBox) maxTokensSpinBox.value = cfg_maxTokens;
        if (thinkingBudgetSpinBox) thinkingBudgetSpinBox.value = cfg_thinkingBudget;
        if (reasoningEffortCombo) {
            var efforts = reasoningEffortCombo.efforts || ["off", "low", "medium", "high"];
            reasoningEffortCombo.currentIndex = Math.max(0, efforts.indexOf(cfg_reasoningEffort));
        }
        if (usesResponsesAPICheckBox) usesResponsesAPICheckBox.checked = cfg_usesResponsesAPI;
        if (showThoughtsCheckBox) showThoughtsCheckBox.checked = cfg_showThoughts;
        if (apiEndpointField) apiEndpointField.text = cfg_apiEndpoint;
        syncEndpointPresetIndex();
        syncModelComboIndex();
    }

    // Pure writes for adapter defaults — no wallet/models/capture (caller is in a txn).
    function writeAdapterDefaults(apiType) {
        var presets = Api.getPresets(apiType) || [];
        var pick = null;
        var baseApiType = (apiType === "gemini" || apiType === "gemini_interactions") ? "gemini" : apiType;

        if (baseApiType === "openai" && cfg_openaiLastProvider && cfg_openaiLastProvider.length > 0) {
            for (var j = 0; j < presets.length; j++) {
                if (presets[j].name === cfg_openaiLastProvider) {
                    pick = presets[j];
                    break;
                }
            }
            if (pick && (!pick.url || pick.url.length === 0) && cfg_openaiLastEndpoint && cfg_openaiLastEndpoint.length > 0) {
                cfg_apiEndpoint = cfg_openaiLastEndpoint;
                cfg_providerName = pick.name;
                cfg_modelName = "";
                _allowModelAutoSelect = true;
                if (apiEndpointField) apiEndpointField.text = cfg_apiEndpoint;
                syncEndpointPresetIndex();
                return;
            }
        }
        if (!pick) {
            for (var i = 0; i < presets.length; i++) {
                if (presets[i].url && presets[i].url.length > 0) {
                    pick = presets[i];
                    break;
                }
            }
        }
        if (pick) {
            if (pick.url && pick.url.length > 0)
                cfg_apiEndpoint = pick.url;
            cfg_providerName = pick.name;
            cfg_usesResponsesAPI = !!pick.usesResponsesAPI;
            if (apiEndpointField) apiEndpointField.text = cfg_apiEndpoint;
        }
        if (baseApiType === "gemini")
            cfg_providerName = "Google Gemini";
        if (apiType === "exa") {
            cfg_modelName = "exa";
            _allowModelAutoSelect = false;
            if (!cfg_apiEndpoint || cfg_apiEndpoint.length === 0)
                cfg_apiEndpoint = "https://api.exa.ai";
            if (apiEndpointField) apiEndpointField.text = cfg_apiEndpoint;
            var exaSlot = currentModelCacheSlot();
            var nextCache = {};
            for (var ck in modelCache) {
                if (modelCache.hasOwnProperty(ck)) nextCache[ck] = modelCache[ck];
            }
            nextCache[exaSlot] = ["exa"];
            modelCache = nextCache;
            cfg_availableModels = JSON.stringify(nextCache);
        } else {
            cfg_modelName = "";
            _allowModelAutoSelect = true;
        }
        syncEndpointPresetIndex();
        if (apiType === "openai") {
            if (cfg_providerName && cfg_providerName.length > 0)
                cfg_openaiLastProvider = cfg_providerName;
            if (cfg_apiEndpoint && cfg_apiEndpoint.length > 0)
                cfg_openaiLastEndpoint = cfg_apiEndpoint;
        }
    }

    function applyAdapterSelection(apiType) {
        if (apiType === cfg_apiType && !inConfigTxn) {
            // Same adapter re-selected: still refresh models/key once.
            _configGen++;
            reconcileConfig({}, _configGen);
            return;
        }
        var prevSlot = currentSlot();
        beginConfigTxn();
        cfg_apiType = apiType;
        writeAdapterDefaults(apiType);
        endConfigTxn({ prevKeySlot: prevSlot });
    }

    function applyProviderSelection(preset) {
        var idx = -1;
        for (var i = 0; i < presetEndpoints.length; i++) {
            if (presetEndpoints[i].name === preset.name) {
                idx = i;
                break;
            }
        }
        if (idx === -1) return;

        var newProviderName = (idx > 0) ? presetEndpoints[idx].name : "Custom";
        var providerChanged = (cfg_providerName || "") !== (newProviderName || "");
        // Re-selecting the already-active provider must not wipe the saved model
        // (settings open / combo index churn can re-fire selection).
        if (!providerChanged && idx > 0) {
            if (endpointPreset) endpointPreset.currentIndex = idx;
            return;
        }

        var prevSlot = currentSlot();
        beginConfigTxn();
        if (endpointPreset) endpointPreset.currentIndex = idx;
        if (idx > 0) {
            var p = presetEndpoints[idx];
            if (p.url && p.url.length > 0)
                cfg_apiEndpoint = p.url;
            cfg_providerName = p.name;
            cfg_usesResponsesAPI = !!p.usesResponsesAPI;
            if (providerChanged && cfg_apiType !== "exa") {
                cfg_modelName = "";
                _allowModelAutoSelect = true;
            }
            if (apiEndpointField)
                apiEndpointField.text = (p.url && p.url.length > 0) ? p.url : cfg_apiEndpoint;
            if (cfg_apiType === "openai") {
                cfg_openaiLastProvider = p.name;
                if (cfg_apiEndpoint) cfg_openaiLastEndpoint = cfg_apiEndpoint;
            }
        } else {
            cfg_providerName = "Custom";
            if (providerChanged && cfg_apiType !== "exa") {
                cfg_modelName = "";
                _allowModelAutoSelect = true;
            }
        }
        endConfigTxn({ prevKeySlot: prevSlot });
    }

    function applyEndpointEdit(text) {
        var prevSlot = currentSlot();
        beginConfigTxn();
        cfg_apiEndpoint = text;
        if (caps.providerPresets) {
            var matched = false;
            for (var i = 1; i < presetEndpoints.length; i++) {
                if (text === presetEndpoints[i].url) {
                    if (endpointPreset) endpointPreset.currentIndex = i;
                    cfg_providerName = presetEndpoints[i].name;
                    cfg_usesResponsesAPI = !!presetEndpoints[i].usesResponsesAPI;
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                if (endpointPreset) endpointPreset.currentIndex = 0;
                cfg_providerName = "Custom";
            }
        }
        if (cfg_apiType === "gemini")
            cfg_providerName = "Google Gemini";
        if (cfg_apiType === "openai") {
            if (cfg_providerName) cfg_openaiLastProvider = cfg_providerName;
            if (text) cfg_openaiLastEndpoint = text;
        }
        endConfigTxn({ prevKeySlot: prevSlot });
    }

    function applyGeminiOptions(changes) {
        var prevSlot = currentSlot();
        if (fetchStatusLabel) fetchStatusLabel.visible = false;
        beginConfigTxn();
        cfg_providerName = "Google Gemini";
        if (changes.authMethod !== undefined) {
            cfg_geminiAuthMethod = changes.authMethod;
            if (changes.authMethod === "agentplatform"
                    && (cfg_apiEndpoint.indexOf("generativelanguage.googleapis.com") !== -1)) {
                cfg_apiEndpoint = "https://aiplatform.googleapis.com";
            } else if (changes.authMethod === "aistudio"
                    && (cfg_apiEndpoint.indexOf("aiplatform.googleapis.com") !== -1)) {
                cfg_apiEndpoint = "https://generativelanguage.googleapis.com";
            }
            if (apiEndpointField) apiEndpointField.text = cfg_apiEndpoint;
        }
        if (changes.apiVariant !== undefined)
            cfg_geminiApiVariant = changes.apiVariant;
        if (changes.vertexAuthType !== undefined)
            cfg_geminiVertexAuthType = changes.vertexAuthType;
        if (changes.projectId !== undefined)
            cfg_geminiProjectId = changes.projectId;
        if (changes.location !== undefined)
            cfg_geminiLocation = changes.location;
        cfg_geminiApiVariant = Api.clampGeminiApiVariant(
            cfg_geminiApiVariant, cfg_geminiAuthMethod, cfg_geminiVertexAuthType);
        endConfigTxn({ prevKeySlot: prevSlot });
    }

    function rememberOpenAIChoice(providerName, endpointUrl) {
        if (cfg_apiType !== "openai") return;
        if (providerName && providerName.length > 0) cfg_openaiLastProvider = providerName;
        if (endpointUrl && endpointUrl.length > 0) cfg_openaiLastEndpoint = endpointUrl;
    }

    function createNewProfile() {
        var name = i18n("New Profile");
        var p = Profiles.createProfile(name, configPage);
        var list = Profiles.loadProfilesRaw(cfg_profiles);
        list.push(p);
        cfg_profiles = JSON.stringify(list);
        profilesList = list;
        applyProfileSelection(p.id);
    }

    function duplicateActiveProfile() {
        var profiles = Profiles.loadProfilesRaw(cfg_profiles);
        var active = Profiles.getActive(profiles, cfg_activeProfileId);
        if (!active) return;

        var currentKey = walletApiKey;

        var p = Profiles.duplicateProfile(active, i18n("%1 (Copy)", active.name));
        profiles.push(p);
        cfg_profiles = JSON.stringify(profiles);
        profilesList = profiles;
        applyProfileSelection(p.id, currentKey);
    }

    function deleteActiveProfile() {
        var profiles = Profiles.loadProfilesRaw(cfg_profiles);
        if (profiles.length <= 1) return;

        var toDelete = cfg_activeProfileId;
        profiles = Profiles.deleteProfile(profiles, toDelete);
        cfg_profiles = JSON.stringify(profiles);
        profilesList = profiles;

        var nextId = profiles[0].id;
        applyProfileSelection(nextId);
    }

    function applyProfileSelection(id, copyKey) {
        var profiles = Profiles.loadProfilesRaw(cfg_profiles);
        var p = Profiles.getActive(profiles, id);
        if (!p) return;

        var prevSlot = currentSlot();
        if (walletKeyDirty && lastKeySlot.length > 0)
            flushDirtyKeyToSlot(lastKeySlot);

        beginConfigTxn();
        _switchingProfile = true;
        cfg_activeProfileId = id;
        Profiles.applyToKCM(p, configPage);
        syncModelParamControls();
        availableModels = [];
        _switchingProfile = false;
        endConfigTxn({ prevKeySlot: prevSlot, copyKey: copyKey });
    }

    // Back-compat alias used by older call sites / mental model.
    function switchToProfile(id, copyKey) {
        applyProfileSelection(id, copyKey);
    }

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: i18n("Profile:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: profileCombo
                Layout.fillWidth: true
                model: profilesList ? profilesList.map(function(p) { return p.name; }) : []
                currentIndex: {
                    if (!profilesList) return 0;
                    for (var i = 0; i < profilesList.length; i++) {
                        if (profilesList[i].id === cfg_activeProfileId) return i;
                    }
                    return 0;
                }
                onActivated: function(index) {
                    switchToProfile(profilesList[index].id);
                }
            }

            QQC2.Button {
                icon.name: "list-add"
                QQC2.ToolTip.text: i18n("New Profile")
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.visible: hovered
                display: QQC2.AbstractButton.IconOnly
                onClicked: createNewProfile()
            }

            QQC2.Button {
                icon.name: "edit-rename"
                QQC2.ToolTip.text: i18n("Rename Profile")
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.visible: hovered
                display: QQC2.AbstractButton.IconOnly
                onClicked: renamePopup.open()
            }

            QQC2.Button {
                icon.name: "edit-copy"
                QQC2.ToolTip.text: i18n("Duplicate Profile")
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.visible: hovered
                display: QQC2.AbstractButton.IconOnly
                onClicked: duplicateActiveProfile()
            }

            QQC2.Button {
                icon.name: "edit-delete"
                QQC2.ToolTip.text: i18n("Delete Profile")
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.visible: hovered
                display: QQC2.AbstractButton.IconOnly
                enabled: profilesList ? profilesList.length > 1 : false
                onClicked: deleteActiveProfile()
            }
        }

        QQC2.Popup {
            id: renamePopup
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            modal: true
            focus: true
            closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
            
            ColumnLayout {
                spacing: Kirigami.Units.gridUnit
                QQC2.Label { text: i18n("Rename Profile") }
                QQC2.TextField {
                    id: renameField
                    Layout.fillWidth: true
                    placeholderText: i18n("Profile Name")
                    text: {
                        var p = Profiles.getActive(profilesList, cfg_activeProfileId);
                        return p ? p.name : "";
                    }
                    onAccepted: renameSubmitBtn.clicked()
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    QQC2.Button {
                        text: i18n("Cancel")
                        onClicked: renamePopup.close()
                    }
                    QQC2.Button {
                        id: renameSubmitBtn
                        text: i18n("Rename")
                        highlighted: true
                        onClicked: {
                            var profiles = Profiles.loadProfilesRaw(cfg_profiles);
                            Profiles.renameProfile(profiles, cfg_activeProfileId, renameField.text.trim());
                            cfg_profiles = JSON.stringify(profiles);
                            profilesList = profiles;
                            renamePopup.close();
                        }
                    }
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        QQC2.ComboBox {
            id: adapterCombo
            Kirigami.FormData.label: i18n("Adapter:")
            Layout.fillWidth: true
            model: adapterChoices.map(function(a) { return a.name; })
            Component.onCompleted: {
                for (var i = 0; i < adapterChoices.length; i++) {
                    if (adapterChoices[i].id === cfg_apiType) {
                        currentIndex = i;
                        return;
                    }
                }
                currentIndex = 0;
            }
            onActivated: function(index) {
                var picked = adapterChoices[index].id;
                if (picked === cfg_apiType) return;
                applyAdapterSelection(picked);
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            text: i18n("Exa does not support tool use")
            visible: cfg_enableTools && usingExaChat
        }

        // --- Gemini Specific Settings ---
        QQC2.ComboBox {
            id: geminiAuthCombo
            Kirigami.FormData.label: i18n("Platform:")
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini"
            model: [i18n("Google AI Studio"), i18n("Google Cloud Agent Platform (Vertex AI)")]
            currentIndex: cfg_geminiAuthMethod === "agentplatform" ? 1 : 0
            onActivated: function(index) {
                if (!_initialized) return;
                applyGeminiOptions({ authMethod: (index === 1 ? "agentplatform" : "aistudio") });
            }
        }

        QQC2.ComboBox {
            id: geminiVertexAuthCombo
            Kirigami.FormData.label: i18n("Authentication:")
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform"
            model: [i18n("API Key (Express Mode)"), i18n("Google Cloud CLI (gcloud)")]
            currentIndex: cfg_geminiVertexAuthType === "gcloud" ? 1 : 0
            onActivated: function(index) {
                if (!_initialized) return;
                applyGeminiOptions({ vertexAuthType: (index === 1 ? "gcloud" : "apikey") });
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform" && cfg_geminiVertexAuthType === "gcloud" && !hasGcloud
            text: i18n("gcloud CLI not found. Please install it to use this authentication method.")
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
        }

        QQC2.ComboBox {
            id: geminiVariantCombo
            Kirigami.FormData.label: i18n("API Variant:")
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini"
            readonly property var variants: (cfg_geminiAuthMethod === "agentplatform" && cfg_geminiVertexAuthType === "apikey")
                ? [{text: i18n("Legacy (generateContent)"), value: "legacy"}]
                : [{text: i18n("Legacy (generateContent)"), value: "legacy"}, {text: i18n("Interactions API (Stateful)"), value: "interactions"}]
            model: variants.map(function(v) { return v.text; })
            currentIndex: {
                for (var i = 0; i < variants.length; i++) {
                    if (variants[i].value === cfg_geminiApiVariant) return i;
                }
                return 0;
            }
            onActivated: function(index) {
                if (!_initialized) return;
                applyGeminiOptions({ apiVariant: variants[index].value });
            }
            onVariantsChanged: {
                if (_initialized && !inConfigTxn && cfg_geminiApiVariant === "interactions" && variants.length === 1) {
                    applyGeminiOptions({ apiVariant: "legacy" });
                }
            }
        }

        QQC2.TextField {
            id: geminiProjectIdField
            Kirigami.FormData.label: i18n("Project ID:")
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform" && cfg_geminiVertexAuthType === "gcloud"
            text: cfg_geminiProjectId
            onTextChanged: {
                if (!_initialized || inConfigTxn) return;
                cfg_geminiProjectId = text;
                rootItem.triggerCapture();
            }
            onEditingFinished: {
                if (!_initialized) return;
                applyGeminiOptions({ projectId: text });
            }
        }

        QQC2.TextField {
            id: geminiLocationField
            Kirigami.FormData.label: i18n("Location:")
            placeholderText: "global"
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform" && cfg_geminiVertexAuthType === "gcloud"
            text: cfg_geminiLocation
            onTextChanged: {
                if (!_initialized || inConfigTxn) return;
                cfg_geminiLocation = text;
                rootItem.triggerCapture();
            }
            onEditingFinished: {
                if (!_initialized) return;
                applyGeminiOptions({ location: text });
            }
        }
        // --- End Gemini Specific Settings ---

        QQC2.ComboBox {
            id: endpointPreset
            Kirigami.FormData.label: i18n("Provider:")
            Layout.fillWidth: true
            visible: caps.providerPresets === true
            editable: false
            model: presetEndpoints.map(function(p) { return p.name; })

            Component.onCompleted: {
                for (var i = 1; i < presetEndpoints.length; i++) {
                    if (cfg_apiEndpoint === presetEndpoints[i].url) {
                        currentIndex = i;
                        return;
                    }
                }
                currentIndex = 0;
            }

            popup: QQC2.Popup {
                width: endpointPreset.width
                implicitHeight: Math.min(providerContentColumn.implicitHeight + (padding * 2),
                                         Kirigami.Units.gridUnit * 20)
                padding: Kirigami.Units.smallSpacing

                onOpened: {
                    providerSearchField.text = "";
                    providerListView.currentIndex = endpointPreset.currentIndex;
                    providerSearchField.forceActiveFocus();
                }

                ColumnLayout {
                    id: providerContentColumn
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.SearchField {
                        id: providerSearchField
                        Layout.fillWidth: true
                        Keys.onDownPressed: providerListView.forceActiveFocus()
                        Keys.onReturnPressed: {
                            if (providerListView.count > 0) {
                                var pick = providerListView.model[0];
                                endpointPreset.selectPreset(pick);
                                endpointPreset.popup.close();
                            }
                        }
                    }

                    QQC2.ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        background: null

                        ListView {
                            id: providerListView
                            clip: true
                            model: presetEndpoints.filter(function(p) {
                                return providerSearchField.text.length === 0
                                    || p.name.toLowerCase().indexOf(providerSearchField.text.toLowerCase()) !== -1;
                            })
                            delegate: QQC2.ItemDelegate {
                                width: ListView.view.width
                                text: modelData.name
                                highlighted: ListView.isCurrentItem || modelData.name === endpointPreset.currentText
                                onClicked: {
                                    endpointPreset.selectPreset(modelData);
                                    endpointPreset.popup.close();
                                }
                            }
                        }
                    }
                }
            }

            function selectPreset(preset) {
                if (!_initialized) return;
                applyProviderSelection(preset);
            }
        }

        QQC2.TextField {
            id: apiEndpointField
            Kirigami.FormData.label: i18n("API Endpoint:")
            placeholderText: "http://localhost:11434/v1"
            Layout.fillWidth: true
            // Adapters with customEndpoint:false (e.g. Exa) keep a fixed URL.
            visible: caps.customEndpoint !== false
            text: cfg_apiEndpoint
            // Live typing updates cfg only; provider identity + wallet/models
            // reconcile on editingFinished so we don't thrash mid-keystroke.
            onTextChanged: {
                if (!_initialized || inConfigTxn) return;
                cfg_apiEndpoint = text;
            }
            onEditingFinished: {
                if (!_initialized || inConfigTxn) return;
                applyEndpointEdit(text);
            }
        }

        ModelPicker {
            id: modelPicker
            Kirigami.FormData.label: i18n("Model:")
            Layout.fillWidth: true
            modelName: cfg_modelName
            availableModels: configPage.availableModels
            fetchInProgress: configPage.fetchInProgress
            fetchVisible: caps.fetchModels === true
            fetchEnabled: !configPage.fetchInProgress && (cfg_apiEndpoint || "").length > 0
            onModelSelected: function(selected) {
                cfg_modelName = selected;
                rootItem.triggerCapture();
            }
            onFetchRequested: ensureModelsLoaded(true)
        }

        QQC2.Label {
            id: fetchStatusLabel
            visible: false
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }

        RowLayout {
            Kirigami.FormData.label: i18n("API Key:")
            visible: !(cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform" && cfg_geminiVertexAuthType === "gcloud")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: apiKeyField
                Layout.fillWidth: true
                placeholderText: (cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform") ? i18n("Paste short-lived access token") : i18n("Optional - for OpenAI, etc.")
                echoMode: TextInput.Password
                text: walletKeyLoaded ? walletApiKey : cfg_apiKey
                onTextChanged: {
                    if (walletKeyLoaded) {
                        walletKeyDirty = (text !== walletApiKey);
                    }
                }
                onEditingFinished: {
                    if (walletKeyDirty) saveWalletKey();
                }
            }

            QQC2.Button {
                id: saveKeyButton
                text: walletSaveInProgress ? i18n("Saving…") :
                      !walletKeyDirty ? i18n("Saved") :
                      !walletAvailable ? i18n("Save to Config (Insecure)") : i18n("Save Key")
                icon.name: !walletKeyDirty ? "dialog-ok-apply" : "document-save"
                enabled: walletKeyDirty && !walletSaveInProgress
                onClicked: saveWalletKey()
            }
        }

        QQC2.Label {
            visible: walletKeyLoaded
            text: walletAvailable ? i18n("Stored in KDE Wallet") : i18n("KDE Wallet unavailable — key stored in config file")
            font: Kirigami.Theme.smallFont
            color: walletAvailable ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Temperature: %1%", Math.round(temperatureSlider.value))
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Slider {
                id: temperatureSlider
                Layout.fillWidth: true
                from: 0
                to: 100
                stepSize: 1
                value: cfg_temperature
                onValueChanged: {
                    if (!_initialized) return;
                    cfg_temperature = value;
                    rootItem.triggerCapture();
                }
            }

            RowLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    text: i18n("Precise")
                    font: Kirigami.Theme.smallFont
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    text: i18n("Creative")
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        QQC2.SpinBox {
            id: maxTokensSpinBox
            Kirigami.FormData.label: i18n("Max Tokens:")
            from: 64
            to: 32768
            stepSize: 64
            editable: true
            value: cfg_maxTokens
            onValueModified: {
                if (!_initialized) return;
                cfg_maxTokens = value;
                rootItem.triggerCapture();
            }
        }

        QQC2.ComboBox {
            id: reasoningEffortCombo
            Kirigami.FormData.label: i18n("Thinking:")
            Layout.fillWidth: true
            visible: caps.reasoningEffort === true
            readonly property var efforts: ["off", "low", "medium", "high"]
            model: [i18n("Off"), i18n("Low"), i18n("Medium"), i18n("High")]
            currentIndex: Math.max(0, efforts.indexOf(cfg_reasoningEffort))
            onActivated: function(index) {
                if (!_initialized) return;
                cfg_reasoningEffort = efforts[index];
                rootItem.triggerCapture();
            }
        }

        QQC2.SpinBox {
            id: thinkingBudgetSpinBox
            Kirigami.FormData.label: i18n("Thinking budget:")
            visible: caps.thinkingBudget === true
            from: 0
            to: 32768
            stepSize: 256
            editable: true
            value: cfg_thinkingBudget
            onValueModified: {
                if (!_initialized) return;
                cfg_thinkingBudget = value;
                rootItem.triggerCapture();
            }
            // Anthropic gates thinking on reasoningEffort != "off"; Gemini uses
            // the budget directly so the spinbox is always enabled there.
            enabled: !caps.reasoningEffort || cfg_reasoningEffort !== "off"
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: caps.reasoningHelp ? i18n(caps.reasoningHelp) : ""
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            // Show any non-empty help text (e.g. Exa grounded-search blurb),
            // not only when thinking knobs are enabled.
            visible: (caps.reasoningHelp || "").length > 0
        }

        QQC2.CheckBox {
            id: showThoughtsCheckBox
            text: i18n("Show thoughts in chat (collapsible)")
            visible: caps.reasoningEffort === true || caps.thinkingBudget === true
            checked: cfg_showThoughts
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_showThoughts = checked;
                rootItem.triggerCapture();
            }

            QQC2.ToolTip.text: i18n("When enabled, the model's reasoning is shown above each reply with a collapsible header. Round-trip of signed thoughts to the API still happens regardless of this setting.")
            QQC2.ToolTip.delay: 500
            QQC2.ToolTip.visible: hovered
        }

        QQC2.CheckBox {
            id: usesResponsesAPICheckBox
            text: i18n("Use Responses API")
            visible: cfg_apiType === "openai"
            checked: cfg_usesResponsesAPI
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_usesResponsesAPI = checked;
                rootItem.triggerCapture();
            }

            QQC2.ToolTip.text: i18n("Required to surface reasoning content on OpenAI / Poe / OpenRouter / Azure (POSTs to /v1/responses instead of /v1/chat/completions). Auto-set when picking a preset.")
            QQC2.ToolTip.delay: 500
            QQC2.ToolTip.visible: hovered
        }



        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        QQC2.CheckBox {
            id: resizeImageAttachmentsCheckBox
            Kirigami.FormData.label: i18n("Attachments:")
            text: i18n("Resize image attachments")
            checked: cfg_resizeImageAttachments
            onCheckedChanged: if (_initialized) cfg_resizeImageAttachments = checked

            QQC2.ToolTip.text: i18n("Resizes large image attachments to fit within 800x600 before sending, reducing upload size and context tokens.")
            QQC2.ToolTip.delay: 500
            QQC2.ToolTip.visible: hovered
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        QQC2.CheckBox {
            id: saveChatHistoryCheckBox
            Kirigami.FormData.label: i18n("Chat History:")
            text: i18n("Auto-save chat history")
            checked: cfg_saveChatHistory
            onCheckedChanged: if (_initialized) cfg_saveChatHistory = checked

            QQC2.ToolTip.text: i18n("Saves to ~/.local/share/plasmallm/chats/")
            QQC2.ToolTip.delay: 500
            QQC2.ToolTip.visible: hovered
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        QQC2.CheckBox {
            id: showNotificationsMinimizedCheckBox
            Kirigami.FormData.label: i18n("Notifications:")
            text: i18n("Show notifications when minimized")
            checked: cfg_showNotificationsMinimized
            onCheckedChanged: if (_initialized) cfg_showNotificationsMinimized = checked

            QQC2.ToolTip.text: i18n("Show system notifications for incoming messages and tool calls when the chat window is minimized or closed.")
            QQC2.ToolTip.delay: 500
            QQC2.ToolTip.visible: hovered
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Save format:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: chatSaveFormatCombo
                Layout.fillWidth: true
                model: [i18n("Plain text (.txt)"), i18n("Structured (.jsonl)")]
                enabled: cfg_saveChatHistory
                currentIndex: cfg_chatSaveFormat === "jsonl" ? 1 : 0
                onCurrentIndexChanged: if (_initialized) cfg_chatSaveFormat = currentIndex === 1 ? "jsonl" : "txt"
            }

            QQC2.Button {
                id: openFolderButton
                text: i18n("Open Folder")
                icon.name: "folder-open"
                onClicked: openFolderSource.connectSource("xdg-open \"${XDG_DATA_HOME:-$HOME/.local/share}/plasmallm/chats/\"")

                QQC2.ToolTip.text: i18n("Open the folder where chat histories are saved")
                QQC2.ToolTip.delay: 500
                QQC2.ToolTip.visible: hovered
            }
        }

        QQC2.Label {
            text: i18n("Saves to ~/.local/share/plasmallm/chats/")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }

        QQC2.ButtonGroup { id: autoClearGroup }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Auto-clear:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.RadioButton {
                text: i18n("Disabled")
                QQC2.ButtonGroup.group: autoClearGroup
                checked: cfg_autoClearMode === 0
                onClicked: if (_initialized) cfg_autoClearMode = 0
            }
            QQC2.RadioButton {
                text: i18n("Instant (always clear when panel opens)")
                QQC2.ButtonGroup.group: autoClearGroup
                checked: cfg_autoClearMode === 1
                onClicked: if (_initialized) cfg_autoClearMode = 1
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                QQC2.RadioButton {
                    id: timedRadio
                    text: i18n("After")
                    QQC2.ButtonGroup.group: autoClearGroup
                    checked: cfg_autoClearMode === 2 || cfg_autoClearMode === 3
                    onClicked: if (_initialized) cfg_autoClearMode = (unitCombo.currentIndex === 0 ? 2 : 3)
                }
                QQC2.SpinBox {
                    from: 1
                    to: unitCombo.currentIndex === 0 ? 3600 : 1440
                    value: unitCombo.currentIndex === 0 ? cfg_autoClearSeconds : cfg_autoClearMinutes
                    enabled: timedRadio.checked
                    onValueModified: {
                        if (!_initialized) return;
                        if (unitCombo.currentIndex === 0)
                            cfg_autoClearSeconds = value
                        else
                            cfg_autoClearMinutes = value
                    }
                }
                QQC2.ComboBox {
                    id: unitCombo
                    model: [i18n("seconds"), i18n("minutes")]
                    currentIndex: cfg_autoClearMode === 3 ? 1 : 0
                    enabled: timedRadio.checked
                    onActivated: if (_initialized) cfg_autoClearMode = (currentIndex === 0 ? 2 : 3)
                }
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

    }
}
