/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtCore
import org.kde.kirigami as Kirigami

BaseConfigPage {
    id: configPage

    property var skillsList: []
    property var disabledList: []
    property var extraDirs: []
    property bool addDirVisible: false

    // Matches the applet's primary scan root (GenericDataLocation honors
    // XDG_DATA_HOME on Linux).
    readonly property url skillsDirUrl: {
        var p = StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/plasmallm/skills";
        return "file://" + p;
    }

    Component.onCompleted: {
        _parseCache();
        _parseDisabled();
        _parseExtraDirs();
    }

    // The applet rewrites skillsCache after every scan; pick up external
    // updates while this dialog is open.
    onCfg_skillsCacheChanged: _parseCache()
    onCfg_skillsDisabledListChanged: _parseDisabled()

    function _parseCache() {
        if (cfg_skillsCache && cfg_skillsCache.length > 0) {
            try { skillsList = JSON.parse(cfg_skillsCache); } catch (e) { skillsList = []; }
        } else {
            skillsList = [];
        }
    }

    function _parseDisabled() {
        if (cfg_skillsDisabledList && cfg_skillsDisabledList.length > 0) {
            try {
                var parsed = JSON.parse(cfg_skillsDisabledList);
                disabledList = Array.isArray(parsed) ? parsed : [];
                return;
            } catch (e) {}
        }
        disabledList = [];
    }

    function _parseExtraDirs() {
        if (cfg_skillsExtraDirs && cfg_skillsExtraDirs.length > 0) {
            try {
                var parsed = JSON.parse(cfg_skillsExtraDirs);
                extraDirs = Array.isArray(parsed) ? parsed : [];
                return;
            } catch (e) {}
        }
        extraDirs = [];
    }

    function _isDisabled(name) {
        return disabledList.indexOf(name) !== -1;
    }

    function _setDisabled(name, disabled) {
        var arr = disabledList.slice();
        var idx = arr.indexOf(name);
        if (disabled && idx === -1) arr.push(name);
        if (!disabled && idx !== -1) arr.splice(idx, 1);
        disabledList = arr;
        cfg_skillsDisabledList = JSON.stringify(arr);
        rootItem.triggerCapture();
    }

    function _saveExtraDirs() {
        cfg_skillsExtraDirs = JSON.stringify(extraDirs);
        rootItem.triggerCapture();
    }

    Kirigami.FormLayout {
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                text: i18n("Enable skills")
                checked: cfg_skillsEnabled
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_skillsEnabled = checked;
                        rootItem.triggerCapture();
                    }
                }
            }

            QQC2.Label {
                text: i18n("Skills are reusable instruction sets the model loads on demand via the skill tool. Add them to ~/.local/share/plasmallm/skills/ as either a folder per skill containing a SKILL.md file, or a single self-contained <name>.md file.")
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.preferredWidth: 300
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            QQC2.Label {
                text: i18n("No skills discovered yet. Add a SKILL.md folder to the directory above or enable the extra directories below.")
                visible: skillsList.length === 0
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Repeater {
                model: skillsList.length

                delegate: RowLayout {
                    readonly property var skill: skillsList[index]
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Switch {
                        visible: skill.valid
                        checked: skill.valid && !configPage._isDisabled(skill.name)
                        onToggled: configPage._setDisabled(skill.name, !checked)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            QQC2.Label {
                                text: skill.valid ? skill.name : skill.dirName
                                font.bold: true
                                color: skill.valid ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                            }
                            QQC2.Label {
                                text: skill.source
                                color: Kirigami.Theme.disabledTextColor
                                font: Kirigami.Theme.smallFont
                            }
                            QQC2.Label {
                                visible: configPage._isDisabled(skill.name)
                                text: i18n("DISABLED")
                                color: Kirigami.Theme.negativeTextColor
                                font: Kirigami.Theme.smallFont
                            }
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: skill.valid ? skill.description : skill.error
                            color: skill.valid ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.negativeTextColor
                            font: Kirigami.Theme.smallFont
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: i18n("Refresh")
                    icon.name: "view-refresh"
                    onClicked: {
                        cfg_skillsRescan = cfg_skillsRescan + 1;
                        rootItem.triggerCapture();
                    }
                }

                QQC2.Button {
                    text: i18n("Open Folder")
                    icon.name: "folder-open"
                    onClicked: Qt.openUrlExternally(configPage.skillsDirUrl)
                    QQC2.ToolTip.text: i18n("Open the skills directory in the file manager")
                    QQC2.ToolTip.delay: 500
                    QQC2.ToolTip.visible: hovered
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            QQC2.CheckBox {
                text: i18n("Also scan ~/.claude/skills")
                checked: cfg_skillsScanClaude
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_skillsScanClaude = checked;
                        rootItem.triggerCapture();
                    }
                }
            }

            QQC2.CheckBox {
                text: i18n("Also scan ~/.agents/skills")
                checked: cfg_skillsScanAgents
                onCheckedChanged: {
                    if (_initialized) {
                        cfg_skillsScanAgents = checked;
                        rootItem.triggerCapture();
                    }
                }
            }

            Repeater {
                model: extraDirs.length

                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: extraDirs[index]
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }

                    QQC2.ToolButton {
                        icon.name: "edit-delete"
                        onClicked: {
                            var arr = configPage.extraDirs.slice();
                            arr.splice(index, 1);
                            configPage.extraDirs = arr;
                            configPage._saveExtraDirs();
                        }
                    }
                }
            }

            ColumnLayout {
                visible: addDirVisible
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: dirField
                    Layout.fillWidth: true
                    placeholderText: i18n("/absolute/path/to/skills")
                }

                RowLayout {
                    QQC2.Button {
                        text: i18n("Save directory")
                        icon.name: "dialog-ok-apply"
                        enabled: dirField.text.trim().length > 0 && dirField.text.trim().indexOf("/") === 0
                        onClicked: {
                            var arr = configPage.extraDirs.slice();
                            arr.push(dirField.text.trim());
                            configPage.extraDirs = arr;
                            configPage._saveExtraDirs();
                            dirField.text = "";
                            addDirVisible = false;
                        }
                    }
                    QQC2.Button {
                        text: i18n("Cancel")
                        icon.name: "dialog-cancel"
                        onClicked: {
                            dirField.text = "";
                            addDirVisible = false;
                        }
                    }
                }
            }

            QQC2.Button {
                text: addDirVisible ? i18n("Cancel") : i18n("Add directory")
                icon.name: addDirVisible ? "dialog-cancel" : "list-add"
                onClicked: addDirVisible = !addDirVisible
            }
        }

        QQC2.Label {
            text: i18n("Enabled skills are advertised to the model by name and description; the model loads full instructions on demand with the skill tool. Loaded skill content is re-sent in full every turn and is never affected by context compaction. Toggles here are global (not per-profile).")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.preferredWidth: 300
        }
    }
}
