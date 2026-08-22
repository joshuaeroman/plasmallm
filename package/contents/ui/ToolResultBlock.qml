/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "api.js" as Api
import "toolManager.js" as ToolManager

Rectangle {
    id: toolBlock

    property string toolName: ""
    property var toolArgs: ({})
    property string stdout: ""
    property string stderr: ""
    property int exitCode: 0
    property bool isRunning: false
    property var attachmentPaths: []

    property bool sessionMode: false
    property string sessionLabel: ""

    signal terminalRequested(string command)
    signal stopRequested(string command)
    signal collapseRequested()

    // Whether the finished result can be folded back into the summary pill.
    property bool collapsible: false

    readonly property var args: {
        if (typeof toolArgs === "object" && toolArgs !== null) return toolArgs;
        if (typeof toolArgs === "string" && toolArgs.length > 0) {
            try {
                return JSON.parse(toolArgs);
            } catch(e) {
                return {};
            }
        }
        return {};
    }

    readonly property string toolIcon: ToolManager.toolIconName(toolBlock.toolName)

    readonly property string toolLabel: ToolManager.resultLabel(
        toolBlock.toolName,
        toolBlock.args,
        (typeof root !== 'undefined' && root.sysInfo && root.sysInfo.userHome) ? root.sysInfo.userHome : "$HOME"
    )

    color: Kirigami.Theme.alternateBackgroundColor
    radius: 4
    border.color: Kirigami.Theme.disabledTextColor
    border.width: 1

    implicitHeight: mainLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
    implicitWidth: parent ? parent.width : 300

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: toolBlock.toolIcon
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: toolBlock.toolLabel
                font.bold: true
                elide: Text.ElideMiddle
            }

            PlasmaComponents.BusyIndicator {
                visible: toolBlock.isRunning
                running: toolBlock.isRunning
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.ToolButton {
                visible: toolBlock.isRunning && toolBlock.toolName === "run_command"
                icon.name: "process-stop"
                onClicked: toolBlock.stopRequested(args.command || "")
                PlasmaComponents.ToolTip.text: i18n("Stop command")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
            }

            Kirigami.Chip {
                visible: sessionMode && sessionLabel !== "" && toolBlock.toolName === "run_command"
                text: sessionLabel
                icon.name: "utilities-terminal"
                closable: false
                checkable: false
                hoverEnabled: true
                activeFocusOnTab: true
                PlasmaComponents.ToolTip.text: i18n("Open terminal attached to this session")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
                onClicked: toolBlock.terminalRequested(args.command || "")
            }

            PlasmaComponents.ToolButton {
                visible: toolBlock.collapsible && !toolBlock.isRunning
                icon.name: "go-up"
                onClicked: toolBlock.collapseRequested()
                PlasmaComponents.ToolTip.text: i18n("Collapse result")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered
            }

            PlasmaComponents.ToolButton {
                visible: !toolBlock.isRunning && (toolBlock.stdout.length > 0 || toolBlock.stderr.length > 0)
                icon.name: "edit-copy"
                onClicked: {
                    var text = toolBlock.stdout;
                    if (toolBlock.stderr) text += "\nstderr: " + toolBlock.stderr;
                    copyToClipboard(text);
                }
                PlasmaComponents.ToolTip.text: i18n("Copy output")
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                PlasmaComponents.ToolTip.visible: hovered && PlasmaComponents.ToolTip.text !== ""
            }
        }

        QQC2.ScrollView {
            id: outputScroll
            visible: !toolBlock.isRunning && (toolBlock.stdout.length > 0 || toolBlock.stderr.length > 0)
            Layout.fillWidth: true
            Layout.maximumHeight: root.uiFontPointSize * 1.4 * 15
            Layout.preferredHeight: Math.min(outputLabel.implicitHeight + Kirigami.Units.smallSpacing * 2, Layout.maximumHeight)
            contentWidth: availableWidth

            background: Rectangle {
                color: "black"
                radius: 2
            }

            // Scroll helper
            Component.onCompleted: {
                if (contentItem && contentItem.hasOwnProperty("interactive")) {
                    contentItem.interactive = Qt.binding(function() {
                        return outputScroll.contentHeight > outputScroll.height + 1;
                    });
                }
            }

            Kirigami.SelectableLabel {
                id: outputLabel
                width: outputScroll.availableWidth
                padding: Kirigami.Units.smallSpacing
                text: {
                    var t = toolBlock.stdout;
                    if (toolBlock.stderr) t += (t ? "\n" : "") + "stderr: " + toolBlock.stderr;
                    return t;
                }
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.family: root.codeFontFamily
                font.pointSize: root.codeFontPointSize
                color: toolBlock.exitCode === 0 ? "white" : Kirigami.Theme.negativeTextColor
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            visible: toolBlock.attachmentPaths && toolBlock.attachmentPaths.length > 0

            Repeater {
                model: toolBlock.attachmentPaths
                delegate: Loader {
                    id: attachmentLoader
                    readonly property string filePath: modelData
                    readonly property bool isImage: filePath.startsWith("data:") || (typeof Api !== 'undefined' && Api.isImageFile(filePath))
                    readonly property string fileName: filePath.startsWith("data:") ? "pasted_image.png" : filePath.split("/").pop()

                    sourceComponent: isImage ? imageThumbComponent : genericFileChipComponent
                }
            }
        }
    }

    Component {
        id: imageThumbComponent
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
            border.color: Kirigami.Theme.disabledTextColor
            border.width: 1
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
        }
    }

    Component {
        id: genericFileChipComponent
        Kirigami.Chip {
            readonly property string fileName: parent ? (parent.fileName || "") : ""
            readonly property string filePath: parent ? (parent.filePath || "") : ""
            text: fileName
            icon.name: (filePath && filePath.indexOf(".") !== -1) ? Api.iconForFile(filePath) : "text-x-generic"
            closable: false
            checkable: false
        }
    }

    // Reference to parent message's clipboard helper if needed
    function copyToClipboard(text) {
        if (typeof messageItem !== 'undefined' && messageItem.copyToClipboard) {
            messageItem.copyToClipboard(text);
        } else {
            // Fallback if not inside ChatMessage
            var temp = Qt.createQmlObject('import QtQuick 2.0; TextEdit { visible: false }', toolBlock);
            temp.text = text;
            temp.selectAll();
            temp.copy();
            temp.destroy();
        }
    }
}
