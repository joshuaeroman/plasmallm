/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus

ColumnLayout {
    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

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
        loadWalletOllamaKey();
        loadWalletSearxngKey();
    }

    Connections {
        target: typeof configPage !== 'undefined' ? configPage : null
        function onCfg_ollamaSearchApiKeyVersionChanged() { loadWalletOllamaKey(); }
        function onCfg_searxngApiKeyVersionChanged() { loadWalletSearxngKey(); }
    }

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
            if (_initialized) cfg_webSearchProvider = currentValue;
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
        onTextChanged: if (_initialized) cfg_searxngUrl = text
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
