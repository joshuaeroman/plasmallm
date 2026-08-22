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
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus

import "api.js" as Api
import "toolManager.js" as ToolManager

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
    property bool fromVoice: false
    property bool isCompacted: false
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

    property string advancedRenderedContent: ""
    property bool isRenderingLatex: false
    readonly property int currentUiFontPointSize: root ? root.uiFontPointSize : Kirigami.Theme.defaultFont.pointSize
    property int activeRenderRequestId: 0
    property int latexRetryCount: 0
    property bool advancedRenderFailed: false
    readonly property int latexRenderMode: Plasmoid.configuration.latexRenderMode
    readonly property bool isLatexFallback: latexRenderMode === 2 && advancedRenderFailed

    readonly property string displayContent: {
        var mode = latexRenderMode;
        if (mode === 0) {
            return strippedContent;
        } else if (mode === 1) {
            return Api.replaceLatexSymbols(strippedContent);
        } else if (mode === 2) {
            if (advancedRenderedContent.length > 0) {
                return advancedRenderedContent;
            }
            if (advancedRenderFailed) {
                return Api.replaceLatexSymbols(strippedContent);
            }
            return strippedContent;
        }
        return Api.replaceLatexSymbols(strippedContent);
    }

    function triggerAdvancedRender() {
        if (isRenderingLatex || isAwaitingResponse) return;
        
        var hasMath = strippedContent.indexOf('$') !== -1 || 
                      strippedContent.indexOf('\\(') !== -1 || 
                      strippedContent.indexOf('\\[') !== -1;
                      
        if (!hasMath) {
            advancedRenderedContent = strippedContent;
            advancedRenderFailed = false;
            return;
        }
        
        isRenderingLatex = true;
        advancedRenderFailed = false;
        
        var colorHex = messageItem.bubbleTextColor ? messageItem.bubbleTextColor.toString() : "";
        var fontPt = Math.round(currentUiFontPointSize || 11);
        var reqId = ++activeRenderRequestId;
        
        var reply = DBus.SessionBus.asyncCall({
            service: "com.joshuaroman.plasmallm.latex",
            path: "/Renderer",
            iface: "com.joshuaroman.plasmallm.latex",
            member: "Render",
            arguments: [messageItem.strippedContent, colorHex, fontPt]
        });

        reply.finished.connect(function() {
            if (reqId !== activeRenderRequestId) return;
            isRenderingLatex = false;
            
            if (reply.isError) {
                var errMsg = reply.error ? (reply.error.message || reply.error.name || String(reply.error)) : "Unknown DBus error";
                console.warn("PlasmaLLM LaTeX DBus Error:", errMsg);
                if (errMsg.indexOf("not provided by any") !== -1 && latexRetryCount < 5) {
                    // Service might be starting up, retry in 500ms
                    latexRetryCount++;
                    dbusRetryTimer.start();
                    return;
                }
                advancedRenderedContent = Api.replaceLatexSymbols(strippedContent);
                advancedRenderFailed = true;
            } else {
                latexRetryCount = 0;
                var val = reply.value;
                if (val !== null && val !== undefined && typeof val === "object" && val.hasOwnProperty("value")) {
                    val = val.value;
                }
                advancedRenderedContent = (typeof val === "string" && val.length > 0) ? val : strippedContent;
                advancedRenderFailed = false;
            }
        });
    }

    Timer {
        id: dbusRetryTimer
        interval: 500
        onTriggered: triggerAdvancedRender()
    }

    onLatexRenderModeChanged: {
        isRenderingLatex = false;
        advancedRenderedContent = "";
        advancedRenderFailed = false;
        if (latexRenderMode === 2 && !isAwaitingResponse) {
            triggerAdvancedRender();
        }
    }

    onStrippedContentChanged: {
        activeRenderRequestId++;
        isRenderingLatex = false;
        advancedRenderedContent = "";
        advancedRenderFailed = false;
        
        if (latexRenderMode === 2 && !isAwaitingResponse) {
            triggerAdvancedRender();
        }
    }

    onBubbleTextColorChanged: {
        if (latexRenderMode === 2 && !isAwaitingResponse) {
            isRenderingLatex = false;
            advancedRenderedContent = "";
            advancedRenderFailed = false;
            triggerAdvancedRender();
        }
    }

    onCurrentUiFontPointSizeChanged: {
        if (latexRenderMode === 2 && !isAwaitingResponse) {
            isRenderingLatex = false;
            advancedRenderedContent = "";
            advancedRenderFailed = false;
            triggerAdvancedRender();
        }
    }

    onIsAwaitingResponseChanged: {
        if (!isAwaitingResponse && latexRenderMode === 2) {
            triggerAdvancedRender();
        }
    }

    Component.onCompleted: {
        if (latexRenderMode === 2 && !isAwaitingResponse) {
            triggerAdvancedRender();
        }
    }

    // latexRendererSource removed for DBus replacement

    property bool isEditing: false
    property string editDraft: ""

    signal shareRequested(int index)
    signal retryRequested(int messageIndex)
    signal editSaved(int messageIndex, string newContent)
    signal editAndRetryRequested(int messageIndex, string newContent)
    signal terminalRequested(string command)
    signal stopRequested(string command, string sourceId)
    signal toolApproved(string name, var args, string callId)
    signal toolDenied(string name, string callId)
    signal scrollRequested()
    signal imageViewRequested(string sourceUrl)

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
    // FYI-only pill for successful skill loads — the body went into system
    // context, not something the user needs to read.
    readonly property bool isSkillLoadedChip: isToolResult && !isToolRunning
        && toolName === "skill" && exitCode === 0

    // Successful plain tool results start collapsed as a small pill when the
    // per-tool preference says so; click to expand, chevron to re-collapse.
    readonly property bool toolCollapsibleResult: !isSkillLoadedChip
        && isToolResult && exitCode === 0
        && ToolManager.shouldCollapseResult(toolName, appConfig.toolsCollapseResults, appConfig.customTools)
    property bool toolResultExpanded: false

    readonly property var _parsedToolArgs: {
        try {
            if (typeof toolArgs === "string" && toolArgs.length > 0) return JSON.parse(toolArgs);
            return (toolArgs && typeof toolArgs === "object") ? toolArgs : {};
        } catch (e) { return {}; }
    }
    readonly property string toolPillText: {
        var home = "$HOME";
        if (typeof root !== 'undefined' && root.sysInfo && root.sysInfo.userHome) home = root.sysInfo.userHome;
        if (isSkillLoadedChip) return i18n("Loaded %1 skill", _parsedToolArgs.name || "");
        return ToolManager.resultLabel(toolName, _parsedToolArgs, home);
    }
    readonly property string strippedContent: content.trim()
    readonly property bool hasBubbleContent: !isToolPending && !isToolRunning && !isToolResult && (isAwaitingResponse || !isAssistant || strippedContent.length > 0)

    readonly property bool useConsoleStyle: outputScheme === "console style" || (outputScheme === "" && (isCommandOutput || isCommandRunning))
    readonly property bool useScrollableContent: outputScheme === "console style" || (outputScheme === "" && isCommandOutput)

    readonly property color bubbleTextColor: {
        var c = isUser ? root.userColor : root.assistantColor;
        var luminance = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
        return luminance < 0.5 ? "#eff0f1" : "#232629";
    }

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

            // Separate label so emoji can use a color-emoji font; theme UI fonts often omit 🗣️.
            PlasmaComponents.Label {
                visible: isUser && fromVoice
                text: "🗣️"
                font.family: "Noto Color Emoji, Noto Emoji, emoji, sans-serif"
                font.pointSize: Math.max(8, Kirigami.Theme.defaultFont.pointSize - (Plasmoid.configuration.chatSpacing < 4 ? 1 : 0))
                Layout.alignment: Qt.AlignVCenter
                Accessible.name: i18n("Voice message")
            }

            PlasmaComponents.Label {
                text: {
                    if (isUser)
                        return Plasmoid.configuration.userName || i18n("You");
                    if (isError)
                        return i18n("Error");
                    if (toolTitle !== "")
                        return toolTitle;
                    if (isWebSearchRunning || isWebSearchResults)
                        return i18n("Web Search");
                    if (Plasmoid.configuration.showModelNameAsAssistant)
                        return Plasmoid.configuration.modelName || Plasmoid.configuration.assistantName || i18n("Assistant");
                    return Plasmoid.configuration.assistantName || i18n("Assistant");
                }
                font.bold: true
                font.pointSize: Math.max(8, Kirigami.Theme.defaultFont.pointSize - (Plasmoid.configuration.chatSpacing < 4 ? 1 : 0))
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents.Label {
                text: timestamp
                font: Kirigami.Theme.smallFont
                opacity: 0.6
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: !messageItem.isCompacted
            }

            RowLayout {
                visible: messageItem.isCompacted
                spacing: 2
                opacity: 0.65
                Layout.alignment: Qt.AlignVCenter

                Kirigami.Icon {
                    source: "archive-insert"
                    implicitWidth: Math.round(Kirigami.Units.iconSizes.small * 0.8)
                    implicitHeight: Math.round(Kirigami.Units.iconSizes.small * 0.8)
                }

                PlasmaComponents.Label {
                    text: i18n("compacted")
                    font.pointSize: Math.max(7, Kirigami.Theme.smallFont.pointSize - 1)
                }

                PlasmaComponents.ToolTip.text: i18n("This message has been summarized into the compacted context. Citations active.")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: compactedBadgeHover.hovered

                HoverHandler {
                    id: compactedBadgeHover
                }
            }

            Item {
                Layout.fillWidth: true
                visible: messageItem.isCompacted
            }

            Kirigami.Icon {
                source: "dialog-warning"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                visible: messageItem.isLatexFallback
                Layout.alignment: Qt.AlignVCenter
                PlasmaComponents.ToolTip.text: i18n("Mathtext rendering fell back to Unicode replacement (matplotlib not installed or error occurred)")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
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
            color: {
                var base = isUser ? root.userColor : root.assistantColor;
                if (messageItem.isCompacted) {
                    var lum = (0.299 * base.r + 0.587 * base.g + 0.114 * base.b);
                    return lum < 0.5 ? Qt.lighter(base, 1.18) : Qt.tint(base, Qt.rgba(1, 1, 1, 0.35));
                }
                return base;
            }
            radius: Math.max(4, messageItem.bubblePadding / 2)
            border.color: isError ? Kirigami.Theme.negativeTextColor : (isUser ? "transparent" : Kirigami.Theme.alternateBackgroundColor)
            border.width: isError ? 2 : 1

            property bool bubbleHovered: false

            HoverHandler {
                id: bubbleHover
                onHoveredChanged: bubble.bubbleHovered = hovered
            }

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
                    color: messageItem.bubbleTextColor
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
                                color: messageItem.bubbleTextColor
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
                                    color: messageItem.bubbleTextColor
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.url || modelData.link || ""
                                    font: Kirigami.Theme.smallFont
                                    color: messageItem.bubbleTextColor
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
                    visible: strippedContent.length > 0 && !isWebSearchResults && !isWebSearchRunning && !messageItem.isEditing
                    text: displayContent
                    wrapMode: Text.Wrap
                    font.family: useConsoleStyle ? root.codeFontFamily : root.uiFontFamily
                    font.pointSize: useConsoleStyle ? root.codeFontPointSize : root.uiFontPointSize
                    color: isError ? Kirigami.Theme.negativeTextColor : messageItem.bubbleTextColor

                    // We use the markdown capability of Kirigami.SelectableLabel if available,
                    // or just plain text if it's a console-style output.
                    textFormat: useConsoleStyle ? Text.PlainText : Text.MarkdownText

                    onLinkActivated: function(link) {
                        if (link.startsWith("file://") && (link.endsWith(".svg") || link.indexOf(".svg?") !== -1)) {
                            messageItem.imageViewRequested(link);
                        } else {
                            Qt.openUrlExternally(link);
                        }
                    }
                }

                // Inline Editor (shown when editing)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: messageItem.isEditing
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(editTextArea.contentHeight + Kirigami.Units.smallSpacing * 4, Kirigami.Units.gridUnit * 12)
                        Layout.minimumHeight: Kirigami.Units.gridUnit * 4

                        QQC2.TextArea {
                            id: editTextArea
                            text: messageItem.editDraft
                            onTextChanged: messageItem.editDraft = text
                            wrapMode: Text.Wrap
                            font.family: root ? root.uiFontFamily : Kirigami.Theme.defaultFont.family
                            font.pointSize: root ? root.uiFontPointSize : Kirigami.Theme.defaultFont.pointSize
                            focus: messageItem.isEditing
                            color: messageItem.bubbleTextColor
                            background: Rectangle {
                                color: Kirigami.Theme.alternateBackgroundColor
                                border.color: Kirigami.Theme.focusColor
                                border.width: 1
                                radius: 4
                            }

                            function submitEdit(event) {
                                if (event.modifiers & Qt.ControlModifier) {
                                    event.accepted = true;
                                    if (messageItem.isUser) {
                                        messageItem.editAndRetryRequested(messageItem.messageIndex, messageItem.editDraft);
                                    } else {
                                        messageItem.editSaved(messageItem.messageIndex, messageItem.editDraft);
                                    }
                                    messageItem.isEditing = false;
                                    messageItem.editDraft = "";
                                } else {
                                    event.accepted = false; // allow multiline newline
                                }
                            }

                            Keys.onEscapePressed: function(event) {
                                event.accepted = true;
                                messageItem.isEditing = false;
                                messageItem.editDraft = "";
                            }

                            Keys.onReturnPressed: function(event) {
                                submitEdit(event);
                            }

                            Keys.onEnterPressed: function(event) {
                                submitEdit(event);
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Button {
                            text: i18n("Cancel")
                            icon.name: "dialog-cancel"
                            onClicked: {
                                messageItem.isEditing = false;
                                messageItem.editDraft = "";
                            }
                        }

                        PlasmaComponents.Button {
                            text: i18n("Save")
                            icon.name: "document-save"
                            onClicked: {
                                messageItem.editSaved(messageItem.messageIndex, messageItem.editDraft);
                                messageItem.isEditing = false;
                                messageItem.editDraft = "";
                            }
                        }

                        PlasmaComponents.Button {
                            text: i18n("Save & Retry")
                            icon.name: "edit-redo"
                            visible: messageItem.isUser
                            onClicked: {
                                messageItem.editAndRetryRequested(messageItem.messageIndex, messageItem.editDraft);
                                messageItem.isEditing = false;
                                messageItem.editDraft = "";
                            }
                        }
                    }
                }

                // Attachments
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: attachmentPaths.length > 0

                    Repeater {
                        model: attachmentPaths
                        delegate: Loader {
                            id: attachmentLoader
                            readonly property string filePath: modelData
                            readonly property bool isImage: filePath.startsWith("data:") || Api.isImageFile(filePath)
                            readonly property string fileName: filePath.startsWith("data:") ? "pasted_image.png" : filePath.split("/").pop()

                            sourceComponent: isImage ? imageThumbnailComponent : genericFileComponent
                        }
                    }
                }
            }

            // Action Buttons Toolbar for Bubble (shown on hover only with opaque background)
            Rectangle {
                id: hoverToolbar
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Kirigami.Units.smallSpacing
                implicitWidth: actionRow.implicitWidth + (Kirigami.Units.smallSpacing * 2)
                implicitHeight: actionRow.implicitHeight + (Kirigami.Units.smallSpacing * 2)
                radius: Math.max(4, messageItem.bubblePadding / 3)
                color: Kirigami.Theme.backgroundColor
                border.color: Kirigami.Theme.alternateBackgroundColor
                border.width: 1
                visible: bubble.bubbleHovered && !messageItem.isEditing
                         && !messageItem.isAwaitingResponse
                         && !(root && root.isLoading)
                         && (messageItem.isUser || (messageItem.isAssistant && messageItem.strippedContent.length > 0))
                z: 10

                RowLayout {
                    id: actionRow
                    anchors.centerIn: parent
                    spacing: 2

                    PlasmaComponents.ToolButton {
                        icon.name: "edit-copy"
                        display: PlasmaComponents.ToolButton.IconOnly
                        PlasmaComponents.ToolTip.text: i18n("Copy to clipboard")
                        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                        PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                        onClicked: {
                            var temp = Qt.createQmlObject('import QtQuick 2.0; TextEdit { visible: false }', messageItem);
                            temp.text = messageItem.strippedContent;
                            temp.selectAll();
                            temp.copy();
                            temp.destroy();
                        }
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "document-edit"
                        display: PlasmaComponents.ToolButton.IconOnly
                        PlasmaComponents.ToolTip.text: messageItem.isUser ? i18n("Edit message") : i18n("Edit response")
                        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                        PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                        onClicked: {
                            messageItem.editDraft = messageItem.content;
                            messageItem.isEditing = true;
                        }
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "view-refresh"
                        display: PlasmaComponents.ToolButton.IconOnly
                        PlasmaComponents.ToolTip.text: messageItem.isUser ? i18n("Retry from here") : i18n("Regenerate response")
                        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                        PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                        onClicked: messageItem.retryRequested(messageItem.messageIndex)
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "share"
                        visible: messageItem.isCommandOutput && !messageItem.shared
                        PlasmaComponents.ToolTip.text: i18n("Share output with assistant")
                        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                        PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                        onClicked: messageItem.shareRequested(messageItem.messageIndex)
                    }
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
            Layout.fillWidth: !(isSkillLoadedChip || (toolCollapsibleResult && !toolResultExpanded))
            sourceComponent: (isSkillLoadedChip || (toolCollapsibleResult && !toolResultExpanded)) ? toolPillComponent : toolResultBlockComponent
        }

        // Compact FYI pill: skill loads ("Loaded x skill") and collapsed tool
        // results (click to expand). Full details stay one click away.
        Component {
            id: toolPillComponent
            Rectangle {
                id: pill
                radius: height / 2
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: Kirigami.Theme.disabledTextColor
                border.width: 1
                readonly property real pillPad: (Plasmoid.configuration.chatSpacing || 0) / 2
                implicitWidth: pillRow.implicitWidth + Kirigami.Units.largeSpacing + pillPad
                implicitHeight: pillRow.implicitHeight + Kirigami.Units.smallSpacing + pillPad
                width: implicitWidth
                height: implicitHeight

                HoverHandler {
                    id: pillHover
                    cursorShape: Qt.PointingHandCursor
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !messageItem.isSkillLoadedChip
                    onClicked: messageItem.toolResultExpanded = true
                }

                PlasmaComponents.ToolTip.text: messageItem.isSkillLoadedChip
                    ? i18n("The model loaded this skill's instructions into context before acting.")
                    : messageItem.toolPillText
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: pillHover.hovered

                RowLayout {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: ToolManager.toolIconName(messageItem.isSkillLoadedChip ? "skill" : messageItem.toolName)
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }

                    PlasmaComponents.Label {
                        text: messageItem.toolPillText
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.disabledTextColor
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
                    }
                }
            }
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
                attachmentPaths: messageItem.attachmentPaths
                collapsible: messageItem.toolCollapsibleResult
                onCollapseRequested: messageItem.toolResultExpanded = false
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

        Component {
            id: imageThumbnailComponent
            Rectangle {
                id: imageThumb
                readonly property string filePath: parent ? (parent.filePath || "") : ""
                readonly property string fileName: parent ? (parent.fileName || "") : ""

                readonly property real maxW: Kirigami.Units.gridUnit * 10
                readonly property real maxH: Kirigami.Units.gridUnit * 10
                readonly property real aspect: (thumbImg.sourceSize.width > 0 && thumbImg.sourceSize.height > 0) ? (thumbImg.sourceSize.width / thumbImg.sourceSize.height) : 1.0

                width: aspect > (maxW / maxH) ? maxW : maxH * aspect
                height: aspect > (maxW / maxH) ? maxW / aspect : maxH
                radius: 4
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: mouseArea.containsMouse ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
                border.width: mouseArea.containsMouse ? 2 : 1
                clip: true

                Image {
                    id: thumbImg
                    anchors.fill: parent
                    anchors.margins: imageThumb.border.width
                    source: imageThumb.filePath.startsWith("data:") ? imageThumb.filePath : Qt.resolvedUrl("file://" + imageThumb.filePath)
                    autoTransform: true
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }

                Kirigami.Icon {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Kirigami.Units.smallSpacing
                    width: Kirigami.Units.iconSizes.small
                    height: Kirigami.Units.iconSizes.small
                    source: "zoom-in"
                    visible: mouseArea.containsMouse

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 4
                        height: parent.height + 4
                        radius: width / 2
                        color: "#80000000"
                        z: -1
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (imageThumb.filePath.startsWith("data:")) {
                            messageItem.imageViewRequested(imageThumb.filePath)
                        } else {
                            Qt.openUrlExternally("file://" + imageThumb.filePath)
                        }
                    }
                }

                PlasmaComponents.ToolTip.text: imageThumb.fileName
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: mouseArea.containsMouse
            }
        }

        Component {
            id: genericFileComponent
            Kirigami.Chip {
                id: chipItem
                readonly property string fileName: parent ? (parent.fileName || "") : ""
                text: fileName
                icon.name: "document-export"
                closable: false
                checkable: false
            }
        }
    }
}
