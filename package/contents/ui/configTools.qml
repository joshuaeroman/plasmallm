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

SimpleKCM {
    id: configPage

    property bool cfg_autoShareCommandOutput
    property bool cfg_autoShareCommandOutputDefault
    property bool cfg_autoRunCommands
    property bool cfg_autoRunCommandsDefault
    property bool cfg_useCommandTool
    property bool cfg_useCommandToolDefault
    property bool cfg_enableWebSearch
    property bool cfg_enableWebSearchDefault
    property string cfg_webSearchProvider
    property string cfg_webSearchProviderDefault
    property string cfg_searxngUrl
    property string cfg_searxngUrlDefault
    property string cfg_searxngApiKey
    property string cfg_searxngApiKeyDefault
    property string cfg_ollamaSearchApiKey
    property string cfg_ollamaSearchApiKeyDefault
    property int cfg_ollamaSearchApiKeyVersion
    property int cfg_ollamaSearchApiKeyVersionDefault
    property int cfg_searxngApiKeyVersion
    property int cfg_searxngApiKeyVersionDefault

    property bool cfg_useSessionMultiplexer
    property bool cfg_useSessionMultiplexerDefault
    property string cfg_sessionMultiplexer
    property string cfg_sessionMultiplexerDefault
    property string cfg_sessionName
    property string cfg_sessionNameDefault

    property bool hasTmux: false
    property bool hasScreen: false

    onHasTmuxChanged: checkBackendAvailability()
    onHasScreenChanged: checkBackendAvailability()

    function checkBackendAvailability() {
        if (!hasTmux && !hasScreen) {
            cfg_useSessionMultiplexer = false;
        } else if (cfg_sessionMultiplexer === "tmux" && !hasTmux && hasScreen) {
            cfg_sessionMultiplexer = "screen";
        } else if (cfg_sessionMultiplexer === "screen" && !hasScreen && hasTmux) {
            cfg_sessionMultiplexer = "tmux";
        }
    }

    P5Support.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var isAvail = data["exit code"] === 0;
            if (sourceName === "command -v tmux") hasTmux = isAvail;
            else if (sourceName === "command -v screen") hasScreen = isAvail;
            disconnectSource(sourceName);
        }
    }


    property string walletOllamaKey: ""
    property bool walletOllamaKeyLoaded: false
    property bool walletOllamaKeyDirty: false
    property bool walletOllamaSaveInProgress: false

    property string walletSearxngKey: ""
    property bool walletSearxngKeyLoaded: false
    property bool walletSearxngKeyDirty: false
    property bool walletSearxngSaveInProgress: false

    property bool walletAvailable: false

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

    function walletWriteOllamaKey(handle, key, onDone) {
        ensureWalletFolder(handle, function(ok) {
            if (!ok) {
                onDone(false);
                return;
            }
            walletCall("writePassword", [new DBus.int32(handle), "PlasmaLLM", "ollamaSearchApiKey", key, "PlasmaLLM"],
                function(result) { onDone(result === 0); },
                function(err) {
                    console.warn("PlasmaLLM: wallet writePassword (ollama) error: " + err);
                    onDone(false);
                }
            );
        });
    }

    function walletWriteSearxngKey(handle, key, onDone) {
        ensureWalletFolder(handle, function(ok) {
            if (!ok) {
                onDone(false);
                return;
            }
            walletCall("writePassword", [new DBus.int32(handle), "PlasmaLLM", "searxngApiKey", key, "PlasmaLLM"],
                function(result) { onDone(result === 0); },
                function(err) {
                    console.warn("PlasmaLLM: wallet writePassword (searxng) error: " + err);
                    onDone(false);
                }
            );
        });
    }

    function loadWalletOllamaKey() {
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    walletOllamaKey = cfg_ollamaSearchApiKey;
                    walletOllamaKeyLoaded = true;
                    return;
                }
                walletAvailable = true;
                walletCall("readPassword", [new DBus.int32(handle), "PlasmaLLM", "ollamaSearchApiKey", "PlasmaLLM"],
                    function(password) {
                        if (password && password.length > 0) {
                            walletOllamaKey = password;
                        } else {
                            walletOllamaKey = cfg_ollamaSearchApiKey;
                        }
                        walletOllamaKeyLoaded = true;
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    },
                    function(err) {
                        walletOllamaKey = cfg_ollamaSearchApiKey;
                        walletOllamaKeyLoaded = true;
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    }
                );
            },
            function(err) {
                walletOllamaKey = cfg_ollamaSearchApiKey;
                walletOllamaKeyLoaded = true;
            }
        );
    }

    function saveWalletOllamaKey() {
        var key = ollamaApiKeyField.text;
        walletOllamaSaveInProgress = true;
        if (!walletAvailable) {
            cfg_ollamaSearchApiKey = key;
            walletOllamaKeyDirty = false;
            walletOllamaSaveInProgress = false;
            return;
        }
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    cfg_ollamaSearchApiKey = key;
                    walletOllamaKeyDirty = false;
                    walletOllamaSaveInProgress = false;
                    return;
                }
                walletWriteOllamaKey(handle, key, function(success) {
                    if (success) {
                        walletOllamaKey = key;
                        cfg_ollamaSearchApiKey = "";
                        walletOllamaKeyDirty = false;
                        cfg_ollamaSearchApiKeyVersion++;
                    }
                    walletOllamaSaveInProgress = false;
                    walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                });
            },
            function(err) {
                cfg_ollamaSearchApiKey = key;
                walletOllamaKeyDirty = false;
                walletOllamaSaveInProgress = false;
            }
        );
    }

    function loadWalletSearxngKey() {
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    walletSearxngKey = cfg_searxngApiKey;
                    walletSearxngKeyLoaded = true;
                    return;
                }
                walletAvailable = true;
                walletCall("readPassword", [new DBus.int32(handle), "PlasmaLLM", "searxngApiKey", "PlasmaLLM"],
                    function(password) {
                        if (password && password.length > 0) {
                            walletSearxngKey = password;
                        } else {
                            walletSearxngKey = cfg_searxngApiKey;
                        }
                        walletSearxngKeyLoaded = true;
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    },
                    function(err) {
                        walletSearxngKey = cfg_searxngApiKey;
                        walletSearxngKeyLoaded = true;
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                    }
                );
            },
            function(err) {
                walletSearxngKey = cfg_searxngApiKey;
                walletSearxngKeyLoaded = true;
            }
        );
    }

    function saveWalletSearxngKey() {
        var key = searxngApiKeyField.text;
        walletSearxngSaveInProgress = true;
        if (!walletAvailable) {
            cfg_searxngApiKey = key;
            walletSearxngKeyDirty = false;
            walletSearxngSaveInProgress = false;
            return;
        }
        walletCall("open", ["kdewallet", new DBus.int64(0), "PlasmaLLM"],
            function(handle) {
                if (handle < 0) {
                    cfg_searxngApiKey = key;
                    walletSearxngKeyDirty = false;
                    walletSearxngSaveInProgress = false;
                    return;
                }
                walletWriteSearxngKey(handle, key, function(success) {
                    if (success) {
                        walletSearxngKey = key;
                        cfg_searxngApiKey = "";
                        walletSearxngKeyDirty = false;
                        cfg_searxngApiKeyVersion++;
                    }
                    walletSearxngSaveInProgress = false;
                    walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "PlasmaLLM"], function(){}, function(){});
                });
            },
            function(err) {
                cfg_searxngApiKey = key;
                walletSearxngKeyDirty = false;
                walletSearxngSaveInProgress = false;
            }
        );
    }

    Component.onCompleted: {
        execSource.connectSource("command -v tmux");
        execSource.connectSource("command -v screen");
        loadWalletOllamaKey();
        loadWalletSearxngKey();
    }

    onCfg_ollamaSearchApiKeyVersionChanged: loadWalletOllamaKey()
    onCfg_searxngApiKeyVersionChanged: loadWalletSearxngKey()

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Commands")
        }

        QQC2.CheckBox {
            id: autoRunCheckBox
            text: i18n("Auto-run commands from LLM")
            checked: cfg_autoRunCommands
            onCheckedChanged: cfg_autoRunCommands = checked

            QQC2.ToolTip.text: i18n("Allow the LLM to execute shell commands. Dangerous if combined with Auto-share.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.CheckBox {
            id: useCommandToolCheckBox
            text: i18n("Run as tool")
            checked: cfg_useCommandTool
            onCheckedChanged: cfg_useCommandTool = checked

            QQC2.ToolTip.text: i18n("Use the run_command tool for command execution. If disabled, falls back to parsing code blocks.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.CheckBox {
            id: autoShareCheckBox
            text: i18n("Auto-share command output with LLM")
            checked: cfg_autoShareCommandOutput
            onCheckedChanged: cfg_autoShareCommandOutput = checked

            QQC2.ToolTip.text: i18n("Automatically send command execution results back to the LLM")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.Label {
            visible: autoShareCheckBox.checked && autoRunCheckBox.checked
            text: i18n("⚠️ DANGER: Both options enabled - the LLM can now execute commands and see their output, enabling an agentic workflow. Only use with trustworthy LLMs.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Session Multiplexer")
        }

        QQC2.CheckBox {
            id: useSessionMultiplexerCheckBox
            text: i18n("Run commands inside a persistent session")
            checked: cfg_useSessionMultiplexer
            onCheckedChanged: cfg_useSessionMultiplexer = checked
            enabled: hasTmux || hasScreen

            QQC2.ToolTip.text: i18n("Execute LLM commands inside a long-lived tmux or screen session so state persists across turns.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.Button {
            text: i18n("Reset Session")
            icon.name: "edit-clear-all"
            visible: useSessionMultiplexerCheckBox.checked
            onClicked: {
                var be = cfg_sessionMultiplexer === "screen" ? "screen" : "tmux";
                var sess = (cfg_sessionName || "").replace(/[^A-Za-z0-9_-]/g, "") || "plasmallm";
                var cmd = be === "tmux" ? "tmux kill-session -t '" + sess + "'" : "screen -S '" + sess + "' -X quit";
                execSource.connectSource(cmd);
            }
        }

        QQC2.ComboBox {
            id: sessionMultiplexerComboBox
            Kirigami.FormData.label: i18n("Backend:")
            model: {
                var opts = [];
                if (hasTmux) opts.push({ text: "tmux", value: "tmux" });
                if (hasScreen) opts.push({ text: "screen", value: "screen" });
                return opts;
            }
            textRole: "text"
            valueRole: "value"
            enabled: useSessionMultiplexerCheckBox.checked && (hasTmux || hasScreen)

            onModelChanged: syncIndex()
            Component.onCompleted: syncIndex()

            function syncIndex() {
                for (var i = 0; i < count; i++) {
                    if (model[i].value === cfg_sessionMultiplexer) {
                        currentIndex = i;
                        break;
                    }
                }
            }

            onActivated: {
                if (currentValue) cfg_sessionMultiplexer = currentValue;
            }
        }

        QQC2.TextField {
            Kirigami.FormData.label: i18n("Session name:")
            placeholderText: "plasmallm"
            text: cfg_sessionName
            onTextChanged: cfg_sessionName = text
            enabled: useSessionMultiplexerCheckBox.checked && (hasTmux || hasScreen)
            Layout.fillWidth: true
        }

        QQC2.Label {
            visible: !(hasTmux || hasScreen)
            text: i18n("Neither 'tmux' nor 'screen' was found on your system. Session multiplexing is unavailable.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Web Search")
        }

        QQC2.CheckBox {
            id: enableWebSearchCheckBox
            text: i18n("Enable web search tool")
            checked: cfg_enableWebSearch
            onCheckedChanged: cfg_enableWebSearch = checked

            QQC2.ToolTip.text: i18n("Allows the LLM to perform web searches.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        ColumnLayout {
            visible: enableWebSearchCheckBox.checked
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: webSearchProviderComboBox
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 15
                model: [
                    { text: i18n("Ollama API"), value: "ollama" },
                    { text: i18n("SearXNG"), value: "searxng" },
                    { text: i18n("DuckDuckGo"), value: "duckduckgo" }
                ]
                textRole: "text"
                valueRole: "value"
                Component.onCompleted: {
                    for (var i = 0; i < count; i++) {
                        if (model[i].value === cfg_webSearchProvider) {
                            currentIndex = i;
                            break;
                        }
                    }
                }
                onActivated: {
                    cfg_webSearchProvider = currentValue;
                }
            }

            // Ollama options
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: cfg_webSearchProvider === "ollama"

                QQC2.TextField {
                    id: ollamaApiKeyField
                    Layout.fillWidth: true
                    placeholderText: i18n("Ollama API key")
                    echoMode: TextInput.Password
                    text: walletOllamaKeyLoaded ? walletOllamaKey : cfg_ollamaSearchApiKey
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

            // SearXNG options
            QQC2.TextField {
                id: searxngUrlField
                Layout.fillWidth: true
                visible: cfg_webSearchProvider === "searxng"
                placeholderText: i18n("SearXNG Instance URL (e.g. https://searx.be)")
                text: cfg_searxngUrl
                onTextChanged: cfg_searxngUrl = text
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: cfg_webSearchProvider === "searxng"

                QQC2.TextField {
                    id: searxngApiKeyField
                    Layout.fillWidth: true
                    placeholderText: i18n("SearXNG API Key/Token (optional)")
                    echoMode: TextInput.Password
                    text: walletSearxngKeyLoaded ? walletSearxngKey : cfg_searxngApiKey
                    onTextChanged: {
                        if (walletSearxngKeyLoaded) {
                            walletSearxngKeyDirty = (text !== walletSearxngKey);
                        }
                    }
                    onEditingFinished: {
                        if (walletSearxngKeyDirty) saveWalletSearxngKey();
                    }
                }

                QQC2.Button {
                    text: walletSearxngSaveInProgress ? i18n("Saving…") :
                          !walletSearxngKeyDirty ? i18n("Saved") :
                          !walletAvailable ? i18n("Save to Config (Insecure)") : i18n("Save Key")
                    icon.name: !walletSearxngKeyDirty ? "dialog-ok-apply" : "document-save"
                    enabled: walletSearxngKeyDirty && !walletSearxngSaveInProgress
                    onClicked: saveWalletSearxngKey()
                }
            }

            QQC2.Label {
                text: cfg_webSearchProvider === "duckduckgo" 
                      ? i18n("DuckDuckGo requires no configuration.") 
                      : cfg_webSearchProvider === "searxng" 
                        ? i18n("Ensure the SearXNG instance has the JSON format enabled.") 
                        : i18n("Enables LLM-triggered web searches via Ollama's search API")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            }
        }
    }
}
