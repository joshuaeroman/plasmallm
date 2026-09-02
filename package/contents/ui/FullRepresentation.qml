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

    // Panel-local voice hotkey: same hold / toggle / auto logic as the mic button.
    // Uses Keys (press+release) so hold-to-talk works; Shortcut alone cannot see releases.
    readonly property string voiceKeySeq: (Plasmoid.configuration.sttPanelShortcut || "").trim()
    readonly property string voiceKeyMicMode: Plasmoid.configuration.sttMicMode || "auto"
    readonly property int voiceKeyAutoHoldMs: Math.max(100, Plasmoid.configuration.sttAutoHoldMs || 250)
    readonly property int voiceKeyHoldMinMs: 250
    property real _voiceKeyPressTime: 0
    property bool _voiceKeyPressActive: false
    property bool _voiceKeyPressStartedRecording: false
    property bool _voiceKeyPttArmed: false

    function _normalizeKeySeq(s) {
        if (!s) return "";
        var t = String(s).toLowerCase().replace(/\s+/g, "");
        t = t.replace(/control/g, "ctrl").replace(/command/g, "meta").replace(/cmd/g, "meta")
             .replace(/option/g, "alt").replace(/osleft/g, "meta").replace(/super/g, "meta");
        var bits = t.split("+").filter(function(b) { return b.length > 0; });
        if (bits.length === 0) return "";
        var key = bits[bits.length - 1];
        var mods = { meta: false, ctrl: false, alt: false, shift: false };
        for (var i = 0; i < bits.length - 1; i++) {
            if (mods.hasOwnProperty(bits[i]))
                mods[bits[i]] = true;
        }
        var out = [];
        if (mods.meta) out.push("meta");
        if (mods.ctrl) out.push("ctrl");
        if (mods.alt) out.push("alt");
        if (mods.shift) out.push("shift");
        out.push(key);
        return out.join("+");
    }

    function _keyNameFromEvent(key) {
        if (key >= Qt.Key_A && key <= Qt.Key_Z)
            return String.fromCharCode(key - Qt.Key_A + 97); // a-z
        if (key >= Qt.Key_0 && key <= Qt.Key_9)
            return String.fromCharCode(key);
        if (key >= Qt.Key_F1 && key <= Qt.Key_F12)
            return "f" + (key - Qt.Key_F1 + 1);
        var named = {};
        named[Qt.Key_Space] = "space";
        named[Qt.Key_Return] = "return";
        named[Qt.Key_Enter] = "enter";
        named[Qt.Key_Tab] = "tab";
        named[Qt.Key_Backspace] = "backspace";
        named[Qt.Key_Escape] = "esc";
        named[Qt.Key_Insert] = "ins";
        named[Qt.Key_Delete] = "del";
        named[Qt.Key_Home] = "home";
        named[Qt.Key_End] = "end";
        named[Qt.Key_PageUp] = "pgup";
        named[Qt.Key_PageDown] = "pgdown";
        named[Qt.Key_Left] = "left";
        named[Qt.Key_Right] = "right";
        named[Qt.Key_Up] = "up";
        named[Qt.Key_Down] = "down";
        named[Qt.Key_Minus] = "-";
        named[Qt.Key_Equal] = "=";
        named[Qt.Key_BracketLeft] = "[";
        named[Qt.Key_BracketRight] = "]";
        named[Qt.Key_Semicolon] = ";";
        named[Qt.Key_Apostrophe] = "'";
        named[Qt.Key_Comma] = ",";
        named[Qt.Key_Period] = ".";
        named[Qt.Key_Slash] = "/";
        named[Qt.Key_Backslash] = "\\";
        named[Qt.Key_QuoteLeft] = "`";
        return named[key] || "";
    }

    function isModifierKey(key) {
        return key === Qt.Key_Control || key === Qt.Key_Shift
            || key === Qt.Key_Alt || key === Qt.Key_Meta
            || key === Qt.Key_AltGr || key === Qt.Key_Super_L
            || key === Qt.Key_Super_R || key === Qt.Key_Hyper_L
            || key === Qt.Key_Hyper_R;
    }

    function _seqFromKeyEvent(event) {
        var keyName = _keyNameFromEvent(event.key);
        if (!keyName)
            return "";
        // Ignore pure modifier key events
        if (isModifierKey(event.key))
            return "";
        var parts = [];
        if (event.modifiers & Qt.MetaModifier) parts.push("meta");
        if (event.modifiers & Qt.ControlModifier) parts.push("ctrl");
        if (event.modifiers & Qt.AltModifier) parts.push("alt");
        if (event.modifiers & Qt.ShiftModifier) parts.push("shift");
        parts.push(keyName);
        return parts.join("+");
    }

    // Match full chord on press. On release, modifiers may already be up — match main key only
    // while a voice-key press is active.
    function voiceKeyPressMatches(event) {
        if (!voiceKeySeq || voiceKeySeq.length === 0)
            return false;
        if (!root.expanded || !root.sttAvailable)
            return false;
        var got = _seqFromKeyEvent(event);
        if (!got)
            return false;
        return got === _normalizeKeySeq(voiceKeySeq);
    }

    function voiceKeyReleaseMatches(event) {
        if (!fullRep._voiceKeyPressActive)
            return false;
        if (event.isAutoRepeat)
            return false;
        // Main key released
        var keyName = _keyNameFromEvent(event.key);
        if (keyName) {
            var want = _normalizeKeySeq(voiceKeySeq);
            var wantKey = want.split("+").pop();
            return keyName === wantKey;
        }
        // Or a required modifier released while holding (end PTT early)
        if (isModifierKey(event.key)) {
            return true;
        }
        return false;
    }

    function handleVoiceKeyPressed(event) {
        if (event.isAutoRepeat)
            return;
        if (root.isTranscribing || root.isLoading || !root.systemPromptReady)
            return;

        fullRep._voiceKeyPressTime = Date.now();
        fullRep._voiceKeyPressActive = true;
        fullRep._voiceKeyPressStartedRecording = root.isRecording;
        fullRep._voiceKeyPttArmed = false;
        voiceKeyHoldTimer.stop();

        var mode = fullRep.voiceKeyMicMode;
        if (mode === "hold") {
            root.startVoiceInput();
            root.setVoiceLatched(false);
            return;
        }
        if (mode === "toggle")
            return;
        // auto: if already recording (toggle session), wait for release to stop
        if (fullRep._voiceKeyPressStartedRecording)
            return;
        voiceKeyHoldTimer.interval = fullRep.voiceKeyAutoHoldMs;
        voiceKeyHoldTimer.start();
    }

    function handleVoiceKeyReleased(event) {
        if (event.isAutoRepeat)
            return;
        fullRep._voiceKeyPressActive = false;
        voiceKeyHoldTimer.stop();
        var mode = fullRep.voiceKeyMicMode;
        var held = Date.now() - fullRep._voiceKeyPressTime;

        if (mode === "hold") {
            if (!root.isRecording)
                return;
            if (held < fullRep.voiceKeyHoldMinMs)
                root.cancelVoiceInput();
            else
                root.stopVoiceInput();
            return;
        }

        if (mode === "toggle") {
            if (root.isTranscribing || root.isLoading)
                return;
            if (root.isRecording)
                root.stopVoiceInput();
            else if (root.startVoiceInput())
                root.setVoiceLatched(true);
            return;
        }

        // --- auto (same as mic button) ---
        if (fullRep._voiceKeyPressStartedRecording) {
            if (root.isRecording)
                root.stopVoiceInput();
            return;
        }
        if (fullRep._voiceKeyPttArmed) {
            if (root.isRecording)
                root.stopVoiceInput();
            fullRep._voiceKeyPttArmed = false;
            return;
        }
        // Released before hold threshold → click-toggle start
        if (!root.isRecording) {
            if (root.startVoiceInput())
                root.setVoiceLatched(true);
        }
    }

    function handleVoiceKeyCanceled() {
        fullRep._voiceKeyPressActive = false;
        voiceKeyHoldTimer.stop();
        if (fullRep.voiceKeyMicMode === "hold" || fullRep._voiceKeyPttArmed) {
            if (root.isRecording)
                root.cancelVoiceInput();
        }
        fullRep._voiceKeyPttArmed = false;
    }

    Timer {
        id: voiceKeyHoldTimer
        interval: fullRep.voiceKeyAutoHoldMs
        repeat: false
        onTriggered: {
            if (!fullRep._voiceKeyPressActive || fullRep._voiceKeyPressStartedRecording)
                return;
            if (fullRep.voiceKeyMicMode !== "auto")
                return;
            if (root.isTranscribing || root.isLoading || !root.systemPromptReady)
                return;
            fullRep._voiceKeyPttArmed = true;
            root.startVoiceInput();
            root.setVoiceLatched(false); // PTT, not latched toggle
        }
    }

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
            { cmd: "/skills",   desc: i18n("List discovered skills and their status") },
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

    readonly property int compactCutoffDisplayIndex: {
        if (!Plasmoid.configuration.compactionEnabled || !root.activeCompaction || !root.activeCompaction.summary)
            return -1;

        var keepTurns = Plasmoid.configuration.compactionKeepRecentTurns || 4;
        var userCount = 0;
        for (var i = root.displayMessages.count - 1; i >= 0; i--) {
            var msg = root.displayMessages.get(i);
            if (msg && msg.role === "user") {
                userCount++;
                if (userCount === keepTurns) {
                    return i;
                }
            }
        }
        return -1;
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 24
    Layout.preferredWidth: Kirigami.Units.gridUnit * 28
    Layout.preferredHeight: Kirigami.Units.gridUnit * 32
    
    header: PlasmaExtras.BasicPlasmoidHeading {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.ToolButton {
                id: profileToolButton
                text: {
                    var profiles = root.profilesList;
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
                    model: root.profilesList
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
                id: retryConfirmDialog
                parent: QQC2.Overlay.overlay
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                modal: true
                focus: true
                closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
                padding: Kirigami.Units.largeSpacing

                property int targetDisplayIndex: -1
                property int removeCount: 0

                background: Rectangle {
                    color: Kirigami.Theme.backgroundColor
                    border.color: Kirigami.Theme.focusColor
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing
                }

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.largeSpacing

                    PlasmaComponents.Label {
                        text: i18n("Retry from this message?")
                        font.bold: true
                    }

                    PlasmaComponents.Label {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
                        text: i18n("This will remove %1 message(s) after this point and generate a new response.", retryConfirmDialog.removeCount)
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Button {
                            text: i18n("Cancel")
                            onClicked: retryConfirmDialog.close()
                        }

                        PlasmaComponents.Button {
                            text: i18n("Retry")
                            icon.name: "view-refresh"
                            onClicked: {
                                var idx = retryConfirmDialog.targetDisplayIndex;
                                retryConfirmDialog.close();
                                if (idx >= 0) {
                                    root.doRetryTruncate(idx);
                                }
                            }
                        }
                    }
                }
            }

            QQC2.Popup {
                id: compactionSummaryDialog
                parent: QQC2.Overlay.overlay
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 26)
                height: Math.min(parent.height - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 22)
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
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "archive-insert"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            PlasmaComponents.Label {
                                text: i18n("Compacted Context Summary")
                                font.bold: true
                            }

                            PlasmaComponents.Label {
                                text: {
                                    if (!root.activeCompaction) return "";
                                    var upTo = root.activeCompaction.compactedUpToMsgId || "";
                                    var time = root.activeCompaction.timestamp ? new Date(root.activeCompaction.timestamp).toLocaleTimeString() : "";
                                    return i18n("Compacted up to %1%2 • Citations active", upTo, time ? " (" + time + ")" : "");
                                }
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                            }
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "window-close"
                            Accessible.name: i18n("Close")
                            onClicked: compactionSummaryDialog.close()
                        }
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                    }

                    QQC2.ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        QQC2.TextArea {
                            id: compactionSummaryArea
                            readOnly: true
                            wrapMode: TextEdit.Wrap
                            text: (root.activeCompaction && root.activeCompaction.summary) ? root.activeCompaction.summary : i18n("No compaction summary available.")
                            selectByMouse: true
                            font: Kirigami.Theme.smallFont
                            background: Rectangle {
                                color: Kirigami.Theme.alternateBackgroundColor
                                radius: Kirigami.Units.smallSpacing / 2
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Button {
                            text: i18n("Copy")
                            icon.name: "edit-copy"
                            enabled: !!(root.activeCompaction && root.activeCompaction.summary)
                            onClicked: {
                                clipboardHelper.text = compactionSummaryArea.text;
                                clipboardHelper.selectAll();
                                clipboardHelper.copy();
                            }
                        }

                        PlasmaComponents.Button {
                            text: root.isCompacting ? i18n("Compacting…") : i18n("Re-compact")
                            icon.name: "view-refresh"
                            enabled: !root.isCompacting && chatMessages.count > 1
                            PlasmaComponents.ToolTip.text: i18n("Incrementally compact new uncompacted conversation turns.")
                            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                            PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                            onClicked: {
                                root.forceCompaction(false);
                            }
                        }

                        PlasmaComponents.Button {
                            text: root.isCompacting ? i18n("Compacting…") : i18n("Recompact All")
                            icon.name: "view-refresh"
                            enabled: !root.isCompacting && chatMessages.count > 1
                            PlasmaComponents.ToolTip.text: i18n("Re-summarize the entire conversation from turn 1 from scratch, creating a fresh, unified compaction.")
                            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                            PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                            onClicked: {
                                root.forceCompaction(true);
                            }
                        }

                        Item { Layout.fillWidth: true }

                        PlasmaComponents.Button {
                            text: i18n("Close")
                            onClicked: compactionSummaryDialog.close()
                        }
                    }
                }
            }

            Connections {
                target: root
                function onConfirmRetryRequested(displayIndex, removeCount) {
                    retryConfirmDialog.targetDisplayIndex = displayIndex;
                    retryConfirmDialog.removeCount = removeCount;
                    retryConfirmDialog.open();
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
                        var prefix = msg.role === "user" ? ((msg.fromVoice ? "🗣️ " : "") + (Plasmoid.configuration.userName || i18n("You"))) :
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
                id: compactionToolButton
                icon.name: root.isCompacting ? "view-refresh" : "archive-insert"
                visible: Plasmoid.configuration.compactionEnabled && Plasmoid.configuration.showIconCompacted && ((root.activeCompaction && root.activeCompaction.summary && root.activeCompaction.summary.length > 0) || root.isCompacting)
                Accessible.name: i18n("View compacted context summary")
                PlasmaComponents.ToolTip.text: root.isCompacting ? i18n("Compacting context in background…") : i18n("View compacted context summary")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: {
                    if (compactionSummaryDialog.opened) {
                        compactionSummaryDialog.close();
                    } else {
                        compactionSummaryDialog.open();
                    }
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
                var prefix = msg.role === "user" ? ((msg.fromVoice ? "🗣️ " : "") + (Plasmoid.configuration.userName || i18n("You"))) :
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

        ColumnLayout {
            anchors.fill: parent
            spacing: Plasmoid.configuration.chatSpacing

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.leftMargin: Plasmoid.configuration.chatSpacing
                Layout.rightMargin: Plasmoid.configuration.chatSpacing
                Layout.topMargin: Plasmoid.configuration.chatSpacing
                visible: root.showApiKeyMigrationNotice
                type: Kirigami.MessageType.Information
                text: root.apiKeyMigrationNoticeText
                // Kirigami's built-in X only sets visible=false (no signal) and
                // would break the binding to showApiKeyMigrationNotice; use an
                // action so dismiss stays in sync with clearChat().
                actions: [
                    Kirigami.Action {
                        text: i18n("Dismiss")
                        icon.name: "dialog-ok"
                        onTriggered: root.dismissApiKeyMigrationNotice()
                    }
                ]
            }

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

                // ---- Follow policy -------------------------------------------------
                // One bit decides everything: followOutput.
                //   - set:   user returns to the very bottom (wheel/drag) or presses
                //            the go-down button
                //   - clear: user wheels/drags away from the bottom, or a finished
                //            response parks the view at its top for reading
                // Every content signal funnels into scrollToBottom(), which no-ops
                // when the bit is off. User intent is captured at the source
                // (WheelHandler / movement events) — never inferred from
                // contentYChanged, so programmatic jumps can never be misread as
                // user input and vice versa.
                property bool followOutput: true
                // A drag/flick/scrollbar gesture is in progress; jumps pause until
                // it ends (movementEnded re-derives followOutput from position).
                property bool dragging: false
                // Coalesces queued jumps: one deferred scrollToBottom per event-loop
                // pass, however many signals fired in that pass.
                property bool _jumpQueued: false

                function scrollToBottom() {
                    if (_jumpQueued) return;
                    _jumpQueued = true;
                    // Defer outside signal handlers: runs after layout has had a
                    // chance to settle, and keeps forceLayout() out of
                    // layout-driven signal handlers (reentrancy hazard).
                    Qt.callLater(function() {
                        _jumpQueued = false;
                        if (!messageList.followOutput || messageList.dragging) return;
                        // Streaming pin exception: while a streamed response grows
                        // taller than the viewport, hold its first line in view
                        // instead of tailing its end.
                        if (root.isLoading && root.streamingMessageIndex >= 0) {
                            var item = messageList.itemAtIndex(root.streamingMessageIndex);
                            if (item && item.height > messageList.height) {
                                messageList.positionViewAtIndex(root.streamingMessageIndex, ListView.Beginning);
                                return;
                            }
                        }
                        forceLayout();
                        positionViewAtEnd();
                    });
                }

                // Observe-only wheel listener. Mouse-wheel scrolling does not emit
                // movementStarted — this is how we know real input happened without
                // touching contentYChanged. target:null keeps the handler from
                // acting on the event; blocking:false lets it propagate so the
                // Flickable still scrolls natively.
                WheelHandler {
                    target: null
                    blocking: false
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function(event) {
                        var up = event.angleDelta.y > 0;
                        Qt.callLater(function() {
                            // Evaluate after Flickable applied the scroll.
                            if (!messageList)
                                return;
                            if (up && !messageList.atYEnd)
                                messageList.followOutput = false;
                            else if (messageList.atYEnd)
                                messageList.followOutput = true;
                        });
                    }
                }

                onMovementStarted: dragging = true
                onMovementEnded: {
                    dragging = false;
                    followOutput = atYEnd;
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
                    fromVoice: !!model.fromVoice
                    isCompacted: fullRep.compactCutoffDisplayIndex >= 0 && index < fullRep.compactCutoffDisplayIndex
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
                        messageList.positionViewAtIndex(index, ListView.Beginning);
                    }
                    onShareRequested: function(index) { root.shareOutput(index); }
                    onRetryRequested: function(msgIndex) { root.retryFromMessage(msgIndex); }
                    onEditSaved: function(msgIndex, newContent) { root.editMessageContent(msgIndex, newContent); }
                    onEditAndRetryRequested: function(msgIndex, newContent) { root.editAndRetryMessage(msgIndex, newContent); }
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

                // Content triggers: every append, mutation, and height change
                // funnels into the same queued jump. Settle jitter and clamp-backs
                // just re-request it — convergence needs no suppression logic.
                onCountChanged: scrollToBottom()

                onContentHeightChanged: scrollToBottom()

                Connections {
                    target: root
                    function onExpandedChanged() {
                        if (!root.expanded && fullRep._voiceKeyPressActive) {
                            fullRep.handleVoiceKeyCanceled();
                        }
                        if (root.expanded) {
                            Plasmoid.status = PlasmaCore.Types.AcceptingInputStatus;
                            if (fullRep.Window.window) {
                                fullRep.Window.window.requestActivate();
                            }
                            inputField.forceActiveFocus(Qt.ShortcutFocusReason);
                            Qt.callLater(function() {
                                if (root.expanded && inputField.enabled) {
                                    inputField.forceActiveFocus(Qt.ShortcutFocusReason);
                                }
                            });
                        }
                    }
                }

                Connections {
                    target: root
                    function onChatContentChanged() {
                        messageList.scrollToBottom();
                    }
                    function onResponseReady(messageIndex) {
                        Qt.callLater(function() {
                            if (!messageList.followOutput || messageList.dragging) return;
                            var item = messageList.itemAtIndex(messageIndex);
                            if (item && item.height > messageList.height) {
                                // Tall finished response: park it at its first line
                                // for reading and pause following until the user
                                // returns to the bottom (or presses go-down).
                                messageList.followOutput = false;
                                messageList.positionViewAtIndex(messageIndex, ListView.Beginning);
                            } else {
                                messageList.scrollToBottom();
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
                visible: !messageList.followOutput && !messageList.atYEnd && messageList.count > 0
                icon.name: "go-down"
                icon.width: Kirigami.Units.iconSizes.small
                icon.height: Kirigami.Units.iconSizes.small
                z: 1
                onClicked: {
                    messageList.followOutput = true;
                    messageList.scrollToBottom();
                }

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
            visible: root.sttStatusText && root.sttStatusText.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: Plasmoid.configuration.chatSpacing
            Layout.rightMargin: Plasmoid.configuration.chatSpacing
            spacing: Kirigami.Units.smallSpacing

            QQC2.BusyIndicator {
                running: visible
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.sttStatusText
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.9
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
                        
                        Component.onCompleted: {
                            if (root.expanded && enabled) {
                                forceActiveFocus(Qt.ShortcutFocusReason);
                            }
                        }

                        onEnabledChanged: {
                            if (root.expanded && enabled && !activeFocus) {
                                forceActiveFocus(Qt.ShortcutFocusReason);
                            }
                        }

                        onActiveFocusChanged: {
                            if (!activeFocus && fullRep._voiceKeyPressActive) {
                                fullRep.handleVoiceKeyCanceled();
                            }
                        }

                        function submitMessage(event) {
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

                        Keys.onPressed: function(event) {
                            // Voice hotkey (same hold/toggle/auto as mic) — steal chord before typing.
                            if (fullRep.voiceKeyPressMatches(event)) {
                                event.accepted = true;
                                fullRep.handleVoiceKeyPressed(event);
                                return;
                            }

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

                        Keys.onReleased: function(event) {
                            if (fullRep.voiceKeyReleaseMatches(event)) {
                                if (!fullRep.isModifierKey(event.key)) {
                                    event.accepted = true;
                                }
                                fullRep.handleVoiceKeyReleased(event);
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
                            inputField.submitMessage(event);
                        }

                        Keys.onEnterPressed: function(event) {
                            inputField.submitMessage(event);
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
                        var profiles = root.profilesList;
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

            // Microphone: hold / toggle / auto (click toggle, hold ≥250ms = PTT).
            PlasmaComponents.ToolButton {
                id: micButton
                visible: root.sttAvailable
                enabled: !root.isLoading && !root.isTranscribing && root.systemPromptReady
                checkable: false
                icon.name: root.isRecording ? "media-record" : (root.isTranscribing ? "view-refresh" : "audio-input-microphone")

                readonly property string micMode: Plasmoid.configuration.sttMicMode || "auto"
                readonly property int autoHoldMs: Math.max(100, Plasmoid.configuration.sttAutoHoldMs || 250)
                readonly property int holdMinMs: 250

                // Press tracking for hold / auto
                property real _pressTime: 0
                property bool _pressStartedRecording: false  // was already recording on press
                property bool _pttArmed: false               // auto: committed to push-to-talk
                property bool _pressActive: false

                PlasmaComponents.ToolTip.text: {
                    if (root.isTranscribing)
                        return i18n("Transcribing…");
                    if (!root.systemPromptReady)
                        return i18n("Preparing…");
                    if (root.isLoading)
                        return i18n("Wait for the current reply");
                    if (root.isRecording) {
                        if (micMode === "toggle" || (micMode === "auto" && !micButton._pttArmed))
                            return i18n("Click to stop and send");
                        return i18n("Release to send");
                    }
                    if (micMode === "toggle")
                        return i18n("Click to start");
                    if (micMode === "hold")
                        return i18n("Hold to talk");
                    return i18n("Click to toggle, hold to talk");
                }
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""

                contentItem: Item {
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        source: micButton.icon.name
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: Kirigami.Units.iconSizes.smallMedium
                        color: root.isRecording ? Kirigami.Theme.negativeTextColor
                             : (micButton.enabled ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor)
                    }
                }

                Timer {
                    id: autoHoldTimer
                    interval: micButton.autoHoldMs
                    repeat: false
                    onTriggered: {
                        if (!micButton._pressActive || micButton._pressStartedRecording)
                            return;
                        if (micButton.micMode !== "auto")
                            return;
                        // Commit to push-to-talk
                        micButton._pttArmed = true;
                        root.startVoiceInput();
                        root.setVoiceLatched(false); // PTT, not latched toggle
                    }
                }

                MouseArea {
                    id: micMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    enabled: micButton.enabled

                    onPressed: function(mouse) {
                        micButton._pressTime = Date.now();
                        micButton._pressActive = true;
                        micButton._pressStartedRecording = root.isRecording;
                        micButton._pttArmed = false;
                        autoHoldTimer.stop();

                        var mode = micButton.micMode;
                        if (mode === "hold") {
                            root.startVoiceInput();
                            root.setVoiceLatched(false);
                            return;
                        }
                        if (mode === "toggle") {
                            // Decide on release (so press doesn't double-fire)
                            return;
                        }
                        // auto: if already in a toggle session, wait for release to stop
                        if (micButton._pressStartedRecording)
                            return;
                        autoHoldTimer.interval = micButton.autoHoldMs;
                        autoHoldTimer.start();
                    }
                    onReleased: function(mouse) {
                        micButton._pressActive = false;
                        autoHoldTimer.stop();
                        var mode = micButton.micMode;
                        var held = Date.now() - micButton._pressTime;

                        if (mode === "hold") {
                            if (!root.isRecording)
                                return;
                            if (held < micButton.holdMinMs)
                                root.cancelVoiceInput();
                            else
                                root.stopVoiceInput();
                            return;
                        }

                        if (mode === "toggle") {
                            if (root.isTranscribing || root.isLoading)
                                return;
                            if (root.isRecording)
                                root.stopVoiceInput();
                            else {
                                if (root.startVoiceInput())
                                    root.setVoiceLatched(true);
                            }
                            return;
                        }

                        // --- auto ---
                        if (micButton._pressStartedRecording) {
                            // Second click on latched recording → stop & send
                            if (root.isRecording)
                                root.stopVoiceInput();
                            return;
                        }
                        if (micButton._pttArmed) {
                            // PTT session: release ends recording
                            if (root.isRecording)
                                root.stopVoiceInput();
                            micButton._pttArmed = false;
                            return;
                        }
                        // Released before hold threshold → click-toggle start
                        if (!root.isRecording) {
                            if (root.startVoiceInput())
                                root.setVoiceLatched(true);
                        }
                    }
                    onCanceled: {
                        micButton._pressActive = false;
                        autoHoldTimer.stop();
                        if (micButton.micMode === "hold" || micButton._pttArmed) {
                            if (root.isRecording)
                                root.cancelVoiceInput();
                        }
                        // Do not start toggle on cancel
                        micButton._pttArmed = false;
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
