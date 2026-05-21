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

    function walletCall(member, args, resolve, reject) {
        var reply = DBus.SessionBus.asyncCall({
            service: "org.kde.kwalletd6",
            path: "/modules/kwalletd6",
            iface: "org.kde.KWallet",
            member: member,
            arguments: args
        });
        reply.finished.connect(function() {
            if (reply.isError) {
                if (reject) reject(reply.error);
            } else {
                var val = reply.value;
                if (val !== null && val !== undefined && val.hasOwnProperty("value")) val = val.value;
                if (resolve) resolve(val);
            }
        });
    }

    function ensureWalletFolder(handle, callback) {
        walletCall("hasFolder", [new DBus.int32(handle), "PlasmaLLM", "PlasmaLLM"],
            function(exists) {
                if (exists) {
                    callback(true);
                } else {
                    walletCall("createFolder", [new DBus.int32(handle), "PlasmaLLM", "PlasmaLLM"],
                        function(created) { callback(created); },
                        function(err) { callback(false); }
                    );
                }
            },
            function(err) { callback(false); }
        );
    }

    function currentSlot() {
        if (cfg_activeProfileId) return Api.profileKeySlot(cfg_activeProfileId);
        
        var t = cfg_apiType;
        if (t === "gemini" && cfg_geminiAuthMethod === "agentplatform") t = "gemini:agentplatform";
        return Api.apiKeySlot(t, cfg_providerName);
    }

    function readFallbackMap() {
        if (!cfg_apiKeysFallback || cfg_apiKeysFallback.length === 0) return {};
        try { return JSON.parse(cfg_apiKeysFallback) || {}; } catch(e) { return {}; }
    }

    function fallbackKeyFor(slot) {
        var m = readFallbackMap();
        if (m.hasOwnProperty(slot)) return m[slot];
        
        // If searching by profile ID and not found, fall back to the legacy slot
        if (slot.indexOf("apiKey:profile:") === 0) {
            var t = cfg_apiType;
            if (t === "gemini" && cfg_geminiAuthMethod === "agentplatform") t = "gemini:agentplatform";
            var legacySlot = Api.apiKeySlot(t, cfg_providerName);
            return fallbackKeyFor(legacySlot);
        }

        return cfg_apiKey || "";
    }

    function writeFallbackKey(slot, key) {
        var m = readFallbackMap();
        m[slot] = key;
        cfg_apiKeysFallback = JSON.stringify(m);
    }

    function walletWriteKey(handle, slot, key, onDone) {
        ensureWalletFolder(handle, function(ok) {
            if (!ok) {
                onDone(false);
                return;
            }
            walletCall("writePassword", [new DBus.int32(handle), "PlasmaLLM", slot, key, "PlasmaLLM"],
                function(result) { onDone(result === 0); },
                function(err) {
                    console.warn("PlasmaLLM: wallet writePassword error: " + err);
                    onDone(false);
                }
            );
        });
    }

    function loadWalletKey(copyKey) {
        var slot = currentSlot();
        walletKeyLoaded = false;
        // Slot may change again before this async chain completes (e.g. adapter
        // switch fires loadWalletKey twice in quick succession). Stale results
        // would clobber the correct key, so each callback verifies its slot is
        // still the active one before applying state.
        function isCurrent() { return slot === currentSlot(); }
        function applyKey(key) {
            if (!isCurrent()) return;
            walletApiKey = key;
            walletKeyLoaded = true;
            if (apiKeyField) apiKeyField.text = walletApiKey;
            walletKeyDirty = false;
        }

        if (copyKey !== undefined && copyKey !== null && copyKey !== "") {
            if (apiKeyField) apiKeyField.text = copyKey;
            walletKeyDirty = true;
            saveWalletKey(); // This writes it to the new slot and sets walletApiKey
            return;
        }

        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    applyKey(fallbackKeyFor(slot));
                    return;
                }
                walletAvailable = true;
                walletCall("readPassword", [new DBus.int32(handle), "PlasmaLLM", slot, "PlasmaLLM"],
                    function(password) {
                        if (password && password.length > 0) {
                            applyKey(password);
                        } else if (slot.indexOf("apiKey:profile:") === 0) {
                            // Try legacy slot fallback
                            var t = cfg_apiType;
                            if (t === "gemini" && cfg_geminiAuthMethod === "agentplatform") t = "gemini:agentplatform";
                            var legacySlot = Api.apiKeySlot(t, cfg_providerName);
                            walletCall("readPassword", [new DBus.int32(handle), "PlasmaLLM", legacySlot, "PlasmaLLM"],
                                function(legacyPassword) {
                                    applyKey(legacyPassword && legacyPassword.length > 0 ? legacyPassword : fallbackKeyFor(slot));
                                    walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                                },
                                function(err) {
                                    applyKey(fallbackKeyFor(slot));
                                    walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                                }
                            );
                            return;
                        } else {
                            applyKey(fallbackKeyFor(slot));
                        }
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    },
                    function(err) {
                        applyKey(fallbackKeyFor(slot));
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    }
                );
            },
            function(err) {
                applyKey(fallbackKeyFor(slot));
            }
        );
    }

    function saveWalletKey() {
        var key = apiKeyField.text.replace(/^\s+|\s+$/g, "");
        var slot = currentSlot();
        walletSaveInProgress = true;
        if (!walletAvailable) {
            writeFallbackKey(slot, key);
            walletApiKey = key;
            walletKeyDirty = false;
            walletSaveInProgress = false;
            ensureModelsLoaded(false);
            return;
        }
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    writeFallbackKey(slot, key);
                    walletApiKey = key;
                    walletKeyDirty = false;
                    walletSaveInProgress = false;
                    ensureModelsLoaded(false);
                    return;
                }
                walletWriteKey(handle, slot, key, function(success) {
                    if (success) {
                        walletApiKey = key;
                        walletKeyDirty = false;
                        cfg_apiKeyVersion++;
                        ensureModelsLoaded(false);
                    }
                    walletSaveInProgress = false;
                    walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                });
            },
            function(err) {
                writeFallbackKey(slot, key);
                walletApiKey = key;
                walletKeyDirty = false;
                walletSaveInProgress = false;
            }
        );
    }

    function refreshAvailableModels() {
        var slot = currentSlot();
        var list = modelCache[slot];
        availableModels = Array.isArray(list) ? list : [];
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

    function ensureModelsLoaded(force) {
        if (cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform") return;
        var slot = currentSlot();
        var have = Array.isArray(modelCache[slot]) && modelCache[slot].length > 0;
        if (!force && have) return;
        if (fetchInProgress) return;
        // Wallet load is async; if we fetch before it returns we'd send the
        // previous slot's key. onWalletKeyLoadedChanged retries once the key
        // for the current slot has actually arrived.
        if (!walletKeyLoaded) return;
        var key = walletApiKey;
        // Skip automatic fetches when no key is set — some endpoints (e.g. local
        // LM Studio) don't need one, but we shouldn't hammer remote providers
        // with guaranteed-401 requests. The manual refresh button bypasses this.
        if (!force && (!key || key.length === 0)) return;
        fetchInProgress = true;
        fetchStatusLabel.visible = false;

        var opts = {
            geminiApiVariant: cfg_geminiApiVariant,
            geminiAuthMethod: cfg_geminiAuthMethod,
            geminiProjectId: cfg_geminiProjectId,
            geminiLocation: cfg_geminiLocation
        };

        var fetchAction = function(effectiveKey) {
            Api.fetchModels(effectiveApiType, apiEndpointField.text, effectiveKey, cfg_usesResponsesAPI, opts, function(error, models) {
            fetchInProgress = false;
            if (error) {
                fetchStatusLabel.text = error;
                fetchStatusLabel.visible = true;
            } else if (!models || models.length === 0) {
                fetchStatusLabel.text = i18n("No models found.");
                fetchStatusLabel.visible = true;
            } else {
                var next = {};
                for (var k in modelCache) if (modelCache.hasOwnProperty(k)) next[k] = modelCache[k];
                next[slot] = models;
                modelCache = next;
                cfg_availableModels = JSON.stringify(next);
                refreshAvailableModels();
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

    onWalletKeyLoadedChanged: {
        if (walletKeyLoaded) ensureModelsLoaded(false);
    }

    Component.onCompleted: {
        profilesList = Profiles.loadProfilesRaw(cfg_profiles);
        loadModelCache();
        loadWalletKey();
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
    readonly property string effectiveApiType: (cfg_apiType === "gemini" && cfg_geminiApiVariant === "interactions") ? "gemini_interactions" : cfg_apiType
    property var caps: Api.getCapabilities(effectiveApiType) || {}

    onCfg_apiTypeChanged: {
        caps = Api.getCapabilities(effectiveApiType) || {};
        loadWalletKey();
        refreshAvailableModels();
        rootItem.triggerCapture();
        // Don't auto-fetch here: when the adapter combo changes cfg_apiType,
        // the endpoint hasn't been swapped yet — applyAdapterDefaults() runs
        // immediately after and triggers the fetch with the correct endpoint.
    }

    onCfg_geminiApiVariantChanged: {
        caps = Api.getCapabilities(effectiveApiType) || {};
        loadWalletKey();
        refreshAvailableModels();
        ensureModelsLoaded(false);
        rootItem.triggerCapture();
    }

    onCfg_geminiAuthMethodChanged: {
        loadWalletKey();
        refreshAvailableModels();
        ensureModelsLoaded(false);
        rootItem.triggerCapture();
    }

    onCfg_providerNameChanged: {
        loadWalletKey();
        refreshAvailableModels();
        ensureModelsLoaded(false);
        rootItem.triggerCapture();
    }

    function applyAdapterDefaults(apiType) {
        var presets = Api.getPresets(apiType) || [];
        var pick = null;
        // For Gemini, we might have switched to "gemini" from "gemini_interactions" or vice versa
        // through the apiVariant dropdown.
        var baseApiType = (apiType === "gemini" || apiType === "gemini_interactions") ? "gemini" : apiType;
        
        // For OpenAI-compatible, restore the last selected provider if we have one.
        if (baseApiType === "openai" && cfg_openaiLastProvider && cfg_openaiLastProvider.length > 0) {
            for (var j = 0; j < presets.length; j++) {
                if (presets[j].name === cfg_openaiLastProvider) {
                    pick = presets[j];
                    break;
                }
            }
            if (pick && (!pick.url || pick.url.length === 0) && cfg_openaiLastEndpoint && cfg_openaiLastEndpoint.length > 0) {
                // Custom preset — use the remembered endpoint URL.
                apiEndpointField.text = cfg_openaiLastEndpoint;
                cfg_providerName = pick.name;
                cfg_modelName = "";
                refreshAvailableModels();
                ensureModelsLoaded(false);
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
            apiEndpointField.text = pick.url;
            cfg_providerName = pick.name;
            cfg_usesResponsesAPI = !!pick.usesResponsesAPI;
        }
        cfg_modelName = "";
        refreshAvailableModels();
        ensureModelsLoaded(false);
    }

    function rememberOpenAIChoice(providerName, endpointUrl) {
        if (cfg_apiType !== "openai") return;
        if (providerName && providerName.length > 0) cfg_openaiLastProvider = providerName;
        if (endpointUrl && endpointUrl.length > 0) cfg_openaiLastEndpoint = endpointUrl;
        rootItem.triggerCapture();
    }

    function createNewProfile() {
        var name = i18n("New Profile");
        var p = Profiles.createProfile(name, configPage);
        var list = Profiles.loadProfilesRaw(cfg_profiles);
        list.push(p);
        cfg_profiles = JSON.stringify(list);
        profilesList = list;
        switchToProfile(p.id);
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
        switchToProfile(p.id, currentKey);
    }

    function deleteActiveProfile() {
        var profiles = Profiles.loadProfilesRaw(cfg_profiles);
        if (profiles.length <= 1) return;
        
        var toDelete = cfg_activeProfileId;
        profiles = Profiles.deleteProfile(profiles, toDelete);
        cfg_profiles = JSON.stringify(profiles);
        profilesList = profiles;
        
        // Pick a new active profile
        var nextId = profiles[0].id;
        switchToProfile(nextId);
    }

    function switchToProfile(id, copyKey) {
        var profiles = Profiles.loadProfilesRaw(cfg_profiles);
        var p = Profiles.getActive(profiles, id);
        if (!p) return;

        _initialized = false;
        _switchingProfile = true;
        cfg_activeProfileId = id;
        Profiles.applyToKCM(p, configPage);
        _switchingProfile = false;

        // Reset models to ensure we don't show stale models from previous profile
        availableModels = [];
        loadWalletKey(copyKey);
        refreshAvailableModels();
        ensureModelsLoaded(false);
        _initialized = true;
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
                cfg_apiType = picked;
                applyAdapterDefaults(picked);
            }
        }

        // --- Gemini Specific Settings ---
        QQC2.ComboBox {
            id: geminiVertexAuthCombo
            Kirigami.FormData.label: i18n("Authentication:")
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform"
            model: [i18n("API Key (Express Mode)"), i18n("Google Cloud CLI (gcloud)")]
            currentIndex: cfg_geminiVertexAuthType === "gcloud" ? 1 : 0
            onActivated: function(index) {
                if (_initialized) cfg_geminiVertexAuthType = (index === 1 ? "gcloud" : "apikey");
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
                if (_initialized) cfg_geminiApiVariant = variants[index].value;
            }
            onVariantsChanged: {
                if (_initialized && cfg_geminiApiVariant === "interactions" && variants.length === 1) {
                    cfg_geminiApiVariant = "legacy";
                }
            }
        }

        QQC2.ComboBox {
            id: geminiAuthCombo
            Kirigami.FormData.label: i18n("Platform:")
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini"
            model: [i18n("Google AI Studio"), i18n("Google Cloud Agent Platform (Vertex AI)")]
            currentIndex: cfg_geminiAuthMethod === "agentplatform" ? 1 : 0
            onActivated: function(index) {
                if (!_initialized) return;
                cfg_geminiAuthMethod = (index === 1 ? "agentplatform" : "aistudio");
                if (index === 1 && apiEndpointField.text.indexOf("generativelanguage.googleapis.com") !== -1) {
                    apiEndpointField.text = "https://aiplatform.googleapis.com";
                } else if (index === 0 && apiEndpointField.text.indexOf("aiplatform.googleapis.com") !== -1) {
                    apiEndpointField.text = "https://generativelanguage.googleapis.com";
                }
            }
        }

        QQC2.TextField {
            id: geminiProjectIdField
            Kirigami.FormData.label: i18n("Project ID:")
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform"
            text: cfg_geminiProjectId
            onTextChanged: {
                if (!_initialized) return;
                cfg_geminiProjectId = text;
                rootItem.triggerCapture();
            }
            onEditingFinished: ensureModelsLoaded(false)
        }

        QQC2.TextField {
            id: geminiLocationField
            Kirigami.FormData.label: i18n("Location:")
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform"
            text: cfg_geminiLocation
            onTextChanged: {
                if (!_initialized) return;
                cfg_geminiLocation = text;
                rootItem.triggerCapture();
            }
            onEditingFinished: ensureModelsLoaded(false)
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
                var idx = -1;
                for (var i = 0; i < presetEndpoints.length; i++) {
                    if (presetEndpoints[i].name === preset.name) {
                        idx = i;
                        break;
                    }
                }
                if (idx === -1) return;

                endpointPreset.currentIndex = idx;
                if (idx > 0) {
                    var p = presetEndpoints[idx];
                    apiEndpointField.text = p.url;
                    if (_initialized) cfg_providerName = p.name;
                    if (_initialized) cfg_usesResponsesAPI = !!p.usesResponsesAPI;
                    rememberOpenAIChoice(p.name, p.url);
                } else {
                    if (_initialized) cfg_providerName = "Custom";
                }
            }
        }

        QQC2.TextField {
            id: apiEndpointField
            Kirigami.FormData.label: i18n("API Endpoint:")
            placeholderText: "http://localhost:11434/v1"
            Layout.fillWidth: true
            text: cfg_apiEndpoint
            onTextChanged: {
                if (!_initialized) return;
                cfg_apiEndpoint = text;
                if (!caps.providerPresets) return;
                // Sync preset selector when active adapter uses presets.
                var matched = false;
                for (var i = 1; i < presetEndpoints.length; i++) {
                    if (text === presetEndpoints[i].url) {
                        endpointPreset.currentIndex = i;
                        cfg_usesResponsesAPI = !!presetEndpoints[i].usesResponsesAPI;
                        matched = true;
                        break;
                    }
                }
                if (!matched) {
                    endpointPreset.currentIndex = 0;
                    cfg_providerName = "Custom";
                }
                rememberOpenAIChoice(cfg_providerName, text);
            }
            onEditingFinished: ensureModelsLoaded(false)
        }

        QQC2.TextField {
            id: modelEntryField
            Kirigami.FormData.label: i18n("Model:")
            Layout.fillWidth: true
            visible: cfg_apiType === "gemini" && cfg_geminiAuthMethod === "agentplatform"
            text: cfg_modelName
            onTextChanged: if (_initialized) cfg_modelName = text
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Model:")
            visible: !modelEntryField.visible
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: modelCombo
                Layout.fillWidth: true
                editable: false

                // Prepend the persisted model name when it isn't in the fetched
                // list so it stays selectable (initial load, stale value, etc.).
                readonly property var displayModels: {
                    if (cfg_modelName && cfg_modelName.length > 0 && availableModels.indexOf(cfg_modelName) === -1) {
                        var list = availableModels.slice();
                        list.unshift(cfg_modelName);
                        return list;
                    }
                    return availableModels;
                }
                model: displayModels
                enabled: displayModels.length > 0 && !fetchInProgress

                onDisplayModelsChanged: {
                    var idx = displayModels.indexOf(cfg_modelName);
                    currentIndex = idx >= 0 ? idx : 0;

                    // Persist the visible selection so applying without
                    // touching the combo doesn't leave cfg_modelName empty.
                    if (_initialized && (!cfg_modelName || cfg_modelName.length === 0) && displayModels.length > 0) {
                        Qt.callLater(() => {
                            if (!cfg_modelName && displayModels.length > 0) {
                                cfg_modelName = displayModels[0];
                            }
                        });
                    }
                }

                Connections {
                    target: configPage
                    function onCfg_modelNameChanged() {
                        var idx = modelCombo.displayModels.indexOf(cfg_modelName);
                        modelCombo.currentIndex = idx >= 0 ? idx : 0;
                    }
                }

                popup: QQC2.Popup {
                    width: modelCombo.width
                    implicitHeight: Math.min(modelContentColumn.implicitHeight + (padding * 2),
                                             Kirigami.Units.gridUnit * 20)
                    padding: Kirigami.Units.smallSpacing

                    onOpened: {
                        modelSearchField.text = "";
                        modelListView.currentIndex = modelCombo.currentIndex;
                        modelSearchField.forceActiveFocus();
                    }

                    ColumnLayout {
                        id: modelContentColumn
                        anchors.fill: parent
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.SearchField {
                            id: modelSearchField
                            Layout.fillWidth: true
                            Keys.onDownPressed: modelListView.forceActiveFocus()
                            Keys.onReturnPressed: {
                                if (modelListView.count > 0) {
                                    var pick = modelListView.model[0];
                                    cfg_modelName = pick;
                                    modelCombo.currentIndex = modelCombo.displayModels.indexOf(pick);
                                    modelCombo.popup.close();
                                }
                            }
                        }

                        QQC2.ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            // Use ScrollView's background or it might be transparent
                            background: null

                            ListView {
                                id: modelListView
                                clip: true
                                model: modelCombo.displayModels.filter(function(m) {
                                    return modelSearchField.text.length === 0
                                        || m.toLowerCase().indexOf(modelSearchField.text.toLowerCase()) !== -1;
                                })
                                delegate: QQC2.ItemDelegate {
                                    width: ListView.view.width
                                    text: modelData
                                    highlighted: ListView.isCurrentItem || modelData === cfg_modelName
                                    onClicked: {
                                        cfg_modelName = modelData;
                                        modelCombo.currentIndex = modelCombo.displayModels.indexOf(modelData);
                                        modelCombo.popup.close();
                                        rootItem.triggerCapture();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            QQC2.Button {
                icon.name: "view-refresh"
                visible: caps.fetchModels === true && !modelEntryField.visible
                enabled: !fetchInProgress
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: fetchInProgress ? i18n("Refreshing…") : i18n("Refresh model list")
                QQC2.ToolTip.delay: 300
                QQC2.ToolTip.visible: hovered
                onClicked: ensureModelsLoaded(true)
            }
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
                onValueChanged: if (_initialized) cfg_temperature = value
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
            onValueModified: if (_initialized) cfg_maxTokens = value
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
                if (_initialized) cfg_reasoningEffort = efforts[index];
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
            onValueModified: if (_initialized) cfg_thinkingBudget = value
            // Anthropic gates thinking on reasoningEffort != "off"; Gemini uses
            // the budget directly so the spinbox is always enabled there.
            enabled: !caps.reasoningEffort || cfg_reasoningEffort !== "off"
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            text: caps.reasoningHelp || ""
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            visible: (caps.reasoningEffort === true || caps.thinkingBudget === true)
                     && (caps.reasoningHelp || "").length > 0
        }

        QQC2.CheckBox {
            id: showThoughtsCheckBox
            text: i18n("Show thoughts in chat (collapsible)")
            visible: caps.reasoningEffort === true || caps.thinkingBudget === true
            checked: cfg_showThoughts
            onCheckedChanged: if (_initialized) cfg_showThoughts = checked

            QQC2.ToolTip.text: i18n("When enabled, the model's reasoning is shown above each reply with a collapsible header. Round-trip of signed thoughts to the API still happens regardless of this setting.")
            QQC2.ToolTip.delay: 500
            QQC2.ToolTip.visible: hovered
        }

        QQC2.CheckBox {
            id: usesResponsesAPICheckBox
            text: i18n("Use Responses API")
            visible: cfg_apiType === "openai"
            checked: cfg_usesResponsesAPI
            onCheckedChanged: if (_initialized) cfg_usesResponsesAPI = checked

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
