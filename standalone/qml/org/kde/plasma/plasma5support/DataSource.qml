/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Standalone stand-in for Plasma5Support's DataSource, implementing only the
// "executable" engine: each connected source is a shell command, run once,
// whose result arrives through newData(). Disconnecting kills a running command.
// Commands are run by the launcher's CommandRunner, which can reach the host
// from inside a Flatpak sandbox.

import QtQuick

QtObject {
    id: dataSource

    property string engine
    property var connectedSources: []
    property int interval
    property var data: ({})

    signal newData(string sourceName, var data)
    signal sourceConnected(string source)
    signal sourceDisconnected(string source)

    readonly property QtObject _runner: StandaloneHost.commandRunner
    readonly property string _owner: _runner.newOwner()
    property var _active: ({})

    function connectSource(source) {
        if (connectedSources.indexOf(source) === -1) {
            connectedSources = connectedSources.concat([source]);
        }
    }

    function disconnectSource(source) {
        connectedSources = connectedSources.filter(s => s !== source);
    }

    function _sync() {
        var wanted = {};
        connectedSources.forEach(s => wanted[s] = true);
        for (var source in _active) {
            if (!wanted[source]) {
                delete _active[source];
                delete data[source];
                _runner.stop(_owner, source);
                sourceDisconnected(source);
            }
        }
        connectedSources.forEach(function(source) {
            if (!_active[source]) {
                _active[source] = true;
                _runner.start(_owner, source);
                sourceConnected(source);
            }
        });
    }

    onConnectedSourcesChanged: _sync()
    onEngineChanged: {
        if (engine !== "executable") {
            console.warn("PlasmaLLM standalone: unsupported Plasma5Support engine", engine);
        }
    }

    readonly property Connections _connections: Connections {
        target: dataSource._runner
        function onFinished(owner, source, result) {
            if (owner !== dataSource._owner || !dataSource._active[source]) return;
            dataSource.data[source] = result;
            dataSource.newData(source, result);
        }
    }

    Component.onCompleted: _sync()
    Component.onDestruction: {
        for (var source in _active) {
            _runner.stop(_owner, source);
        }
    }
}
