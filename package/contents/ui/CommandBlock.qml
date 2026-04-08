/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
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

    signal runRequested(string command)
    signal terminalRequested(string command)
    signal saveRequested(string filePath, string content)

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

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.maximumHeight: commandLabel.font.pixelSize * 1.4 * 10 + Kirigami.Units.smallSpacing
            Layout.preferredHeight: Math.min(commandLabel.implicitHeight, commandLabel.font.pixelSize * 1.4 * 10 + Kirigami.Units.smallSpacing)
            contentWidth: availableWidth

            PlasmaComponents.Label {
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
                text: commandBlock.hasRun ? i18n("Ran") : i18n("Run")
                icon.name: commandBlock.hasRun ? "dialog-ok-apply" : "media-playback-start"
                enabled: !commandBlock.hasRun
                PlasmaComponents.ToolTip.text: i18n("Execute command inline")
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: {
                    commandBlock.hasRun = true;
                    commandBlock.runRequested(commandBlock.commandText);
                }
            }

            PlasmaComponents.Button {
                text: i18n("Terminal")
                icon.name: "utilities-terminal"
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
