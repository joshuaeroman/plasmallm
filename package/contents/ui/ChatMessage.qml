/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "api.js" as Api

/**
 * Renders a single chat message (user, assistant, tool result, etc.)
 */
Kirigami.AbstractCard {
    id: messageItem

    property string role
    property string content
    property string thinking: ""
    property bool shared: false
    property int messageIndex: -1
    property string timestamp: ""
    property string attachmentsStr: ""
    readonly property var attachmentPaths: attachmentsStr.length > 0 ? attachmentsStr.split("\n") : []
    property string tool_call_id: ""
    property string toolArgs: ""
    property string toolName: ""
    property string stdout: ""
    property string stderr: ""
    property int exitCode: 0
    property string outputScheme: ""
    property string toolSummary: ""
    property string toolDataJson: ""
    property string toolView: ""
    property string toolIcon: ""
    property string toolTitle: ""
    onToolDataJsonChanged: toolExpanded = false
    property bool toolExpanded: false
    property bool thinkingExpanded: false

    signal shareRequested(int index)
    signal retryRequested()
    signal terminalRequested(string command)
    signal stopRequested(string command, string sourceId)
    signal toolApproved(string name, var args, string callId)
    signal toolDenied(string name, string callId)
    signal scrollRequested()

    property bool sessionMode: false
    property string sessionLabel: ""
    property int commandRunStateTick: 0
    property var appConfig: ({})
    property bool isAwaitingResponse: false

    readonly property bool isUser: role === "user"
    readonly property bool isAssistant: role === "assistant"
    readonly property bool isError: role === "error"
    readonly property bool isCommandOutput: role === "command_output"
    readonly property bool isCommandRunning: role === "command_running"
    readonly property bool isWebSearchRunning: role === "web_search_running" || (role === "tool_running_rich" && toolView === "search")
    readonly property bool isWebSearchResults: role === "web_search_results" || (role === "tool_result_rich" && toolView === "search")
    readonly property bool isToolRunningRich: role === "tool_running_rich"
    readonly property bool isToolResultRich: role === "tool_result_rich"
    readonly property bool isToolPending: role === "tool_pending"
    readonly property bool isToolRunning: role === "tool_running"
    readonly property bool isToolResult: role === "tool_result"
    readonly property string strippedContent: content.trim()
    readonly property bool hasBubbleContent: !isToolPending && !isToolRunning && !isToolResult && (isAwaitingResponse || !isAssistant || strippedContent.length > 0)

    readonly property bool useConsoleStyle: outputScheme === "console style" || (outputScheme === "" && (isCommandOutput || isCommandRunning))
    readonly property bool useScrollableContent: outputScheme === "console style" || (outputScheme === "" && isCommandOutput)

    readonly property real itemSpacing: Math.min(Kirigami.Units.smallSpacing, Plasmoid.configuration.chatSpacing)
    readonly property real bubblePadding: Math.max(Kirigami.Units.smallSpacing, Math.min(Kirigami.Units.gridUnit * 0.75, Plasmoid.configuration.chatSpacing + Kirigami.Units.smallSpacing))
    readonly property int messageAlignment: isUser ? Qt.AlignRight : Qt.AlignLeft
    readonly property real bubbleWidthMultiplier: 0.75
    readonly property bool shouldLimitWidth: isUser || isAssistant || isError

    Layout.fillWidth: true
    Layout.topMargin: 0
    Layout.bottomMargin: 0

    padding: 0
    verticalPadding: 0
    horizontalPadding: 0

    background: null
    contentItem: ColumnLayout {
        spacing: messageItem.itemSpacing

        // Timestamp and Role Header
        RowLayout {
            Layout.fillWidth: !messageItem.shouldLimitWidth
            Layout.preferredWidth: messageItem.shouldLimitWidth ? messageItem.width * messageItem.bubbleWidthMultiplier : -1
            Layout.alignment: messageItem.shouldLimitWidth ? messageItem.messageAlignment : Qt.AlignLeft
            spacing: messageItem.itemSpacing
            visible: !isToolPending && !isToolRunning && !isToolResult && (hasBubbleContent || thinking.length > 0)

            Kirigami.Icon {
                source: isUser ? "user" : (isError ? "error" : (toolIcon !== "" ? toolIcon : (isWebSearchRunning || isWebSearchResults ? "browser-search" : "dialog-messages")))
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents.Label {
                text: isUser ? i18n("You") : (isError ? i18n("Error") : (toolTitle !== "" ? toolTitle : (isWebSearchRunning || isWebSearchResults ? i18n("Web Search") : i18n("Assistant"))))
                font.bold: true
                font.pointSize: Math.max(8, Kirigami.Theme.defaultFont.pointSize - (Plasmoid.configuration.chatSpacing < 4 ? 1 : 0))
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents.Label {
                text: timestamp
                font: Kirigami.Theme.smallFont
                opacity: 0.6
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
            }
        }

        // Thinking Block
        ColumnLayout {
            Layout.fillWidth: !messageItem.shouldLimitWidth
            Layout.preferredWidth: messageItem.shouldLimitWidth ? messageItem.width * messageItem.bubbleWidthMultiplier : -1
            Layout.alignment: messageItem.messageAlignment
            visible: isAssistant && thinking.length > 0
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                QQC2.CheckBox {
                    id: thinkingCheck
                    text: i18n("Thinking")
                    checked: messageItem.thinkingExpanded
                    onToggled: messageItem.thinkingExpanded = checked
                }
                Item { Layout.fillWidth: true }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: thinkingText.implicitHeight + Kirigami.Units.gridUnit
                visible: thinkingCheck.checked
                color: Kirigami.Theme.alternateBackgroundColor
                radius: Kirigami.Units.smallSpacing

                Flickable {
                    anchors.fill: parent
                    anchors.margins: messageItem.bubblePadding
                    contentWidth: width
                    contentHeight: thinkingText.implicitHeight
                    clip: true

                    PlasmaComponents.Label {
                        id: thinkingText
                        width: parent.width
                        text: thinking
                        wrapMode: Text.Wrap
                        font.family: root.thoughtsFontFamily
                        font.pointSize: root.thoughtsFontPointSize
                        opacity: 0.8
                    }
                }
            }
        }

        // Message Bubble
        Rectangle {
            id: bubble
            Layout.fillWidth: !messageItem.shouldLimitWidth
            Layout.preferredWidth: messageItem.shouldLimitWidth ? messageItem.width * messageItem.bubbleWidthMultiplier : -1
            Layout.alignment: messageItem.shouldLimitWidth ? messageItem.messageAlignment : Qt.AlignLeft
            Layout.preferredHeight: contentLayout.implicitHeight + (messageItem.bubblePadding * 2)
            visible: hasBubbleContent
            color: isUser ? Kirigami.Theme.alternateBackgroundColor : Kirigami.Theme.backgroundColor
            radius: Math.max(4, messageItem.bubblePadding / 2)
            border.color: isError ? Kirigami.Theme.negativeTextColor : (isUser ? "transparent" : Kirigami.Theme.alternateBackgroundColor)
            border.width: isError ? 2 : 1

            ColumnLayout {
                id: contentLayout
                anchors.fill: parent
                anchors.margins: messageItem.bubblePadding
                spacing: messageItem.itemSpacing

                // Loading Indicator
                PlasmaComponents.BusyIndicator {
                    Layout.alignment: Qt.AlignLeft
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                    visible: (isAssistant && isAwaitingResponse && strippedContent.length === 0) || isWebSearchRunning
                    running: visible
                }

                // Web Search Query (Always visible if running or has results)
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: isWebSearchRunning || (isWebSearchResults && toolSummary !== "")
                    text: isWebSearchRunning ? content : i18n("Searched for: %1", toolSummary)
                    font.italic: true
                    opacity: 0.8
                }

                // Web Search Results (Collapsible)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: isWebSearchResults && toolDataJson !== ""
                    spacing: Kirigami.Units.smallSpacing

                    MouseArea {
                        id: toolHeader
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            messageItem.toolExpanded = !messageItem.toolExpanded;
                            if (messageItem.toolExpanded) {
                                messageItem.scrollRequested();
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: messageItem.toolExpanded ? "arrow-down" : "arrow-right"
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                                Layout.alignment: Qt.AlignVCenter
                            }

                            PlasmaComponents.Label {
                                text: i18n("Show %1 results", (function() {
                                    try {
                                        var r = JSON.parse(toolDataJson);
                                        var items = r.results || r;
                                        return Array.isArray(items) ? items.length : 0;
                                    } catch(e) { return 0; }
                                })())
                                font.bold: true
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: messageItem.toolExpanded
                        spacing: Kirigami.Units.gridUnit

                        Repeater {
                            model: {
                                try {
                                    var r = JSON.parse(toolDataJson);
                                    return r.results || r;
                                } catch(e) { return []; }
                            }
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.title || modelData.name || "Result"
                                    font.bold: true
                                    wrapMode: Text.Wrap
                                    color: Kirigami.Theme.linkColor
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally(modelData.url || modelData.link || "")
                                    }
                                }

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: (modelData.snippet || modelData.description || modelData.content || "").trim()
                                    wrapMode: Text.Wrap
                                    font: Kirigami.Theme.smallFont
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.url || modelData.link || ""
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.5
                                    elide: Text.ElideMiddle
                                    visible: text !== ""
                                }
                            }
                        }
                    }
                }

                // Text Content
                Kirigami.SelectableLabel {
                    Layout.fillWidth: true
                    visible: strippedContent.length > 0 && !isWebSearchResults && !isWebSearchRunning
                    text: strippedContent
                    wrapMode: Text.Wrap
                    font.family: useConsoleStyle ? root.codeFontFamily : root.uiFontFamily
                    font.pointSize: useConsoleStyle ? root.codeFontPointSize : root.uiFontPointSize
                    color: isError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor

                    // We use the markdown capability of Kirigami.SelectableLabel if available,
                    // or just plain text if it's a console-style output.
                    textFormat: useConsoleStyle ? Text.PlainText : Text.MarkdownText
                }

                // Attachments
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: attachmentPaths.length > 0

                    Repeater {
                        model: attachmentPaths
                        delegate: Kirigami.Chip {
                            text: modelData.split("/").pop()
                            icon.name: Api.isImageFile(modelData) ? "image-x-generic" : "document-export"
                            closable: false
                            checkable: false
                        }
                    }
                }
            }

            // Action Buttons for Bubble
            RowLayout {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                visible: isAssistant && strippedContent.length > 0

                PlasmaComponents.ToolButton {
                    icon.name: "edit-copy"
                    PlasmaComponents.ToolTip.text: i18n("Copy to clipboard")
                    PlasmaComponents.ToolTip.visible: hovered
                    onClicked: {
                        var temp = Qt.createQmlObject('import QtQuick 2.0; TextEdit { visible: false }', messageItem);
                        temp.text = strippedContent;
                        temp.selectAll();
                        temp.copy();
                        temp.destroy();
                    }
                }

                PlasmaComponents.ToolButton {
                    icon.name: "share"
                    visible: isCommandOutput && !shared
                    PlasmaComponents.ToolTip.text: i18n("Share output with assistant")
                    PlasmaComponents.ToolTip.visible: hovered
                    onClicked: messageItem.shareRequested(messageItem.messageIndex)
                }
            }
        }

        Loader {
            visible: isToolPending
            Layout.fillWidth: true
            sourceComponent: toolApprovalCardComponent
        }

        Loader {
            visible: isToolRunning || isToolResult
            Layout.fillWidth: true
            sourceComponent: toolResultBlockComponent
        }

        Component {
            id: toolResultBlockComponent
            ToolResultBlock {
                toolName: messageItem.toolName
                toolArgs: messageItem.toolArgs
                stdout: messageItem.stdout
                stderr: messageItem.stderr
                exitCode: messageItem.exitCode
                isRunning: messageItem.isToolRunning
                sessionMode: messageItem.sessionMode
                sessionLabel: messageItem.sessionLabel
                onTerminalRequested: cmd => messageItem.terminalRequested(cmd)
                onStopRequested: cmd => messageItem.stopRequested(cmd, "")
            }
        }

        Component {
            id: toolApprovalCardComponent
            ToolApprovalCard {
                toolName: messageItem.content
                tool_call_id: messageItem.tool_call_id
                toolArgsJson: messageItem.toolArgs
                appConfig: messageItem.appConfig
                onApproved: function(name, args, callId) {
                    messageItem.toolApproved(name, args, callId);
                }
                onDenied: function(name, callId) {
                    messageItem.toolDenied(name, callId);
                }
            }
        }
    }
}
