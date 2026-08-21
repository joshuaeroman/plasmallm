/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus

import "../api.js" as Api
import "../wallet.js" as Wallet

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

    property string walletExaKey: ""
    property bool walletExaKeyLoaded: false
    property bool walletExaKeyDirty: false
    property bool walletExaSaveInProgress: false

    property bool walletAvailable: false

    function loadSearchWalletKey(provider, legacyNames, cfgDefault, applyFn) {
        var primary = Api.searchKeySlot(provider);
        var extras = Api.searchLegacyKeySlots(provider).concat(legacyNames || []);
        Wallet.readKey(DBus, primary, extras, {}, cfgDefault || "", function(res) {
            if (res && res.available)
                walletAvailable = true;
            applyFn((res && res.key) || cfgDefault || "");
        });
    }

    function saveSearchWalletKey(provider, key, setCfg, bumpVersion, done) {
        // The plaintext config entry is written only when KWallet could not
        // store the key; on success it is cleared so the key lives only there.
        Wallet.writeKey(DBus, Api.searchKeySlot(provider), key, function(res) {
            if (res && res.available)
                walletAvailable = true;
            if (res && res.success) {
                setCfg("");
                bumpVersion();
            } else {
                setCfg(key);
            }
            if (done) done();
        });
    }

    function loadWalletOllamaKey() {
        loadSearchWalletKey("ollama", ["ollamaSearchApiKey", "ollamaApiKey"], cfg_ollamaSearchApiKey,
            function(k) {
                walletOllamaKey = k;
                walletOllamaKeyLoaded = true;
            });
    }

    function saveWalletOllamaKey() {
        var key = ollamaApiKeyField.text;
        walletOllamaSaveInProgress = true;
        walletOllamaKey = key;
        walletOllamaKeyDirty = false;
        saveSearchWalletKey("ollama", key,
            function(k) { cfg_ollamaSearchApiKey = k; },
            function() { cfg_ollamaSearchApiKeyVersion++; },
            function() { walletOllamaSaveInProgress = false; });
    }

    function loadWalletSearxngKey() {
        loadSearchWalletKey("searxng", ["searxngApiKey"], cfg_searxngApiKey,
            function(k) {
                walletSearxngKey = k;
                walletSearxngKeyLoaded = true;
            });
    }

    function saveWalletSearxngKey() {
        var key = searxngApiKeyField.text;
        walletSearxngSaveInProgress = true;
        walletSearxngKey = key;
        walletSearxngKeyDirty = false;
        saveSearchWalletKey("searxng", key,
            function(k) { cfg_searxngApiKey = k; },
            function() { cfg_searxngApiKeyVersion++; },
            function() { walletSearxngSaveInProgress = false; });
    }

    function loadWalletExaKey() {
        loadSearchWalletKey("exa", ["exaApiKey"], cfg_exaApiKey,
            function(k) {
                walletExaKey = k;
                walletExaKeyLoaded = true;
            });
    }

    function saveWalletExaKey() {
        var key = exaApiKeyField.text;
        walletExaSaveInProgress = true;
        walletExaKey = key;
        walletExaKeyDirty = false;
        saveSearchWalletKey("exa", key,
            function(k) { cfg_exaApiKey = k; },
            function() { cfg_exaApiKeyVersion++; },
            function() { walletExaSaveInProgress = false; });
    }

    Component.onCompleted: {
        loadWalletOllamaKey();
        loadWalletSearxngKey();
        loadWalletExaKey();
    }

    Connections {
        target: typeof configPage !== 'undefined' ? configPage : null
        function onCfg_ollamaSearchApiKeyVersionChanged() { loadWalletOllamaKey(); }
        function onCfg_searxngApiKeyVersionChanged() { loadWalletSearxngKey(); }
        function onCfg_exaApiKeyVersionChanged() { loadWalletExaKey(); }
    }

    QQC2.ComboBox {
        id: webSearchProviderComboBox
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 15
        model: [
            { text: i18n("Ollama API"), value: "ollama" },
            { text: i18n("SearXNG"), value: "searxng" },
            { text: i18n("DuckDuckGo"), value: "duckduckgo" },
            { text: i18n("Exa Search"), value: "exa" }
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

    // Exa options
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: cfg_webSearchProvider === "exa"

        QQC2.TextField {
            id: exaApiKeyField
            Layout.fillWidth: true
            placeholderText: i18n("Exa API key")
            echoMode: TextInput.Password
            text: walletExaKeyLoaded ? walletExaKey : cfg_exaApiKey
            onTextChanged: {
                if (walletExaKeyLoaded) {
                    walletExaKeyDirty = (text !== walletExaKey);
                }
            }
            onEditingFinished: {
                if (walletExaKeyDirty) saveWalletExaKey();
            }
        }

        QQC2.Button {
            text: walletExaSaveInProgress ? i18n("Saving…") :
                  !walletExaKeyDirty ? i18n("Saved") :
                  !walletAvailable ? i18n("Save to Config (Insecure)") : i18n("Save Key")
            icon.name: !walletExaKeyDirty ? "dialog-ok-apply" : "document-save"
            enabled: walletExaKeyDirty && !walletExaSaveInProgress
            onClicked: saveWalletExaKey()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: cfg_webSearchProvider === "exa"

        QQC2.Label {
            text: i18n("Search Type:")
        }

        QQC2.ComboBox {
            id: exaSearchTypeComboBox
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 12
            model: [
                { text: i18n("Auto (Default)"), value: "auto" },
                { text: i18n("Fast"), value: "fast" },
                { text: i18n("Instant"), value: "instant" },
                { text: i18n("Deep Lite"), value: "deep-lite" },
                { text: i18n("Deep"), value: "deep" },
                { text: i18n("Deep Reasoning"), value: "deep-reasoning" }
            ]
            textRole: "text"
            valueRole: "value"
            Component.onCompleted: {
                for (var i = 0; i < count; i++) {
                    if (model[i].value === cfg_exaSearchType) {
                        currentIndex = i;
                        break;
                    }
                }
            }
            onActivated: {
                if (_initialized) cfg_exaSearchType = currentValue;
            }
        }
    }

    QQC2.Label {
        text: cfg_webSearchProvider === "duckduckgo" 
              ? i18n("DuckDuckGo requires no configuration.") 
              : cfg_webSearchProvider === "searxng" 
                ? i18n("Ensure the SearXNG instance has the JSON format enabled.") 
                : cfg_webSearchProvider === "exa"
                  ? i18n("Enables LLM-triggered neural web searches via Exa API.")
                  : i18n("Enables LLM-triggered web searches via Ollama's search API")
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
    }
}
