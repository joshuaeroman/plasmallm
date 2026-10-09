/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Standalone stand-in for org.kde.plasma.configuration's ConfigModel, read by
// ConfigWindow.qml to build the settings sidebar from config/config.qml.

import QtQuick

QtObject {
    default property list<QtObject> categories
}
