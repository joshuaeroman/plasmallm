/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

import "toolManager.js" as ToolManager

Kirigami.Card {
    id: root
    
    property string toolName: ""
    property string tool_call_id: ""
    property var toolArgsJson: ({})
    property var appConfig: ({})
    
    signal approved(string name, var args, string callId)
    signal denied(string name, string callId)

    readonly property var args: {
        if (!toolArgsJson) return {};
        if (typeof toolArgsJson === "object") return toolArgsJson;
        if (typeof toolArgsJson === "string" && toolArgsJson.length > 0) {
            try {
                var parsed = JSON.parse(toolArgsJson);
                return parsed;
            } catch(e) {
                console.error("PlasmaLLM DEBUG: ToolApprovalCard.qml parse error: " + e + " for string: " + toolArgsJson);
                return {};
            }
        }
        return {};
    }

    readonly property string displayName: {
        var meta = ToolManager.getToolMetadata(toolName, appConfig);
        return meta && meta.displayName ? meta.displayName : toolName;
    }

    banner.title: i18n("Tool Request: %1", displayName)
    
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        
        QQC2.Label {
            text: root.args.justification ? i18n("Justification: %1", root.args.justification) : ""
            visible: text !== ""
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // Argument preview
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            
            Repeater {
                model: Object.keys(root.args).filter(function(key) { return key !== 'justification'; })
                delegate: RowLayout {
                    Layout.fillWidth: true
                    QQC2.Label {
                        text: modelData + ":"
                        font.bold: true
                        Layout.alignment: Qt.AlignTop
                    }
                    QQC2.Label {
                        text: {
                            var val = root.args[modelData];
                            if (typeof val === "object") return JSON.stringify(val);
                            return String(val);
                        }
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Deny")
                icon.name: "dialog-cancel"
                onClicked: {
                    root.denied(toolName, root.tool_call_id);
                }
            }

            QQC2.Button {
                text: i18n("Approve")
                icon.name: "dialog-ok-apply"
                font.bold: true
                highlighted: true
                onClicked: {
                    root.approved(toolName, root.args, root.tool_call_id);
                }
            }
        }
    }
}
