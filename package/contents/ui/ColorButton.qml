/*
    SPDX-FileCopyrightText: 2015 David Edmundson <davidedmundson@kde.org>
    SPDX-FileCopyrightText: 2026 Joshua Roman (adapted for PlasmaLLM)

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as QtDialogs
import org.kde.kirigami as Kirigami

QQC2.Button {
    id: root

    property alias color: colorDialog.selectedColor
    property alias dialogTitle: colorDialog.title
    property bool showAlphaChannel: true

    signal accepted(color color)

    readonly property real _buttonMargins: Kirigami.Units.smallSpacing // Adapted for consistency

    implicitWidth: Kirigami.Units.gridUnit * 2 + _buttonMargins * 2

    Accessible.name: i18n("Color button")
    Accessible.description: enabled
      ? i18n("Current color is %1. This button will open a color chooser dialog.", color)
      : i18n("Current color is %1.", color)

    // checkerboard background for alpha
    Canvas {
        anchors.fill: colorBlock
        visible: colorDialog.selectedColor.a < 1

        onPaint: {
            const ctx = getContext('2d');
            ctx.fillStyle = "white";
            ctx.fillRect(0, 0, width, height);
            ctx.fillStyle = "#cccccc";
            for (let j = 0; j < width; j += 16) {
                for (let i = 0; i < height; i += 16) {
                    ctx.fillRect(j, i, 8, 8);
                    ctx.fillRect(j + 8, i + 8, 8, 8);
                }
            }
        }
    }

    Rectangle {
        id: colorBlock
        anchors.centerIn: parent
        height: parent.height - _buttonMargins * 2
        width: parent.width - _buttonMargins * 2
        color: enabled ? colorDialog.selectedColor : Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.textColor
        border.width: 1
        opacity: enabled ? 1.0 : 0.5
    }

    QtDialogs.ColorDialog {
        id: colorDialog
        onAccepted: root.accepted(selectedColor)
    }

    onClicked: {
        colorDialog.open();
    }
}
