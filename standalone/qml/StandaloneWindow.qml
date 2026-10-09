/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Top-level window for the standalone build: hosts the plasmoid's main.qml
// (its PlasmoidItem root resolves to the shim in org/kde/plasma/plasmoid).

import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

QQC2.ApplicationWindow {
    id: window

    title: "PlasmaLLM"
    visible: true
    width: Kirigami.Units.gridUnit * 28
    height: Kirigami.Units.gridUnit * 32
    minimumWidth: Kirigami.Units.gridUnit * 20
    minimumHeight: Kirigami.Units.gridUnit * 24

    // The applet behaves as "expanded" (popup open) while the user is looking
    // at it; it uses this to decide on notifications and unread markers.
    readonly property bool attended: window.active || (configWindowLoader.item?.active ?? false)

    Settings {
        location: StandaloneHost.stateFile
        category: "MainWindow"
        property alias width: window.width
        property alias height: window.height
    }

    Loader {
        id: applet
        anchors.fill: parent
        source: StandaloneHost.mainScript
        focus: true
        onLoaded: item.expanded = window.attended
    }

    onAttendedChanged: {
        if (applet.item && applet.item.expanded !== attended) {
            applet.item.expanded = attended;
        }
    }

    Connections {
        target: applet.item
        // "/close" collapses the applet; the window equivalent is minimizing.
        function onExpandedChanged() {
            if (!applet.item.expanded && window.attended) {
                window.showMinimized();
            }
        }
    }

    Connections {
        target: Plasmoid
        function onStatusChanged() {
            if (Plasmoid.status === PlasmaCore.Types.RequiresAttentionStatus && !window.active) {
                window.alert(0);
            }
        }
        function onConfigureRequested() {
            window.openConfig();
        }
    }

    function openConfig() {
        if (configWindowLoader.active && configWindowLoader.item) {
            configWindowLoader.item.raise();
            configWindowLoader.item.requestActivate();
            return;
        }
        configWindowLoader.active = true;
    }

    Loader {
        id: configWindowLoader
        active: false
        sourceComponent: ConfigWindow {
            transientParent: window
            onClosing: Qt.callLater(() => configWindowLoader.active = false)
        }
        onLoaded: {
            item.show();
            item.requestActivate();
        }
    }

    Component.onCompleted: {
        if (StandaloneHost.showConfigOnStart) {
            openConfig();
        }
    }
}
