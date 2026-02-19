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
    property int cfg_chatSpacing
    property int cfg_chatSpacingDefault
    property bool cfg_saveChatHistory
    property bool cfg_saveChatHistoryDefault
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
    property int cfg_autoClearMode
    property int cfg_autoClearModeDefault
    property int cfg_autoClearSeconds
    property int cfg_autoClearSecondsDefault
    property int cfg_autoClearMinutes
    property int cfg_autoClearMinutesDefault
    property string cfg_lastClosedTimestamp
    property string cfg_lastClosedTimestampDefault

    property var availableModels: []
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

    function walletWriteKey(handle, key, onDone) {
        ensureWalletFolder(handle, function(ok) {
            if (!ok) {
                onDone(false);
                return;
            }
            walletCall("writePassword", [new DBus.int32(handle), "PlasmaLLM", "apiKey", key, "PlasmaLLM"],
                function(result) { onDone(result === 0); },
                function(err) {
                    console.warn("PlasmaLLM: wallet writePassword error: " + err);
                    onDone(false);
                }
            );
        });
    }

    function loadWalletKey() {
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    walletApiKey = cfg_apiKey;
                    walletKeyLoaded = true;
                    return;
                }
                walletAvailable = true;
                walletCall("readPassword", [new DBus.int32(handle), "PlasmaLLM", "apiKey", "PlasmaLLM"],
                    function(password) {
                        if (password && password.length > 0) {
                            walletApiKey = password;
                        } else {
                            walletApiKey = cfg_apiKey;
                        }
                        walletKeyLoaded = true;
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    },
                    function(err) {
                        walletApiKey = cfg_apiKey;
                        walletKeyLoaded = true;
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    }
                );
            },
            function(err) {
                walletApiKey = cfg_apiKey;
                walletKeyLoaded = true;
            }
        );
    }

    function saveWalletKey() {
        var key = apiKeyField.text;
        walletSaveInProgress = true;
        if (!walletAvailable) {
            cfg_apiKey = key;
            walletKeyDirty = false;
            walletSaveInProgress = false;
            return;
        }
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    cfg_apiKey = key;
                    walletKeyDirty = false;
                    walletSaveInProgress = false;
                    return;
                }
                walletWriteKey(handle, key, function(success) {
                    if (success) {
                        walletApiKey = key;
                        cfg_apiKey = "";
                        walletKeyDirty = false;
                        cfg_apiKeyVersion++;
                    }
                    walletSaveInProgress = false;
                    walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                });
            },
            function(err) {
                cfg_apiKey = key;
                walletKeyDirty = false;
                walletSaveInProgress = false;
            }
        );
    }

    Component.onCompleted: loadWalletKey()

    readonly property var presetEndpoints: [
        { name: "Custom",                   url: "" },
        // Local / self-hosted
        { name: "Ollama (local)",            url: "http://localhost:11434/v1" },
        { name: "LM Studio (local)",         url: "http://localhost:1234/v1" },
        { name: "LocalAI (local)",           url: "http://localhost:8080/v1" },
        { name: "vLLM (local)",              url: "http://localhost:8000/v1" },
        { name: "KoboldCpp (local)",         url: "http://localhost:5001/v1" },
        { name: "text-generation-webui (local)", url: "http://localhost:5000/v1" },
        // Cloud providers
        { name: "Poe",                       url: "https://api.poe.com/v1" },
        { name: "OpenAI",                    url: "https://api.openai.com/v1" },
        { name: "Anthropic (OpenAI-compat)", url: "https://api.anthropic.com/v1" },
        { name: "Google Gemini",             url: "https://generativelanguage.googleapis.com/v1beta/openai" },
        { name: "Groq",                      url: "https://api.groq.com/openai/v1" },
        { name: "Together AI",               url: "https://api.together.xyz/v1" },
        { name: "Mistral",                   url: "https://api.mistral.ai/v1" },
        { name: "OpenRouter",                url: "https://openrouter.ai/api/v1" },
        { name: "Perplexity",                url: "https://api.perplexity.ai" },
        { name: "DeepSeek",                  url: "https://api.deepseek.com/v1" },
        { name: "xAI (Grok)",               url: "https://api.x.ai/v1" },
        { name: "Fireworks AI",              url: "https://api.fireworks.ai/inference/v1" },
        { name: "Cerebras",                  url: "https://api.cerebras.ai/v1" },
        { name: "DeepInfra",                 url: "https://api.deepinfra.com/v1/openai" },
        { name: "Cohere",                    url: "https://api.cohere.ai/compatibility/v1" },
        { name: "SambaNova",                 url: "https://api.sambanova.ai/v1" },
        { name: "Novita AI",                 url: "https://api.novita.ai/v3/openai" }
    ]

    Kirigami.FormLayout {
        anchors.fill: parent

        QQC2.ComboBox {
            id: endpointPreset
            Kirigami.FormData.label: "Provider:"
            Layout.fillWidth: true
            model: presetEndpoints.map(function(p) { return p.name; })
            Component.onCompleted: {
                // Select the matching preset, or "Custom" if no match
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
                    apiEndpointField.text = presetEndpoints[index].url;
                    cfg_providerName = presetEndpoints[index].name;
                }
            }
        }

        QQC2.TextField {
            id: apiEndpointField
            Kirigami.FormData.label: "API Endpoint:"
            placeholderText: "http://localhost:11434/v1"
            Layout.fillWidth: true
            text: cfg_apiEndpoint
            onTextChanged: {
                cfg_apiEndpoint = text;
                // Update preset selector if it no longer matches
                var matched = false;
                for (var i = 1; i < presetEndpoints.length; i++) {
                    if (text === presetEndpoints[i].url) {
                        endpointPreset.currentIndex = i;
                        matched = true;
                        break;
                    }
                }
                if (!matched) {
                    endpointPreset.currentIndex = 0;
                    cfg_providerName = "Custom";
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Model:"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: modelNameField
                Layout.fillWidth: true
                placeholderText: "e.g. llama3, gpt-4, etc."
                text: cfg_modelName
                onTextChanged: cfg_modelName = text
            }

            QQC2.Button {
                text: "Fetch Models"
                icon.name: "view-refresh"
                onClicked: {
                    enabled = false;
                    modelCombo.visible = false;
                    fetchStatusLabel.visible = false;
                    Api.fetchModels(apiEndpointField.text, apiKeyField.text, function(error, models) {
                        enabled = true;
                        if (error) {
                            fetchStatusLabel.text = error;
                            fetchStatusLabel.visible = true;
                        } else if (models.length === 0) {
                            fetchStatusLabel.text = "No models found.";
                            fetchStatusLabel.visible = true;
                        } else {
                            availableModels = models;
                            modelCombo.visible = true;
                            fetchStatusLabel.visible = false;
                        }
                    });
                }
            }
        }

        QQC2.Label {
            id: fetchStatusLabel
            visible: false
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        QQC2.ComboBox {
            id: modelCombo
            Kirigami.FormData.label: "Available Models:"
            visible: false
            model: availableModels
            Layout.fillWidth: true
            onActivated: {
                modelNameField.text = currentText;
            }
        }

        RowLayout {
            Kirigami.FormData.label: "API Key:"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: apiKeyField
                Layout.fillWidth: true
                placeholderText: "Optional - for OpenAI, etc."
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
                text: walletSaveInProgress ? "Saving..." :
                      !walletKeyDirty ? "Saved" :
                      !walletAvailable ? "Save to Config (Insecure)" : "Save Key"
                icon.name: !walletKeyDirty ? "dialog-ok-apply" : "document-save"
                enabled: walletKeyDirty && !walletSaveInProgress
                onClicked: saveWalletKey()
            }
        }

        QQC2.Label {
            visible: walletKeyLoaded
            text: walletAvailable ? "Stored in KDE Wallet" : "KDE Wallet unavailable — key stored in config file"
            font: Kirigami.Theme.smallFont
            color: walletAvailable ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
        }

        ColumnLayout {
            Kirigami.FormData.label: "Temperature: " + Math.round(temperatureSlider.value) + "%"
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
                    text: "Precise"
                    font: Kirigami.Theme.smallFont
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    text: "Creative"
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        QQC2.SpinBox {
            id: maxTokensSpinBox
            Kirigami.FormData.label: "Max Tokens:"
            from: 64
            to: 32768
            stepSize: 64
            editable: true
            value: cfg_maxTokens
            onValueModified: cfg_maxTokens = value
        }

        ColumnLayout {
            Kirigami.FormData.label: "Chat Spacing: " + Math.round(chatSpacingSlider.value) + "px"
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
                    text: "Compact"
                    font: Kirigami.Theme.smallFont
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    text: "Spacious"
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: "Appearance:"
            text: "Show provider and model in title"
            checked: cfg_showProviderInTitle
            onCheckedChanged: cfg_showProviderInTitle = checked
        }

        QQC2.CheckBox {
            id: saveChatHistoryCheckBox
            Kirigami.FormData.label: "Chat History:"
            text: "Auto-save chat history"
            checked: cfg_saveChatHistory
            onCheckedChanged: cfg_saveChatHistory = checked

            QQC2.ToolTip.text: "Saves to ~/PlasmaLLM/chats/"
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.Label {
            text: "Saves to ~/PlasmaLLM/chats/"
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }

        QQC2.ButtonGroup { id: autoClearGroup }

        ColumnLayout {
            Kirigami.FormData.label: "Auto-clear:"
            spacing: Kirigami.Units.smallSpacing

            QQC2.RadioButton {
                text: "Disabled"
                QQC2.ButtonGroup.group: autoClearGroup
                checked: cfg_autoClearMode === 0
                onClicked: cfg_autoClearMode = 0
            }
            QQC2.RadioButton {
                text: "Instant (always clear when panel opens)"
                QQC2.ButtonGroup.group: autoClearGroup
                checked: cfg_autoClearMode === 1
                onClicked: cfg_autoClearMode = 1
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                QQC2.RadioButton {
                    QQC2.ButtonGroup.group: autoClearGroup
                    checked: cfg_autoClearMode === 2
                    onClicked: cfg_autoClearMode = 2
                }
                QQC2.SpinBox {
                    from: 1; to: 3600
                    value: cfg_autoClearSeconds
                    onValueModified: cfg_autoClearSeconds = value
                    enabled: cfg_autoClearMode === 2
                }
                QQC2.Label { text: "seconds" }
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                QQC2.RadioButton {
                    QQC2.ButtonGroup.group: autoClearGroup
                    checked: cfg_autoClearMode === 3
                    onClicked: cfg_autoClearMode = 3
                }
                QQC2.SpinBox {
                    from: 1; to: 1440
                    value: cfg_autoClearMinutes
                    onValueModified: cfg_autoClearMinutes = value
                    enabled: cfg_autoClearMode === 3
                }
                QQC2.Label { text: "minutes" }
            }
        }

        QQC2.CheckBox {
            id: autoShareCheckBox
            Kirigami.FormData.label: "Commands:"
            text: "Auto-share command output with LLM"
            checked: cfg_autoShareCommandOutput
            onCheckedChanged: cfg_autoShareCommandOutput = checked

            QQC2.ToolTip.text: "Automatically send Run command results back to the LLM"
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.CheckBox {
            id: autoRunCheckBox
            text: "Auto-run commands from LLM"
            checked: cfg_autoRunCommands
            onCheckedChanged: cfg_autoRunCommands = checked

            QQC2.ToolTip.text: "WARNING: When combined with Auto-share, enables agentic workflow. Only use with very trustworthy LLMs."
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.Label {
            visible: autoShareCheckBox.checked && autoRunCheckBox.checked
            text: "⚠️ DANGER: Both options enabled - the LLM can now execute commands and see their output, enabling an agentic workflow. Only use with trustworthy LLMs."
            wrapMode: Text.Wrap
            Layout.preferredWidth: 300
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
        }

    }
}
