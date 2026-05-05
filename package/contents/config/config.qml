/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "im-user"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-font"
        source: "configAppearance.qml"
    }
    ConfigCategory {
        name: i18n("System Prompt")
        icon: "dialog-scripts"
        source: "configSystemPrompt.qml"
    }
    ConfigCategory {
        name: i18n("Tasks")
        icon: "view-task"
        source: "configTasks.qml"
    }
    ConfigCategory {
        name: i18n("Tools")
        icon: "configure"
        source: "configTools.qml"
    }
}
