/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils

import "api.js" as Api

BaseConfigPage {
    id: configPage

    function buildToolsConfig() {
        return {
            i18n: i18n,
            sessionAutoMode: false,
            sessionFullAutoMode: false,
            enableTools: cfg_enableTools,
            enableWebSearch: cfg_enableWebSearch,
            enableDesktopAutomation: cfg_enableDesktopAutomation,
            searchConfigured: false,
            useCommandTool: cfg_useCommandTool,
            autoRunCommands: cfg_autoRunCommands,
            toolsReadFileEnabled: cfg_toolsReadFileEnabled,
            toolsReadFileAutoRun: cfg_toolsReadFileAutoRun,
            toolsWriteFileEnabled: cfg_toolsWriteFileEnabled,
            toolsWriteFileAutoRun: cfg_toolsWriteFileAutoRun,
            toolsListDirEnabled: cfg_toolsListDirEnabled,
            toolsListDirAutoRun: cfg_toolsListDirAutoRun,
            toolsHttpGetEnabled: cfg_toolsHttpGetEnabled,
            toolsHttpGetAutoRun: cfg_toolsHttpGetAutoRun,
            toolsHttpRequestEnabled: cfg_toolsHttpRequestEnabled,
            toolsHttpRequestAutoRun: cfg_toolsHttpRequestAutoRun,
            toolsSearchFilesEnabled: cfg_toolsSearchFilesEnabled,
            toolsSearchFilesAutoRun: cfg_toolsSearchFilesAutoRun,
            toolsGetClipboardEnabled: cfg_toolsGetClipboardEnabled,
            toolsGetClipboardAutoRun: cfg_toolsGetClipboardAutoRun,
            toolsSetClipboardEnabled: cfg_toolsSetClipboardEnabled,
            toolsSetClipboardAutoRun: cfg_toolsSetClipboardAutoRun,
            toolsNotifyEnabled: cfg_toolsNotifyEnabled,
            toolsNotifyAutoRun: cfg_toolsNotifyAutoRun,
            toolsOpenUrlEnabled: cfg_toolsOpenUrlEnabled,
            toolsOpenUrlAutoRun: cfg_toolsOpenUrlAutoRun,
            toolsPathWhitelist: cfg_toolsPathWhitelist,
            toolsReadMaxBytes: cfg_toolsReadMaxBytes,
            toolsWriteMaxBytes: cfg_toolsWriteMaxBytes,
            toolsHttpMaxBytes: cfg_toolsHttpMaxBytes,
            toolsInstructions: cfg_toolsInstructions,
            localizeSystemPrompt: cfg_localizeSystemPrompt,
            customTools: cfg_customTools
        };
    }

    function buildPreview() {
        var real = {};
        try { if (cfg_gatheredSysInfo) real = JSON.parse(cfg_gatheredSysInfo); } catch(e) {}
        var info = {};
        if (cfg_sysInfoOS)       info.osRelease  = real.osRelease  || "<OS name>";
        if (cfg_sysInfoShell)    info.shell       = real.shell      || "<shell>";
        if (cfg_sysInfoHostname) info.hostname    = real.hostname   || "<hostname>";
        if (cfg_sysInfoKernel)   info.kernel      = real.kernel     || "<kernel>";
        if (cfg_sysInfoDesktop)  info.desktop     = real.desktop    || "<desktop>";
        if (cfg_sysInfoUser)     info.user        = real.user       || "<username>";
        if (cfg_sysInfoCPU) {
            info.cpu      = real.cpu      || "<CPU model>";
            info.cpuCores = real.cpuCores || "<cores>";
            info.cpuArch  = real.cpuArch  || "<arch>";
        }
        if (cfg_sysInfoMemory)   info.memory  = real.memory  || "<memory>";
        if (cfg_sysInfoGPU)      info.gpu     = real.gpu     || "<GPU name>";
        if (cfg_sysInfoDisk)     info.disk    = real.disk    || "<lsblk output>";
        if (cfg_sysInfoNetwork)  info.network = real.network || "<network>";
        if (cfg_sysInfoLocale)   info.locale  = real.locale  || "<locale>";
        return Api.buildSystemPrompt(info, cfg_systemPrompt, {
            i18n: i18n,
            sysInfoDateTime: cfg_sysInfoDateTime,
            autoRunCommands: cfg_autoRunCommands,
            autoMode: false,
            commandToolEnabled: cfg_useCommandTool,
            sessionMultiplexer: cfg_useSessionMultiplexer ? (cfg_sessionMultiplexer + ": " + cfg_sessionName) : "",
            localizeSystemPrompt: cfg_localizeSystemPrompt,
            toolsConfig: buildToolsConfig()
        });
    }

    property string promptPreview: buildPreview()

    Kirigami.FormLayout {
        GridLayout {
            Kirigami.FormData.label: i18n("System Info:")
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: 0

            QQC2.CheckBox {
                text: i18n("OS")
                checked: cfg_sysInfoOS
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoOS = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("Shell")
                checked: cfg_sysInfoShell
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoShell = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("Hostname")
                checked: cfg_sysInfoHostname
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoHostname = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("Kernel")
                checked: cfg_sysInfoKernel
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoKernel = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("Desktop")
                checked: cfg_sysInfoDesktop
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoDesktop = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("User")
                checked: cfg_sysInfoUser
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoUser = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("CPU")
                checked: cfg_sysInfoCPU
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoCPU = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("Memory")
                checked: cfg_sysInfoMemory
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoMemory = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("GPU")
                checked: cfg_sysInfoGPU
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoGPU = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("Block Devices")
                checked: cfg_sysInfoDisk
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoDisk = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("Network")
                checked: cfg_sysInfoNetwork
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoNetwork = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("Locale")
                checked: cfg_sysInfoLocale
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoLocale = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
            QQC2.CheckBox {
                text: i18n("Date/Time")
                checked: cfg_sysInfoDateTime
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_sysInfoDateTime = checked;
                        rootItem.triggerCapture();
                    }
                }
            }
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Template:")
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 32
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: i18n("This is the full system prompt sent to the model. Use {{placeholders}} to pull in dynamic content like system details, enabled tools, or desktop automation instructions. Anything else you write is used verbatim. Critical runtime instructions (driving, skip-approvals mode) are appended automatically when active, even if you remove their placeholder.")
            wrapMode: Text.Wrap
        }

        QQC2.TextArea {
            id: systemPromptArea
            Kirigami.FormData.label: i18n("System Prompt:")
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 32
            Layout.minimumHeight: Kirigami.Units.gridUnit * 12
            placeholderText: i18n("Write your system prompt here…")
            wrapMode: Text.Wrap
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: cfg_systemPrompt
            onTextChanged: {
                if (_initialized) {
                    cfg_systemPrompt = text;
                    rootItem.triggerCapture();
                }
            }
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Placeholders:")
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 32
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: [
                    { tag: "{{system_info}}", desc: i18n("Enabled system info selected in the checklist above") },
                    { tag: "{{tools}}", desc: i18n("Enabled tool descriptions and guidelines from the Tools menu") },
                    { tag: "{{session_multiplexer}}", desc: i18n("Persistent tmux or screen session multiplexer instructions (when active)") },
                    { tag: "{{approval_mode}}", desc: i18n("Notice indicating skip-approvals mode (/auto) is active") },
                    { tag: "{{driving_instructions}}", desc: i18n("Desktop automation coordinates and guidelines (when driving)") }
                ]

                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.Button {
                        text: modelData.tag
                        icon.name: "list-add"
                        onClicked: systemPromptArea.insert(systemPromptArea.cursorPosition, modelData.tag)
                    }

                    QQC2.Label {
                        text: modelData.desc
                        color: Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                    }
                }
            }
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Localization:")
            visible: !Qt.locale().name.toLowerCase().startsWith("en")
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 32
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                text: i18n("Localize System Prompt")
                checked: cfg_localizeSystemPrompt
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_localizeSystemPrompt = checked;
                        rootItem.triggerCapture();
                    }
                }
                QQC2.ToolTip.text: i18n("Translate default prompt templates and dynamic system sections into your desktop language.")
            }

            QQC2.Label {
                text: i18n("Note: Localizing system instructions and tools into non-English languages may reduce tool-calling reliability and instruction-following accuracy on some models.")
                visible: cfg_localizeSystemPrompt
                color: Kirigami.Theme.neutralTextColor
                font: Kirigami.Theme.smallFont
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.preferredWidth: 1
            }
        }

        QQC2.Button {
            Kirigami.FormData.label: i18n("Actions:")
            text: i18n("Reset to Default Template")
            icon.name: "edit-undo"
            onClicked: {
                if (_initialized) {
                    var defTpl = cfg_localizeSystemPrompt ? Api.getLocalizedDefaultSystemPromptTemplate(i18n) : Api.DEFAULT_SYSTEM_PROMPT_TEMPLATE;
                    cfg_systemPrompt = defTpl;
                    systemPromptArea.text = cfg_systemPrompt;
                    rootItem.triggerCapture();
                }
            }
        }

        QQC2.TextArea {
            Kirigami.FormData.label: i18n("Preview:")
            Layout.fillWidth: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 32
            Layout.minimumHeight: Kirigami.Units.gridUnit * 14
            readOnly: true
            wrapMode: Text.Wrap
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: promptPreview
        }
    }
}
