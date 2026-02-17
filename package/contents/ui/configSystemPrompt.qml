/*
    SPDX-FileCopyrightText: 2024 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils

import "api.js" as Api

SimpleKCM {
    id: configPage

    // Declared here because Plasma injects all cfg_ properties onto every config page
    property string cfg_apiEndpoint
    property string cfg_apiEndpointDefault
    property string cfg_providerName
    property string cfg_providerNameDefault
    property string cfg_modelName
    property string cfg_modelNameDefault
    property string cfg_apiKey
    property string cfg_apiKeyDefault
    property int cfg_temperature
    property int cfg_temperatureDefault
    property int cfg_maxTokens
    property int cfg_maxTokensDefault
    property int cfg_chatSpacing
    property int cfg_chatSpacingDefault
    property bool cfg_saveChatHistory
    property bool cfg_saveChatHistoryDefault
    property bool cfg_autoShareCommandOutput
    property bool cfg_autoShareCommandOutputDefault
    property bool cfg_autoRunCommands
    property bool cfg_autoRunCommandsDefault
    property bool cfg_showProviderInTitle
    property bool cfg_showProviderInTitleDefault
    property bool cfg_sysInfoOS
    property bool cfg_sysInfoOSDefault
    property bool cfg_sysInfoShell
    property bool cfg_sysInfoShellDefault
    property bool cfg_sysInfoHostname
    property bool cfg_sysInfoHostnameDefault
    property bool cfg_sysInfoKernel
    property bool cfg_sysInfoKernelDefault
    property bool cfg_sysInfoDesktop
    property bool cfg_sysInfoDesktopDefault
    property bool cfg_sysInfoUser
    property bool cfg_sysInfoUserDefault
    property bool cfg_sysInfoCPU
    property bool cfg_sysInfoCPUDefault
    property bool cfg_sysInfoMemory
    property bool cfg_sysInfoMemoryDefault
    property bool cfg_sysInfoGPU
    property bool cfg_sysInfoGPUDefault
    property bool cfg_sysInfoDisk
    property bool cfg_sysInfoDiskDefault
    property bool cfg_sysInfoNetwork
    property bool cfg_sysInfoNetworkDefault
    property bool cfg_sysInfoLocale
    property bool cfg_sysInfoLocaleDefault
    property string cfg_customSystemPrompt
    property string cfg_customSystemPromptDefault
    property string cfg_gatheredSysInfo
    property string cfg_gatheredSysInfoDefault
    property int cfg_apiKeyVersion
    property int cfg_apiKeyVersionDefault

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
        return Api.buildSystemPrompt(info, cfg_customSystemPrompt, { autoRunCommands: cfg_autoRunCommands });
    }

    property string promptPreview: buildPreview()

    Kirigami.FormLayout {
        anchors.fill: parent

        GridLayout {
            Kirigami.FormData.label: "System Info:"
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: 0

            QQC2.CheckBox {
                text: "OS"
                checked: cfg_sysInfoOS
                onCheckedChanged: cfg_sysInfoOS = checked
            }
            QQC2.CheckBox {
                text: "Shell"
                checked: cfg_sysInfoShell
                onCheckedChanged: cfg_sysInfoShell = checked
            }
            QQC2.CheckBox {
                text: "Hostname"
                checked: cfg_sysInfoHostname
                onCheckedChanged: cfg_sysInfoHostname = checked
            }
            QQC2.CheckBox {
                text: "Kernel"
                checked: cfg_sysInfoKernel
                onCheckedChanged: cfg_sysInfoKernel = checked
            }
            QQC2.CheckBox {
                text: "Desktop"
                checked: cfg_sysInfoDesktop
                onCheckedChanged: cfg_sysInfoDesktop = checked
            }
            QQC2.CheckBox {
                text: "User"
                checked: cfg_sysInfoUser
                onCheckedChanged: cfg_sysInfoUser = checked
            }
            QQC2.CheckBox {
                text: "CPU"
                checked: cfg_sysInfoCPU
                onCheckedChanged: cfg_sysInfoCPU = checked
            }
            QQC2.CheckBox {
                text: "Memory"
                checked: cfg_sysInfoMemory
                onCheckedChanged: cfg_sysInfoMemory = checked
            }
            QQC2.CheckBox {
                text: "GPU"
                checked: cfg_sysInfoGPU
                onCheckedChanged: cfg_sysInfoGPU = checked
            }
            QQC2.CheckBox {
                text: "Block Devices"
                checked: cfg_sysInfoDisk
                onCheckedChanged: cfg_sysInfoDisk = checked
            }
            QQC2.CheckBox {
                text: "Network"
                checked: cfg_sysInfoNetwork
                onCheckedChanged: cfg_sysInfoNetwork = checked
            }
            QQC2.CheckBox {
                text: "Locale"
                checked: cfg_sysInfoLocale
                onCheckedChanged: cfg_sysInfoLocale = checked
            }
        }

        QQC2.TextArea {
            id: customPromptArea
            Kirigami.FormData.label: "Custom Instructions:"
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 6
            placeholderText: "Additional instructions for the LLM..."
            wrapMode: Text.Wrap
            text: cfg_customSystemPrompt
            onTextChanged: cfg_customSystemPrompt = text
        }

        QQC2.TextArea {
            Kirigami.FormData.label: "Preview:"
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
