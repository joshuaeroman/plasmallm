/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

    QQC2.CheckBox {
        id: autoRunCheckBox
        text: i18n("Ask before running commands from LLM")
        checked: !cfg_autoRunCommands
        onCheckedChanged: if (_initialized) cfg_autoRunCommands = !checked

        QQC2.ToolTip.text: i18n("Prompt for approval before executing shell commands from the LLM. Dangerous to uncheck as the LLM will see output and may run further commands.")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: 500
    }

    QQC2.Label {
        visible: !autoRunCheckBox.checked
        text: i18n("⚠️ DANGER: 'Ask before running' is disabled - the LLM can now execute commands without permission and will see their output, enabling an agentic workflow. Only use with trustworthy LLMs.")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        color: Kirigami.Theme.negativeTextColor
        font: Kirigami.Theme.smallFont
    }

    QQC2.Label {
        text: i18n("Note: This tool is not restricted by the path whitelist.")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    QQC2.Label {
        text: i18n("Session Multiplexer")
        font.bold: true
    }

    QQC2.CheckBox {
        id: useSessionMultiplexerCheckBox
        text: i18n("Run commands inside a persistent session")
        checked: cfg_useSessionMultiplexer
        onCheckedChanged: if (_initialized) cfg_useSessionMultiplexer = checked
        enabled: configPage.hasTmux || configPage.hasScreen

        QQC2.ToolTip.text: i18n("Execute LLM commands inside a long-lived tmux or screen session so state persists across turns.")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: 500
    }

    QQC2.Button {
        text: i18n("Reset Session")
        icon.name: "edit-clear-all"
        visible: useSessionMultiplexerCheckBox.checked
        onClicked: {
            var be = cfg_sessionMultiplexer === "screen" ? "screen" : "tmux";
            var sess = (cfg_sessionName || "").replace(/[^A-Za-z0-9_-]/g, "") || "plasmallm";
            var cmd = be === "tmux" ? "tmux kill-session -t '" + sess + "'" : "screen -S '" + sess + "' -X quit";
            configPage.execSource.connectSource(cmd);
        }
    }

    QQC2.ComboBox {
        id: sessionMultiplexerComboBox
        model: {
            var opts = [];
            if (configPage.hasTmux) opts.push({ text: "tmux", value: "tmux" });
            if (configPage.hasScreen) opts.push({ text: "screen", value: "screen" });
            return opts;
        }
        textRole: "text"
        valueRole: "value"
        enabled: useSessionMultiplexerCheckBox.checked && (configPage.hasTmux || configPage.hasScreen)

        onModelChanged: syncIndex()
        Component.onCompleted: syncIndex()

        function syncIndex() {
            for (var i = 0; i < count; i++) {
                if (model[i].value === cfg_sessionMultiplexer) {
                    currentIndex = i;
                    break;
                }
            }
        }

        onActivated: {
            if (_initialized && currentValue) cfg_sessionMultiplexer = currentValue;
        }
    }

    QQC2.TextField {
        placeholderText: "Session name (e.g. plasmallm)"
        text: cfg_sessionName
        onTextChanged: if (_initialized) cfg_sessionName = text
        enabled: useSessionMultiplexerCheckBox.checked && (configPage.hasTmux || configPage.hasScreen)
        Layout.fillWidth: true
    }

    QQC2.Label {
        visible: !(configPage.hasTmux || configPage.hasScreen)
        text: i18n("Neither 'tmux' nor 'screen' was found on your system. Session multiplexing is unavailable.")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        color: Kirigami.Theme.negativeTextColor
        font: Kirigami.Theme.smallFont
    }
}
