/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaExtras.Representation {
    id: fullRep

    readonly property var slashCommands: [
        { cmd: "/auto",     desc: "Toggle auto mode (auto-run + auto-share) for this session" },
        { cmd: "/clear",    desc: "Clear the chat" },
        { cmd: "/copy",     desc: "Copy conversation to clipboard" },
        { cmd: "/history",  desc: "Open chat history folder" },
        { cmd: "/model",    desc: "Show or switch model (/model <name>)" },
        { cmd: "/run",      desc: "Run last command" },
        { cmd: "/save",     desc: "Save chat to file" },
        { cmd: "/settings", desc: "Open settings" },
        { cmd: "/term",     desc: "Run last command in terminal" },
    ]

    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 24
    Layout.preferredWidth: Kirigami.Units.gridUnit * 28
    Layout.preferredHeight: Kirigami.Units.gridUnit * 32

    header: PlasmaExtras.BasicPlasmoidHeading {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: {
                    if (!Plasmoid.configuration.showProviderInTitle) return "";
                    var provider = Plasmoid.configuration.providerName;
                    var model = Plasmoid.configuration.modelName;
                    var endpoint = Plasmoid.configuration.apiEndpoint;

                    if (provider === "Custom" && endpoint) {
                        try {
                            var url = new URL(endpoint);
                            var hostPort = url.host;
                            if (url.port) {
                                hostPort = url.hostname + ":" + url.port;
                            }
                            provider = hostPort;
                        } catch (e) {
                            provider = endpoint;
                        }
                    }

                    if (provider && model) {
                        return provider + " | " + model;
                    } else if (model) {
                        return model;
                    } else {
                        return "PlasmaLLM";
                    }
                }
                font.bold: true
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                text: "AUTO"
                visible: root.isAutoMode
                font.bold: true
                color: Kirigami.Theme.negativeTextColor
                PlasmaComponents.ToolTip.text: "Auto mode active — commands run and share output automatically"
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
            }

            PlasmaComponents.ToolButton {
                icon.name: "clock"
                Accessible.name: "Open chat history folder"
                PlasmaComponents.ToolTip.text: "Open chat history folder"
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                visible: Plasmoid.configuration.saveChatHistory
                onClicked: root.openChatsFolder()
            }

            PlasmaComponents.ToolButton {
                icon.name: "edit-copy"
                Accessible.name: "Copy conversation"
                PlasmaComponents.ToolTip.text: "Copy conversation"
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                enabled: root.displayMessages.count > 0
                onClicked: {
                    var text = "";
                    for (var i = 0; i < root.displayMessages.count; i++) {
                        var msg = root.displayMessages.get(i);
                        var prefix = msg.role === "user" ? "You" :
                                     msg.role === "assistant" ? "Assistant" :
                                     msg.role === "command_output" ? "Command" :
                                     msg.role === "error" ? "Error" : "";
                        if (prefix) {
                            text += prefix + ": " + msg.content + "\n\n";
                        }
                    }
                    clipboardHelper.text = text.trim();
                    clipboardHelper.selectAll();
                    clipboardHelper.copy();
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "edit-clear-history"
                Accessible.name: "Clear chat"
                PlasmaComponents.ToolTip.text: "Clear chat"
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: { root.clearChat(); inputField.forceActiveFocus(); }
            }

            PlasmaComponents.ToolButton {
                icon.name: "configure"
                Accessible.name: "Settings"
                PlasmaComponents.ToolTip.text: "Settings"
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: Plasmoid.internalAction("configure").trigger()
            }
        }
    }

    // Hidden helper for clipboard access
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    Connections {
        target: root
        function onCopyConversationRequested() {
            var text = "";
            for (var i = 0; i < root.displayMessages.count; i++) {
                var msg = root.displayMessages.get(i);
                var prefix = msg.role === "user" ? "You" :
                             msg.role === "assistant" ? "Assistant" :
                             msg.role === "command_output" ? "Command" :
                             msg.role === "error" ? "Error" : "";
                if (prefix) text += prefix + ": " + msg.content + "\n\n";
            }
            clipboardHelper.text = text.trim();
            clipboardHelper.selectAll();
            clipboardHelper.copy();
        }
    }

    contentItem: ColumnLayout {
        spacing: Plasmoid.configuration.chatSpacing

        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: messageList
                clip: true
                spacing: 0
                headerPositioning: ListView.OverlayHeader
                header: Item { height: Plasmoid.configuration.chatSpacing }
                model: root.displayMessages

                delegate: ChatMessage {
                    width: messageList.width
                    role: model.role
                    content: model.content
                    commandsStr: model.commandsStr ? model.commandsStr : ""
                    shared: model.shared ? model.shared : false
                    messageIndex: model.index
                    timestamp: model.timestamp ? model.timestamp : ""
                    onShareRequested: function(index) { root.shareOutput(index); }
                    onRetryRequested: root.sendToLLM()
                    onExecuteRequested: function(command) { root.executeCommand(command); }
                    onTerminalRequested: function(command) { root.runInTerminal(command); }
                    onSaveRequested: function(filePath, content) { root.saveScript(filePath, content); }
                }

                onCountChanged: {
                    Qt.callLater(function() {
                        messageList.positionViewAtEnd();
                    });
                }

                Connections {
                    target: root
                    function onExpandedChanged() {
                        if (root.expanded) {
                            inputField.forceActiveFocus();
                        }
                    }
                    function onResponseReady(messageIndex) {
                        Qt.callLater(function() {
                            messageList.positionViewAtIndex(messageIndex, ListView.Beginning);
                        });
                    }
                }

                PlasmaExtras.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - (Kirigami.Units.gridUnit * 4)
                    visible: messageList.count === 0
                    text: "Send a message to start chatting"
                    iconName: "im-user"
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            QQC2.ScrollView {
                id: inputScrollView

                // Slash command autocomplete popup
                QQC2.Popup {
                    id: slashPopup
                    parent: inputScrollView
                    x: 0
                    y: -height - Kirigami.Units.smallSpacing
                    width: inputScrollView.width
                    padding: Kirigami.Units.smallSpacing
                    closePolicy: QQC2.Popup.NoAutoClose
                    visible: {
                        var t = inputField.text;
                        return inputField.activeFocus &&
                               t.startsWith("/") &&
                               t.indexOf(" ") === -1 &&
                               filteredSlashCommands.length > 0;
                    }

                    property var filteredSlashCommands: {
                        var t = inputField.text.toLowerCase();
                        if (!t.startsWith("/") || t.indexOf(" ") !== -1) return [];
                        return fullRep.slashCommands.filter(function(c) { return c.cmd.startsWith(t); });
                    }

                    contentItem: ListView {
                        id: slashList
                        implicitHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 10)
                        model: slashPopup.filteredSlashCommands
                        delegate: PlasmaComponents.ItemDelegate {
                            width: slashList.width
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                PlasmaComponents.Label {
                                    text: modelData.cmd
                                    font.bold: true
                                    color: Kirigami.Theme.highlightColor
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.desc
                                    color: Kirigami.Theme.disabledTextColor
                                    elide: Text.ElideRight
                                }
                            }
                            onClicked: {
                                inputField.text = modelData.cmd === "/model" ? "/model " : modelData.cmd;
                                inputField.cursorPosition = inputField.text.length;
                                inputField.forceActiveFocus();
                            }
                        }
                    }
                }

                // Model name autocomplete popup
                QQC2.Popup {
                    id: modelPopup
                    parent: inputScrollView
                    x: 0
                    y: -height - Kirigami.Units.smallSpacing
                    width: inputScrollView.width
                    padding: Kirigami.Units.smallSpacing
                    closePolicy: QQC2.Popup.NoAutoClose

                    property var filteredModels: {
                        var t = inputField.text;
                        if (!t.toLowerCase().startsWith("/model ")) return [];
                        var query = t.substring(7).toLowerCase();
                        var models = root.fetchedModels;
                        if (!models || models.length === 0) return [];
                        return query.length === 0 ? models :
                               models.filter(function(m) { return m.toLowerCase().indexOf(query) !== -1; });
                    }

                    visible: inputField.activeFocus &&
                             inputField.text.toLowerCase().startsWith("/model ") &&
                             filteredModels.length > 0

                    function applyModel(name) {
                        inputField.text = "/model " + name;
                        inputField.cursorPosition = inputField.text.length;
                        inputField.forceActiveFocus();
                    }

                    contentItem: ListView {
                        id: modelList
                        implicitHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 10)
                        model: modelPopup.filteredModels
                        delegate: PlasmaComponents.ItemDelegate {
                            width: modelList.width
                            contentItem: PlasmaComponents.Label {
                                text: modelData
                                font.bold: Plasmoid.configuration.modelName === modelData
                                color: Plasmoid.configuration.modelName === modelData
                                       ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                            }
                            onClicked: modelPopup.applyModel(modelData)
                        }
                    }
                }

                Layout.fillWidth: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 2
                Layout.maximumHeight: Kirigami.Units.gridUnit * 8
                Layout.preferredHeight: Math.min(inputField.contentHeight + Kirigami.Units.smallSpacing * 2, Kirigami.Units.gridUnit * 8)

                QQC2.TextArea {
                    id: inputField
                    Accessible.name: "Message input"
                    placeholderText: root.systemPromptReady ? "Type a message..." : "Initializing..."
                    enabled: !root.isLoading && root.systemPromptReady
                    focus: true
                    wrapMode: Text.Wrap

                    Keys.onTabPressed: function(event) {
                        if (inputField.text.toLowerCase().startsWith("/model ") && modelPopup.filteredModels.length === 1) {
                            inputField.text = "/model " + modelPopup.filteredModels[0];
                            inputField.cursorPosition = inputField.text.length;
                            event.accepted = true;
                        } else if (slashPopup.filteredSlashCommands.length === 1) {
                            var cmd = slashPopup.filteredSlashCommands[0].cmd;
                            inputField.text = cmd === "/model" ? "/model " : cmd;
                            inputField.cursorPosition = inputField.text.length;
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }

                    Keys.onReturnPressed: function(event) {
                        if (event.modifiers & Qt.ShiftModifier) {
                            event.accepted = false;
                        } else {
                            event.accepted = true;
                            var sendText = text.trim();
                            if (sendText.toLowerCase().startsWith("/model ") && modelPopup.filteredModels.length === 1) {
                                sendText = "/model " + modelPopup.filteredModels[0];
                            } else if (sendText.startsWith("/") && sendText.indexOf(" ") === -1 &&
                                    slashPopup.filteredSlashCommands.length === 1) {
                                sendText = slashPopup.filteredSlashCommands[0].cmd;
                            }
                            if (sendText.length > 0) {
                                root.sendMessage(sendText);
                                text = "";
                            }
                        }
                    }
                }
            }

            PlasmaComponents.Button {
                text: "Send"
                icon.name: "document-send"
                visible: !root.isLoading
                enabled: root.systemPromptReady && inputField.text.trim().length > 0
                onClicked: {
                    var sendText = inputField.text.trim();
                    if (sendText.toLowerCase().startsWith("/model ") && modelPopup.filteredModels.length === 1) {
                        sendText = "/model " + modelPopup.filteredModels[0];
                    } else if (sendText.startsWith("/") && sendText.indexOf(" ") === -1 &&
                            slashPopup.filteredSlashCommands.length === 1) {
                        sendText = slashPopup.filteredSlashCommands[0].cmd;
                    }
                    if (sendText.length > 0) {
                        root.sendMessage(sendText);
                        inputField.text = "";
                    }
                }
            }

            PlasmaComponents.Button {
                text: "Stop"
                icon.name: "media-playback-stop"
                visible: root.isLoading
                onClicked: root.cancelRequest()
            }
        }
    }
}
