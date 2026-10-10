/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Settings window for the standalone build. Mirrors what plasmashell's
// AppletConfiguration.qml does for the config pages: every page gets a
// cfg_<key> initial property per config key, edits are tracked through the
// cfg_<key>Changed signals, and Apply copies them back to Plasmoid.configuration.

import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

QQC2.ApplicationWindow {
    id: configWindow

    // Strings come from libplasma / plasmashell catalogs so they are already translated.
    title: i18ndc("libplasma6", "%1 is the name of the applet", "Configure %1...", "PlasmaLLM")
    width: Kirigami.Units.gridUnit * 44
    height: Kirigami.Units.gridUnit * 36
    minimumWidth: Kirigami.Units.gridUnit * 30
    minimumHeight: Kirigami.Units.gridUnit * 20

    property var categories: []
    property int currentIndex: -1
    property bool dirty: false
    property bool configurationChangedSent: false
    // Action to run once the user has answered the unsaved-changes prompt.
    property var pendingAction: null
    property bool closeConfirmed: false

    readonly property Item currentPage: pageStack.currentItem

    Settings {
        location: StandaloneHost.stateFile
        category: "ConfigWindow"
        property alias width: configWindow.width
        property alias height: configWindow.height
    }

    // Built from the package's config/config.qml so the sidebar matches the plasmoid.
    function loadCategories() {
        var component = Qt.createComponent(StandaloneHost.configModel);
        if (component.status !== Component.Ready) {
            console.warn("PlasmaLLM: cannot load config model:", component.errorString());
            return;
        }
        var model = component.createObject(configWindow);
        var list = [];
        for (var i = 0; i < model.categories.length; i++) {
            var c = model.categories[i];
            if (c.visible) list.push({ name: c.name, icon: c.icon, source: c.source });
        }
        categories = list;
    }

    function isConfigurationChanged() {
        var page = currentPage;
        if (!page) return false;
        var config = Plasmoid.configuration;
        return StandaloneHost.configKeys().some(function(key) {
            var cfgKey = "cfg_" + key;
            if (!page.hasOwnProperty(cfgKey)) return false;
            var a = config[key], b = page[cfgKey];
            return a != b && String(a) !== String(b);
        });
    }

    function settingValueChanged() {
        dirty = configurationChangedSent || isConfigurationChanged()
            || (currentPage?.unsavedChanges ?? false);
    }

    function saveConfig() {
        var page = currentPage;
        if (!page) return;
        if (typeof page.saveConfig === "function") {
            page.saveConfig();
        }
        var config = Plasmoid.configuration;
        StandaloneHost.configKeys().forEach(function(key) {
            var cfgKey = "cfg_" + key;
            if (cfgKey in page) {
                config[key] = page[cfgKey];
            }
        });
        StandaloneHost.writeConfig();
        configurationChangedSent = false;
        dirty = false;
    }

    function openCategory(index) {
        if (index < 0 || index >= categories.length) return;
        var category = categories[index];
        var props = { "title": category.name };
        var config = Plasmoid.configuration;
        StandaloneHost.configKeys().forEach(function(key) {
            props["cfg_" + key] = config[key];
        });
        var url = StandaloneHost.uiDir.toString() + category.source;
        pageStack.replace(null, url, props, QQC2.StackView.Immediate);
        currentIndex = index;
        configurationChangedSent = false;
        dirty = false;
        connectPage(pageStack.currentItem);
    }

    function connectPage(page) {
        if (!page) return;
        StandaloneHost.configKeys().forEach(function(key) {
            var changed = page["cfg_" + key + "Changed"];
            if (changed) changed.connect(settingValueChanged);
        });
        if (page.configurationChanged) {
            page.configurationChanged.connect(function() {
                configurationChangedSent = true;
                settingValueChanged();
            });
        }
        if (page.unsavedChangesChanged) {
            page.unsavedChangesChanged.connect(settingValueChanged);
        }
    }

    // Runs `action` now, or after asking about unsaved changes.
    function guarded(action) {
        if (!dirty) {
            action();
            return;
        }
        pendingAction = action;
        unsavedDialog.open();
    }

    onClosing: function(close) {
        if (closeConfirmed || !dirty) return;
        close.accepted = false;
        guarded(function() {
            closeConfirmed = true;
            configWindow.close();
        });
    }

    Kirigami.PromptDialog {
        id: unsavedDialog
        title: i18ndc("plasma_shell_org.kde.plasma.desktop", "@title:window dialog title", "Apply Settings")
        subtitle: i18ndc("plasma_shell_org.kde.plasma.desktop", "@label dialog body", "The current page has unsaved changes. Apply the changes or discard them?")
        standardButtons: Kirigami.Dialog.Apply | Kirigami.Dialog.Discard | Kirigami.Dialog.Cancel
        onApplied: {
            configWindow.saveConfig();
            close();
            var action = configWindow.pendingAction;
            configWindow.pendingAction = null;
            if (action) action();
        }
        onDiscarded: {
            configWindow.dirty = false;
            configWindow.configurationChangedSent = false;
            close();
            var action = configWindow.pendingAction;
            configWindow.pendingAction = null;
            if (action) action();
        }
        onRejected: configWindow.pendingAction = null
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        QQC2.ScrollView {
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 11
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            background: Rectangle {
                Kirigami.Theme.colorSet: Kirigami.Theme.View
                Kirigami.Theme.inherit: false
                color: Kirigami.Theme.backgroundColor
            }

            ListView {
                id: sidebar
                model: configWindow.categories
                currentIndex: configWindow.currentIndex
                clip: true
                delegate: QQC2.ItemDelegate {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    text: modelData.name
                    icon.name: modelData.icon
                    highlighted: ListView.isCurrentItem
                    onClicked: {
                        if (index === configWindow.currentIndex) return;
                        var target = index;
                        configWindow.guarded(() => configWindow.openCategory(target));
                    }
                }
            }
        }

        Kirigami.Separator {
            Layout.fillHeight: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Kirigami.Heading {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                level: 2
                text: configWindow.categories[configWindow.currentIndex]?.name ?? ""
            }

            QQC2.StackView {
                id: pageStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            QQC2.DialogButtonBox {
                Layout.fillWidth: true
                standardButtons: QQC2.DialogButtonBox.Ok | QQC2.DialogButtonBox.Apply | QQC2.DialogButtonBox.Cancel
                Component.onCompleted: standardButton(QQC2.DialogButtonBox.Apply).enabled
                    = Qt.binding(() => configWindow.dirty)
                onAccepted: {
                    configWindow.saveConfig();
                    configWindow.close();
                }
                onApplied: configWindow.saveConfig()
                onRejected: {
                    configWindow.closeConfirmed = true;
                    configWindow.close();
                }
            }
        }
    }

    Component.onCompleted: {
        loadCategories();
        openCategory(0);
    }
}
