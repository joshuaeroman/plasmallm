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

    property var availableModels: []
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

    onCfg_availableModelsChanged: {
        if (cfg_availableModels && cfg_availableModels.length > 0) {
            try { availableModels = JSON.parse(cfg_availableModels); } catch(e) {}
        } else {
            availableModels = [];
        }
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
        loadWalletKey();
        loadWalletOllamaKey();
    }

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
            Kirigami.FormData.label: i18n("Provider:")
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
                    Api.fetchModels(presetEndpoints[index].url, apiKeyField.text, function(error, models) {
                        if (!error && models.length > 0) {
                            availableModels = models;
                            cfg_availableModels = JSON.stringify(models);
                        }
                    });
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
                cfg_availableModels = "";
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
            Kirigami.FormData.label: i18n("Model:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: modelNameField
                Layout.fillWidth: true
                placeholderText: i18n("e.g. llama3, gpt-4, etc.")
                text: cfg_modelName
                onTextChanged: cfg_modelName = text
            }

            QQC2.Button {
                text: i18n("Fetch Models")
                icon.name: "view-refresh"
                onClicked: {
                    enabled = false;
                    fetchStatusLabel.visible = false;
                    Api.fetchModels(apiEndpointField.text, apiKeyField.text, function(error, models) {
                        enabled = true;
                        if (error) {
                            fetchStatusLabel.text = error;
                            fetchStatusLabel.visible = true;
                        } else if (models.length === 0) {
                            fetchStatusLabel.text = i18n("No models found.");
                            fetchStatusLabel.visible = true;
                        } else {
                            availableModels = models;
                            cfg_availableModels = JSON.stringify(models);
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
            Kirigami.FormData.label: i18n("Available Models:")
            visible: availableModels.length > 0
            model: availableModels
            Layout.fillWidth: true
            onActivated: {
                modelNameField.text = currentText;
            }
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
