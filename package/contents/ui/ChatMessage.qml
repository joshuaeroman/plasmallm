/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import QtQuick.Controls as QQC2
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
    property string attachmentsStr: ""
    readonly property var attachmentPaths: attachmentsStr.length > 0 ? attachmentsStr.split("\n") : []
    property bool webSearchExpanded: false

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
    readonly property bool isWebSearchResults: role === "web_search_results"
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
            implicitHeight: isWebSearchResults ? webSearchColumn.implicitHeight + messageItem.spacing * 3 : messageContentRow.implicitHeight + messageItem.spacing * 3 + (attachmentFlow.visible ? attachmentFlow.height + Kirigami.Units.smallSpacing : 0)
            radius: 6
            color: {
                if (isError) return Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.15);
                if (isUser) return Kirigami.Theme.highlightColor;
                if (isCommandOutput || isCommandRunning) return Kirigami.Theme.alternateBackgroundColor;
                if (isWebSearchResults) return Qt.rgba(Kirigami.Theme.positiveTextColor.r, Kirigami.Theme.positiveTextColor.g, Kirigami.Theme.positiveTextColor.b, 0.1);
                return Kirigami.Theme.backgroundColor;
            }
            border.color: Qt.rgba(Kirigami.Theme.disabledTextColor.r, Kirigami.Theme.disabledTextColor.g, Kirigami.Theme.disabledTextColor.b, 0.3)
            border.width: (isAssistant || isWebSearchResults) ? 1 : 0

            // Collapsible web search results
            ColumnLayout {
                id: webSearchColumn
                visible: isWebSearchResults
                anchors.fill: parent
                anchors.margins: messageItem.spacing * 1.5
                spacing: Kirigami.Units.smallSpacing

                Item {
                    Layout.fillWidth: true
                    implicitHeight: webSearchHeaderRow.implicitHeight

                    RowLayout {
                        id: webSearchHeaderRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: webSearchExpanded ? "arrow-down" : "arrow-right"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: i18n("Web Search Results")
                            font.bold: true
                            color: Kirigami.Theme.textColor
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: webSearchExpanded = !webSearchExpanded
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Loader {
                    visible: webSearchExpanded
                    Layout.fillWidth: true
                    Layout.maximumHeight: scrollMaxHeight
                    Layout.preferredHeight: visible ? Math.min(item ? item.implicitHeight : 0, scrollMaxHeight) : 0

                    readonly property real scrollMaxHeight: Kirigami.Theme.defaultFont.pixelSize * 1.4 * 20

                    sourceComponent: scrollableMarkdownContent
                }
            }

            // Attached image thumbnails
            Flow {
                id: attachmentFlow
                visible: !isWebSearchResults && messageItem.attachmentPaths.length > 0
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: messageItem.spacing * 1.5
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: messageItem.attachmentPaths
                    Image {
                        source: "file://" + modelData
                        fillMode: Image.PreserveAspectFit
                        width: Math.min(sourceSize.width, attachmentFlow.width)
                        height: Math.min(sourceSize.height, Kirigami.Units.gridUnit * 10)
                        smooth: true
                        horizontalAlignment: Image.AlignLeft
                    }
                }
            }

            // Standard message content
            RowLayout {
                id: messageContentRow
                visible: !isWebSearchResults
                anchors.fill: parent
                anchors.topMargin: attachmentFlow.visible ? attachmentFlow.height + attachmentFlow.anchors.margins + Kirigami.Units.smallSpacing : messageItem.spacing * 1.5
                anchors.leftMargin: messageItem.spacing * 1.5
                anchors.rightMargin: messageItem.spacing * 1.5
                anchors.bottomMargin: messageItem.spacing * 1.5
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.BusyIndicator {
                    visible: isCommandRunning || isThinking
                    running: visible
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                Loader {
                    Layout.fillWidth: true
                    Layout.maximumHeight: isCommandOutput ? scrollMaxHeight : -1
                    Layout.preferredHeight: isCommandOutput ? Math.min(item ? item.implicitHeight : 0, scrollMaxHeight) : (item ? item.implicitHeight : 0)

                    readonly property real scrollMaxHeight: Kirigami.Theme.defaultFont.pixelSize * 1.4 * 20

                    sourceComponent: isCommandOutput ? scrollableContent : plainContent
                }

                Component {
                    id: scrollableContent
                    QQC2.ScrollView {
                        contentWidth: availableWidth
                        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                        QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded

                        PlasmaComponents.Label {
                            width: parent.width
                            text: messageItem.strippedContent
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            font.family: "monospace"
                            color: Kirigami.Theme.textColor
                        }
                    }
                }

                Component {
                    id: plainContent
                    PlasmaComponents.Label {
                        width: parent ? parent.width : implicitWidth
                        text: isThinking ? i18n("Thinking…") : messageItem.strippedContent
                        textFormat: (isAssistant && !isThinking) ? Text.MarkdownText : Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: isCommandRunning ? "monospace" : font.family
                        font.italic: isThinking
                        color: isThinking ? Kirigami.Theme.disabledTextColor :
                               isUser ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    }
                }
            }

            Component {
                id: scrollableMarkdownContent
                QQC2.ScrollView {
                    contentWidth: availableWidth
                    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                    QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded

                    PlasmaComponents.Label {
                        width: parent.width
                        text: messageItem.content
                        textFormat: Text.MarkdownText
                        wrapMode: Text.Wrap
                        color: Kirigami.Theme.textColor
                    }
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
                PlasmaComponents.ToolTip.text: i18n("Copy message")
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: messageItem.copyToClipboard(messageItem.content)
            }

            // Retry button for error messages
            PlasmaComponents.Button {
                visible: isError
                text: i18n("Retry")
                icon.name: "view-refresh"
                onClicked: messageItem.retryRequested()
            }

            // Share with LLM button for command output
            PlasmaComponents.Button {
                visible: isCommandOutput && !messageItem.shared
                text: i18n("Share with LLM")
                icon.name: "document-share"
                PlasmaComponents.ToolTip.text: i18n("Include this output in the conversation")
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
