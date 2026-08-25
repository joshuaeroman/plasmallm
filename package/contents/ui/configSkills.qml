/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "skills.js" as Skills

BaseConfigPage {
    id: configPage

    property var skillsList: []
    property var disabledList: []
    property var scriptAutoRunList: []
    property var extraDirs: []
    property bool addDirVisible: false
    property bool refreshing: false

    // Matches the applet's primary scan root (GenericDataLocation honors
    // XDG_DATA_HOME on Linux). Strip file:// — QML StandardPaths may return a URL.
    readonly property string skillsDirPath: Skills.toLocalPath(
        StandardPaths.writableLocation(StandardPaths.GenericDataLocation)
    ) + "/plasmallm/skills"

    property string scanStdout: ""

    Component.onCompleted: {
        _parseCache();
        _parseDisabled();
        _parseScriptAutoRun();
        _parseExtraDirs();
    }

    // The applet rewrites skillsCache after every scan; pick up external
    // updates while this dialog is open.
    onCfg_skillsCacheChanged: _parseCache()
    onCfg_skillsDisabledListChanged: _parseDisabled()
    onCfg_skillsScriptsAutoRunChanged: _parseScriptAutoRun()

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

    function _parseScriptAutoRun() {
        if (cfg_skillsScriptsAutoRun && cfg_skillsScriptsAutoRun.length > 0) {
            try {
                var parsed = JSON.parse(cfg_skillsScriptsAutoRun);
                scriptAutoRunList = Array.isArray(parsed) ? parsed : [];
                return;
            } catch (e) {}
        }
        scriptAutoRunList = [];
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

    function _isScriptAutoRun(name) {
        return scriptAutoRunList.indexOf(name) !== -1;
    }

    function _setScriptAutoRun(name, enabled) {
        var arr = scriptAutoRunList.slice();
        var idx = arr.indexOf(name);
        if (enabled && idx === -1) arr.push(name);
        if (!enabled && idx !== -1) arr.splice(idx, 1);
        scriptAutoRunList = arr;
        cfg_skillsScriptsAutoRun = JSON.stringify(arr);
        rootItem.triggerCapture();
    }

    function _hasScripts(skill) {
        return skill && skill.valid && skill.scripts && skill.scripts.length > 0;
    }

    function _saveExtraDirs() {
        cfg_skillsExtraDirs = JSON.stringify(extraDirs);
        rootItem.triggerCapture();
    }

    function _skillsRoots() {
        var home = Skills.toLocalPath(StandardPaths.writableLocation(StandardPaths.HomeLocation));
        var dataHome = Skills.toLocalPath(StandardPaths.writableLocation(StandardPaths.GenericDataLocation));
        var roots = [];
        if (dataHome) roots.push({ dir: dataHome + "/plasmallm/skills", source: "plasmallm" });
        var bundled = Skills.toLocalPath(Qt.resolvedUrl("../skills"));
        if (bundled) roots.push({ dir: bundled, source: "bundled" });
        if (home) {
            if (cfg_skillsScanClaude) roots.push({ dir: home + "/.claude/skills", source: "claude" });
            if (cfg_skillsScanAgents) roots.push({ dir: home + "/.agents/skills", source: "agents" });
        }
        for (var i = 0; i < extraDirs.length; i++) {
            var d = Skills.toLocalPath(extraDirs[i]).trim();
            if (d.length > 0) roots.push({ dir: d, source: "custom" });
        }
        return roots;
    }

    function refreshSkills() {
        var roots = _skillsRoots();
        if (roots.length === 0 || refreshing) return;
        refreshing = true;
        scanStdout = "";
        scanSource.connectSource(Skills.buildScanCommand(roots));
    }

    function openSkillsFolder() {
        var dir = Skills.shellQuotePath(configPage.skillsDirPath);
        openFolderSource.connectSource("mkdir -p " + dir + " && xdg-open " + dir);
    }

    P5Support.DataSource {
        id: scanSource
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            if (data["stdout"]) configPage.scanStdout += data["stdout"];
            if (data["exit code"] === undefined) return;
            var stdout = configPage.scanStdout;
            configPage.scanStdout = "";
            disconnectSource(source);
            configPage.refreshing = false;
            if (!stdout || String(stdout).indexOf("===PLASMALLM_SKILL_END") === -1) {
                console.warn("PlasmaLLM: skill refresh produced no output; keeping previous skill list");
                return;
            }
            var parsed = Skills.parseScanOutput(stdout, configPage._skillsRoots());
            cfg_skillsCache = Skills.toCacheJson(parsed);
            configPage._parseCache();
            cfg_skillsRescan = cfg_skillsRescan + 1;
            rootItem.triggerCapture();
        }
    }

    P5Support.DataSource {
        id: openFolderSource
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source);
        }
    }

    Kirigami.FormLayout {
        width: Math.min(parent.width, Kirigami.Units.gridUnit * 32)
        Layout.maximumWidth: Kirigami.Units.gridUnit * 32

        ColumnLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
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
                text: i18n("Skills are reusable instruction sets the model loads on demand via the skill tool. PlasmaLLM ships built-in skills (source: bundled). Add your own to ~/.local/share/plasmallm/skills/ as a folder containing SKILL.md or a self-contained <name>.md file; a user skill with the same name overrides the bundled one.")
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            QQC2.Label {
                text: i18n("No skills discovered yet. Add a SKILL.md folder to the directory above or enable the extra directories below.")
                visible: skillsList.length === 0
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            }

            Repeater {
                model: skillsList.length

                delegate: RowLayout {
                    readonly property var skill: skillsList[index]
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 28
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Switch {
                        visible: skill.valid
                        checked: skill.valid && !configPage._isDisabled(skill.name)
                        onToggled: configPage._setDisabled(skill.name, !checked)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            QQC2.Label {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                text: skill.valid ? skill.name : skill.dirName
                                font.bold: true
                                elide: Text.ElideRight
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
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        QQC2.CheckBox {
                            visible: configPage._hasScripts(skill)
                            text: i18n("Allow running skill scripts without approval")
                            checked: configPage._isScriptAutoRun(skill.name)
                            onToggled: configPage._setScriptAutoRun(skill.name, checked)
                        }
                    }
                }
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: refreshing ? i18n("Refreshing…") : i18n("Refresh")
                    icon.name: "view-refresh"
                    enabled: !refreshing
                    onClicked: configPage.refreshSkills()
                }

                QQC2.Button {
                    text: i18n("Open Folder")
                    icon.name: "folder-open"
                    onClicked: configPage.openSkillsFolder()
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
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 28
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
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
        }
    }
}
