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
import "toolManager.js" as ToolManager

BaseConfigPage {
    id: configPage

    property var activeAdapter: Api.getAdapter(cfg_apiType)
    property var adapterCapabilities: activeAdapter ? activeAdapter.capabilities : {}

    property bool hasTmux: false
    property bool hasScreen: false
    property bool _tmuxChecked: false
    property bool _screenChecked: false

    property alias execSource: execSource

    property var whitelistPaths: []

    function parseWhitelist() {
        if (!cfg_toolsPathWhitelist) {
            whitelistPaths = ["$HOME"];
            return;
        }
        try {
            var parsed = JSON.parse(cfg_toolsPathWhitelist);
            if (Array.isArray(parsed)) {
                whitelistPaths = parsed;
            } else {
                whitelistPaths = ["$HOME"];
            }
        } catch (e) {
            console.error("Error parsing whitelist:", e);
            whitelistPaths = ["$HOME"];
        }
    }

    function saveWhitelist() {
        if (!_initialized) return;
        cfg_toolsPathWhitelist = JSON.stringify(whitelistPaths);
        configPage.triggerCapture();
    }

    function checkBackendAvailability() {
        if (!_tmuxChecked || !_screenChecked) return;
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
            if (sourceName === "command -v tmux") {
                hasTmux = isAvail;
                _tmuxChecked = true;
            } else if (sourceName === "command -v screen") {
                hasScreen = isAvail;
                _screenChecked = true;
            }
            configPage.checkBackendAvailability();
            disconnectSource(sourceName);
        }
    }

    Component.onCompleted: {
        execSource.connectSource("command -v tmux");
        execSource.connectSource("command -v screen");
        configPage.parseWhitelist();
    }

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("General Tool Settings")
        }

        QQC2.CheckBox {
            id: enableToolsMaster
            Kirigami.FormData.label: i18n("System state:")
            text: i18n("Enable Tools")
            checked: cfg_enableTools
            onCheckedChanged: {
                if (_initialized) {
                    cfg_enableTools = checked;
                    rootItem.triggerCapture();
                }
            }
            
            QQC2.ToolTip.text: i18n("Master switch for all tool-calling functionality.")
            QQC2.ToolTip.visible: hovered
        }

        ColumnLayout {
            id: whitelistColumn
            Kirigami.FormData.label: i18n("Path whitelist:")
            enabled: cfg_enableTools
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true

            function removeAt(idx) {
                var arr = whitelistPaths.slice();
                arr.splice(idx, 1);
                whitelistPaths = arr;
                saveWhitelist();
            }

            function addPath(path) {
                if (whitelistPaths.indexOf(path) === -1) {
                    var arr = whitelistPaths.slice();
                    arr.push(path);
                    whitelistPaths = arr;
                    saveWhitelist();
                }
            }

            Repeater {
                model: whitelistPaths
                delegate: RowLayout {
                    Layout.fillWidth: true
                    QQC2.TextField {
                        text: modelData
                        Layout.fillWidth: true
                        readOnly: true
                    }
                    QQC2.ToolButton {
                        icon.name: "edit-delete"
                        onClicked: whitelistColumn.removeAt(index)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                QQC2.TextField {
                    id: newPathField
                    Layout.fillWidth: true
                    placeholderText: i18n("Add path, e.g. $HOME/projects")
                    onAccepted: addPathButton.clicked()
                }
                QQC2.Button {
                    id: addPathButton
                    icon.name: "list-add"
                    text: i18n("Add")
                    enabled: newPathField.text.trim().length > 0
                    onClicked: {
                        var path = newPathField.text.trim();
                        whitelistColumn.addPath(path);
                        newPathField.text = "";
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Whitelist applies to file-system tools (read, write, list, search). Note: 'run_command' is not restricted by this list.")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Max read size:")
            enabled: cfg_enableTools
            QQC2.SpinBox {
                from: 1
                to: 10240
                value: cfg_toolsReadMaxBytes / 1024
                onValueModified: if (_initialized) cfg_toolsReadMaxBytes = value * 1024
            }
            QQC2.Label { text: "KB" }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Max write size:")
            enabled: cfg_enableTools
            QQC2.SpinBox {
                from: 1
                to: 10240
                value: cfg_toolsWriteMaxBytes / 1024
                onValueModified: if (_initialized) cfg_toolsWriteMaxBytes = value * 1024
            }
            QQC2.Label { text: "KB" }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Max HTTP response:")
            enabled: cfg_enableTools
            QQC2.SpinBox {
                from: 1
                to: 10240
                value: cfg_toolsHttpMaxBytes / 1024
                onValueModified: if (_initialized) cfg_toolsHttpMaxBytes = value * 1024
            }
            QQC2.Label { text: "KB" }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Native Adapter Features")
            visible: !!(adapterCapabilities && (adapterCapabilities.nativeGoogleSearch || adapterCapabilities.nativeCodeExecution))
        }

        QQC2.CheckBox {
            id: nativeGoogleSearchCheckBox
            Kirigami.FormData.label: i18n("Google Search:")
            text: i18n("Enable Native Google Search Grounding")
            checked: cfg_enableNativeGoogleSearch
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_enableNativeGoogleSearch = checked;
                rootItem.triggerCapture();
            }
            visible: !!(adapterCapabilities && adapterCapabilities.nativeGoogleSearch)
            enabled: cfg_enableTools

            QQC2.ToolTip.text: i18n("Use Gemini's built-in Google Search for grounding. This overrides the standard web search tool.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.CheckBox {
            id: nativeCodeExecutionCheckBox
            Kirigami.FormData.label: i18n("Code Execution:")
            text: i18n("Enable Native Python Code Execution")
            checked: cfg_enableNativeCodeExecution
            onCheckedChanged: {
                if (!_initialized) return;
                cfg_enableNativeCodeExecution = checked;
                rootItem.triggerCapture();
            }
            visible: !!(adapterCapabilities && adapterCapabilities.nativeCodeExecution)
            enabled: cfg_enableTools

            QQC2.ToolTip.text: i18n("Allow Gemini to write and execute Python code in a secure server-side sandbox.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            text: i18n("Combining Native tools with commands requires a newer model. Your currently selected model (%1) may encounter errors.", cfg_modelName)
            visible: (cfg_enableNativeGoogleSearch || cfg_enableNativeCodeExecution) && 
                     cfg_useCommandTool &&
                     cfg_modelName && (cfg_modelName.indexOf("gemini-1") !== -1 || cfg_modelName.indexOf("gemini-2") !== -1)
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Individual Tools")
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 30
            spacing: Kirigami.Units.largeSpacing
            enabled: cfg_enableTools
            opacity: enabled ? 1.0 : 0.6

            // Helper component for tool cards
            component ToolCard : Kirigami.AbstractCard {
                id: card
                property string toolName: ""
                property string configSource: ""
                property bool isToolEnabled: false
                signal toggled(bool checked)

                readonly property var toolMetadata: ToolManager.getToolMetadata(toolName, null)

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.CheckBox {
                            id: mainCheckBox
                            checked: card.isToolEnabled
                            onCheckedChanged: {
                                if (card.isToolEnabled !== checked) {
                                    card.toggled(checked);
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true

                            QQC2.Label {
                                text: card.toolMetadata && card.toolMetadata.displayName ? card.toolMetadata.displayName : card.toolName
                                font.bold: true
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                            }

                            QQC2.Label {
                                text: card.toolMetadata ? card.toolMetadata.description : ""
                                font: Kirigami.Theme.smallFont
                                color: Kirigami.Theme.disabledTextColor
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                visible: text.length > 0
                            }
                        }
                    }

                    // Options container with background differentiation
                    QQC2.Control {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.gridUnit * 2
                        visible: card.isToolEnabled
                        padding: Kirigami.Units.largeSpacing
                        
                        background: Rectangle {
                            color: Kirigami.Theme.alternateBackgroundColor
                            opacity: 0.3
                            radius: Kirigami.Units.smallSpacing
                        }

                        contentItem: Loader {
                            source: card.configSource
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            ToolCard {
                toolName: "run_command"
                isToolEnabled: cfg_useCommandTool
                onToggled: checked => { if (_initialized) { cfg_useCommandTool = checked; rootItem.triggerCapture(); } }
                configSource: "tools/RunCommandConfig.qml"
            }

            ToolCard {
                toolName: "web_search"
                isToolEnabled: cfg_enableWebSearch
                onToggled: checked => { if (_initialized) { cfg_enableWebSearch = checked; rootItem.triggerCapture(); } }
                configSource: "tools/WebSearchConfig.qml"
            }

            ToolCard {
                toolName: "read_file"
                isToolEnabled: cfg_toolsReadFileEnabled
                onToggled: checked => { 
                    if (_initialized) {
                        cfg_toolsReadFileEnabled = checked;
                        rootItem.triggerCapture();
                    }
                }
                configSource: "tools/ReadFileConfig.qml"
            }

            ToolCard {
                toolName: "write_file"
                isToolEnabled: cfg_toolsWriteFileEnabled
                onToggled: checked => { if (_initialized) { cfg_toolsWriteFileEnabled = checked; rootItem.triggerCapture(); } }
                configSource: "tools/WriteFileConfig.qml"
            }

            ToolCard {
                toolName: "list_dir"
                isToolEnabled: cfg_toolsListDirEnabled
                onToggled: checked => { if (_initialized) { cfg_toolsListDirEnabled = checked; rootItem.triggerCapture(); } }
                configSource: "tools/ListDirConfig.qml"
            }

            ToolCard {
                toolName: "search_files"
                isToolEnabled: cfg_toolsSearchFilesEnabled
                onToggled: checked => { 
                    if (_initialized) {
                        cfg_toolsSearchFilesEnabled = checked;
                        rootItem.triggerCapture();
                    }
                }
                configSource: "tools/SearchFilesConfig.qml"
            }

            ToolCard {
                toolName: "http_get"
                isToolEnabled: cfg_toolsHttpGetEnabled
                onToggled: checked => { if (_initialized) { cfg_toolsHttpGetEnabled = checked; rootItem.triggerCapture(); } }
                configSource: "tools/HttpGetConfig.qml"
            }

            ToolCard {
                toolName: "http_request"
                isToolEnabled: cfg_toolsHttpRequestEnabled
                onToggled: checked => { if (_initialized) { cfg_toolsHttpRequestEnabled = checked; rootItem.triggerCapture(); } }
                configSource: "tools/HttpRequestConfig.qml"
            }

            ToolCard {
                toolName: "get_clipboard"
                isToolEnabled: cfg_toolsGetClipboardEnabled
                onToggled: checked => { if (_initialized) { cfg_toolsGetClipboardEnabled = checked; rootItem.triggerCapture(); } }
                configSource: "tools/GetClipboardConfig.qml"
            }

            ToolCard {
                toolName: "set_clipboard"
                isToolEnabled: cfg_toolsSetClipboardEnabled
                onToggled: checked => { 
                    if (_initialized) {
                        cfg_toolsSetClipboardEnabled = checked;
                        rootItem.triggerCapture();
                    }
                }
                configSource: "tools/SetClipboardConfig.qml"
            }

            ToolCard {
                toolName: "notify"
                isToolEnabled: cfg_toolsNotifyEnabled
                onToggled: checked => { if (_initialized) { cfg_toolsNotifyEnabled = checked; rootItem.triggerCapture(); } }
                configSource: "tools/NotifyConfig.qml"
            }

            ToolCard {
                toolName: "open_url"
                isToolEnabled: cfg_toolsOpenUrlEnabled
                onToggled: checked => { if (_initialized) { cfg_toolsOpenUrlEnabled = checked; rootItem.triggerCapture(); } }
                configSource: "tools/OpenUrlConfig.qml"
            }
        }
    }
}
