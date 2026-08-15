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
import "driverManager.js" as DriverManager

BaseConfigPage {
    id: configPage

    property var activeAdapter: Api.getAdapter(cfg_apiType)
    property var adapterCapabilities: activeAdapter ? activeAdapter.capabilities : {}
    // Dedicated Exa adapter, or OpenAI-compatible preset/endpoint pointed at Exa.
    readonly property bool usingExaChat: {
        if (cfg_apiType === "exa")
            return true;
        if (cfg_apiType !== "openai")
            return false;
        if ((cfg_providerName || "") === "Exa")
            return true;
        var ep = cfg_apiEndpoint || "";
        var m = String(ep).match(/^https?:\/\/([^\/:?#]+)/i);
        if (!m)
            return false;
        var host = m[1].toLowerCase();
        return host === "api.exa.ai" || host === "exa.ai" || (host.length > 7 && host.slice(-7) === ".exa.ai");
    }

    property bool hasTmux: false
    property bool hasScreen: false
    property bool _tmuxChecked: false
    property bool _screenChecked: false
    property bool driverDetected: false

    property alias execSource: execSource

    property var whitelistPaths: []

    function parseWhitelist() {
        if (!cfg_toolsPathWhitelist) {
            whitelistPaths = ["$HOME", "/tmp", "$XDG_RUNTIME_DIR"];
            return;
        }
        try {
            var parsed = JSON.parse(cfg_toolsPathWhitelist);
            if (Array.isArray(parsed)) {
                whitelistPaths = parsed;
            } else {
                whitelistPaths = ["$HOME", "/tmp", "$XDG_RUNTIME_DIR"];
            }
        } catch (e) {
            console.error("Error parsing whitelist:", e);
            whitelistPaths = ["$HOME", "/tmp", "$XDG_RUNTIME_DIR"];
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

    Timer {
        id: driverCheckTimer
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            DriverManager.isDriverActive(function(active) {
                configPage.driverDetected = active;
            });
        }
    }

    function getDefaultInstruction(toolName) {
        var meta = ToolManager.getToolMetadata(toolName, null);
        var raw = meta ? (meta.longDescription || meta.description || "") : "";
        if (cfg_localizeSystemPrompt && raw.length > 0) {
            return i18n(raw);
        }
        return raw;
    }

    function getInstructionOverride(toolName, instructionsJson) {
        var blob = instructionsJson !== undefined ? instructionsJson : cfg_toolsInstructions;
        if (!blob) return "";
        try {
            var map = typeof blob === "string" ? JSON.parse(blob) : blob;
            return (map && map[toolName]) ? String(map[toolName]) : "";
        } catch(e) {
            return "";
        }
    }

    function getInstructionText(toolName, instructionsJson) {
        var override = getInstructionOverride(toolName, instructionsJson);
        if (override.length > 0) return override;
        return getDefaultInstruction(toolName);
    }

    function hasInstructionOverride(toolName, instructionsJson) {
        return getInstructionOverride(toolName, instructionsJson).length > 0;
    }

    function setInstructionOverride(toolName, text) {
        if (!_initialized) return;
        var map = {};
        try {
            if (cfg_toolsInstructions) {
                map = typeof cfg_toolsInstructions === "string" ? JSON.parse(cfg_toolsInstructions) : cfg_toolsInstructions;
            }
        } catch(e) {}
        if (!map || typeof map !== "object" || Array.isArray(map)) map = {};
        var defaultInst = getDefaultInstruction(toolName);
        if (text && text.trim().length > 0 && text.trim() !== defaultInst.trim()) {
            map[toolName] = text.trim();
        } else {
            delete map[toolName];
        }
        var newBlob = JSON.stringify(map);
        if (cfg_toolsInstructions !== newBlob) {
            cfg_toolsInstructions = newBlob;
            rootItem.triggerCapture();
        }
    }

    Component.onCompleted: {
        DriverManager.init(DBus.SessionBus);
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
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            QQC2.ToolTip.visible: hovered
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            text: i18n("Exa does not support tool use")
            visible: cfg_enableTools && usingExaChat
        }

        RowLayout {
            id: desktopAutomationRow
            Kirigami.FormData.label: i18n("Desktop Automation:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                id: enableDesktopAutomationCheckbox
                checked: cfg_enableDesktopAutomation
                enabled: cfg_enableTools && configPage.driverDetected
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_enableDesktopAutomation = checked;
                        rootItem.triggerCapture();
                    }
                }
                
                QQC2.ToolTip.text: i18n("Allows the LLM to request a session to see and drive your desktop.")
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.visible: hovered
            }

            QQC2.Label {
                id: enableDesktopAutomationLabel
                text: configPage.driverDetected ? i18n("Enable Desktop Automation") : i18n("Enable Desktop Automation (requires <a href=\"https://github.com/joshuaeroman/plasmallm-desktop-driver\">driver</a>)")
                textFormat: Text.RichText
                opacity: cfg_enableTools ? 1.0 : 0.6
                onLinkActivated: function(link) {
                    Qt.openUrlExternally(link)
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor

                    QQC2.ToolTip.text: i18n("Allows the LLM to request a session to see and drive your desktop.")
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    QQC2.ToolTip.visible: containsMouse
                }
            }
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
                    placeholderText: i18n("Add path, e.g. $HOME/projects, /tmp")
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

        RowLayout {
            Kirigami.FormData.label: i18n("Max tool loop depth:")
            enabled: cfg_enableTools
            QQC2.CheckBox {
                id: enableToolCallLimitCheckBox
                checked: cfg_enableToolCallLimit
                onCheckedChanged: if (_initialized) cfg_enableToolCallLimit = checked
            }
            QQC2.SpinBox {
                from: 1
                to: 100
                value: cfg_maxToolCallDepth
                enabled: enableToolCallLimitCheckBox.checked && cfg_enableTools
                onValueModified: if (_initialized) cfg_maxToolCallDepth = value
            }
            QQC2.Label { text: i18n("steps") }
        }

        QQC2.Label {
            enabled: cfg_enableTools
            text: i18n("Note: This limit does not apply to desktop automation sessions.")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
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
            QQC2.ToolTip.delay: 500
            QQC2.ToolTip.visible: hovered
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
            QQC2.ToolTip.delay: 500
            QQC2.ToolTip.visible: hovered
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

                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.mediumSpacing
                            Layout.fillWidth: true

                            Loader {
                                source: card.configSource
                                Layout.fillWidth: true
                                visible: card.configSource.length > 0
                            }

                            Kirigami.Separator {
                                Layout.fillWidth: true
                                visible: card.configSource.length > 0
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                RowLayout {
                                    Layout.fillWidth: true
                                    QQC2.Label {
                                        text: i18n("Prompt Instructions:")
                                        font.bold: true
                                        Layout.fillWidth: true
                                    }
                                    QQC2.Button {
                                        text: i18n("Reset")
                                        icon.name: "edit-undo"
                                        flat: true
                                        visible: instructionArea.text.trim() !== configPage.getDefaultInstruction(card.toolName).trim()
                                        onClicked: {
                                            instructionArea.text = configPage.getDefaultInstruction(card.toolName);
                                            configPage.setInstructionOverride(card.toolName, "");
                                        }
                                    }
                                }

                                QQC2.TextArea {
                                    id: instructionArea
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: Kirigami.Units.gridUnit * 4
                                    wrapMode: Text.Wrap
                                    font.family: "monospace"
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    text: configPage.getInstructionText(card.toolName, cfg_toolsInstructions)
                                    onTextChanged: {
                                        if (_initialized && text !== configPage.getInstructionText(card.toolName, cfg_toolsInstructions)) {
                                            configPage.setInstructionOverride(card.toolName, text);
                                        }
                                    }
                                }
                            }
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
