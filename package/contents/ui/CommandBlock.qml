/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtCore
import QtQuick.Dialogs
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: commandBlock

    property string commandText
    property bool hasRun: false

    signal runRequested(string command, string sourceId)
    signal terminalRequested(string command)
    signal saveRequested(string filePath, string content)
    signal stopRequested(string command, string sourceId)

    readonly property string blockId: Math.random().toString(36).substring(2, 15)

    property bool sessionMode: false
    property string sessionLabel: ""
    property bool isRunning: false

    // Hidden helper for clipboard access
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    color: Kirigami.Theme.alternateBackgroundColor
    radius: 4
    border.color: Kirigami.Theme.disabledTextColor
    border.width: 1

    implicitHeight: commandLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
    implicitWidth: commandLayout.implicitWidth + Kirigami.Units.smallSpacing * 2

    ColumnLayout {
        id: commandLayout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Chip {
            Layout.fillWidth: true
            visible: sessionMode && sessionLabel !== ""
            text: sessionLabel
            icon.name: "utilities-terminal"
            closable: false
            checkable: false
            hoverEnabled: false
            activeFocusOnTab: false
        }

        QQC2.ScrollView {
            id: cmdScroll
            Layout.fillWidth: true
            Layout.maximumHeight: commandLabel.font.pixelSize * 1.4 * 10 + Kirigami.Units.smallSpacing
            Layout.preferredHeight: Math.min(commandLabel.implicitHeight, commandLabel.font.pixelSize * 1.4 * 10 + Kirigami.Units.smallSpacing)
            contentWidth: availableWidth

            // Keep the inner Flickable from eating wheel events when there's
            // nothing to scroll — otherwise the outer chat list can't scroll
            // while the cursor is over a command block, which fights the
            // autoscroll-tracking logic in FullRepresentation.qml.
            Component.onCompleted: {
                if (contentItem && contentItem.hasOwnProperty("interactive")) {
                    contentItem.interactive = Qt.binding(function() {
                        return cmdScroll.contentHeight > cmdScroll.height + 1;
                    });
                }
            }

            Kirigami.SelectableLabel {
                id: commandLabel
                width: parent.width
                text: commandBlock.commandText
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Button {
                text: i18n("Save")
                icon.name: "document-save"
                PlasmaComponents.ToolTip.text: i18n("Save as script file")
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: saveDialog.open()
            }

            PlasmaComponents.Button {
                text: i18n("Copy")
                icon.name: "edit-copy"
                PlasmaComponents.ToolTip.text: i18n("Copy to clipboard")
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: {
                    clipboardHelper.text = commandBlock.commandText;
                    clipboardHelper.selectAll();
                    clipboardHelper.copy();
                }
            }

            PlasmaComponents.Button {
                text: {
                    if (sessionMode && hasRun && isRunning) return i18n("Stop");
                    return hasRun ? i18n("Ran") : i18n("Run");
                }
                icon.name: {
                    if (sessionMode && hasRun && isRunning) return "process-stop";
                    return hasRun ? "dialog-ok-apply" : "media-playback-start";
                }
                enabled: !hasRun || (sessionMode && isRunning)
                PlasmaComponents.ToolTip.text: (sessionMode && hasRun && isRunning) ? i18n("Stop running command") : i18n("Execute command inline")
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: {
                    if (sessionMode && hasRun && isRunning) {
                        commandBlock.stopRequested(commandBlock.commandText, commandBlock.blockId);
                    } else {
                        commandBlock.hasRun = true;
                        commandBlock.runRequested(commandBlock.commandText, commandBlock.blockId);
                    }
                }
            }

            PlasmaComponents.Button {
                text: i18n("Terminal")
                icon.name: "utilities-terminal"
                visible: !sessionMode
                PlasmaComponents.ToolTip.text: i18n("Open in terminal emulator")
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: commandBlock.terminalRequested(commandBlock.commandText)
            }
        }
    }

    FileDialog {
        id: saveDialog
        title: i18n("Save Script")
        fileMode: FileDialog.SaveFile
        currentFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation)
        selectedFile: currentFolder + "/script.sh"
        nameFilters: [i18n("Shell scripts (*.sh)"), i18n("All files (*)")]
        onAccepted: {
            var path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
            commandBlock.saveRequested(path, commandBlock.commandText);
        }
    }
}
