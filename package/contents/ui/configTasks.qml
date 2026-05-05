/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils

BaseConfigPage {
    id: configPage

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
                            taskAutoSubmitCheck.checked = tasksList[index].hasOwnProperty("autoSubmit") ? tasksList[index].autoSubmit : true;
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
                        taskAutoSubmitCheck.checked = true;
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

                QQC2.CheckBox {
                    id: taskAutoSubmitCheck
                    text: i18n("Auto-submit task prompt to chat")
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
                        var entry = { name: name, prompt: taskPromptField.text.trim(), auto: taskAutoCheck.checked, autoSubmit: taskAutoSubmitCheck.checked };
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
