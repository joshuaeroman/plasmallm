/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Standalone stand-in for PlasmoidItem: always shows the full representation.
// StandaloneWindow drives `expanded` from window focus, the way a panel popup
// opens and closes.

import QtQuick

Item {
    id: item

    property bool expanded: false
    property bool hideOnWindowDeactivate
    property bool activationTogglesExpanded
    property Component compactRepresentation
    property Component fullRepresentation
    property Component preferredRepresentation
    property real switchWidth
    property real switchHeight
    property string toolTipMainText
    property string toolTipSubText
    property int toolTipTextFormat
    property Component toolTipItem

    readonly property Item fullRepresentationItem: fullLoader.item
    readonly property Item compactRepresentationItem: null

    Loader {
        id: fullLoader
        anchors.fill: parent
        active: false
        sourceComponent: item.fullRepresentation
    }

    // Like plasmashell, build the representation only after the applet has
    // finished loading (e.g. main.qml clears its ListModel role-template rows
    // in Component.onCompleted; a view created earlier would show them).
    Component.onCompleted: Qt.callLater(() => fullLoader.active = true)
}
