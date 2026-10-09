/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils
import org.kde.kquickcontrols
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.plasma5support as P5Support

import "api.js" as Api
import "wallet.js" as Wallet
import "walletCore.js" as WalletCore
import "tts.js" as Tts
import "profiles.js" as Profiles

BaseConfigPage {
    id: configPage

    title: i18n("Text to Speech")

    property var availableModels: []
    property bool fetchInProgress: false
    property string walletApiKey: ""
    property bool walletKeyLoaded: false
    property bool walletAvailable: false
    property bool walletKeyDirty: false
    property string lastKeySlot: ""
    property int _ttsKeyGen: 0
    property bool testInProgress: false
    property string testStatusText: ""

    readonly property var ttsPresets: Tts.providerPresets()
    readonly property var ttsBackends: Tts.backendChoices()
    readonly property bool isSpdBackend: (cfg_ttsBackend || "spd_say") === "spd_say"
    readonly property bool isEndpointBackend: (cfg_ttsBackend || "") === "openai_speech"
    readonly property bool isCustomBackend: (cfg_ttsBackend || "") === "custom_cli"

    P5Support.DataSource {
        id: ttsTestRunner
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var exitCode = data["exit code"];
            if (exitCode === undefined)
                return;
            disconnectSource(source);
            testInProgress = false;
            var stderr = (data.stderr || "").replace(/^\s+|\s+$/g, "");
            var stdout = (data.stdout || "").replace(/^\s+|\s+$/g, "");
            if (exitCode === 0) {
                statusLabel.text = i18n("Text-to-speech test completed successfully.");
            } else {
                var detail = stderr || stdout || "";
                if (detail.length > 240)
                    detail = detail.substring(0, 240);
                if (detail.length)
                    statusLabel.text = i18n("TTS test failed (exit %1): %2", exitCode, detail);
                else
                    statusLabel.text = i18n("TTS test failed (exit %1).", exitCode);
            }
            statusLabel.visible = true;
        }
    }

    function currentTtsSlot() {
        return Api.ttsKeySlot(cfg_ttsProviderName, cfg_ttsApiEndpoint);
    }

    function readFallbackMap() {
        return WalletCore.parseFallbackMap(cfg_apiKeysFallback);
    }

    function fallbackKeyFor(slot) {
        return WalletCore.lookupFallback(readFallbackMap(),
            [slot].concat(Api.ttsLegacyKeySlots(cfg_ttsProviderName, cfg_ttsApiEndpoint)), "");
    }

    function writeFallbackKey(slot, key) {
        cfg_apiKeysFallback = WalletCore.stringifyFallbackMap(
            WalletCore.putFallback(readFallbackMap(), slot, key));
    }

    function loadWalletKey() {
        var myGen = ++_ttsKeyGen;
        var slot = currentTtsSlot();
        lastKeySlot = slot;
        walletKeyLoaded = false;

        function applyKey(key, sourceMsg) {
            if (myGen !== _ttsKeyGen || slot !== currentTtsSlot())
                return;
            walletApiKey = key || "";
            walletKeyLoaded = true;
            if (apiKeyField)
                apiKeyField.text = walletApiKey;
            walletKeyDirty = false;
            if (sourceMsg) {
                statusLabel.text = sourceMsg;
                statusLabel.visible = true;
            }
        }

        Wallet.readKey(DBus, slot, Api.ttsLegacyKeySlots(cfg_ttsProviderName, cfg_ttsApiEndpoint),
            readFallbackMap(), "",
            function(res) {
                if (myGen !== _ttsKeyGen || slot !== currentTtsSlot())
                    return;
                walletAvailable = !!(res && res.available);
                var key = (res && res.key) ? res.key : fallbackKeyFor(slot);
                if (key && key.length > 0) {
                    applyKey(key);
                    return;
                }

                // If no key saved for TTS, automatically reuse existing key from STT
                var sttSlot = Api.sttKeySlot(cfg_ttsProviderName, cfg_ttsApiEndpoint);
                Wallet.readKey(DBus, sttSlot, Api.sttLegacyKeySlots(cfg_ttsProviderName, cfg_ttsApiEndpoint),
                    readFallbackMap(), "",
                    function(sttRes) {
                        if (myGen !== _ttsKeyGen || slot !== currentTtsSlot())
                            return;
                        var sttKey = (sttRes && sttRes.key) ? sttRes.key : WalletCore.lookupFallback(readFallbackMap(), [sttSlot], "");
                        if (sttKey && sttKey.length > 0) {
                            applyKey(sttKey, i18n("Reused API key from Speech to Text."));
                            // Persist to TTS slot in wallet
                            Wallet.writeKey(DBus, slot, sttKey, function() {});
                            return;
                        }

                        // Check chat profiles for matching provider/endpoint
                        var profiles = Profiles.loadProfilesRaw(cfg_profiles);
                        var checkList = [];
                        var activeP = Profiles.getActive(profiles, cfg_activeProfileId);
                        if (activeP) checkList.push(activeP);
                        for (var i = 0; i < profiles.length; i++) {
                            if (!activeP || profiles[i].id !== activeP.id)
                                checkList.push(profiles[i]);
                        }

                        function checkNextProfile(idx) {
                            if (idx >= checkList.length) {
                                // Final check: single-slot fallback cfg_apiKey
                                if (cfg_apiKey && cfg_apiKey.length > 0 && cfg_ttsProviderName === "OpenRouter") {
                                    applyKey(cfg_apiKey, i18n("Reused API key from General settings."));
                                    Wallet.writeKey(DBus, slot, cfg_apiKey, function() {});
                                } else {
                                    applyKey("");
                                }
                                return;
                            }
                            var p = checkList[idx];
                            var matches = (p.providerName && p.providerName.toLowerCase() === (cfg_ttsProviderName || "").toLowerCase())
                                || (p.apiEndpoint && WalletCore.normalizeEndpoint(p.apiEndpoint) === WalletCore.normalizeEndpoint(cfg_ttsApiEndpoint));
                            if (matches) {
                                var cSlot = Api.chatKeySlot(p.id, p.apiType || "openai", p.providerName || "", p.apiEndpoint || "", null);
                                Wallet.readKey(DBus, cSlot, Api.legacyKeySlots(p.id, p.apiType || "openai", p.providerName || "", p.apiEndpoint || "", null),
                                    readFallbackMap(), "",
                                    function(chatRes) {
                                        if (myGen !== _ttsKeyGen || slot !== currentTtsSlot())
                                            return;
                                        var cKey = (chatRes && chatRes.key) ? chatRes.key : WalletCore.lookupFallback(readFallbackMap(), [cSlot], "");
                                        if (cKey && cKey.length > 0) {
                                            applyKey(cKey, i18n("Reused API key from Chat profile (%1).", p.name || p.providerName));
                                            Wallet.writeKey(DBus, slot, cKey, function() {});
                                        } else {
                                            checkNextProfile(idx + 1);
                                        }
                                    }
                                );
                            } else {
                                checkNextProfile(idx + 1);
                            }
                        }
                        checkNextProfile(0);
                    }
                );
            }
        );
    }

    function saveWalletKey() {
        var slot = currentTtsSlot();
        var key = apiKeyField ? apiKeyField.text.replace(/^\s+|\s+$/g, "") : "";
        walletApiKey = key;
        walletKeyDirty = false;

        Wallet.writeKey(DBus, slot, key, function(res) {
            if (res && res.available)
                walletAvailable = true;
            if (res && res.success) {
                cfg_apiKeysFallback = WalletCore.stringifyFallbackMap(
                    WalletCore.removeFallback(readFallbackMap(), slot));
                statusLabel.text = i18n("API key saved to KWallet.");
            } else {
                writeFallbackKey(slot, key);
                statusLabel.text = i18n("API key saved to local fallback.");
            }
            statusLabel.visible = true;
        });
    }

    function syncProviderCombo() {
        var idx = 0;
        for (var i = 0; i < ttsPresets.length; i++) {
            if (ttsPresets[i].name === cfg_ttsProviderName) {
                idx = i;
                break;
            }
        }
        if (!cfg_ttsProviderName || cfg_ttsProviderName.length === 0) {
            for (var j = 0; j < ttsPresets.length; j++) {
                if (ttsPresets[j].url && ttsPresets[j].url === cfg_ttsApiEndpoint) {
                    idx = j;
                    cfg_ttsProviderName = ttsPresets[j].name;
                    break;
                }
            }
        }
        if (providerCombo && providerCombo.currentIndex !== idx)
            providerCombo.currentIndex = idx;
    }

    function syncModelCombo() {
        if (modelPicker)
            modelPicker.syncIndex();
    }

    function loadModelCache() {
        availableModels = [];
        if (cfg_ttsAvailableModels && cfg_ttsAvailableModels.length > 0) {
            try {
                var arr = JSON.parse(cfg_ttsAvailableModels);
                if (Array.isArray(arr))
                    availableModels = arr;
            } catch (e) {}
        }
        if (!availableModels || availableModels.length === 0) {
            availableModels = Tts.defaultKnownModels();
        }
        syncModelCombo();
    }

    function fetchModels() {
        if (fetchInProgress)
            return;
        var endpoint = (cfg_ttsApiEndpoint || "").replace(/\/+$/, "");
        if (!endpoint) {
            statusLabel.text = i18n("Set an API endpoint first.");
            statusLabel.visible = true;
            return;
        }
        fetchInProgress = true;
        statusLabel.text = i18n("Fetching TTS models…");
        statusLabel.visible = true;
        var key = walletApiKey || (apiKeyField ? apiKeyField.text : "") || "";
        Tts.fetchModels(endpoint, key, cfg_ttsBackend || "openai_speech", function(err, models) {
            fetchInProgress = false;
            if (err) {
                statusLabel.text = err;
                statusLabel.visible = true;
                return;
            }
            availableModels = models || [];
            cfg_ttsAvailableModels = JSON.stringify(availableModels);
            if (cfg_ttsModelName && availableModels.indexOf(cfg_ttsModelName) === -1) {
                // keep selection; combo will prepend it
            } else if ((!cfg_ttsModelName || cfg_ttsModelName.length === 0) && availableModels.length > 0) {
                cfg_ttsModelName = availableModels[0];
            }
            syncModelCombo();
            syncVoiceCombo();
            statusLabel.text = i18n("Loaded %1 TTS model(s).", availableModels.length);
            statusLabel.visible = true;
        });
    }

    function applyProviderPreset(index) {
        if (index < 0 || index >= ttsPresets.length) return;
        var p = ttsPresets[index];
        cfg_ttsProviderName = p.name;
        if (p.url && p.url.length > 0)
            cfg_ttsApiEndpoint = p.url;
        if (p.model && p.model.length > 0)
            cfg_ttsModelName = p.model;
        if (p.voice && p.voice.length > 0)
            cfg_ttsVoice = p.voice;
        if (p.responseFormat && p.responseFormat.length > 0)
            cfg_ttsResponseFormat = p.responseFormat;
        loadWalletKey();
        syncModelCombo();
        syncVoiceCombo();
    }

    function syncBackendCombo() {
        var b = cfg_ttsBackend || "spd_say";
        for (var i = 0; i < ttsBackends.length; i++) {
            if (ttsBackends[i].id === b) {
                if (backendCombo && backendCombo.currentIndex !== i)
                    backendCombo.currentIndex = i;
                return;
            }
        }
        if (backendCombo)
            backendCombo.currentIndex = 0;
    }

    function applyBackend(index) {
        if (index < 0 || index >= ttsBackends.length) return;
        cfg_ttsBackend = ttsBackends[index].id;
        if (cfg_ttsBackend === "openai_speech") {
            loadWalletKey();
            syncProviderCombo();
            syncVoiceCombo();
        }
    }

    function syncVoiceCombo() {
        if (!voiceCombo) return;
        var isGemini = (cfg_ttsModelName || "").indexOf("gemini") >= 0;
        var list = isGemini ? Tts.knownGeminiVoices() : Tts.knownOpenAiVoices();
        voiceCombo.model = list;
        var cur = cfg_ttsVoice || (isGemini ? "Zephyr" : "alloy");
        var idx = list.indexOf(cur);
        voiceCombo.currentIndex = idx >= 0 ? idx : 0;
    }

    function runVoiceTest() {
        statusLabel.visible = false;
        testInProgress = true;
        var sample = i18n("Hello! Text to speech is working in PlasmaLLM.");
        var prepared = Tts.prepareTextForSpeech(sample, cfg_ttsStyleHint);

        var configObj = {
            ttsEnabled: true,
            ttsBackend: cfg_ttsBackend || "spd_say",
            ttsProviderName: cfg_ttsProviderName || "",
            ttsApiEndpoint: cfg_ttsApiEndpoint || "",
            ttsModelName: cfg_ttsModelName || "",
            ttsVoice: cfg_ttsVoice || "",
            ttsResponseFormat: cfg_ttsResponseFormat || "pcm",
            ttsRate: cfg_ttsRate || 0,
            ttsPitch: cfg_ttsPitch || 0,
            ttsLanguage: cfg_ttsLanguage || "",
            ttsCliBinary: cfg_ttsCliBinary || "spd-say",
            ttsCliTemplate: cfg_ttsCliTemplate || "",
            ttsCliExtraArgs: cfg_ttsCliExtraArgs || "",
            ttsStyleHint: cfg_ttsStyleHint || ""
        };

        var key = apiKeyField ? apiKeyField.text : walletApiKey;

        Tts.speak({
            config: configObj,
            text: sample,
            apiKey: key,
            runCommand: function(cmd, cb) {
                ttsTestRunner.connectSource(cmd);
            },
            callback: function(err, res) {
                if (err) {
                    testInProgress = false;
                    statusLabel.text = err;
                    statusLabel.visible = true;
                }
            }
        });
    }

    property bool _initialized: false
    Component.onCompleted: {
        loadModelCache();
        syncBackendCombo();
        syncProviderCombo();
        syncModelCombo();
        syncVoiceCombo();
        loadWalletKey();
        _initialized = true;
    }

    onCfg_ttsBackendChanged: if (_initialized) syncBackendCombo()
    onCfg_ttsProviderNameChanged: if (_initialized) syncProviderCombo()
    onCfg_ttsApiEndpointChanged: {
        if (!_initialized) return;
        var slot = currentTtsSlot();
        if (slot !== lastKeySlot)
            loadWalletKey();
    }
    onCfg_ttsModelNameChanged: {
        if (_initialized) {
            syncModelCombo();
            syncVoiceCombo();
        }
    }
    onCfg_ttsAvailableModelsChanged: if (_initialized) loadModelCache()

    Kirigami.FormLayout {
        width: Math.min(parent.width, Kirigami.Units.gridUnit * 32)
        Layout.maximumWidth: Kirigami.Units.gridUnit * 32

        QQC2.CheckBox {
            id: enableCheck
            Kirigami.FormData.label: i18n("Text to Speech:")
            text: i18n("Enable text-to-speech output")
            checked: cfg_ttsEnabled
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_ttsEnabled = checked;
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            text: i18n("Enables speech synthesis. Messages can be read aloud using the speaker button on chat responses.")
        }

        QQC2.CheckBox {
            id: autoReadCheck
            Kirigami.FormData.label: i18n("Auto-read:")
            text: i18n("Automatically read new assistant responses aloud")
            checked: cfg_ttsAutoRead
            enabled: cfg_ttsEnabled
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_ttsAutoRead = checked;
            }
        }

        QQC2.CheckBox {
            id: autoReadVoiceOnlyCheck
            text: i18n("Only auto-read when prompted with voice (STT)")
            checked: cfg_ttsAutoReadOnlyVoicePrompted
            enabled: cfg_ttsEnabled && cfg_ttsAutoRead
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_ttsAutoReadOnlyVoicePrompted = checked;
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("When 'Only when prompted with voice' is checked, typed prompts won't trigger audio playback, but voice-dictated questions will speak the answer back.")
        }

        QQC2.CheckBox {
            id: waitReadyCheck
            text: i18n("Don't output text until TTS is ready")
            checked: cfg_ttsWaitUntilReady
            enabled: cfg_ttsEnabled && cfg_ttsAutoRead
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_ttsWaitUntilReady = checked;
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Hides response text while generating and preparing audio, displaying the response only when speech is ready to play.")
        }

        QQC2.TextField {
            id: styleHintField
            Kirigami.FormData.label: i18n("Style / tone hint:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            placeholderText: i18n("e.g. <sarcastic>, [whispering], <excited>")
            text: cfg_ttsStyleHint || ""
            onTextChanged: {
                if (!_initialized) return;
                cfg_ttsStyleHint = text;
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Speech hint or tone directive (supported by Gemini and modern TTS endpoints). You can use tags like <sarcastic> or placeholders like [tone: sarcastic] {text}.")
        }

        QQC2.CheckBox {
            id: allowAgentStyleControlCheck
            text: i18n("Allow agent to set their own tone/style")
            checked: cfg_ttsAllowAgentStyleControl
            enabled: cfg_ttsEnabled
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_ttsAllowAgentStyleControl = checked;
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Exposes a tool allowing the assistant to dynamically adjust its speech style or emotion based on conversation context or user requests.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Synthesizer")
            Layout.fillWidth: true
        }

        QQC2.ComboBox {
            id: backendCombo
            Kirigami.FormData.label: i18n("TTS backend:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            model: ttsBackends.map(function(b) { return b.name; })
            onActivated: function(index) {
                applyBackend(index);
            }
        }

        // --- SPEECH DISPATCHER (LOCAL CLI) SECTION ---
        RowLayout {
            Kirigami.FormData.label: i18n("Speech rate:")
            visible: isSpdBackend
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22

            QQC2.Slider {
                id: rateSlider
                Layout.fillWidth: true
                from: -100
                to: 100
                stepSize: 5
                value: cfg_ttsRate || 0
                onMoved: {
                    if (!_initialized) return;
                    cfg_ttsRate = Math.round(value);
                }
            }

            QQC2.Label {
                text: (rateSlider.value > 0 ? "+" : "") + rateSlider.value + "%"
                font: Kirigami.Theme.smallFont
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Speech pitch:")
            visible: isSpdBackend
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22

            QQC2.Slider {
                id: pitchSlider
                Layout.fillWidth: true
                from: -100
                to: 100
                stepSize: 5
                value: cfg_ttsPitch || 0
                onMoved: {
                    if (!_initialized) return;
                    cfg_ttsPitch = Math.round(value);
                }
            }

            QQC2.Label {
                text: (pitchSlider.value > 0 ? "+" : "") + pitchSlider.value + "%"
                font: Kirigami.Theme.smallFont
            }
        }

        QQC2.TextField {
            id: spdVoiceField
            Kirigami.FormData.label: i18n("Voice name:")
            visible: isSpdBackend
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            placeholderText: i18n("Default or specific voice (spd-say -L)")
            text: cfg_ttsVoice || ""
            onTextChanged: {
                if (!_initialized) return;
                cfg_ttsVoice = text;
            }
        }

        QQC2.TextField {
            id: spdLangField
            Kirigami.FormData.label: i18n("Language hint:")
            visible: isSpdBackend
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            placeholderText: i18n("Optional ISO code, e.g. en, de, fr")
            text: cfg_ttsLanguage || ""
            onTextChanged: {
                if (!_initialized) return;
                cfg_ttsLanguage = text;
            }
        }

        // --- ENDPOINT (OPENROUTER / OPENAI) SECTION ---
        QQC2.ComboBox {
            id: providerCombo
            visible: isEndpointBackend
            Kirigami.FormData.label: i18n("Provider preset:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            model: ttsPresets.map(function(p) { return p.name; })
            onActivated: function(index) {
                applyProviderPreset(index);
            }
        }

        QQC2.TextField {
            id: endpointField
            visible: isEndpointBackend
            Kirigami.FormData.label: i18n("API Endpoint:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            text: cfg_ttsApiEndpoint || ""
            onTextChanged: {
                if (!_initialized) return;
                cfg_ttsApiEndpoint = text;
            }
        }

        RowLayout {
            visible: isEndpointBackend
            Kirigami.FormData.label: i18n("API key:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: apiKeyField
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.minimumWidth: Kirigami.Units.gridUnit * 8
                echoMode: showKeyCheck.checked ? TextInput.Normal : TextInput.Password
                placeholderText: i18n("Provider API key")
                onTextChanged: {
                    if (!_initialized || !walletKeyLoaded) return;
                    walletKeyDirty = true;
                }
                onAccepted: saveWalletKey()
            }

            QQC2.ToolButton {
                id: showKeyCheck
                checkable: true
                icon.name: checked ? "password-show-on" : "password-show-off"
                QQC2.ToolTip.text: i18n("Show/hide key")
                QQC2.ToolTip.visible: hovered
            }

            QQC2.Button {
                text: i18n("Save")
                icon.name: "document-save"
                display: QQC2.AbstractButton.TextBesideIcon
                onClicked: saveWalletKey()
                QQC2.ToolTip.text: i18n("Save API key")
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.visible: hovered
            }
        }

        ModelPicker {
            id: modelPicker
            visible: isEndpointBackend
            Kirigami.FormData.label: i18n("Model:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            modelName: cfg_ttsModelName
            availableModels: configPage.availableModels
            fetchInProgress: configPage.fetchInProgress
            fetchVisible: isEndpointBackend
            fetchEnabled: isEndpointBackend && !configPage.fetchInProgress && (cfg_ttsApiEndpoint || "").length > 0
            fetchTooltip: i18n("Fetch TTS models")
            onModelSelected: function(selected) {
                cfg_ttsModelName = selected;
                syncVoiceCombo();
                rootItem.triggerCapture();
            }
            onFetchRequested: fetchModels()
        }

        QQC2.ComboBox {
            id: voiceCombo
            visible: isEndpointBackend
            Kirigami.FormData.label: i18n("Voice:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            editable: true
            onActivated: function(index) {
                if (!_initialized) return;
                cfg_ttsVoice = currentText;
            }
            onEditTextChanged: {
                if (!_initialized) return;
                cfg_ttsVoice = editText;
            }
        }

        QQC2.ComboBox {
            id: formatCombo
            visible: isEndpointBackend
            Kirigami.FormData.label: i18n("Audio format:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            model: ["pcm", "mp3"]
            currentIndex: (cfg_ttsResponseFormat || "pcm") === "mp3" ? 1 : 0
            onActivated: function(index) {
                if (!_initialized) return;
                cfg_ttsResponseFormat = index === 1 ? "mp3" : "pcm";
            }
        }

        QQC2.Label {
            visible: isEndpointBackend && (cfg_ttsModelName || "").indexOf("gemini") >= 0
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Note: Gemini TTS requires 'pcm'. PlasmaLLM automatically converts the raw 24kHz stream into playable WAV audio.")
        }

        // --- CUSTOM CLI SECTION ---
        QQC2.TextField {
            id: customBinaryField
            visible: isCustomBackend
            Kirigami.FormData.label: i18n("Command / binary:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            placeholderText: i18n("e.g. espeak-ng, piper")
            text: cfg_ttsCliBinary || ""
            onTextChanged: {
                if (!_initialized) return;
                cfg_ttsCliBinary = text;
            }
        }

        QQC2.TextField {
            id: customTemplateField
            visible: isCustomBackend
            Kirigami.FormData.label: i18n("Command template:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            placeholderText: i18n("e.g. echo {text} | piper --model en.onnx --output_raw | pw-play -")
            text: cfg_ttsCliTemplate || ""
            onTextChanged: {
                if (!_initialized) return;
                cfg_ttsCliTemplate = text;
            }
        }

        QQC2.Label {
            visible: isCustomBackend
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Placeholders: {text} (quoted text), {voice} (voice identifier), {rate} (speech rate). If omitted, text is appended.")
        }

        // --- TEST BUTTON & STATUS ---
        RowLayout {
            Kirigami.FormData.label: i18n("Test:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Test Voice")
                icon.name: "audio-volume-high"
                enabled: !testInProgress
                onClicked: runVoiceTest()
            }

            QQC2.BusyIndicator {
                running: testInProgress
                visible: testInProgress
                Layout.preferredWidth: Kirigami.Units.gridUnit
                Layout.preferredHeight: Kirigami.Units.gridUnit
            }
        }

        QQC2.Label {
            id: statusLabel
            visible: false
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
        }
    }
}
