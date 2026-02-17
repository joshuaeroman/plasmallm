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

    contentItem: ColumnLayout {
        spacing: Plasmoid.configuration.chatSpacing

        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: messageList
                clip: true
                spacing: Plasmoid.configuration.chatSpacing
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

                    Keys.onReturnPressed: function(event) {
                        if (event.modifiers & Qt.ShiftModifier) {
                            event.accepted = false;
                        } else {
                            event.accepted = true;
                            if (text.trim().length > 0) {
                                root.sendMessage(text.trim());
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
                    if (inputField.text.trim().length > 0) {
                        root.sendMessage(inputField.text.trim());
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
