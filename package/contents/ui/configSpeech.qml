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

import "api.js" as Api
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

    readonly property var sttPresets: Stt.providerPresets()

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
                if (val !== null && val !== undefined && val.hasOwnProperty("value"))
                    val = val.value;
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
                        function(created) { callback(!!created); },
                        function(err) { callback(false); }
                    );
                }
            },
            function(err) { callback(false); }
        );
    }

    function currentSttSlot() {
        return Api.sttKeySlot(cfg_sttProviderName, cfg_sttApiEndpoint);
    }

    function readFallbackMap() {
        if (!cfg_apiKeysFallback || cfg_apiKeysFallback.length === 0) return {};
        try { return JSON.parse(cfg_apiKeysFallback) || {}; } catch (e) { return {}; }
    }

    function fallbackKeyFor(slot) {
        var m = readFallbackMap();
        if (m.hasOwnProperty(slot)) return m[slot] || "";
        return "";
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
                    console.warn("PlasmaLLM STT: wallet writePassword error:", err);
                    onDone(false);
                }
            );
        });
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

        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (myGen !== _sttKeyGen) {
                    if (handle >= 0)
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    return;
                }
                if (handle < 0) {
                    walletAvailable = false;
                    applyKey(fallbackKeyFor(slot));
                    return;
                }
                walletAvailable = true;
                walletCall("readPassword", [new DBus.int32(handle), "PlasmaLLM", slot, "PlasmaLLM"],
                    function(password) {
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                        if (password && password.length > 0)
                            applyKey(String(password).replace(/^\s+|\s+$/g, ""));
                        else
                            applyKey(fallbackKeyFor(slot));
                    },
                    function(err) {
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                        applyKey(fallbackKeyFor(slot));
                    }
                );
            },
            function(err) {
                walletAvailable = false;
                applyKey(fallbackKeyFor(slot));
            }
        );
    }

    function saveWalletKey() {
        var slot = currentSttSlot();
        var key = apiKeyField ? apiKeyField.text.replace(/^\s+|\s+$/g, "") : "";
        walletApiKey = key;
        walletKeyDirty = false;

        if (!walletAvailable) {
            writeFallbackKey(slot, key);
            statusLabel.text = i18n("API key saved to local fallback (KWallet unavailable).");
            statusLabel.visible = true;
            return;
        }

        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    writeFallbackKey(slot, key);
                    statusLabel.text = i18n("API key saved to local fallback (KWallet unavailable).");
                    statusLabel.visible = true;
                    return;
                }
                walletWriteKey(handle, slot, key, function(success) {
                    walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    if (success) {
                        statusLabel.text = i18n("API key saved to KWallet.");
                    } else {
                        writeFallbackKey(slot, key);
                        statusLabel.text = i18n("API key saved to local fallback.");
                    }
                    statusLabel.visible = true;
                });
            },
            function(err) {
                writeFallbackKey(slot, key);
                statusLabel.text = i18n("API key saved to local fallback.");
                statusLabel.visible = true;
            }
        );
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
        var list = modelCombo.displayModels;
        var name = cfg_sttModelName || "";
        var idx = list.indexOf(name);
        if (idx < 0)
            idx = 0;
        if (modelCombo.currentIndex !== idx)
            modelCombo.currentIndex = idx;
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

    function fetchModels() {
        if (fetchInProgress)
            return;
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
        loadModelCache();
        syncProviderCombo();
        loadWalletKey();
        Qt.callLater(function() {
            _initialized = true;
        });
    }

    onCfg_sttProviderNameChanged: if (_initialized) syncProviderCombo()
    onCfg_sttApiEndpointChanged: {
        if (!_initialized) return;
        // Reload key for new slot when endpoint identity changes
        loadWalletKey();
    }
    onCfg_sttModelNameChanged: if (_initialized) syncModelCombo()
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
            id: providerCombo
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

        RowLayout {
            Kirigami.FormData.label: i18n("Model:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: modelCombo
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.minimumWidth: Kirigami.Units.gridUnit * 8
                editable: true
                readonly property var displayModels: {
                    var list = availableModels.slice();
                    if (cfg_sttModelName && cfg_sttModelName.length > 0 && list.indexOf(cfg_sttModelName) === -1)
                        list.unshift(cfg_sttModelName);
                    return list;
                }
                model: displayModels
                displayText: cfg_sttModelName || ""
                onActivated: function(index) {
                    if (!_initialized) return;
                    if (index >= 0 && index < displayModels.length)
                        cfg_sttModelName = displayModels[index];
                }
                onAccepted: {
                    if (!_initialized) return;
                    cfg_sttModelName = editText;
                }
                // Keep editText in sync when selection changes externally
                onDisplayModelsChanged: syncModelCombo()
            }

            QQC2.Button {
                text: fetchInProgress ? i18n("Fetching…") : i18n("Fetch")
                icon.name: "view-refresh"
                // Icon+short label avoids clipping the trailing button in narrow dialogs.
                display: QQC2.AbstractButton.TextBesideIcon
                enabled: !fetchInProgress && (cfg_sttApiEndpoint || "").length > 0
                onClicked: fetchModels()
                QQC2.ToolTip.text: i18n("Fetch STT models")
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.visible: hovered
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("OpenRouter lists STT models only via transcription modalities (this page does that).")
        }

        RowLayout {
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

        QQC2.ComboBox {
            id: backendCombo
            Kirigami.FormData.label: i18n("STT backend:")
            Layout.fillWidth: true
            model: [i18n("OpenAI-compatible transcriptions")]
            currentIndex: 0
            onActivated: {
                if (!_initialized) return;
                cfg_sttBackend = "openai_transcriptions";
            }
            Component.onCompleted: {
                if (!cfg_sttBackend || cfg_sttBackend.length === 0)
                    cfg_sttBackend = "openai_transcriptions";
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
