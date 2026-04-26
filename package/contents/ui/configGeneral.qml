/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils
import org.kde.plasma.workspace.dbus as DBus

import "api.js" as Api

SimpleKCM {
    id: configPage

    property string cfg_apiEndpoint
    property string cfg_apiEndpointDefault
    property string cfg_apiType
    property string cfg_apiTypeDefault
    property string cfg_providerName
    property string cfg_providerNameDefault
    property string cfg_modelName
    property string cfg_modelNameDefault
    property string cfg_apiKey
    property string cfg_apiKeyDefault
    property int cfg_temperature
    property int cfg_temperatureDefault
    property int cfg_maxTokens
    property int cfg_maxTokensDefault
    property string cfg_reasoningEffort
    property string cfg_reasoningEffortDefault
    property int cfg_thinkingBudget
    property int cfg_thinkingBudgetDefault
    property bool cfg_showThoughts
    property bool cfg_showThoughtsDefault
    property bool cfg_usesResponsesAPI
    property bool cfg_usesResponsesAPIDefault
    property int cfg_chatSpacing
    property int cfg_chatSpacingDefault
    property bool cfg_saveChatHistory
    property bool cfg_saveChatHistoryDefault
    property string cfg_chatSaveFormat
    property string cfg_chatSaveFormatDefault
    property bool cfg_autoShareCommandOutput
    property bool cfg_autoShareCommandOutputDefault
    property bool cfg_autoRunCommands
    property bool cfg_autoRunCommandsDefault
    property bool cfg_showProviderInTitle
    property bool cfg_showProviderInTitleDefault
    // Declared here because Plasma injects all cfg_ properties onto every config page
    property string cfg_customSystemPrompt
    property string cfg_customSystemPromptDefault
    property string cfg_gatheredSysInfo
    property string cfg_gatheredSysInfoDefault
    property bool cfg_sysInfoOS
    property bool cfg_sysInfoOSDefault
    property bool cfg_sysInfoShell
    property bool cfg_sysInfoShellDefault
    property bool cfg_sysInfoHostname
    property bool cfg_sysInfoHostnameDefault
    property bool cfg_sysInfoKernel
    property bool cfg_sysInfoKernelDefault
    property bool cfg_sysInfoDesktop
    property bool cfg_sysInfoDesktopDefault
    property bool cfg_sysInfoUser
    property bool cfg_sysInfoUserDefault
    property bool cfg_sysInfoCPU
    property bool cfg_sysInfoCPUDefault
    property bool cfg_sysInfoMemory
    property bool cfg_sysInfoMemoryDefault
    property bool cfg_sysInfoGPU
    property bool cfg_sysInfoGPUDefault
    property bool cfg_sysInfoDisk
    property bool cfg_sysInfoDiskDefault
    property bool cfg_sysInfoNetwork
    property bool cfg_sysInfoNetworkDefault
    property bool cfg_sysInfoLocale
    property bool cfg_sysInfoLocaleDefault
    property int cfg_apiKeyVersion
    property int cfg_apiKeyVersionDefault
    property string cfg_apiKeysFallback
    property string cfg_apiKeysFallbackDefault
    property bool cfg_apiKeyMigrated
    property bool cfg_apiKeyMigratedDefault
    property int cfg_autoClearMode
    property int cfg_autoClearModeDefault
    property int cfg_autoClearSeconds
    property int cfg_autoClearSecondsDefault
    property int cfg_autoClearMinutes
    property int cfg_autoClearMinutesDefault
    property string cfg_lastClosedTimestamp
    property string cfg_lastClosedTimestampDefault
    property string cfg_availableModels
    property string cfg_availableModelsDefault
    property string cfg_ollamaApiKey
    property string cfg_ollamaApiKeyDefault
    property int cfg_ollamaApiKeyVersion
    property int cfg_ollamaApiKeyVersionDefault
    property bool cfg_useCommandTool
    property bool cfg_useCommandToolDefault
    property string cfg_tasks
    property string cfg_tasksDefault
    property string cfg_openaiLastProvider
    property string cfg_openaiLastProviderDefault
    property string cfg_openaiLastEndpoint
    property string cfg_openaiLastEndpointDefault

    property var modelCache: ({})
    property var availableModels: []
    property bool fetchInProgress: false
    property string walletApiKey: ""
    property bool walletKeyLoaded: false
    property bool walletAvailable: false
    property bool walletKeyDirty: false
    property bool walletSaveInProgress: false
    property string walletOllamaKey: ""
    property bool walletOllamaKeyLoaded: false
    property bool walletOllamaKeyDirty: false
    property bool walletOllamaSaveInProgress: false

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
        return Api.apiKeySlot(cfg_apiType, cfg_providerName);
    }

    function readFallbackMap() {
        if (!cfg_apiKeysFallback || cfg_apiKeysFallback.length === 0) return {};
        try { return JSON.parse(cfg_apiKeysFallback) || {}; } catch(e) { return {}; }
    }

    function fallbackKeyFor(slot) {
        var m = readFallbackMap();
        if (m.hasOwnProperty(slot)) return m[slot];
        // Legacy single-slot fallback for the very first migration case.
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

    function loadWalletKey() {
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
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    applyKey(fallbackKeyFor(slot));
                    return;
                }
                walletAvailable = true;
                walletCall("readPassword", [new DBus.int32(handle), "PlasmaLLM", slot, "PlasmaLLM"],
                    function(password) {
                        applyKey(password && password.length > 0 ? password : fallbackKeyFor(slot));
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
            return;
        }
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    writeFallbackKey(slot, key);
                    walletApiKey = key;
                    walletKeyDirty = false;
                    walletSaveInProgress = false;
                    return;
                }
                walletWriteKey(handle, slot, key, function(success) {
                    if (success) {
                        walletApiKey = key;
                        walletKeyDirty = false;
                        cfg_apiKeyVersion++;
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

    function currentModelSlot() {
        var t = cfg_apiType || "openai";
        var p = (cfg_providerName && cfg_providerName.length > 0) ? cfg_providerName : t;
        return t + ":" + p;
    }

    function refreshAvailableModels() {
        var slot = currentModelSlot();
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
        var slot = currentModelSlot();
        var have = Array.isArray(modelCache[slot]) && modelCache[slot].length > 0;
        if (!force && have) return;
        if (fetchInProgress) return;
        // Wallet load is async; if we fetch before it returns we'd send the
        // previous slot's key. onWalletKeyLoadedChanged retries once the key
        // for the current slot has actually arrived.
        if (!walletKeyLoaded) return;
        fetchInProgress = true;
        fetchStatusLabel.visible = false;
        var key = walletApiKey;
        Api.fetchModels(cfg_apiType, apiEndpointField.text, key, cfg_usesResponsesAPI, function(error, models) {
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
    }

    onCfg_availableModelsChanged: loadModelCache()

    onWalletKeyLoadedChanged: {
        if (walletKeyLoaded) ensureModelsLoaded(false);
    }

    function walletWriteOllamaKey(handle, key, onDone) {
        ensureWalletFolder(handle, function(ok) {
            if (!ok) {
                onDone(false);
                return;
            }
            walletCall("writePassword", [new DBus.int32(handle), "PlasmaLLM", "ollamaApiKey", key, "PlasmaLLM"],
                function(result) { onDone(result === 0); },
                function(err) {
                    console.warn("PlasmaLLM: wallet writePassword (ollama) error: " + err);
                    onDone(false);
                }
            );
        });
    }

    function loadWalletOllamaKey() {
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    walletOllamaKey = cfg_ollamaApiKey;
                    walletOllamaKeyLoaded = true;
                    return;
                }
                walletCall("readPassword", [new DBus.int32(handle), "PlasmaLLM", "ollamaApiKey", "PlasmaLLM"],
                    function(password) {
                        if (password && password.length > 0) {
                            walletOllamaKey = password;
                        } else {
                            walletOllamaKey = cfg_ollamaApiKey;
                        }
                        walletOllamaKeyLoaded = true;
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    },
                    function(err) {
                        walletOllamaKey = cfg_ollamaApiKey;
                        walletOllamaKeyLoaded = true;
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    }
                );
            },
            function(err) {
                walletOllamaKey = cfg_ollamaApiKey;
                walletOllamaKeyLoaded = true;
            }
        );
    }

    function saveWalletOllamaKey() {
        var key = ollamaApiKeyField.text;
        walletOllamaSaveInProgress = true;
        if (!walletAvailable) {
            cfg_ollamaApiKey = key;
            walletOllamaKeyDirty = false;
            walletOllamaSaveInProgress = false;
            return;
        }
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    cfg_ollamaApiKey = key;
                    walletOllamaKeyDirty = false;
                    walletOllamaSaveInProgress = false;
                    return;
                }
                walletWriteOllamaKey(handle, key, function(success) {
                    if (success) {
                        walletOllamaKey = key;
                        cfg_ollamaApiKey = "";
                        walletOllamaKeyDirty = false;
                        cfg_ollamaApiKeyVersion++;
                    }
                    walletOllamaSaveInProgress = false;
                    walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                });
            },
            function(err) {
                cfg_ollamaApiKey = key;
                walletOllamaKeyDirty = false;
                walletOllamaSaveInProgress = false;
            }
        );
    }

    Component.onCompleted: {
        loadModelCache();
        loadWalletKey();
        loadWalletOllamaKey();
    }

    // OpenAI-compatible presets only (Anthropic/Gemini each have a single fixed
    // endpoint, so they don't need a preset dropdown). The "Custom" sentinel at
    // index 0 lets users pick a non-preset endpoint without a separate toggle.
    readonly property var presetEndpoints: {
        var raw = Api.getPresets("openai") || [];
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
    property var caps: Api.getCapabilities(cfg_apiType) || {}
    onCfg_apiTypeChanged: {
        caps = Api.getCapabilities(cfg_apiType) || {};
        loadWalletKey();
        refreshAvailableModels();
        // Don't auto-fetch here: when the adapter combo changes cfg_apiType,
        // the endpoint hasn't been swapped yet — applyAdapterDefaults() runs
        // immediately after and triggers the fetch with the correct endpoint.
    }
    onCfg_providerNameChanged: {
        loadWalletKey();
        refreshAvailableModels();
        ensureModelsLoaded(false);
    }

    function applyAdapterDefaults(apiType) {
        var presets = Api.getPresets(apiType) || [];
        var pick = null;
        // For OpenAI-compatible, restore the last selected provider if we have one.
        if (apiType === "openai" && cfg_openaiLastProvider && cfg_openaiLastProvider.length > 0) {
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
    }

    Kirigami.FormLayout {
        anchors.fill: parent

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

        QQC2.ComboBox {
            id: endpointPreset
            Kirigami.FormData.label: i18n("Provider:")
            Layout.fillWidth: true
            visible: caps.providerPresets === true
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
            onActivated: function(index) {
                if (index > 0) {
                    var preset = presetEndpoints[index];
                    apiEndpointField.text = preset.url;
                    cfg_providerName = preset.name;
                    cfg_usesResponsesAPI = !!preset.usesResponsesAPI;
                    rememberOpenAIChoice(preset.name, preset.url);
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

        RowLayout {
            Kirigami.FormData.label: i18n("Model:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: modelCombo
                Layout.fillWidth: true
                // Prepend the persisted model name when it isn't in the fetched
                // list so it stays selectable (initial load, stale value, etc.).
                readonly property var displayModels: {
                    var list = availableModels.slice();
                    if (cfg_modelName && cfg_modelName.length > 0 && list.indexOf(cfg_modelName) === -1) {
                        list.unshift(cfg_modelName);
                    }
                    return list;
                }
                model: displayModels
                enabled: displayModels.length > 0 && !fetchInProgress
                onDisplayModelsChanged: {
                    var idx = displayModels.indexOf(cfg_modelName);
                    currentIndex = idx >= 0 ? idx : 0;
                }
                onActivated: {
                    cfg_modelName = currentText;
                }
            }

            QQC2.Button {
                icon.name: "view-refresh"
                visible: caps.fetchModels === true
                enabled: !fetchInProgress
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: fetchInProgress ? i18n("Refreshing…") : i18n("Refresh model list")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 300
                onClicked: ensureModelsLoaded(true)
            }
        }

        QQC2.Label {
            id: fetchStatusLabel
            visible: false
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        RowLayout {
            Kirigami.FormData.label: i18n("API Key:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: apiKeyField
                Layout.fillWidth: true
                placeholderText: i18n("Optional - for OpenAI, etc.")
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
                onValueChanged: cfg_temperature = value
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
            onValueModified: cfg_maxTokens = value
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
                cfg_reasoningEffort = efforts[index];
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
            onValueModified: cfg_thinkingBudget = value
            // Anthropic gates thinking on reasoningEffort != "off"; Gemini uses
            // the budget directly so the spinbox is always enabled there.
            enabled: !caps.reasoningEffort || cfg_reasoningEffort !== "off"
        }

        QQC2.Label {
            Layout.fillWidth: true
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
            onCheckedChanged: cfg_showThoughts = checked

            QQC2.ToolTip.text: i18n("When enabled, the model's reasoning is shown above each reply with a collapsible header. Round-trip of signed thoughts to the API still happens regardless of this setting.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.CheckBox {
            id: usesResponsesAPICheckBox
            text: i18n("Use Responses API")
            visible: cfg_apiType === "openai"
            checked: cfg_usesResponsesAPI
            onCheckedChanged: cfg_usesResponsesAPI = checked

            QQC2.ToolTip.text: i18n("Required to surface reasoning content on OpenAI / Poe / OpenRouter / Azure (POSTs to /v1/responses instead of /v1/chat/completions). Auto-set when picking a preset.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Chat Spacing: %1px", Math.round(chatSpacingSlider.value))
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Slider {
                id: chatSpacingSlider
                Layout.fillWidth: true
                from: 2
                to: 24
                stepSize: 1
                value: cfg_chatSpacing
                onValueChanged: cfg_chatSpacing = value
            }

            RowLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    text: i18n("Compact")
                    font: Kirigami.Theme.smallFont
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    text: i18n("Spacious")
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Appearance:")
            text: i18n("Show provider and model in title")
            checked: cfg_showProviderInTitle
            onCheckedChanged: cfg_showProviderInTitle = checked
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
            onCheckedChanged: cfg_saveChatHistory = checked

            QQC2.ToolTip.text: i18n("Saves to ~/PlasmaLLM/chats/")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.ComboBox {
            id: chatSaveFormatCombo
            Kirigami.FormData.label: i18n("Save format:")
            model: [i18n("Plain text (.txt)"), i18n("Structured (.jsonl)")]
            enabled: cfg_saveChatHistory
            currentIndex: cfg_chatSaveFormat === "jsonl" ? 1 : 0
            onCurrentIndexChanged: cfg_chatSaveFormat = currentIndex === 1 ? "jsonl" : "txt"
        }

        QQC2.Label {
            text: i18n("Saves to ~/PlasmaLLM/chats/")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }

        QQC2.ButtonGroup { id: autoClearGroup }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Auto-clear:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.RadioButton {
                text: i18n("Disabled")
                QQC2.ButtonGroup.group: autoClearGroup
                checked: cfg_autoClearMode === 0
                onClicked: cfg_autoClearMode = 0
            }
            QQC2.RadioButton {
                text: i18n("Instant (always clear when panel opens)")
                QQC2.ButtonGroup.group: autoClearGroup
                checked: cfg_autoClearMode === 1
                onClicked: cfg_autoClearMode = 1
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                QQC2.RadioButton {
                    id: timedRadio
                    text: i18n("After")
                    QQC2.ButtonGroup.group: autoClearGroup
                    checked: cfg_autoClearMode === 2 || cfg_autoClearMode === 3
                    onClicked: cfg_autoClearMode = (unitCombo.currentIndex === 0 ? 2 : 3)
                }
                QQC2.SpinBox {
                    from: 1
                    to: unitCombo.currentIndex === 0 ? 3600 : 1440
                    value: unitCombo.currentIndex === 0 ? cfg_autoClearSeconds : cfg_autoClearMinutes
                    enabled: timedRadio.checked
                    onValueModified: {
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
                    onActivated: cfg_autoClearMode = (currentIndex === 0 ? 2 : 3)
                }
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        QQC2.CheckBox {
            id: autoShareCheckBox
            Kirigami.FormData.label: i18n("Commands:")
            text: i18n("Auto-share command output with LLM")
            checked: cfg_autoShareCommandOutput
            onCheckedChanged: cfg_autoShareCommandOutput = checked

            QQC2.ToolTip.text: i18n("Automatically send Run command results back to the LLM")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.CheckBox {
            id: autoRunCheckBox
            text: i18n("Auto-run commands from LLM")
            checked: cfg_autoRunCommands
            onCheckedChanged: cfg_autoRunCommands = checked

            QQC2.ToolTip.text: i18n("WARNING: When combined with Auto-share, enables agentic workflow. Only use with very trustworthy LLMs.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.CheckBox {
            id: useCommandToolCheckBox
            text: i18n("Use tool calling for commands")
            checked: cfg_useCommandTool
            onCheckedChanged: cfg_useCommandTool = checked

            QQC2.ToolTip.text: i18n("Use the run_command tool for command execution. Disable for models that don't support tool calling (falls back to code block parsing).")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.Label {
            visible: autoShareCheckBox.checked && autoRunCheckBox.checked
            text: i18n("⚠️ DANGER: Both options enabled - the LLM can now execute commands and see their output, enabling an agentic workflow. Only use with trustworthy LLMs.")
            wrapMode: Text.Wrap
            Layout.preferredWidth: 300
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Web Search:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: ollamaApiKeyField
                Layout.fillWidth: true
                placeholderText: i18n("Ollama API key for web search")
                echoMode: TextInput.Password
                text: walletOllamaKeyLoaded ? walletOllamaKey : cfg_ollamaApiKey
                onTextChanged: {
                    if (walletOllamaKeyLoaded) {
                        walletOllamaKeyDirty = (text !== walletOllamaKey);
                    }
                }
                onEditingFinished: {
                    if (walletOllamaKeyDirty) saveWalletOllamaKey();
                }
            }

            QQC2.Button {
                text: walletOllamaSaveInProgress ? i18n("Saving…") :
                      !walletOllamaKeyDirty ? i18n("Saved") :
                      !walletAvailable ? i18n("Save to Config (Insecure)") : i18n("Save Key")
                icon.name: !walletOllamaKeyDirty ? "dialog-ok-apply" : "document-save"
                enabled: walletOllamaKeyDirty && !walletOllamaSaveInProgress
                onClicked: saveWalletOllamaKey()
            }
        }

        QQC2.Label {
            text: i18n("Enables LLM-triggered web searches via Ollama's search API")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

    }
}
