/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "api.js" as Api

Item {
    id: messageItem

    property string role
    property string content
    property string commandsStr: ""
    readonly property var commands: commandsStr.length > 0 ? commandsStr.split("\n\x1F") : []
    property bool shared: false
    property int messageIndex: -1
    property string timestamp: ""

    signal shareRequested(int index)
    signal retryRequested()
    signal executeRequested(string command)
    signal terminalRequested(string command)
    signal saveRequested(string filePath, string content)

    readonly property bool isUser: role === "user"
    readonly property bool isAssistant: role === "assistant"
    readonly property bool isError: role === "error"
    readonly property bool isCommandOutput: role === "command_output"
    readonly property bool isCommandRunning: role === "command_running"
    readonly property bool isThinking: isAssistant && content.length === 0
    readonly property string strippedContent: isAssistant ? Api.stripCodeBlocks(content).trim() : content
    readonly property bool hasBubbleContent: isThinking || !isAssistant || strippedContent.length > 0
    readonly property int spacing: Plasmoid.configuration.chatSpacing

    implicitHeight: messageColumn.implicitHeight + Math.round(spacing / 4) * 2
    implicitWidth: parent ? parent.width : 300

    // Hidden helper for clipboard access
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    function copyToClipboard(text) {
        clipboardHelper.text = text;
        clipboardHelper.selectAll();
        clipboardHelper.copy();
    }

    ColumnLayout {
        id: messageColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: messageItem.spacing
        anchors.rightMargin: messageItem.spacing
        anchors.topMargin: Math.round(messageItem.spacing / 4)
        anchors.bottomMargin: Math.round(messageItem.spacing / 4)
        spacing: Math.round(messageItem.spacing / 4)

        Rectangle {
            visible: hasBubbleContent
            Layout.fillWidth: true
            Layout.maximumWidth: parent.width * 0.85
            Layout.alignment: isUser ? Qt.AlignRight : Qt.AlignLeft
            implicitHeight: messageContentRow.implicitHeight + messageItem.spacing * 3
            radius: 6
            color: {
                if (isError) return Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.15);
                if (isUser) return Kirigami.Theme.highlightColor;
                if (isCommandOutput || isCommandRunning) return Kirigami.Theme.alternateBackgroundColor;
                return Kirigami.Theme.backgroundColor;
            }
            border.color: Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.3)
            border.width: isAssistant ? 1 : 0

            RowLayout {
                id: messageContentRow
                anchors.fill: parent
                anchors.margins: messageItem.spacing * 1.5
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.BusyIndicator {
                    visible: isCommandRunning || isThinking
                    running: visible
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                PlasmaComponents.Label {
                    id: messageText
                    Layout.fillWidth: true
                    text: isThinking ? "Thinking..." : messageItem.strippedContent
                    textFormat: (isAssistant && !isThinking) ? Text.MarkdownText : Text.PlainText
                    wrapMode: Text.Wrap
                    font.family: (isCommandOutput || isCommandRunning) ? "monospace" : messageText.font.family
                    font.italic: isThinking
                    color: isThinking ? Kirigami.Theme.disabledTextColor :
                           isUser ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: isUser ? Qt.AlignRight : Qt.AlignLeft
            spacing: Kirigami.Units.smallSpacing
            visible: !isCommandRunning && hasBubbleContent

            PlasmaComponents.Label {
                visible: messageItem.timestamp.length > 0
                text: messageItem.timestamp
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }

            PlasmaComponents.ToolButton {
                icon.name: "edit-copy"
                PlasmaComponents.ToolTip.text: "Copy message"
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: messageItem.copyToClipboard(messageItem.content)
            }

            // Retry button for error messages
            PlasmaComponents.Button {
                visible: isError
                text: "Retry"
                icon.name: "view-refresh"
                onClicked: messageItem.retryRequested()
            }

            // Share with LLM button for command output
            PlasmaComponents.Button {
                visible: isCommandOutput && !messageItem.shared
                text: "Share with LLM"
                icon.name: "document-share"
                PlasmaComponents.ToolTip.text: "Include this output in the conversation"
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: messageItem.shareRequested(messageItem.messageIndex)
            }
        }

        // Command blocks for assistant messages
        Repeater {
            model: isAssistant ? messageItem.commands : []

            CommandBlock {
                Layout.fillWidth: true
                Layout.leftMargin: -messageItem.spacing
                Layout.rightMargin: -messageItem.spacing
                commandText: modelData
                onRunRequested: function(command) { messageItem.executeRequested(command); }
                onTerminalRequested: function(command) { messageItem.terminalRequested(command); }
                onSaveRequested: function(filePath, content) { messageItem.saveRequested(filePath, content); }
            }
        }
    }
}
