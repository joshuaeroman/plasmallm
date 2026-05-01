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
    property string cfg_ollamaApiKey
    property string cfg_ollamaApiKeyDefault
    property int cfg_ollamaApiKeyVersion
    property int cfg_ollamaApiKeyVersionDefault

    property string walletOllamaKey: ""
    property bool walletOllamaKeyLoaded: false
    property bool walletOllamaKeyDirty: false
    property bool walletOllamaSaveInProgress: false
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
                walletAvailable = true;
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
        loadWalletOllamaKey();
    }

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
            Kirigami.FormData.label: i18n("Web Search")
        }

        QQC2.CheckBox {
            id: enableWebSearchCheckBox
            text: i18n("Enable web search tool")
            checked: cfg_enableWebSearch
            onCheckedChanged: cfg_enableWebSearch = checked

            QQC2.ToolTip.text: i18n("Allows the LLM to perform web searches using Ollama's search API.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        ColumnLayout {
            visible: enableWebSearchCheckBox.checked
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: ollamaApiKeyField
                    Layout.fillWidth: true
                    placeholderText: i18n("Ollama API key")
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
                Layout.preferredWidth: 1
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            }
        }
    }
}
