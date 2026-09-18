/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

import "../commandValidator.js" as CommandValidator

ColumnLayout {
    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

    QQC2.CheckBox {
        id: autoRunCheckBox
        text: i18n("Ask before running commands from LLM")
        checked: !cfg_autoRunCommands
        onCheckedChanged: if (_initialized) cfg_autoRunCommands = !checked

        QQC2.ToolTip.text: i18n("Prompt for approval before executing shell commands from the LLM. Dangerous to uncheck as the LLM will see output and may run further commands.")
        QQC2.ToolTip.delay: 500
        QQC2.ToolTip.visible: hovered
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
        QQC2.ToolTip.delay: 500
        QQC2.ToolTip.visible: hovered
    }

    QQC2.Button {
        id: resetSessionButton
        text: i18n("Reset Session")
        visible: useSessionMultiplexerCheckBox.checked
        onClicked: {
            var be = cfg_sessionMultiplexer === "screen" ? "screen" : "tmux";
            var sess = (cfg_sessionName || "").replace(/[^A-Za-z0-9_-]/g, "") || "plasmallm";
            var cmd = be === "tmux" ? "tmux kill-session -t '" + sess + "'" : "screen -S '" + sess + "' -X quit";
            configPage.execSource.connectSource(cmd);
        }

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: "media-playback-stop"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                color: Kirigami.Theme.negativeTextColor
            }
            QQC2.Label {
                text: resetSessionButton.text
                color: Kirigami.Theme.negativeTextColor
            }
        }

        QQC2.ToolTip.text: i18n("Kill persistent session (stops all processes and resets shell state)")
        QQC2.ToolTip.delay: 500
        QQC2.ToolTip.visible: hovered
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

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    QQC2.Label {
        text: i18n("Command Validation")
        font.bold: true
    }

    QQC2.CheckBox {
        id: validatorCheckBox
        text: i18n("Validate commands against their justification with a second model")
        checked: cfg_commandValidatorEnabled
        onCheckedChanged: if (_initialized) cfg_commandValidatorEnabled = checked

        QQC2.ToolTip.text: i18n("Before a command runs, the selected model checks that the command does what the LLM's justification says. Mismatched commands are denied automatically.")
        QQC2.ToolTip.delay: 500
        QQC2.ToolTip.visible: hovered
    }

    QQC2.Label {
        visible: validatorCheckBox.checked
        text: i18n("The validator checks that the command does what its justification says and that it is well-written shell (no incomplete constructs or syntax errors). Mismatched or malformed commands are denied automatically and the reason is returned to the LLM. If the validator cannot run (error or timeout), the command falls back to asking for approval.")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
    }

    ColumnLayout {
        visible: validatorCheckBox.checked
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            text: i18n("Validator profile:")
            font.bold: true
        }

        QQC2.ComboBox {
            id: validatorProfileCombo
            Layout.fillWidth: true
            model: configPage.validatorProfileChoices
            textRole: "name"
            onActivated: function(index) {
                if (_initialized && index >= 0 && index < configPage.validatorProfileChoices.length)
                    cfg_commandValidatorProfileId = configPage.validatorProfileChoices[index].id;
            }
            Component.onCompleted: syncValidatorProfile()
            Connections {
                target: configPage
                function onCfg_commandValidatorProfileIdChanged() { validatorProfileCombo.syncValidatorProfile(); }
            }
            function syncValidatorProfile() {
                var targetId = cfg_commandValidatorProfileId || "active";
                for (var i = 0; i < count; i++) {
                    if (model[i].id === targetId) {
                        if (currentIndex !== i) currentIndex = i;
                        return;
                    }
                }
                if (currentIndex !== 0) currentIndex = 0;
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            text: {
                var p = configPage.selectedValidatorProfile;
                var detected = CommandValidator.backendFor({
                    endpoint: p.apiEndpoint,
                    modelName: p.modelName,
                    backend: cfg_commandValidatorBackend || "auto"
                });
                return i18n("Provider: %1  |  Model: %2\nBackend: %3",
                    p.providerName || i18n("Default"),
                    p.modelName || i18n("None"),
                    detected === "decisions" ? i18n("Structured decisions (Jev)") : i18n("Chat completion (JSON)"));
            }
        }

        QQC2.Label {
            text: i18n("Backend:")
            font.bold: true
            Layout.topMargin: Kirigami.Units.smallSpacing
        }

        QQC2.ComboBox {
            id: validatorBackendCombo
            Layout.fillWidth: true
            model: [
                { text: i18n("Auto-detect"), value: "auto" },
                { text: i18n("Structured decisions (Jev/TypeSafe)"), value: "decisions" },
                { text: i18n("Chat completion (JSON verdict)"), value: "chat" }
            ]
            textRole: "text"
            valueRole: "value"
            onActivated: if (_initialized && currentValue) cfg_commandValidatorBackend = currentValue
            Component.onCompleted: syncValidatorBackend()
            Connections {
                target: configPage
                function onCfg_commandValidatorBackendChanged() { validatorBackendCombo.syncValidatorBackend(); }
            }
            function syncValidatorBackend() {
                var v = cfg_commandValidatorBackend || "auto";
                for (var i = 0; i < count; i++) {
                    if (model[i].value === v) {
                        if (currentIndex !== i) currentIndex = i;
                        return;
                    }
                }
                if (currentIndex !== 0) currentIndex = 0;
            }
        }

        QQC2.Label {
            text: i18n("Maximum mismatch probability allowed before a command is rejected (structured decisions backend):")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            font: Kirigami.Theme.smallFont
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: validatorThresholdSpin
                from: 5
                to: 95
                stepSize: 5
                value: Math.round((cfg_commandValidatorThreshold || 0.5) * 100)
                editable: true
                onValueModified: if (_initialized) cfg_commandValidatorThreshold = value / 100
            }

            QQC2.Label {
                text: i18n("% (lower = stricter)")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: configPage.validatorTestInProgress ? i18n("Testing…") : i18n("Test Validator")
                icon.name: "network-connect"
                enabled: !configPage.validatorTestInProgress
                onClicked: configPage.testCommandValidator()
            }

            QQC2.BusyIndicator {
                running: configPage.validatorTestInProgress
                visible: configPage.validatorTestInProgress
                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.2
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: configPage.validatorTestStatusType
            text: configPage.validatorTestStatusMessage
            visible: configPage.validatorTestStatusMessage.length > 0 && !configPage.validatorTestInProgress
            showCloseButton: true
            onVisibleChanged: {
                if (!visible) configPage.validatorTestStatusMessage = "";
            }
        }
    }
}
