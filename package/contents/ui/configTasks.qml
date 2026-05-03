/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils

SimpleKCM {
    id: configPage

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
    property string cfg_customSystemPrompt
    property string cfg_customSystemPromptDefault
    property string cfg_gatheredSysInfo
    property string cfg_gatheredSysInfoDefault
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
    property int cfg_apiKeyVersion
    property int cfg_apiKeyVersionDefault
    property int cfg_autoClearMode
    property int cfg_autoClearModeDefault
    property int cfg_autoClearSeconds
    property int cfg_autoClearSecondsDefault
    property int cfg_autoClearMinutes
    property int cfg_autoClearMinutesDefault
    property string cfg_lastClosedTimestamp
    property string cfg_lastClosedTimestampDefault
    property string cfg_availableModels
    property string cfg_availableModelsDefault
    property bool cfg_enableWebSearch
    property bool cfg_enableWebSearchDefault
    property string cfg_webSearchProvider
    property string cfg_webSearchProviderDefault
    property string cfg_searxngUrl
    property string cfg_searxngUrlDefault
    property string cfg_searxngApiKey
    property string cfg_searxngApiKeyDefault
    property int cfg_searxngApiKeyVersion
    property int cfg_searxngApiKeyVersionDefault
    property string cfg_ollamaSearchApiKey
    property string cfg_ollamaSearchApiKeyDefault
    property int cfg_ollamaSearchApiKeyVersion
    property int cfg_ollamaSearchApiKeyVersionDefault
    property string cfg_tasks
    property string cfg_tasksDefault

    property bool cfg_useSessionMultiplexer
    property bool cfg_useSessionMultiplexerDefault
    property string cfg_sessionMultiplexer
    property string cfg_sessionMultiplexerDefault
    property string cfg_sessionName
    property string cfg_sessionNameDefault

    property bool cfg_sysInfoDateTime
    property bool cfg_sysInfoDateTimeDefault

    property var tasksList: []
    property bool taskEditorVisible: false
    property int taskEditIndex: -1

    Component.onCompleted: {
        if (cfg_tasks && cfg_tasks.length > 0) {
            try { tasksList = JSON.parse(cfg_tasks); } catch(e) { tasksList = []; }
        }
    }

    Kirigami.FormLayout {
        anchors.fill: parent

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: i18n("No tasks configured. Add a task to create reusable prompt shortcuts.")
                visible: tasksList.length === 0
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Repeater {
                model: tasksList.length
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: tasksList[index].name
                        font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: tasksList[index].prompt.length > 40 ? tasksList[index].prompt.substring(0, 40) + "…" : tasksList[index].prompt
                        elide: Text.ElideRight
                        color: Kirigami.Theme.disabledTextColor
                    }
                    QQC2.Label {
                        visible: tasksList[index].auto
                        text: i18n("AUTO")
                        color: Kirigami.Theme.negativeTextColor
                        font: Kirigami.Theme.smallFont
                    }
                    QQC2.ToolButton {
                        icon.name: "edit-entry"
                        onClicked: {
                            taskEditIndex = index;
                            taskNameField.text = tasksList[index].name;
                            taskPromptField.text = tasksList[index].prompt;
                            taskAutoCheck.checked = tasksList[index].auto;
                            taskEditorVisible = true;
                        }
                    }
                    QQC2.ToolButton {
                        icon.name: "edit-delete"
                        onClicked: {
                            var arr = tasksList.slice();
                            arr.splice(index, 1);
                            tasksList = arr;
                            cfg_tasks = JSON.stringify(tasksList);
                        }
                    }
                }
            }

            QQC2.Button {
                text: taskEditorVisible ? i18n("Cancel") : i18n("Add Task")
                icon.name: taskEditorVisible ? "dialog-cancel" : "list-add"
                onClicked: {
                    if (taskEditorVisible) {
                        taskEditorVisible = false;
                        taskEditIndex = -1;
                    } else {
                        taskEditIndex = -1;
                        taskNameField.text = "";
                        taskPromptField.text = "";
                        taskAutoCheck.checked = false;
                        taskEditorVisible = true;
                    }
                }
            }

            ColumnLayout {
                visible: taskEditorVisible
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: taskNameField
                    Layout.fillWidth: true
                    placeholderText: i18n("Task name")
                }

                QQC2.TextArea {
                    id: taskPromptField
                    Layout.fillWidth: true
                    Layout.minimumHeight: Kirigami.Units.gridUnit * 3
                    placeholderText: i18n("Prompt to send")
                    wrapMode: Text.Wrap
                }

                QQC2.CheckBox {
                    id: taskAutoCheck
                    text: i18n("Enable auto mode (auto-run + auto-share)")
                }

                QQC2.Label {
                    id: taskErrorLabel
                    visible: false
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                QQC2.Button {
                    text: taskEditIndex >= 0 ? i18n("Update Task") : i18n("Save Task")
                    icon.name: "dialog-ok-apply"
                    enabled: taskNameField.text.trim().length > 0 && taskPromptField.text.trim().length > 0
                    onClicked: {
                        var name = taskNameField.text.trim();
                        var arr = tasksList.slice();
                        for (var i = 0; i < arr.length; i++) {
                            if (i !== taskEditIndex && arr[i].name.toLowerCase() === name.toLowerCase()) {
                                taskErrorLabel.text = i18n("A task named \"%1\" already exists.", arr[i].name);
                                taskErrorLabel.visible = true;
                                return;
                            }
                        }
                        taskErrorLabel.visible = false;
                        var entry = { name: name, prompt: taskPromptField.text.trim(), auto: taskAutoCheck.checked };
                        if (taskEditIndex >= 0) {
                            arr[taskEditIndex] = entry;
                        } else {
                            arr.push(entry);
                        }
                        tasksList = arr;
                        cfg_tasks = JSON.stringify(tasksList);
                        taskEditorVisible = false;
                        taskEditIndex = -1;
                    }
                }
            }
        }

        QQC2.Label {
            text: i18n("Tasks are reusable prompt shortcuts. Use /task <name> in chat or the toolbar button to run them. Tasks with auto mode will temporarily enable auto-run and auto-share.")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.preferredWidth: 300
        }
    }
}
