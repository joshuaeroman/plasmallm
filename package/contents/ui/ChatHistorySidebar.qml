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
    // Off, saved summaries stay in the files but rows show the first prompt.
    property bool showSummaries: true

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

                // Rows arrive newest first, so each day group is contiguous.
                section.property: "group"
                section.criteria: ViewSection.FullString
                section.delegate: PlasmaComponents.Label {
                    required property string section
                    width: ListView.view.width
                    topPadding: Kirigami.Units.largeSpacing
                    leftPadding: Kirigami.Units.largeSpacing
                    rightPadding: Kirigami.Units.largeSpacing
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    elide: Text.ElideRight
                    text: {
                        switch (section) {
                        case "today": return i18n("Today");
                        case "yesterday": return i18n("Yesterday");
                        case "week": return i18n("Previous 7 days");
                        default: return i18n("Older");
                        }
                    }
                }

                delegate: PlasmaComponents.ItemDelegate {
                    id: entry
                    width: ListView.view.width
                    padding: Kirigami.Units.largeSpacing
                    highlighted: model.name === root.currentChatFile
                    // Summary title when there is one, else the first prompt.
                    readonly property string shownTitle: sidebar.showSummaries ? (model.title || "") : ""
                    readonly property string label: shownTitle || model.preview || ""
                    Accessible.name: label + (model.dateTime ? ", " + model.dateTime : "")

                    // With a title, the tooltip shows the first prompt it summarizes.
                    PlasmaComponents.ToolTip.text: model.preview || ""
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                    PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
                        && (!!shownTitle || previewLabel.truncated)

                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            id: previewLabel
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: entry.label
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: model.when || model.dateTime || model.name || ""
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
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
