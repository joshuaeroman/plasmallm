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
    // Command validation status: "", "running", "passed", "failed", "error".
    property string validationState: ""
    property string validationReason: ""
    property string validationModel: ""
    property string validationConfidence: ""
    
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
                console.error("PlasmaLLM: ToolApprovalCard parse error: " + e + " for string: " + toolArgsJson);
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

        RowLayout {
            Layout.fillWidth: true
            visible: root.validationState !== ""
            spacing: Kirigami.Units.smallSpacing

            QQC2.BusyIndicator {
                running: root.validationState === "running"
                visible: running
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            Kirigami.Icon {
                visible: root.validationState !== "running"
                source: root.validationState === "passed" ? "dialog-ok-apply"
                       : root.validationState === "failed" ? "dialog-cancel"
                       : "data-warning"
                color: root.validationState === "passed" ? Kirigami.Theme.positiveTextColor
                       : root.validationState === "failed" ? Kirigami.Theme.negativeTextColor
                       : Kirigami.Theme.neutralTextColor
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                color: root.validationState === "passed" ? Kirigami.Theme.positiveTextColor
                       : root.validationState === "failed" ? Kirigami.Theme.negativeTextColor
                       : root.validationState === "error" ? Kirigami.Theme.neutralTextColor
                       : Kirigami.Theme.disabledTextColor
                text: {
                    if (root.validationState === "running")
                        return i18n("Validating command against its justification…");
                    if (root.validationState === "passed") {
                        var by = root.validationModel ? i18n(" (by %1)", root.validationModel) : "";
                        var conf = root.validationConfidence !== "" ? i18n(" confidence %1", root.validationConfidence) : "";
                        return i18n("Validated: matches justification%1%2", by, conf);
                    }
                    if (root.validationState === "failed")
                        return root.validationReason !== "" ? root.validationReason : i18n("Command does not match its justification.");
                    if (root.validationState === "error")
                        return root.validationReason;
                    return "";
                }
            }
        }

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
                enabled: root.validationState !== "running"
                onClicked: {
                    root.approved(toolName, root.args, root.tool_call_id);
                }
            }
        }
    }
}
