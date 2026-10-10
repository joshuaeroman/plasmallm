# SPDX-FileCopyrightText: 2026 Joshua Roman
# SPDX-License-Identifier: BSD-3-Clause
#
# Replaces plasma-workspace's top-level CMakeLists.txt so only the
# org.kde.plasma.workspace.dbus QML module (components/dbus) is built.

cmake_minimum_required(VERSION 3.16)
project(plasma-workspace-dbus)

# Matches plasma-workspace's top-level settings.
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)
include(ECMQtDeclareLoggingCategory)

find_package(Qt6 REQUIRED COMPONENTS DBus Qml Quick)
find_package(PkgConfig REQUIRED)
pkg_check_modules(DBus REQUIRED IMPORTED_TARGET dbus-1)

add_subdirectory(components/dbus)
