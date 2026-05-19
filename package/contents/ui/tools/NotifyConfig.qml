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
    
    QQC2.CheckBox {
        text: i18n("Ask before running")
        checked: !cfg_toolsNotifyAutoRun
        onCheckedChanged: if (_initialized) cfg_toolsNotifyAutoRun = !checked
    }
}
