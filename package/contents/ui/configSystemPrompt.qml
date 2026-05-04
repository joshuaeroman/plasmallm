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
        return Api.buildSystemPrompt(info, cfg_customSystemPrompt, { 
            autoRunCommands: cfg_autoRunCommands, 
            commandToolEnabled: cfg_useCommandTool 
        });    }

    property string promptPreview: buildPreview()

    Kirigami.FormLayout {
        anchors.fill: parent

        GridLayout {
            Kirigami.FormData.label: i18n("System Info:")
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: 0

            QQC2.CheckBox {
                text: i18n("OS")
                checked: cfg_sysInfoOS
                onCheckedChanged: cfg_sysInfoOS = checked
            }
            QQC2.CheckBox {
                text: i18n("Shell")
                checked: cfg_sysInfoShell
                onCheckedChanged: cfg_sysInfoShell = checked
            }
            QQC2.CheckBox {
                text: i18n("Hostname")
                checked: cfg_sysInfoHostname
                onCheckedChanged: cfg_sysInfoHostname = checked
            }
            QQC2.CheckBox {
                text: i18n("Kernel")
                checked: cfg_sysInfoKernel
                onCheckedChanged: cfg_sysInfoKernel = checked
            }
            QQC2.CheckBox {
                text: i18n("Desktop")
                checked: cfg_sysInfoDesktop
                onCheckedChanged: cfg_sysInfoDesktop = checked
            }
            QQC2.CheckBox {
                text: i18n("User")
                checked: cfg_sysInfoUser
                onCheckedChanged: cfg_sysInfoUser = checked
            }
            QQC2.CheckBox {
                text: i18n("CPU")
                checked: cfg_sysInfoCPU
                onCheckedChanged: cfg_sysInfoCPU = checked
            }
            QQC2.CheckBox {
                text: i18n("Memory")
                checked: cfg_sysInfoMemory
                onCheckedChanged: cfg_sysInfoMemory = checked
            }
            QQC2.CheckBox {
                text: i18n("GPU")
                checked: cfg_sysInfoGPU
                onCheckedChanged: cfg_sysInfoGPU = checked
            }
            QQC2.CheckBox {
                text: i18n("Block Devices")
                checked: cfg_sysInfoDisk
                onCheckedChanged: cfg_sysInfoDisk = checked
            }
            QQC2.CheckBox {
                text: i18n("Network")
                checked: cfg_sysInfoNetwork
                onCheckedChanged: cfg_sysInfoNetwork = checked
            }
            QQC2.CheckBox {
                text: i18n("Locale")
                checked: cfg_sysInfoLocale
                onCheckedChanged: cfg_sysInfoLocale = checked
            }
            QQC2.CheckBox {
                text: i18n("Date/Time")
                checked: cfg_sysInfoDateTime
                onCheckedChanged: cfg_sysInfoDateTime = checked
            }
        }

        QQC2.TextArea {
            id: customPromptArea
            Kirigami.FormData.label: i18n("Custom Instructions:")
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 6
            placeholderText: i18n("Additional instructions for the LLM…")
            wrapMode: Text.Wrap
            text: cfg_customSystemPrompt
            onTextChanged: cfg_customSystemPrompt = text
        }

        QQC2.TextArea {
            Kirigami.FormData.label: i18n("Preview:")
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 14
            readOnly: true
            wrapMode: Text.Wrap
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: promptPreview
        }
    }
}
