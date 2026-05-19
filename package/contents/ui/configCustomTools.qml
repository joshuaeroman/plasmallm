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

    property var customToolsList: []
    property bool toolEditorVisible: false
    property int toolEditIndex: -1

    Component.onCompleted: {
        if (cfg_customTools && cfg_customTools.length > 0) {
            try { customToolsList = JSON.parse(cfg_customTools); } catch(e) { customToolsList = []; }
        }
    }

    Kirigami.FormLayout {
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: i18n("No custom tools configured. Add a custom tool to expose your own commands to the LLM.")
                visible: customToolsList.length === 0
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Repeater {
                model: customToolsList.length
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: customToolsList[index].name
                        font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: customToolsList[index].description
                        elide: Text.ElideRight
                        color: Kirigami.Theme.disabledTextColor
                    }
                    QQC2.Label {
                        visible: customToolsList[index].autoRun
                        text: i18n("AUTO")
                        color: Kirigami.Theme.negativeTextColor
                        font: Kirigami.Theme.smallFont
                    }
                    QQC2.ToolButton {
                        icon.name: "edit-entry"
                        onClicked: {
                            toolEditIndex = index;
                            toolNameField.text = customToolsList[index].name;
                            toolDescField.text = customToolsList[index].description;
                            toolCmdField.text = customToolsList[index].commandTemplate;
                            toolRootCheck.checked = customToolsList[index].requireSuperuser;
                            toolAutoCheck.checked = customToolsList[index].autoRun;
                            toolEditorVisible = true;
                        }
                    }
                    QQC2.ToolButton {
                        icon.name: "edit-delete"
                        onClicked: {
                            var arr = customToolsList.slice();
                            arr.splice(index, 1);
                            customToolsList = arr;
                            cfg_customTools = JSON.stringify(customToolsList);
                            rootItem.triggerCapture();
                        }
                    }
                }
            }

            QQC2.Button {
                text: toolEditorVisible ? i18n("Cancel") : i18n("Add Custom Tool")
                icon.name: toolEditorVisible ? "dialog-cancel" : "list-add"
                onClicked: {
                    if (toolEditorVisible) {
                        toolEditorVisible = false;
                        toolEditIndex = -1;
                    } else {
                        toolEditIndex = -1;
                        toolNameField.text = "echo";
                        toolDescField.text = i18n("Echoes back the message provided.");
                        toolCmdField.text = "echo {message}";
                        toolRootCheck.checked = false;
                        toolAutoCheck.checked = false;
                        toolEditorVisible = true;
                    }
                }
            }

            ColumnLayout {
                visible: toolEditorVisible
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: toolNameField
                    Layout.fillWidth: true
                    placeholderText: i18n("Tool name (e.g. systemctl_service)")
                    validator: RegularExpressionValidator { regularExpression: /^[a-zA-Z0-9_-]+$/ }
                }

                QQC2.TextField {
                    id: toolDescField
                    Layout.fillWidth: true
                    placeholderText: i18n("Description (instructs the LLM what this tool does)")
                }

                QQC2.TextArea {
                    id: toolCmdField
                    Layout.fillWidth: true
                    Layout.minimumHeight: Kirigami.Units.gridUnit * 3
                    placeholderText: i18n("Command template (e.g. systemctl {action} {service})")
                    wrapMode: Text.Wrap
                }

                QQC2.CheckBox {
                    id: toolRootCheck
                    text: i18n("Require Superuser (runs with pkexec)")
                }

                QQC2.CheckBox {
                    id: toolAutoCheck
                    text: i18n("Auto-run tool (no confirmation dialog)")
                }

                QQC2.Label {
                    id: toolErrorLabel
                    visible: false
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                QQC2.Button {
                    text: toolEditIndex >= 0 ? i18n("Update Tool") : i18n("Save Tool")
                    icon.name: "dialog-ok-apply"
                    enabled: toolNameField.text.trim().length > 0 && toolCmdField.text.trim().length > 0 && toolDescField.text.trim().length > 0
                    onClicked: {
                        var name = toolNameField.text.trim();
                        var arr = customToolsList.slice();
                        for (var i = 0; i < arr.length; i++) {
                            if (i !== toolEditIndex && arr[i].name.toLowerCase() === name.toLowerCase()) {
                                toolErrorLabel.text = i18n("A tool named \"%1\" already exists.", arr[i].name);
                                toolErrorLabel.visible = true;
                                return;
                            }
                        }
                        toolErrorLabel.visible = false;
                        var entry = {
                            name: name,
                            description: toolDescField.text.trim(),
                            commandTemplate: toolCmdField.text.trim(),
                            requireSuperuser: toolRootCheck.checked,
                            autoRun: toolAutoCheck.checked
                        };
                        if (toolEditIndex >= 0) {
                            arr[toolEditIndex] = entry;
                        } else {
                            arr.push(entry);
                        }
                        customToolsList = arr;
                        cfg_customTools = JSON.stringify(customToolsList);
                        rootItem.triggerCapture();
                        toolEditorVisible = false;
                        toolEditIndex = -1;
                    }
                }
            }
        }

        QQC2.Label {
            text: i18n("Custom tools allow you to expose your own commands to the LLM. Use placeholders like {variable} in the Command Template to define parameters the LLM can fill. Values provided by the LLM are automatically shell-escaped.")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.preferredWidth: 300
            Layout.topMargin: Kirigami.Units.largeSpacing
        }
    }
}
