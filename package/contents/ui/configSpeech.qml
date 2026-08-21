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
import "stt.js" as Stt
import "profiles.js" as Profiles

BaseConfigPage {
    id: configPage

    title: i18n("Speech to Text")

    property var availableModels: []
    property bool fetchInProgress: false
    property string walletApiKey: ""
    property bool walletKeyLoaded: false
    property bool walletAvailable: false
    property bool walletKeyDirty: false
    property string lastKeySlot: ""
    property int _sttKeyGen: 0
    property bool cliTestInProgress: false
    property bool cliCacheCheckInProgress: false
    property string cliCacheStatus: ""
    property int _cacheGen: 0
    property string cliCudaStatus: ""
    property int _cudaGen: 0

    readonly property var sttPresets: Stt.providerPresets()
    readonly property var sttBackends: Stt.backendChoices()
    readonly property bool isCliBackend: (cfg_sttBackend || "") === "whisper_cli"

    P5Support.DataSource {
        id: whisperCacheCheck
        engine: "executable"
        connectedSources: []
        property string pendingModel: ""
        property int pendingGen: 0
        onNewData: function(source, data) {
            var exitCode = data["exit code"];
            if (exitCode === undefined)
                return;
            disconnectSource(source);
            var model = pendingModel;
            var gen = pendingGen;
            if (gen !== configPage._cacheGen)
                return;
            cliCacheCheckInProgress = false;
            pendingModel = "";
            var stdout = ((data.stdout || "") + "").replace(/^\s+|\s+$/g, "");
            if (stdout.indexOf("DOWNLOADED") === 0) {
                cliCacheStatus = i18n("Model “%1” is on disk.", model);
            } else {
                var hint = Stt.whisperDownloadSizeHint(model);
                if (hint && hint.length)
                    cliCacheStatus = i18n("Model “%1” is not downloaded. The first transcription will fetch it (%2) into ~/.cache/whisper and can take a long time.", model, hint);
                else
                    cliCacheStatus = i18n("Model “%1” is not downloaded. The first transcription will fetch it into ~/.cache/whisper and can take a long time.", model);
            }
        }
    }

    P5Support.DataSource {
        id: whisperCudaCheck
        engine: "executable"
        connectedSources: []
        property int pendingGen: 0
        onNewData: function(source, data) {
            var exitCode = data["exit code"];
            if (exitCode === undefined)
                return;
            disconnectSource(source);
            if (pendingGen !== configPage._cudaGen)
                return;
            var stdout = ((data.stdout || "") + "").replace(/^\s+|\s+$/g, "");
            if (exitCode === 0 && stdout.indexOf("1") === 0)
                cliCudaStatus = i18n("CUDA is available to Whisper.");
            else
                cliCudaStatus = i18n("CUDA is not available in this Whisper environment. Use cpu or Default.");
        }
    }

    P5Support.DataSource {
        id: whisperTest
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var exitCode = data["exit code"];
            if (exitCode === undefined)
                return;
            disconnectSource(source);
            cliTestInProgress = false;
            var stderr = (data.stderr || "").replace(/^\s+|\s+$/g, "");
            var stdout = (data.stdout || "").replace(/^\s+|\s+$/g, "");
            if (exitCode === 0) {
                statusLabel.text = i18n("Whisper CLI responded to --help.");
            } else {
                var detail = stderr || stdout || "";
                if (detail.length > 240)
                    detail = detail.substring(0, 240);
                if (detail.length)
                    statusLabel.text = i18n("Whisper CLI test failed (exit %1): %2", exitCode, detail);
                else
                    statusLabel.text = i18n("Whisper CLI test failed (exit %1). Check the command.", exitCode);
            }
            statusLabel.visible = true;
        }
    }

    function currentSttSlot() {
        return Api.sttKeySlot(cfg_sttProviderName, cfg_sttApiEndpoint);
    }

    function readFallbackMap() {
        return WalletCore.parseFallbackMap(cfg_apiKeysFallback);
    }

    function fallbackKeyFor(slot) {
        return WalletCore.lookupFallback(readFallbackMap(),
            [slot].concat(Api.sttLegacyKeySlots(cfg_sttProviderName, cfg_sttApiEndpoint)), "");
    }

    function writeFallbackKey(slot, key) {
        cfg_apiKeysFallback = WalletCore.stringifyFallbackMap(
            WalletCore.putFallback(readFallbackMap(), slot, key));
    }

    function loadWalletKey() {
        var myGen = ++_sttKeyGen;
        var slot = currentSttSlot();
        lastKeySlot = slot;
        walletKeyLoaded = false;

        function applyKey(key) {
            if (myGen !== _sttKeyGen || slot !== currentSttSlot())
                return;
            walletApiKey = key || "";
            walletKeyLoaded = true;
            if (apiKeyField)
                apiKeyField.text = walletApiKey;
            walletKeyDirty = false;
        }

        Wallet.readKey(DBus, slot, Api.sttLegacyKeySlots(cfg_sttProviderName, cfg_sttApiEndpoint),
            readFallbackMap(), "",
            function(res) {
                if (myGen !== _sttKeyGen || slot !== currentSttSlot())
                    return;
                walletAvailable = !!(res && res.available);
                applyKey(res ? res.key : fallbackKeyFor(slot));
            }
        );
    }

    function saveWalletKey() {
        var slot = currentSttSlot();
        var key = apiKeyField ? apiKeyField.text.replace(/^\s+|\s+$/g, "") : "";
        walletApiKey = key;
        walletKeyDirty = false;

        // The plaintext config copy is written only when KWallet could not
        // store the key, and scrubbed when it could.
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
        for (var i = 0; i < sttPresets.length; i++) {
            if (sttPresets[i].name === cfg_sttProviderName) {
                idx = i;
                break;
            }
        }
        // If endpoint matches a preset URL, select it
        if (!cfg_sttProviderName || cfg_sttProviderName.length === 0) {
            for (var j = 0; j < sttPresets.length; j++) {
                if (sttPresets[j].url && sttPresets[j].url === cfg_sttApiEndpoint) {
                    idx = j;
                    cfg_sttProviderName = sttPresets[j].name;
                    break;
                }
            }
        }
        if (providerCombo.currentIndex !== idx)
            providerCombo.currentIndex = idx;
    }

    function syncModelCombo() {
        if (modelPicker)
            modelPicker.syncIndex();
    }

    function loadModelCache() {
        availableModels = [];
        if (cfg_sttAvailableModels && cfg_sttAvailableModels.length > 0) {
            try {
                var arr = JSON.parse(cfg_sttAvailableModels);
                if (Array.isArray(arr))
                    availableModels = arr;
            } catch (e) {}
        }
        syncModelCombo();
    }

    function syncBackendCombo() {
        var id = cfg_sttBackend || "openai_transcriptions";
        var idx = 0;
        for (var i = 0; i < sttBackends.length; i++) {
            if (sttBackends[i].id === id) {
                idx = i;
                break;
            }
        }
        if (backendCombo.currentIndex !== idx)
            backendCombo.currentIndex = idx;
    }

    function applyCliModelList() {
        Stt.fetchModels("", "", "whisper_cli", function(err, models) {
            availableModels = models || [];
            if (!cfg_sttModelName || cfg_sttModelName.length === 0
                    || availableModels.indexOf(cfg_sttModelName) === -1) {
                cfg_sttModelName = "base";
            }
            syncModelCombo();
            checkWhisperCache(cfg_sttModelName);
        });
    }

    function checkWhisperCache(model) {
        if (!isCliBackend) {
            cliCacheStatus = "";
            return;
        }
        var id = (model || cfg_sttModelName || "").replace(/^\s+|\s+$/g, "");
        if (!id.length) {
            cliCacheStatus = "";
            return;
        }
        var cmd = Stt.whisperCacheCheckCommand(id);
        if (!cmd || cmd.length === 0) {
            cliCacheStatus = "";
            return;
        }
        var myGen = ++_cacheGen;
        cliCacheCheckInProgress = true;
        cliCacheStatus = i18n("Checking whether “%1” is downloaded…", id);
        whisperCacheCheck.pendingModel = id;
        whisperCacheCheck.pendingGen = myGen;
        whisperCacheCheck.connectSource(cmd);
    }

    function checkWhisperCuda() {
        if (!isCliBackend || (cfg_sttCliDevice || "") !== "cuda") {
            cliCudaStatus = "";
            return;
        }
        var cmd = Stt.whisperCudaCheckCommand(cfg_sttCliBinary || "whisper");
        if (!cmd || cmd.length === 0) {
            cliCudaStatus = "";
            return;
        }
        var myGen = ++_cudaGen;
        cliCudaStatus = i18n("Checking CUDA…");
        whisperCudaCheck.pendingGen = myGen;
        whisperCudaCheck.connectSource(cmd);
    }

    function applyBackend(index) {
        if (!_initialized) return;
        var choice = sttBackends[index];
        if (!choice) return;
        cfg_sttBackend = choice.id;
        if (choice.id === "whisper_cli") {
            if (!cfg_sttCliBinary || cfg_sttCliBinary.length === 0)
                cfg_sttCliBinary = "whisper";
            applyCliModelList();
        } else {
            loadModelCache();
            cliCacheStatus = "";
        }
    }

    function testWhisperCli() {
        if (cliTestInProgress)
            return;
        var prefix = (cfg_sttCliBinary || "whisper").replace(/^\s+|\s+$/g, "") || "whisper";
        cliTestInProgress = true;
        statusLabel.text = i18n("Testing Whisper CLI…");
        statusLabel.visible = true;
        whisperTest.connectSource(prefix + " --help");
    }

    function fetchModels() {
        if (fetchInProgress)
            return;
        if (isCliBackend) {
            applyCliModelList();
            statusLabel.text = i18n("Loaded %1 STT model(s).", availableModels.length);
            statusLabel.visible = true;
            return;
        }
        var endpoint = (cfg_sttApiEndpoint || "").replace(/\/+$/, "");
        if (!endpoint) {
            statusLabel.text = i18n("Set an API endpoint first.");
            statusLabel.visible = true;
            return;
        }
        fetchInProgress = true;
        statusLabel.text = i18n("Fetching STT models…");
        statusLabel.visible = true;
        var key = walletApiKey || (apiKeyField ? apiKeyField.text : "") || "";
        Stt.fetchModels(endpoint, key, cfg_sttBackend || "openai_transcriptions", function(err, models) {
            fetchInProgress = false;
            if (err) {
                statusLabel.text = err;
                statusLabel.visible = true;
                return;
            }
            availableModels = models || [];
            cfg_sttAvailableModels = JSON.stringify(availableModels);
            if (cfg_sttModelName && availableModels.indexOf(cfg_sttModelName) === -1) {
                // keep selection; combo will prepend it
            } else if ((!cfg_sttModelName || cfg_sttModelName.length === 0) && availableModels.length > 0) {
                cfg_sttModelName = availableModels[0];
            }
            syncModelCombo();
            statusLabel.text = i18n("Loaded %1 STT model(s).", availableModels.length);
            statusLabel.visible = true;
        });
    }

    function applyProvider(index) {
        if (!_initialized) return;
        var preset = sttPresets[index];
        if (!preset) return;
        cfg_sttProviderName = preset.name;
        if (preset.url && preset.url.length > 0)
            cfg_sttApiEndpoint = preset.url;
        loadWalletKey();
    }

    // One-time migration: old design pointed sttProfileId at a chat profile.
    function migrateFromChatProfileIfNeeded() {
        if (cfg_sttMigratedFromProfile)
            return;
        if (cfg_sttApiEndpoint && cfg_sttApiEndpoint.length > 0) {
            cfg_sttMigratedFromProfile = true;
            return;
        }
        if (!cfg_sttProfileId || cfg_sttProfileId.length === 0) {
            cfg_sttMigratedFromProfile = true;
            return;
        }
        var profiles = Profiles.loadProfilesRaw(cfg_profiles);
        var p = Profiles.getActive(profiles, cfg_sttProfileId);
        if (p) {
            cfg_sttProviderName = p.providerName || "";
            cfg_sttApiEndpoint = p.apiEndpoint || "";
            cfg_sttModelName = p.modelName || "";
            if (cfg_sttApiEndpoint && cfg_sttModelName)
                cfg_sttEnabled = true;
        }
        cfg_sttMigratedFromProfile = true;
    }

    Component.onCompleted: {
        migrateFromChatProfileIfNeeded();
        if (!cfg_sttBackend || cfg_sttBackend.length === 0)
            cfg_sttBackend = "openai_transcriptions";
        if (isCliBackend) {
            applyCliModelList();
        } else {
            loadModelCache();
            cliCacheStatus = "";
        }
        syncProviderCombo();
        syncBackendCombo();
        loadWalletKey();
        Qt.callLater(function() {
            _initialized = true;
            if (isCliBackend)
                checkWhisperCuda();
        });
    }

    onCfg_sttBackendChanged: {
        if (!_initialized) return;
        syncBackendCombo();
        if (isCliBackend) {
            applyCliModelList();
        } else {
            loadModelCache();
            cliCacheStatus = "";
            cliCudaStatus = "";
        }
    }
    onCfg_sttCliBinaryChanged: if (_initialized && isCliBackend) checkWhisperCuda()
    onCfg_sttCliDeviceChanged: if (_initialized) checkWhisperCuda()
    onCfg_sttProviderNameChanged: if (_initialized) syncProviderCombo()
    onCfg_sttApiEndpointChanged: {
        if (!_initialized) return;
        // Reload key for new slot when endpoint identity changes
        loadWalletKey();
    }
    onCfg_sttModelNameChanged: {
        if (_initialized) {
            syncModelCombo();
            if (isCliBackend)
                checkWhisperCache(cfg_sttModelName);
        }
    }
    onCfg_sttAvailableModelsChanged: if (_initialized) loadModelCache()

    Kirigami.FormLayout {
        // Prefer shrink-to-fit inside the Plasma config dialog; long combo
        // model strings must not force the window wider than the shell allows.
        width: Math.min(parent.width, Kirigami.Units.gridUnit * 32)
        Layout.maximumWidth: Kirigami.Units.gridUnit * 32

        QQC2.CheckBox {
            id: enableCheck
            Kirigami.FormData.label: i18n("Voice input:")
            text: i18n("Enable microphone input")
            checked: cfg_sttEnabled
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_sttEnabled = checked;
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            text: i18n("Configures the speech-to-text engine only. Transcripts use your active chat profile (General).")
        }

        QQC2.ComboBox {
            id: micModeCombo
            Kirigami.FormData.label: i18n("Mic button:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            // Short labels keep the FormLayout narrow; details live in help text.
            model: [
                i18n("Auto"),
                i18n("Hold to talk"),
                i18n("Toggle")
            ]
            readonly property var modeIds: ["auto", "hold", "toggle"]
            currentIndex: {
                var m = cfg_sttMicMode || "auto";
                var i = modeIds.indexOf(m);
                return i >= 0 ? i : 0;
            }
            onActivated: function(index) {
                if (!_initialized) return;
                cfg_sttMicMode = modeIds[index] || "auto";
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Auto: click toggles recording; hold 250 ms+ for push-to-talk. Hold: press-and-hold only. Toggle: click to start/stop.")
        }

        KeySequenceItem {
            id: sttShortcutItem
            Kirigami.FormData.label: i18n("Voice shortcut:")
            // Require a modifier so the binding does not fight typing in the input field.
            patterns: ShortcutPattern.Modifier | ShortcutPattern.ModifierAndKey
            keySequence: cfg_sttPanelShortcut || ""
            onKeySequenceModified: {
                if (!_initialized) return;
                var seq = keySequence;
                cfg_sttPanelShortcut = (seq === undefined || seq === null) ? "" : ("" + seq);
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("While PlasmaLLM is open and focused, uses the same mic mode as the button (auto: short press toggles, hold 250 ms+ is push-to-talk). Does not open the panel—use Activate widget on the Shortcuts page. Default: Ctrl+M. Clear to disable.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Transcriber")
            Layout.fillWidth: true
        }

        QQC2.ComboBox {
            id: backendCombo
            Kirigami.FormData.label: i18n("STT backend:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            model: sttBackends.map(function(b) { return b.name; })
            onActivated: function(index) {
                applyBackend(index);
            }
        }

        QQC2.ComboBox {
            id: providerCombo
            visible: !isCliBackend
            Kirigami.FormData.label: i18n("Provider:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            model: sttPresets.map(function(p) { return p.name; })
            onActivated: function(index) {
                applyProvider(index);
            }
        }

        QQC2.TextField {
            id: endpointField
            visible: !isCliBackend
            Kirigami.FormData.label: i18n("Endpoint:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            placeholderText: "https://openrouter.ai/api/v1"
            text: cfg_sttApiEndpoint
            onTextChanged: {
                if (!_initialized) return;
                cfg_sttApiEndpoint = text;
            }
            onEditingFinished: {
                if (!_initialized) return;
                // Custom typing: mark provider Custom if URL no longer matches a preset
                var matched = false;
                for (var i = 0; i < sttPresets.length; i++) {
                    if (sttPresets[i].url && sttPresets[i].url === cfg_sttApiEndpoint) {
                        cfg_sttProviderName = sttPresets[i].name;
                        matched = true;
                        break;
                    }
                }
                if (!matched && cfg_sttApiEndpoint.length > 0)
                    cfg_sttProviderName = "Custom";
                syncProviderCombo();
                loadWalletKey();
            }
        }

        ModelPicker {
            id: modelPicker
            Kirigami.FormData.label: i18n("Model:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            modelName: cfg_sttModelName
            availableModels: configPage.availableModels
            fetchInProgress: configPage.fetchInProgress
            fetchVisible: !isCliBackend
            fetchEnabled: !isCliBackend && !configPage.fetchInProgress && (cfg_sttApiEndpoint || "").length > 0
            fetchTooltip: i18n("Fetch STT models")
            onModelSelected: function(selected) {
                cfg_sttModelName = selected;
                rootItem.triggerCapture();
            }
            onFetchRequested: fetchModels()
        }

        QQC2.Label {
            visible: isCliBackend && cliCacheStatus.length > 0
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: cliCacheStatus
        }

        QQC2.Label {
            visible: !isCliBackend
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("OpenRouter lists STT models only via transcription modalities (this page does that).")
        }

        RowLayout {
            visible: !isCliBackend
            Kirigami.FormData.label: i18n("API key:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: apiKeyField
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.minimumWidth: Kirigami.Units.gridUnit * 8
                echoMode: TextInput.Password
                placeholderText: i18n("Provider API key")
                onTextChanged: {
                    if (!_initialized || !walletKeyLoaded) return;
                    walletKeyDirty = true;
                }
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

        QQC2.TextField {
            id: cliBinaryField
            visible: isCliBackend
            Kirigami.FormData.label: i18n("Command:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            placeholderText: "whisper"
            text: cfg_sttCliBinary
            onTextChanged: {
                if (!_initialized) return;
                cfg_sttCliBinary = text;
            }
        }

        QQC2.Label {
            visible: isCliBackend
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Command prefix, inserted as-is. Examples: whisper, python3 -m whisper, toolbox run whisper.")
        }

        RowLayout {
            visible: isCliBackend
            Kirigami.FormData.label: i18n("Test:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Test CLI")
                icon.name: "dialog-ok-apply"
                enabled: !cliTestInProgress
                onClicked: testWhisperCli()
            }
        }

        QQC2.ComboBox {
            id: cliTaskCombo
            visible: isCliBackend
            Kirigami.FormData.label: i18n("Task:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            model: [i18n("Transcribe"), i18n("Translate")]
            readonly property var taskIds: ["transcribe", "translate"]
            currentIndex: {
                var t = cfg_sttCliTask || "transcribe";
                var i = taskIds.indexOf(t);
                return i >= 0 ? i : 0;
            }
            onActivated: function(index) {
                if (!_initialized) return;
                cfg_sttCliTask = taskIds[index] || "transcribe";
            }
        }

        QQC2.ComboBox {
            id: cliDeviceCombo
            visible: isCliBackend
            Kirigami.FormData.label: i18n("Device:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            model: [i18n("Default"), "cpu", "cuda"]
            readonly property var deviceIds: ["", "cpu", "cuda"]
            currentIndex: {
                var d = cfg_sttCliDevice || "";
                var i = deviceIds.indexOf(d);
                return i >= 0 ? i : 0;
            }
            onActivated: function(index) {
                if (!_initialized) return;
                cfg_sttCliDevice = deviceIds[index] || "";
            }
        }

        QQC2.Label {
            visible: isCliBackend && cliCudaStatus.length > 0
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.85
            text: cliCudaStatus
        }

        QQC2.CheckBox {
            id: cliFp16Check
            visible: isCliBackend
            Kirigami.FormData.label: i18n("FP16:")
            text: i18n("Use --fp16 True (GPU)")
            checked: cfg_sttCliFp16
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_sttCliFp16 = checked;
            }
        }

        QQC2.SpinBox {
            id: cliThreadsSpin
            visible: isCliBackend
            Kirigami.FormData.label: i18n("Threads:")
            from: 0
            to: 64
            value: cfg_sttCliThreads >= 0 ? cfg_sttCliThreads : 0
            onValueModified: {
                if (!_initialized) return;
                cfg_sttCliThreads = value;
            }
        }

        QQC2.Label {
            visible: isCliBackend
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("0 omits --threads (Whisper default). FP16 off is safer on CPU.")
        }

        QQC2.TextField {
            id: cliPromptField
            visible: isCliBackend
            Kirigami.FormData.label: i18n("Initial prompt:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            placeholderText: i18n("Optional vocabulary / style hint")
            text: cfg_sttCliInitialPrompt
            onTextChanged: {
                if (!_initialized) return;
                cfg_sttCliInitialPrompt = text;
            }
        }

        QQC2.TextField {
            id: cliExtraField
            visible: isCliBackend
            Kirigami.FormData.label: i18n("Extra args:")
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            placeholderText: i18n("Optional, appended as-is")
            text: cfg_sttCliExtraArgs
            onTextChanged: {
                if (!_initialized) return;
                cfg_sttCliExtraArgs = text;
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Options")
            Layout.fillWidth: true
        }

        QQC2.TextField {
            id: languageField
            Kirigami.FormData.label: i18n("Language hint:")
            Layout.fillWidth: true
            placeholderText: i18n("Optional, e.g. en or ja (empty = auto)")
            text: cfg_sttLanguage
            onTextChanged: {
                if (!_initialized) return;
                cfg_sttLanguage = text;
            }
        }

        QQC2.SpinBox {
            id: maxSecondsSpin
            Kirigami.FormData.label: i18n("Max recording (seconds):")
            from: 5
            to: 300
            value: cfg_sttMaxSeconds > 0 ? cfg_sttMaxSeconds : 60
            onValueModified: {
                if (!_initialized) return;
                cfg_sttMaxSeconds = value;
            }
        }

        QQC2.Label {
            id: statusLabel
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            visible: false
            opacity: 0.9
        }
    }
}
