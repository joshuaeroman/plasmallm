/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaExtras.Representation {
    id: fullRep

    readonly property var slashCommands: [
        { cmd: "/auto",     desc: i18n("Toggle auto mode (auto-run + auto-share) for this session") },
        { cmd: "/clear",    desc: i18n("Clear the chat") },
        { cmd: "/close",    desc: i18n("Close the panel") },
        { cmd: "/copy",     desc: i18n("Copy conversation to clipboard") },
        { cmd: "/history",  desc: i18n("Open chat history folder") },
        { cmd: "/model",    desc: i18n("Show or switch model (/model <name>)") },
        { cmd: "/run",      desc: i18n("Run last command") },
        { cmd: "/save",     desc: i18n("Save chat to file") },
        { cmd: "/settings", desc: i18n("Open settings") },
        { cmd: "/task",     desc: i18n("Run a saved task (/task <name>)") },
        { cmd: "/term",     desc: i18n("Run last command in terminal") },
    ]

    property var configuredTasks: {
        var json = Plasmoid.configuration.tasks;
        if (!json || json.length === 0) return [];
        try { return JSON.parse(json); } catch(e) { return []; }
    }

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
                text: i18n("AUTO")
                visible: root.isAutoMode
                font.bold: true
                color: Kirigami.Theme.negativeTextColor

            }

            PlasmaComponents.ToolButton {
                id: taskToolButton
                icon.name: "view-task"
                Accessible.name: i18n("Run a task")
                PlasmaComponents.ToolTip.text: i18n("Run a task")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                visible: fullRep.configuredTasks.length > 0
                onClicked: taskMenu.open()

                QQC2.Menu {
                    id: taskMenu
                    y: taskToolButton.height

                    Instantiator {
                        model: fullRep.configuredTasks
                        delegate: QQC2.MenuItem {
                            text: modelData.name + (modelData.auto ? " (auto)" : "")
                            onTriggered: root.sendMessage("/task " + modelData.name)
                        }
                        onObjectAdded: function(index, object) { taskMenu.insertItem(index, object); }
                        onObjectRemoved: function(index, object) { taskMenu.removeItem(object); }
                    }
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "clock"
                Accessible.name: i18n("Open chat history folder")
                PlasmaComponents.ToolTip.text: i18n("Open chat history folder")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                visible: Plasmoid.configuration.saveChatHistory
                onClicked: root.openChatsFolder()
            }

            PlasmaComponents.ToolButton {
                icon.name: "edit-copy"
                Accessible.name: i18n("Copy conversation")
                PlasmaComponents.ToolTip.text: i18n("Copy conversation")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                enabled: root.displayMessages.count > 0
                onClicked: {
                    var text = "";
                    for (var i = 0; i < root.displayMessages.count; i++) {
                        var msg = root.displayMessages.get(i);
                        var prefix = msg.role === "user" ? i18n("You") :
                                     msg.role === "assistant" ? i18n("Assistant") :
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
                Accessible.name: i18n("Clear chat")
                PlasmaComponents.ToolTip.text: i18n("Clear chat")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: { root.clearChat(); inputField.forceActiveFocus(); }
            }

            PlasmaComponents.ToolButton {
                icon.name: "configure"
                Accessible.name: i18n("Settings")
                PlasmaComponents.ToolTip.text: i18n("Settings")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: Plasmoid.internalAction("configure").trigger()
            }

            PlasmaComponents.ToolButton {
                icon.name: "window-pin"
                checkable: true
                checked: Plasmoid.configuration.pin
                Accessible.name: Plasmoid.configuration.pin ? i18n("Don't keep open") : i18n("Keep open")
                PlasmaComponents.ToolTip.text: Plasmoid.configuration.pin ? i18n("Don't keep open") : i18n("Keep open")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
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
                var prefix = msg.role === "user" ? i18n("You") :
                             msg.role === "assistant" ? i18n("Assistant") :
                             msg.role === "command_output" ? i18n("Command") :
                             msg.role === "error" ? i18n("Error") : "";
                if (prefix) text += prefix + ": " + msg.content + "\n\n";
            }
            clipboardHelper.text = text.trim();
            clipboardHelper.selectAll();
            clipboardHelper.copy();
        }
    }

    contentItem: ColumnLayout {
        spacing: Plasmoid.configuration.chatSpacing

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PlasmaComponents.ScrollView {
                anchors.fill: parent

            ListView {
                id: messageList
                clip: true
                spacing: 0
                headerPositioning: ListView.OverlayHeader
                header: Item { height: Plasmoid.configuration.chatSpacing }
                model: root.displayMessages
                // Keep delegates alive well beyond the viewport so their
                // measured heights don't churn as the user scrolls — that
                // churn was making contentHeight oscillate (e.g. 1648→4240
                // in one tick) which yanks the visible scroll position.
                cacheBuffer: Math.max(2000, height * 4)
                reuseItems: false

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
                    thinking: model.thinking ? model.thinking : ""
                    commandsStr: model.commandsStr ? model.commandsStr : ""
                    shared: model.shared ? model.shared : false
                    messageIndex: model.index
                    timestamp: model.timestamp ? model.timestamp : ""
                    attachmentsStr: model.attachmentsStr ? model.attachmentsStr : ""
                    onShareRequested: function(index) { root.shareOutput(index); }
                    onRetryRequested: root.sendToLLM()
                    onExecuteRequested: function(command) { root.executeCommand(command); }
                    onTerminalRequested: function(command) { root.runInTerminal(command); }
                    onSaveRequested: function(filePath, content) { root.saveScript(filePath, content); }
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
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
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
                        source: parent.isImg ? "file://" + modelData.filePath : ""
                        autoTransform: true
                        fillMode: Image.PreserveAspectFit
                        height: Math.min(sourceSize.height, Kirigami.Units.gridUnit * 4)
                        width: Math.min(sourceSize.width, Kirigami.Units.gridUnit * 6)
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
                                inputField.text = (modelData.cmd === "/model" || modelData.cmd === "/task") ? modelData.cmd + " " : modelData.cmd;
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

                // Task name autocomplete popup
                QQC2.Popup {
                    id: taskPopup
                    parent: inputScrollView
                    x: 0
                    y: -height - Kirigami.Units.smallSpacing
                    width: inputScrollView.width
                    padding: Kirigami.Units.smallSpacing
                    closePolicy: QQC2.Popup.NoAutoClose

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

                    contentItem: ListView {
                        id: taskList
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

                Layout.fillWidth: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 2
                Layout.maximumHeight: Kirigami.Units.gridUnit * 8
                Layout.preferredHeight: Math.min(inputField.contentHeight + Kirigami.Units.smallSpacing * 2, Kirigami.Units.gridUnit * 8)

                QQC2.TextArea {
                    id: inputField
                    Accessible.name: i18n("Message input")
                    placeholderText: root.systemPromptReady ? i18n("Type a message…") : i18n("Initializing…")
                    enabled: !root.isLoading && root.systemPromptReady
                    focus: true
                    wrapMode: Text.Wrap

                    Keys.onTabPressed: function(event) {
                        if (inputField.text.toLowerCase().startsWith("/task ") && taskPopup.filteredTasks.length === 1) {
                            inputField.text = "/task " + taskPopup.filteredTasks[0].name;
                            inputField.cursorPosition = inputField.text.length;
                            event.accepted = true;
                        } else if (inputField.text.toLowerCase().startsWith("/model ") && modelPopup.filteredModels.length === 1) {
                            inputField.text = "/model " + modelPopup.filteredModels[0];
                            inputField.cursorPosition = inputField.text.length;
                            event.accepted = true;
                        } else if (slashPopup.filteredSlashCommands.length === 1) {
                            var cmd = slashPopup.filteredSlashCommands[0].cmd;
                            inputField.text = (cmd === "/model" || cmd === "/task") ? cmd + " " : cmd;
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
                            } else if (sendText.startsWith("/") && sendText.indexOf(" ") === -1 &&
                                    slashPopup.filteredSlashCommands.length === 1) {
                                sendText = slashPopup.filteredSlashCommands[0].cmd;
                            }
                            if (sendText.length > 0 || root.pendingAttachments.length > 0) {
                                root.sendMessage(sendText, root.pendingAttachments);
                                text = "";
                                root.pendingAttachments = [];
                            }
                        }
                    }
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "mail-attachment"
                visible: !root.isLoading
                enabled: root.systemPromptReady
                PlasmaComponents.ToolTip.text: i18n("Attach file or image")
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: attachDialog.open()
            }

            PlasmaComponents.Button {
                text: i18n("Send")
                icon.name: "document-send"
                visible: !root.isLoading
                enabled: root.systemPromptReady && (inputField.text.trim().length > 0 || root.pendingAttachments.length > 0)
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
                        root.sendMessage(sendText, root.pendingAttachments);
                        inputField.text = "";
                        root.pendingAttachments = [];
                    }
                }
            }

            PlasmaComponents.Button {
                text: i18n("Stop")
                icon.name: "media-playback-stop"
                visible: root.isLoading
                onClicked: root.cancelRequest()
            }
        }
    }
}
