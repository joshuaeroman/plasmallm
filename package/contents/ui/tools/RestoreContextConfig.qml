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

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        type: Kirigami.MessageType.Information
        text: i18n("This tool allows the primary assistant to retrieve original transcripts from cited message ranges. It runs automatically without asking for permission when Context Compaction is active.")
        visible: true
    }
}
