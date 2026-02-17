/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "General"
        icon: "im-user"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: "System Prompt"
        icon: "dialog-scripts"
        source: "configSystemPrompt.qml"
    }
}
