/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Standalone stand-in for the Plasmoid object plasmashell provides to applets.
// Only the members PlasmaLLM and the PlasmaExtras components touch are here.

pragma Singleton

import QtQuick
import org.kde.plasma.core as PlasmaCore

QtObject {
    id: plasmoid

    readonly property QtObject configuration: StandaloneHost.configuration

    // Always a free-floating "desktop" applet: no panel, no pin button.
    readonly property int formFactor: PlasmaCore.Types.Planar
    readonly property int location: PlasmaCore.Types.Floating
    readonly property int containmentDisplayHints: 0
    property int status: PlasmaCore.Types.ActiveStatus

    readonly property string title: "PlasmaLLM"
    readonly property string icon: "dialog-messages"
    readonly property string pluginName: "com.joshuaroman.plasmallm"
    readonly property bool userConfiguring: false
    property list<QtObject> contextualActions

    signal internalActionsChanged(var actions)
    // Emitted by the "configure" action; StandaloneWindow opens the settings.
    signal configureRequested()

    readonly property PlasmaCore.Action _configureAction: PlasmaCore.Action {
        text: i18ndc("libplasma6", "%1 is the name of the applet", "Configure %1...", plasmoid.title)
        onTriggered: plasmoid.configureRequested()
    }

    function internalAction(name) {
        return name === "configure" ? _configureAction : null;
    }
}
