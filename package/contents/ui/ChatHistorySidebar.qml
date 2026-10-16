/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

// Recent chats beside the conversation on wide layouts. Shares
// root.historyFilesModel with the header button's menu, which takes over
// when this is hidden.
ColumnLayout {
    id: sidebar
    spacing: 0

    property bool showNewChat: true

    signal newChatRequested()
    signal chatChosen(string file)
    signal openFolderRequested()
    signal clearAllRequested()

    PlasmaComponents.ToolButton {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        visible: sidebar.showNewChat
        icon.name: "list-add"
        text: i18n("New chat")
        onClicked: sidebar.newChatRequested()
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        visible: sidebar.showNewChat
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        PlasmaComponents.ScrollView {
            anchors.fill: parent

            ListView {
                id: historyList
                clip: true
                model: root.historyFilesModel || null
                spacing: Kirigami.Units.smallSpacing
                topMargin: Kirigami.Units.smallSpacing
                bottomMargin: Kirigami.Units.smallSpacing

                delegate: PlasmaComponents.ItemDelegate {
                    id: entry
                    width: ListView.view.width
                    padding: Kirigami.Units.largeSpacing
                    highlighted: model.name === root.currentChatFile
                    Accessible.name: (model.dateTime || "") + (model.preview ? ": " + model.preview : "")

                    PlasmaComponents.ToolTip.text: model.preview || ""
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                    PlasmaComponents.ToolTip.visible: hovered && previewLabel.truncated

                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: model.dateTime || model.name || ""
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.Label {
                            id: previewLabel
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: model.preview || ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    onClicked: sidebar.chatChosen(model.file)
                }
            }
        }

        PlasmaComponents.BusyIndicator {
            anchors.centerIn: parent
            visible: root.isFetchingHistory && historyList.count === 0
            running: visible
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - (Kirigami.Units.largeSpacing * 2)
            visible: !root.isFetchingHistory && historyList.count === 0
            text: i18n("No recent chats")
            iconName: "clock"
        }
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Item { Layout.fillWidth: true }

        PlasmaComponents.ToolButton {
            icon.name: "folder-open"
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Open history folder...")
            Accessible.name: text
            PlasmaComponents.ToolTip.text: text
            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            PlasmaComponents.ToolTip.visible: hovered
            onClicked: sidebar.openFolderRequested()
        }

        PlasmaComponents.ToolButton {
            icon.name: "edit-clear-history"
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Clear all history...")
            Accessible.name: text
            enabled: historyList.count > 0
            PlasmaComponents.ToolTip.text: text
            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            PlasmaComponents.ToolTip.visible: hovered
            onClicked: sidebar.clearAllRequested()
        }
    }
}
