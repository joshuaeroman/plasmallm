/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    Layout.fillWidth: true

    QQC2.Label {
        text: i18n("Runs a .sh file inside a skill folder. Per-run approval is skipped only when that skill has “Allow running skill scripts without approval” checked on the Skills settings page.")
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
}
