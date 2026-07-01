/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.draganddrop as DragDrop

import "profiles.js" as Profiles
import "driverManager.js" as DriverManager

PlasmaExtras.Representation {
    id: fullRep

    property var slashCommands: {
        var list = [
            { cmd: "/approve",  desc: i18n("Approve the pending tool request") },
            { cmd: "/auto",     desc: i18n("Toggle skip approvals for this session") },
            { cmd: "/clear",    desc: i18n("Clear the chat") },
            { cmd: "/close",    desc: i18n("Close the panel") },
            { cmd: "/copy",     desc: i18n("Copy conversation to clipboard") },
            { cmd: "/deny",     desc: i18n("Deny the pending tool request") },
            { cmd: "/history",  desc: i18n("Open chat history folder") },
            { cmd: "/model",    desc: i18n("Show or switch model (/model <name>)") },
            { cmd: "/profile",  desc: i18n("Switch profile (/profile <name>)") },
            { cmd: "/save",     desc: i18n("Save chat to file") },
            { cmd: "/settings", desc: i18n("Open settings") },
            { cmd: "/task",     desc: i18n("Run a saved task (/task <name>)") }
        ];
        if (root.isDriverServiceActive) {
            list.push({ cmd: "/drive", desc: i18n("Toggle Drive Desktop mode (starts handshake and auto mode)") });
        }
        return list;
    }

    property var configuredTasks: {
        var json = Plasmoid.configuration.tasks;
        if (!json || json.length === 0) return [];
        try { return JSON.parse(json); } catch(e) { return []; }
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 24
    Layout.preferredWidth: Kirigami.Units.gridUnit * 28
    Layout.preferredHeight: Kirigami.Units.gridUnit * 32
    
    onActiveFocusChanged: {
        if (!activeFocus) {
            Plasmoid.status = PlasmaCore.Types.ActiveStatus;
        }
    }

    header: PlasmaExtras.BasicPlasmoidHeading {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.ToolButton {
                id: profileToolButton
                text: {
                    var profiles = Profiles.loadProfiles(Plasmoid.configuration);
                    var active = Profiles.getActive(profiles, Plasmoid.configuration.activeProfileId);
                    var name = active ? active.name : "Default";
                    
                    if (!Plasmoid.configuration.showProviderInTitle) {
                        return name === "Default" ? "PlasmaLLM" : name;
                    }
                    
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

                    var details = "";
                    if (provider && model) {
                        details = provider + " | " + model;
                    } else if (model) {
                        details = model;
                    }

                    if (details) {
                        if (name === "Default") {
                            return details;
                        } else {
                            return name + " (" + details + ")";
                        }
                    }
                    
                    return name === "Default" ? "PlasmaLLM" : name;
                }
                font.bold: true
                Layout.fillWidth: true
                visible: Plasmoid.configuration.showIconProfile
                checkable: true
                checked: profileMenu.opened
                onClicked: {
                    if (profileMenu.opened) {
                        profileMenu.close()
                    } else {
                        profileMenu.popup(profileToolButton, 0, profileToolButton.height)
                    }
                }

                QQC2.Menu {
                    id: profileMenu
                    closePolicy: QQC2.Menu.CloseOnEscape | QQC2.Menu.CloseOnPressOutsideParent
                }

                Instantiator {
                    model: Profiles.loadProfiles(Plasmoid.configuration)
                    onObjectAdded: function(index, object) { profileMenu.insertItem(index, object); }
                    onObjectRemoved: function(index, object) { profileMenu.removeItem(object); }
                    delegate: QQC2.MenuItem {
                        text: modelData.name + (modelData.modelName ? " (" + modelData.modelName + ")" : "")
                        onTriggered: {
                            root.switchProfile(modelData.id);
                        }
                        QQC2.CheckBox {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: Kirigami.Units.smallSpacing
                            checked: modelData.id === Plasmoid.configuration.activeProfileId
                            enabled: false
                            opacity: checked ? 1 : 0
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                visible: !Plasmoid.configuration.showIconProfile
            }

            PlasmaComponents.ToolButton {
                id: autoToolButton
                icon.name: "media-playback-start"
                visible: Plasmoid.configuration.showIconAuto || root.isAutoMode
                checkable: true
                checked: root.sessionFullAutoMode
                Accessible.name: i18n("Toggle Full Auto Mode")
                PlasmaComponents.ToolTip.text: i18n("Toggle Full Auto Mode: When enabled, all tools run automatically for this session.")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                onClicked: root.sendMessage("/auto")
            }

            PlasmaComponents.ToolButton {
                id: driveToolButton
                icon.name: "input-mouse"
                visible: Plasmoid.configuration.enableDesktopAutomation && root.isDriverServiceActive
                checkable: true
                checked: root.isDrivingActive
                Accessible.name: i18n("Drive Desktop")
                PlasmaComponents.ToolTip.text: root.isDrivingActive 
                    ? i18n("Stop Driving Desktop (disconnect)") 
                    : i18n("Drive Desktop (starts handshake and enables auto mode)")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                onClicked: {
                    root.sessionAutoMode = !root.sessionAutoMode;
                    inputField.forceActiveFocus();
                }
            }

            PlasmaComponents.ToolButton {
                id: taskToolButton
                icon.name: "view-task"
                Accessible.name: i18n("Run a task")
                PlasmaComponents.ToolTip.text: i18n("Run a task")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                visible: Plasmoid.configuration.showIconTasks || fullRep.configuredTasks.length > 0
                checkable: true
                checked: taskMenu.opened

                onClicked: {
                    if (taskMenu.opened) {
                        taskMenu.close()
                    } else {
                        taskMenu.popup(taskToolButton, 0, taskToolButton.height)
                    }
                }

                QQC2.Menu {
                    id: taskMenu
                    closePolicy: QQC2.Menu.CloseOnEscape | QQC2.Menu.CloseOnPressOutsideParent
                }

                Instantiator {
                    model: fullRep.configuredTasks
                    onObjectAdded: function(index, object) { taskMenu.insertItem(index, object); }
                    onObjectRemoved: function(index, object) { taskMenu.removeItem(object); }
                    delegate: QQC2.MenuItem {
                        text: modelData.name + (modelData.auto ? " (auto)" : "")
                        onTriggered: {
                            root.sendMessage("/task " + modelData.name);
                        }
                    }
                }
            }

            PlasmaComponents.ToolButton {
                id: historyToolButton
                icon.name: "clock"
                Accessible.name: i18n("Chat History")
                PlasmaComponents.ToolTip.text: i18n("Chat History")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && !historyMenu.opened && PlasmaComponents.ToolTip.text !== ""
                visible: Plasmoid.configuration.showIconHistory && Plasmoid.configuration.saveChatHistory
                checkable: true
                checked: historyMenu.opened

                onClicked: {
                    if (Plasmoid.configuration.chatSaveFormat === "jsonl") {
                        if (historyMenu.opened) {
                            historyMenu.close()
                        } else {
                            historyMenu.popup(historyToolButton, 0, historyToolButton.height)
                        }
                    } else {
                        root.openChatsFolder();
                    }
                }

                QQC2.Menu {
                    id: historyMenu
                    closePolicy: QQC2.Menu.CloseOnEscape | QQC2.Menu.CloseOnPressOutsideParent

                    QQC2.MenuItem {
                        visible: root.isFetchingHistory
                        text: i18n("Loading...")
                        enabled: false
                    }

                    QQC2.MenuItem {
                        visible: !root.isFetchingHistory && (!root.historyFilesModel || root.historyFilesModel.count === 0)
                        text: i18n("No recent chats")
                        enabled: false
                    }

                    QQC2.MenuSeparator {
                        visible: root.historyFilesModel && root.historyFilesModel.count > 0
                    }

                    QQC2.MenuItem {
                        text: i18n("Open history folder...")
                        onTriggered: {
                            root.openChatsFolder();
                        }
                    }

                    QQC2.MenuSeparator {
                        visible: root.historyFilesModel && root.historyFilesModel.count > 0
                    }

                    QQC2.MenuItem {
                        visible: root.historyFilesModel && root.historyFilesModel.count > 0
                        text: i18n("Clear all history...")
                        icon.name: "edit-clear-history"
                        onTriggered: {
                            clearHistorySheet.open();
                        }
                    }
                }

                Instantiator {
                    model: root.historyFilesModel || null
                    onObjectAdded: function(index, object) { historyMenu.insertItem(index + 2, object); }
                    onObjectRemoved: function(index, object) { historyMenu.removeItem(object); }
                    delegate: QQC2.MenuItem {
                        text: (model.dateTime || model.name || "") + (model.preview ? ": " + model.preview : "")
                        onTriggered: {
                            root.loadChatJsonl(model.file);
                        }
                    }
                }
            }

            QQC2.Popup {
                id: clearHistorySheet
                parent: QQC2.Overlay.overlay
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                modal: true
                focus: true
                closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
                padding: Kirigami.Units.largeSpacing

                background: Rectangle {
                    color: Kirigami.Theme.backgroundColor
                    border.color: Kirigami.Theme.focusColor
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing
                }

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.largeSpacing

                    PlasmaComponents.Label {
                        text: i18n("Clear All History")
                        font.bold: true
                    }

                    PlasmaComponents.Label {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                        text: i18n("Are you sure you want to delete all chat history files? This action cannot be undone.")
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents.Button {
                            text: i18n("Clear All")
                            icon.name: "edit-clear-history"
                            onClicked: {
                                root.clearAllHistory();
                                clearHistorySheet.close();
                            }
                        }
                        PlasmaComponents.Button {
                            text: i18n("Cancel")
                            onClicked: clearHistorySheet.close()
                        }
                    }
                }
            }

            QQC2.Popup {
                id: imageViewerPopup
                parent: QQC2.Overlay.overlay
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, imgViewerImage.implicitWidth + padding * 2)
                height: Math.min(parent.height - Kirigami.Units.largeSpacing * 2, imgViewerImage.implicitHeight + padding * 2)
                modal: true
                focus: true
                closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
                padding: 0
                property string sourceUrl: ""

                background: Rectangle {
                    color: Kirigami.Theme.backgroundColor
                    border.color: Kirigami.Theme.focusColor
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing
                }

                contentItem: Item {
                    Flickable {
                        anchors.fill: parent
                        contentWidth: imgViewerImage.width
                        contentHeight: imgViewerImage.height
                        clip: true

                        Image {
                            id: imgViewerImage
                            source: imageViewerPopup.sourceUrl
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            fillMode: Image.Pad
                        }
                    }
                    
                    PlasmaComponents.ToolButton {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Kirigami.Units.smallSpacing
                        icon.name: "window-close"
                        onClicked: imageViewerPopup.close()
                        
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            radius: width / 2
                            color: Kirigami.Theme.backgroundColor
                            opacity: 0.8
                            z: -1
                        }
                    }
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "edit-copy"
                Accessible.name: i18n("Copy conversation")
                PlasmaComponents.ToolTip.text: i18n("Copy conversation")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                visible: Plasmoid.configuration.showIconCopy && root.displayMessages.count > 0
                enabled: root.displayMessages.count > 0
                onClicked: {
                    var text = "";
                    for (var i = 0; i < root.displayMessages.count; i++) {
                        var msg = root.displayMessages.get(i);
                        var prefix = msg.role === "user" ? (Plasmoid.configuration.userName || i18n("You")) :
                                     msg.role === "assistant" ? (Plasmoid.configuration.showModelNameAsAssistant ? (Plasmoid.configuration.modelName || Plasmoid.configuration.assistantName || i18n("Assistant")) : (Plasmoid.configuration.assistantName || i18n("Assistant"))) :
                                     msg.role === "command_output" ? i18n("Command") :
                                     msg.role === "error" ? i18n("Error") : "";
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
                visible: Plasmoid.configuration.showIconClear
                Accessible.name: i18n("Clear chat")
                PlasmaComponents.ToolTip.text: i18n("Clear chat")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                onClicked: { root.clearChat(); inputField.forceActiveFocus(); }
            }

            PlasmaComponents.ToolButton {
                icon.name: "configure"
                visible: Plasmoid.configuration.showIconSettings
                Accessible.name: i18n("Settings")
                PlasmaComponents.ToolTip.text: i18n("Settings")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                onClicked: Plasmoid.internalAction("configure").trigger()
            }

            PlasmaComponents.ToolButton {
                icon.name: "window-pin"
                visible: Plasmoid.configuration.showIconPin && Plasmoid.formFactor !== PlasmaCore.Types.Planar
                checkable: true
                checked: Plasmoid.configuration.pin
                Accessible.name: Plasmoid.configuration.pin ? i18n("Don't keep open") : i18n("Keep open")
                PlasmaComponents.ToolTip.text: Plasmoid.configuration.pin ? i18n("Don't keep open") : i18n("Keep open")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                onClicked: Plasmoid.configuration.pin = !Plasmoid.configuration.pin
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
                var prefix = msg.role === "user" ? (Plasmoid.configuration.userName || i18n("You")) :
                             msg.role === "assistant" ? (Plasmoid.configuration.showModelNameAsAssistant ? (Plasmoid.configuration.modelName || Plasmoid.configuration.assistantName || i18n("Assistant")) : (Plasmoid.configuration.assistantName || i18n("Assistant"))) :
                             msg.role === "command_output" ? i18n("Command") :
                             msg.role === "error" ? i18n("Error") : "";
                if (prefix) text += prefix + ": " + msg.content + "\n\n";
            }
            clipboardHelper.text = text.trim();
            clipboardHelper.selectAll();
            clipboardHelper.copy();
        }
        function onPopulateInputRequested(text) {
            inputField.text = text;
            inputField.cursorPosition = text.length;
            inputField.forceActiveFocus();
        }
    }

    contentItem: Item {
        id: representationContent

        MouseArea {
            anchors.fill: parent
            z: 99
            propagateComposedEvents: true
            onPressed: function(mouse) {
                Plasmoid.status = PlasmaCore.Types.AcceptingInputStatus;
                mouse.accepted = false;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Plasmoid.configuration.chatSpacing

            Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Plasmoid.configuration.chatSpacing
            Layout.rightMargin: Plasmoid.configuration.chatSpacing

            PlasmaComponents.ScrollView {
                anchors.fill: parent

            ListView {
                id: messageList
                clip: true
                spacing: Plasmoid.configuration.chatSpacing
                headerPositioning: ListView.OverlayHeader
                header: Item { height: Plasmoid.configuration.chatSpacing }
                model: root.displayMessages
                // Use reuseItems: true to avoid the "destruction/recreation" loop
                // observed with complex delegates and structural model changes.
                cacheBuffer: height * 2
                reuseItems: true

                // Track whether user is near the bottom to avoid fighting manual scrolling.
                // nearBottomThreshold gives some slack so small upward scrolls still
                // count as "sticky" — atYEnd alone has effectively zero tolerance.
                readonly property real nearBottomThreshold: Kirigami.Units.gridUnit * 8
                readonly property bool atBottom: atYEnd || contentHeight <= height ||
                                                 (contentHeight - contentY - height) <= nearBottomThreshold
                // Latched true when streaming begins at bottom; cleared when streaming ends or user scrolls away
                property bool trackingStream: false
                // Latched true while user is pinned to the bottom; cleared on manual scroll-away, re-latched on returning to end
                property bool stickToBottom: true
                // Set while we're issuing a programmatic scroll so the resulting
                // movementStarted/contentY updates don't get mistaken for user input
                property bool programmaticScroll: false

                function scrollToEnd() {
                    programmaticScroll = true;
                    positionViewAtEnd();
                    // Hold the guard across the next event-loop tick so the
                    // contentYChanged signals that arrive after the layout
                    // settles aren't misread as user input.
                    Qt.callLater(function() { messageList.programmaticScroll = false; });
                }

                delegate: ChatMessage {
                    width: messageList.width
                    role: model.role
                    content: model.content
                    thinking: model.thinking !== undefined ? model.thinking : ""
                    shared: model.shared !== undefined ? model.shared : false
                    messageIndex: index
                    timestamp: model.timestamp !== undefined ? model.timestamp : ""
                    attachmentsStr: model.attachmentsStr !== undefined ? model.attachmentsStr : ""
                    isAwaitingResponse: index === root.streamingMessageIndex && root.isLoading
                    outputScheme: model.outputScheme !== undefined ? model.outputScheme : ""
                    tool_call_id: model.tool_call_id !== undefined ? model.tool_call_id : ""
                    toolArgs: model.toolArgs !== undefined ? model.toolArgs : ""
                    toolName: model.toolName !== undefined ? model.toolName : ""
                    stdout: model.stdout !== undefined ? model.stdout : ""
                    stderr: model.stderr !== undefined ? model.stderr : ""
                    exitCode: model.exitCode !== undefined ? model.exitCode : 0
                    toolSummary: model.toolSummary !== undefined ? model.toolSummary : ""
                    toolDataJson: model.toolDataJson !== undefined ? model.toolDataJson : ""
                    toolView: model.toolView !== undefined ? model.toolView : ""
                    toolIcon: model.toolIcon !== undefined ? model.toolIcon : ""
                    toolTitle: model.toolTitle !== undefined ? model.toolTitle : ""
                    sessionMode: Plasmoid.configuration.useSessionMultiplexer
                    appConfig: root.getToolsConfig()

                    sessionLabel: root.sessionChipText()
                    commandRunStateTick: root.commandRunStateTick
                    onScrollRequested: {
                        messageList.programmaticScroll = true;
                        messageList.positionViewAtIndex(index, ListView.Beginning);
                        Qt.callLater(function() { messageList.programmaticScroll = false; });
                    }
                    onShareRequested: function(index) { root.shareOutput(index); }
                    onRetryRequested: root.sendToLLM()
                    onTerminalRequested: function(command) { root.runInTerminal(command); }
                    onStopRequested: function(command, sourceId) { root.stopCommandByText(command, sourceId); }
                    onToolApproved: function(name, args, callId) {
                        displayMessages.remove(index);
                        root.executeTool(name, args, callId);
                        inputField.forceActiveFocus();
                    }
                    onToolDenied: function(name, callId) {
                        displayMessages.remove(index);
                        root.handleToolOutput(null, "", i18n("The user denied this tool call."), 1, { name: name, callId: callId });
                        inputField.forceActiveFocus();
                    }
                    onImageViewRequested: function(sourceUrl) {
                        imageViewerPopup.sourceUrl = sourceUrl;
                        imageViewerPopup.open();
                    }
                }

                // movementStarted fires for wheel, scrollbar drag, and touch flicks —
                // unlike onFlickStarted which only fires for touch/drag flicks. Guard
                // against the programmatic scrolls we issue ourselves.
                // Mouse-wheel scrolling on this Flickable does NOT emit
                // movementStarted, but it DOES emit contentYChanged. Use that
                // as the user-input signal: any non-programmatic contentY
                // change re-derives stickToBottom from the new position.
                onContentYChanged: {
                    if (programmaticScroll) return;
                    trackingStream = false;
                    stickToBottom = atBottom;
                }

                onCountChanged: {
                    var wasAtBottom = messageList.atBottom || root.isAutoMode || messageList.trackingStream || messageList.stickToBottom;
                    if (wasAtBottom && root.isLoading && root.streamingMessageIndex >= 0) {
                        trackingStream = true;
                    }
                    if (wasAtBottom) {
                        stickToBottom = true;
                        Qt.callLater(messageList.scrollToEnd);
                    }
                }

                onContentHeightChanged: {

                    if (programmaticScroll) return;
                    if (atBottom) return;
                    if (!stickToBottom && !(root.isLoading && trackingStream)) return;
                    if (root.isLoading && root.streamingMessageIndex >= 0) {
                        var item = messageList.itemAtIndex(root.streamingMessageIndex);
                        if (item && item.height > messageList.height) {
                            programmaticScroll = true;
                            messageList.positionViewAtIndex(root.streamingMessageIndex, ListView.Beginning);
                            Qt.callLater(function() { messageList.programmaticScroll = false; });
                            return;
                        }
                    }
                    scrollToEnd();
                }

                Connections {
                    target: root
                    function onExpandedChanged() {
                        if (root.expanded) {
                            inputField.forceActiveFocus();
                        }
                    }
                    function onResponseReady(messageIndex) {
                        messageList.trackingStream = false;
                        Qt.callLater(function() {
                            if (root.isAutoMode && messageList.atBottom) {
                                messageList.scrollToEnd();
                                messageList.stickToBottom = true;
                                return;
                            }
                            var item = messageList.itemAtIndex(messageIndex);
                            if (item && item.height <= messageList.height) {
                                messageList.scrollToEnd();
                                messageList.stickToBottom = true;
                            } else {
                                messageList.programmaticScroll = true;
                                messageList.positionViewAtIndex(messageIndex, ListView.Beginning);
                                messageList.programmaticScroll = false;
                                messageList.stickToBottom = false;
                            }
                        });
                    }
                }

                PlasmaExtras.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - (Kirigami.Units.gridUnit * 4)
                    visible: messageList.count === 0
                    text: i18n("Send a message to start chatting")
                    iconName: "im-user"
                }
            }
        }

            PlasmaComponents.RoundButton {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Kirigami.Units.smallSpacing
                visible: !messageList.atBottom && messageList.count > 0 && !root.isLoading
                icon.name: "go-down"
                icon.width: Kirigami.Units.iconSizes.small
                icon.height: Kirigami.Units.iconSizes.small
                z: 1
                onClicked: messageList.scrollToEnd()

                background: Rectangle {
                    radius: width / 2
                    color: Kirigami.Theme.backgroundColor
                    opacity: 0.85
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1
                }
            }
        }

        FileDialog {
            id: attachDialog
            title: i18n("Attach File")
            fileMode: FileDialog.OpenFile
            currentFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation)
            nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg)"), i18n("Text files (*.txt *.md *.json *.csv *.log *.xml *.yaml *.yml *.ini *.conf *.sh *.py *.js *.ts *.qml)"), i18n("All files (*)")]
            onAccepted: {
                var path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
                root.attachFile(path);
            }
        }

        // Attachment preview strip
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: Plasmoid.configuration.chatSpacing
            Layout.rightMargin: Plasmoid.configuration.chatSpacing
            spacing: Kirigami.Units.smallSpacing
            visible: root.pendingAttachments.length > 0

            Repeater {
                model: root.pendingAttachments

                Rectangle {
                    width: isImg ? thumbImg.width + Kirigami.Units.smallSpacing * 2 + removeBtn.width : fileLabel.implicitWidth + Kirigami.Units.smallSpacing * 3 + removeBtn.width
                    height: isImg ? Math.min(thumbImg.implicitHeight, Kirigami.Units.gridUnit * 4) + Kirigami.Units.smallSpacing * 2 : Kirigami.Units.gridUnit * 1.5
                    radius: 4
                    color: Kirigami.Theme.alternateBackgroundColor
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1

                    readonly property bool isImg: !!modelData.dataUrl

                    Image {
                        id: thumbImg
                        visible: parent.isImg
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: Kirigami.Units.smallSpacing
                        source: parent.isImg ? (modelData.dataUrl || Qt.resolvedUrl("file://" + modelData.filePath)) : ""
                        autoTransform: true
                        fillMode: Image.PreserveAspectFit
                        height: Math.min(sourceSize.height, Kirigami.Units.gridUnit * 4)
                        width: Math.min(sourceSize.width, Kirigami.Units.gridUnit * 6)
                        smooth: true
                        mipmap: true
                    }

                    PlasmaComponents.Label {
                        id: fileLabel
                        visible: !parent.isImg
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        text: modelData.fileName || "file"
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideMiddle
                        width: Math.min(implicitWidth, Kirigami.Units.gridUnit * 8)
                    }

                    PlasmaComponents.ToolButton {
                        id: removeBtn
                        anchors.right: parent.right
                        anchors.top: parent.top
                        icon.name: "edit-delete-remove"
                        width: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
                        height: width
                        onClicked: {
                            var list = root.pendingAttachments.slice();
                            list.splice(index, 1);
                            root.pendingAttachments = list;
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Plasmoid.configuration.chatSpacing
            Layout.rightMargin: Plasmoid.configuration.chatSpacing
            Layout.bottomMargin: Plasmoid.configuration.chatSpacing
            spacing: Kirigami.Units.smallSpacing

            Item {
                id: inputAreaWrapper
                Layout.fillWidth: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 2
                Layout.maximumHeight: Kirigami.Units.gridUnit * 8
                Layout.preferredHeight: Math.min(inputField.contentHeight + Kirigami.Units.smallSpacing * 2, Kirigami.Units.gridUnit * 8)

                QQC2.ScrollView {
                    id: inputScrollView
                    anchors.fill: parent

                    QQC2.TextArea {
                        id: inputField
                        Accessible.name: i18n("Message input")
                        placeholderText: root.systemPromptReady ? i18n("Type a message…") : i18n("Initializing…")
                        enabled: !root.isLoading && root.systemPromptReady
                        focus: true
                        wrapMode: Text.Wrap
                        
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                Plasmoid.status = PlasmaCore.Types.AcceptingInputStatus;
                            }
                        }

                        Keys.onPressed: function(event) {
                            var isCtrlV = (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier));
                            var isShiftInsert = (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier));
                            
                            if (isCtrlV || isShiftInsert) {
                                clipboardHelper.text = "";
                                clipboardHelper.paste();
                                var clipboardText = clipboardHelper.text;
                                
                                if (clipboardText.startsWith("file://")) {
                                    var lines = clipboardText.split("\n");
                                    for (var i = 0; i < lines.length; i++) {
                                        var line = lines[i].trim();
                                        if (line.startsWith("file://")) {
                                            var path = decodeURIComponent(line.replace(/^file:\/\//, ""));
                                            root.attachFile(path);
                                        }
                                    }
                                    event.accepted = true;
                                } else if (clipboardText.length === 0) {
                                    root.pasteImageFromClipboard();
                                    event.accepted = true;
                                }
                            }
                        }

                        Keys.onTabPressed: function(event) {
                            if (inputField.text.toLowerCase().startsWith("/task ") && taskPopup.filteredTasks.length === 1) {
                                inputField.text = "/task " + taskPopup.filteredTasks[0].name;
                                inputField.cursorPosition = inputField.text.length;
                                event.accepted = true;
                            } else if (inputField.text.toLowerCase().startsWith("/model ") && modelPopup.filteredModels.length === 1) {
                                inputField.text = "/model " + modelPopup.filteredModels[0];
                                inputField.cursorPosition = inputField.text.length;
                                event.accepted = true;
                            } else if (inputField.text.toLowerCase().startsWith("/profile ") && profilePopup.filteredProfiles.length === 1) {
                                inputField.text = "/profile " + profilePopup.filteredProfiles[0].name;
                                inputField.cursorPosition = inputField.text.length;
                                event.accepted = true;
                            } else if (slashPopup.filteredSlashCommands.length === 1) {
                                var cmd = slashPopup.filteredSlashCommands[0].cmd;
                                inputField.text = (cmd === "/model" || cmd === "/task" || cmd === "/profile") ? cmd + " " : cmd;
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
                                if (sendText.toLowerCase().startsWith("/task ") && taskPopup.filteredTasks.length === 1) {
                                    sendText = "/task " + taskPopup.filteredTasks[0].name;
                                } else if (sendText.toLowerCase().startsWith("/model ") && modelPopup.filteredModels.length === 1) {
                                    sendText = "/model " + modelPopup.filteredModels[0];
                                } else if (sendText.toLowerCase().startsWith("/profile ") && profilePopup.filteredProfiles.length === 1) {
                                    sendText = "/profile " + profilePopup.filteredProfiles[0].name;
                                } else if (sendText.startsWith("/") && sendText.indexOf(" ") === -1 &&
                                        slashPopup.filteredSlashCommands.length === 1) {
                                    sendText = slashPopup.filteredSlashCommands[0].cmd;
                                }
                                if (sendText.length > 0 || root.pendingAttachments.length > 0) {
                                    if (root.sendMessage(sendText, root.pendingAttachments)) {
                                        text = "";
                                        root.pendingAttachments = [];
                                    }
                                }
                            }
                        }
                    }
                }

                // Slash command autocomplete popup
                Rectangle {
                    id: slashPopup
                    z: 99
                    x: 0
                    y: -height - Kirigami.Units.smallSpacing
                    width: inputAreaWrapper.width
                    height: slashList.implicitHeight + Kirigami.Units.smallSpacing * 2
                    color: Kirigami.Theme.backgroundColor
                    border.color: Kirigami.Theme.focusColor
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing
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

                    ListView {
                        id: slashList
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        clip: true
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
                                inputField.text = (modelData.cmd === "/model" || modelData.cmd === "/task" || modelData.cmd === "/profile") ? modelData.cmd + " " : modelData.cmd;
                                inputField.cursorPosition = inputField.text.length;
                                inputField.forceActiveFocus();
                            }
                        }
                    }
                }

                // Model name autocomplete popup
                Rectangle {
                    id: modelPopup
                    z: 99
                    x: 0
                    y: -height - Kirigami.Units.smallSpacing
                    width: inputAreaWrapper.width
                    height: modelList.implicitHeight + Kirigami.Units.smallSpacing * 2
                    color: Kirigami.Theme.backgroundColor
                    border.color: Kirigami.Theme.focusColor
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing

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

                    ListView {
                        id: modelList
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        clip: true
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

                // Profile name autocomplete popup
                Rectangle {
                    id: profilePopup
                    z: 99
                    x: 0
                    y: -height - Kirigami.Units.smallSpacing
                    width: inputAreaWrapper.width
                    height: profileList.implicitHeight + Kirigami.Units.smallSpacing * 2
                    color: Kirigami.Theme.backgroundColor
                    border.color: Kirigami.Theme.focusColor
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing

                    property var filteredProfiles: {
                        var t = inputField.text;
                        if (!t.toLowerCase().startsWith("/profile ")) return [];
                        var query = t.substring(9).toLowerCase();
                        var profiles = Profiles.loadProfiles(Plasmoid.configuration);
                        if (!profiles || profiles.length === 0) return [];
                        return query.length === 0 ? profiles :
                               profiles.filter(function(p) { return p.name.toLowerCase().indexOf(query) !== -1; });
                    }

                    visible: inputField.activeFocus &&
                             inputField.text.toLowerCase().startsWith("/profile ") &&
                             filteredProfiles.length > 0

                    ListView {
                        id: profileList
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        clip: true
                        implicitHeight: Math.min(contentHeight, Math.max(Kirigami.Units.gridUnit * 5, messageList.height - Kirigami.Units.smallSpacing * 2))
                        model: profilePopup.filteredProfiles
                        delegate: PlasmaComponents.ItemDelegate {
                            width: profileList.width
                            contentItem: PlasmaComponents.Label {
                                text: modelData.name
                                font.bold: Plasmoid.configuration.activeProfileId === modelData.id
                                color: Plasmoid.configuration.activeProfileId === modelData.id
                                       ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                            }
                            onClicked: {
                                inputField.text = "/profile " + modelData.name;
                                inputField.cursorPosition = inputField.text.length;
                                inputField.forceActiveFocus();
                            }
                        }
                    }
                }

                // Task name autocomplete popup
                Rectangle {
                    id: taskPopup
                    z: 99
                    x: 0
                    y: -height - Kirigami.Units.smallSpacing
                    width: inputAreaWrapper.width
                    height: taskList.implicitHeight + Kirigami.Units.smallSpacing * 2
                    color: Kirigami.Theme.backgroundColor
                    border.color: Kirigami.Theme.focusColor
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing

                    property var filteredTasks: {
                        var t = inputField.text;
                        if (!t.toLowerCase().startsWith("/task ")) return [];
                        var query = t.substring(6).toLowerCase();
                        var tasks = fullRep.configuredTasks;
                        if (!tasks || tasks.length === 0) return [];
                        return query.length === 0 ? tasks :
                               tasks.filter(function(tk) { return tk.name.toLowerCase().indexOf(query) !== -1; });
                    }

                    visible: inputField.activeFocus &&
                             inputField.text.toLowerCase().startsWith("/task ") &&
                             filteredTasks.length > 0

                    ListView {
                        id: taskList
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        clip: true
                        implicitHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 10)
                        model: taskPopup.filteredTasks
                        delegate: PlasmaComponents.ItemDelegate {
                            width: taskList.width
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                PlasmaComponents.Label {
                                    text: modelData.name
                                    font.bold: true
                                }
                                PlasmaComponents.Label {
                                    visible: modelData.auto
                                    text: i18n("AUTO")
                                    font: Kirigami.Theme.smallFont
                                    color: Kirigami.Theme.negativeTextColor
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.prompt.length > 30 ? modelData.prompt.substring(0, 30) + "…" : modelData.prompt
                                    color: Kirigami.Theme.disabledTextColor
                                    elide: Text.ElideRight
                                }
                            }
                            onClicked: {
                                inputField.text = "/task " + modelData.name;
                                inputField.cursorPosition = inputField.text.length;
                                inputField.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "mail-attachment"
                visible: true
                enabled: !root.isLoading && root.systemPromptReady
                PlasmaComponents.ToolTip.text: i18n("Attach file or image")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                onClicked: attachDialog.open()
            }

            PlasmaComponents.Button {
                id: killButton
                text: i18n("Kill")
                visible: Plasmoid.configuration.useSessionMultiplexer
                enabled: root.systemPromptReady && root.sessionActive
                onClicked: root.resetSession()
                PlasmaComponents.ToolTip.text: i18n("Kill persistent session (stops all processes and resets shell state)")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        source: "media-playback-stop"
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                        color: killButton.enabled ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
                    }
                    PlasmaComponents.Label {
                        text: killButton.text
                        color: killButton.enabled ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
                    }
                }
            }

            PlasmaComponents.Button {
                text: i18n("Send")
                icon.name: "document-send"
                visible: true
                enabled: !root.isLoading && root.systemPromptReady && (inputField.text.trim().length > 0 || root.pendingAttachments.length > 0)
                onClicked: {
                    var sendText = inputField.text.trim();
                    if (sendText.toLowerCase().startsWith("/task ") && taskPopup.filteredTasks.length === 1) {
                        sendText = "/task " + taskPopup.filteredTasks[0].name;
                    } else if (sendText.toLowerCase().startsWith("/model ") && modelPopup.filteredModels.length === 1) {
                        sendText = "/model " + modelPopup.filteredModels[0];
                    } else if (sendText.startsWith("/") && sendText.indexOf(" ") === -1 &&
                            slashPopup.filteredSlashCommands.length === 1) {
                        sendText = slashPopup.filteredSlashCommands[0].cmd;
                    }
                    if (sendText.length > 0 || root.pendingAttachments.length > 0) {
                        if (root.sendMessage(sendText, root.pendingAttachments)) {
                            inputField.text = "";
                            root.pendingAttachments = [];
                        }
                    }
                }
            }

            PlasmaComponents.Button {
                text: i18n("Stop")
                icon.name: "media-playback-stop"
                visible: root.isLoading
                enabled: root.isLoading
                onClicked: root.cancelRequest()
                PlasmaComponents.ToolTip.text: i18n("Cancel LLM request")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
            }
        }
    }

    DragDrop.DropArea {
        id: mainDropArea
        anchors.fill: parent
        preventStealing: false

        property bool containsAcceptableDrag: false

        onDragEnter: event => {
            var urls = [];
            if (event.mimeData.urls && event.mimeData.urls.length > 0) {
                urls = event.mimeData.urls;
            } else if (event.mimeData.url) {
                urls = [event.mimeData.url];
            }
            
            var hasLocalFile = false;
            for (var i = 0; i < urls.length; i++) {
                if (urls[i].toString().startsWith("file:///")) {
                    hasLocalFile = true;
                    break;
                }
            }
            
            containsAcceptableDrag = hasLocalFile;
            if (!hasLocalFile) {
                event.ignore();
            }
        }

        onDragLeave: event => {
            containsAcceptableDrag = false;
        }

        onDrop: event => {
            if (containsAcceptableDrag) {
                var urls = [];
                if (event.mimeData.urls && event.mimeData.urls.length > 0) {
                    urls = event.mimeData.urls;
                } else if (event.mimeData.url) {
                    urls = [event.mimeData.url];
                }
                for (var i = 0; i < urls.length; i++) {
                    var urlStr = urls[i].toString();
                    if (urlStr.startsWith("file://")) {
                        var path = decodeURIComponent(urlStr.replace(/^file:\/\//, ""));
                        root.attachFile(path);
                    }
                }
            }
            containsAcceptableDrag = false;
        }
    }

    Rectangle {
        id: dropOverlay
        anchors.fill: parent
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.85)
        visible: mainDropArea.containsDrag && mainDropArea.containsAcceptableDrag
        z: 9999
        border.color: Kirigami.Theme.focusColor
        border.width: 2
        radius: Kirigami.Units.smallSpacing

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: "mail-attachment"
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Kirigami.Units.iconSizes.huge
                implicitHeight: Kirigami.Units.iconSizes.huge
                color: Kirigami.Theme.focusColor
            }

            PlasmaComponents.Label {
                text: i18n("Drop files here to attach")
                Layout.alignment: Qt.AlignHCenter
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.5
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
}
