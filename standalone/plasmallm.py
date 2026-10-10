#!/usr/bin/python3 -s
#
#    SPDX-FileCopyrightText: 2026 Joshua Roman
#    SPDX-License-Identifier: GPL-2.0-or-later
#
# Standalone host for the PlasmaLLM plasmoid.
#
# Runs package/contents/ui/main.qml in a normal application window instead of
# plasmashell. The pieces plasmashell normally provides are replaced here:
#   - Plasmoid.configuration: a QQmlPropertyMap backed by config/main.xml and
#     persisted to ~/.config/plasmallmrc (KConfig format)
#   - the applet's translation domain: set on the KLocalizedQmlContext that
#     org.kde.plasma.core installs; catalogs come from <prefix>/share/locale
#   - org.kde.plasma.plasmoid / org.kde.plasma.configuration: QML shim modules
#     in share/plasmallm/qml that take precedence over the system ones
#   - org.kde.plasma.plasma5support: a shim whose "executable" DataSource runs
#     commands through CommandRunner, on the host when running as a Flatpak
# Everything else (Kirigami, Plasma components, Plasma5Support, workspace DBus)
# is the real KDE runtime, so KDE Plasma 6 libraries must be installed.
#
# "-s" keeps a pip-installed PySide6 in ~/.local (which bundles its own Qt) from
# shadowing the distro PySide6 that matches the system Qt the KDE QML plugins
# were built against.

import argparse
import json
import os
import re
import signal
import sys
import tempfile
import warnings
import xml.etree.ElementTree as ET

from PySide6.QtCore import QCoreApplication, QObject, QProcess, Property, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QColor, QIcon
from PySide6.QtQml import QQmlApplicationEngine, QQmlComponent, QQmlEngine, QQmlPropertyMap
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtWidgets import QApplication

APP_ID = "com.joshuaroman.plasmallm"
I18N_DOMAIN = "plasma_applet_" + APP_ID
CONFIG_GROUP = "General"
PLASMA_APPLETSRC = "plasma-org.kde.plasma.desktop-appletsrc"


def find_data_dir():
    """Return <prefix>/share/plasmallm, which holds package/ and qml/.

    The launcher is installed as <prefix>/bin/plasmallm; translations live in
    <prefix>/share/locale. PLASMALLM_DATA_DIR overrides the lookup.
    """
    here = os.path.dirname(os.path.realpath(__file__))
    data = os.environ.get("PLASMALLM_DATA_DIR") or os.path.join(here, "..", "share", "plasmallm")
    if not os.path.isfile(os.path.join(data, "package", "metadata.json")):
        sys.exit("plasmallm: package data not found in %s (build with `make standalone`)" % data)
    return os.path.abspath(data)


# --------------------------------------------------------------------------
# KConfig (ini) reading/writing
# --------------------------------------------------------------------------

_GROUP_RE = re.compile(r"^\[(.*)\]\s*$")


def kconfig_unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n == "s":
                out.append(" ")
            elif n == "t":
                out.append("\t")
            elif n == "n":
                out.append("\n")
            elif n == "r":
                out.append("\r")
            elif n == "\\":
                out.append("\\")
            elif n == "x" and re.fullmatch(r"[0-9a-fA-F]{2}", s[i + 2:i + 4]):
                out.append(chr(int(s[i + 2:i + 4], 16)))
                i += 4
                continue
            else:
                out.append("\\" + n)
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def kconfig_escape(s):
    out = []
    for i, c in enumerate(s):
        if c == "\\":
            out.append("\\\\")
        elif c == "\n":
            out.append("\\n")
        elif c == "\t":
            out.append("\\t")
        elif c == "\r":
            out.append("\\r")
        elif c == " " and (i == 0 or i == len(s) - 1):
            out.append("\\s")
        elif ord(c) < 32:
            out.append("\\x%02x" % ord(c))
        else:
            out.append(c)
    return "".join(out)


def read_kconfig(path):
    """Return {group_name: {key: raw_unescaped_value}} for a KConfig file."""
    groups = {}
    current = groups.setdefault("<default>", {})
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                m = _GROUP_RE.match(line)
                if m:
                    current = groups.setdefault(m.group(1), {})
                    continue
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                # Drop KConfig flags ("key[$e]") and localized keys ("key[de]").
                if "[" in key:
                    if not key.endswith("[$e]") and not key.endswith("[$i]"):
                        continue
                    key = key[:key.index("[")]
                current[key] = kconfig_unescape(value)
    except FileNotFoundError:
        pass
    return groups


def find_plasma_applet_config():
    """Find the [General] config of a PlasmaLLM widget in the Plasma shell config."""
    path = os.path.join(config_home(), PLASMA_APPLETSRC)
    groups = read_kconfig(path)
    best = None
    for name, entries in groups.items():
        if entries.get("plugin") != APP_ID:
            continue
        cfg = groups.get(name + "][Configuration][" + CONFIG_GROUP)
        if cfg and (best is None or len(cfg) > len(best)):
            best = cfg
    return best


def config_home():
    return os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")


# --------------------------------------------------------------------------
# Plasmoid.configuration
# --------------------------------------------------------------------------

class ConfigSchema:
    """Entries of config/main.xml: name -> (type, default python value).

    Handles the kcfg types main.xml uses (Bool, Int, Double, Color, String);
    anything else is treated as String.
    """

    def __init__(self, path):
        self.entries = {}
        root = ET.parse(path).getroot()
        for el in root.iter():
            if el.tag.split("}")[-1] != "entry":
                continue
            name = el.get("name")
            typ = el.get("type", "String")
            default_text = ""
            for child in el:
                if child.tag.split("}")[-1] == "default":
                    default_text = child.text or ""
            self.entries[name] = (typ, self.parse(typ, default_text))

    @staticmethod
    def parse(typ, text):
        if typ == "Bool":
            return text.strip().lower() in ("true", "1", "on", "yes")
        if typ in ("Int", "UInt", "LongLong", "ULongLong"):
            try:
                return int(text.strip() or 0)
            except ValueError:
                return 0
        if typ == "Double":
            try:
                return float(text.strip() or 0)
            except ValueError:
                return 0.0
        if typ == "Color":
            t = text.strip()
            parts = t.split(",")
            if len(parts) in (3, 4) and all(p.strip().isdigit() for p in parts):
                return QColor(*[int(p) for p in parts])
            return QColor(t) if t else QColor()
        return text

    @staticmethod
    def serialize(typ, value):
        if typ == "Bool":
            return "true" if value else "false"
        if typ in ("Int", "UInt", "LongLong", "ULongLong"):
            try:
                return str(int(value))
            except (TypeError, ValueError):
                return "0"
        if typ == "Double":
            return repr(float(value or 0))
        if typ == "Color":
            c = QColor(value)
            if c.alpha() == 255:
                return "%d,%d,%d" % (c.red(), c.green(), c.blue())
            return "%d,%d,%d,%d" % (c.red(), c.green(), c.blue(), c.alpha())
        return kconfig_escape("" if value is None else str(value))

    def normalize(self, typ, value):
        """Coerce a value written from QML back to the schema type."""
        if typ == "Bool":
            return bool(value)
        if typ in ("Int", "UInt", "LongLong", "ULongLong"):
            try:
                return int(value)
            except (TypeError, ValueError):
                return 0
        if typ == "Double":
            try:
                return float(value)
            except (TypeError, ValueError):
                return 0.0
        if typ == "Color":
            return QColor(value)
        return "" if value is None else str(value)


class Configuration:
    """Owns the QQmlPropertyMap exposed as Plasmoid.configuration."""

    def __init__(self, schema, path):
        self.schema = schema
        self.path = os.path.abspath(path)
        with warnings.catch_warnings():
            # PySide marks QQmlPropertyMap's only constructor as deprecated.
            warnings.simplefilter("ignore", DeprecationWarning)
            self.map = QQmlPropertyMap()
        self._saving = QTimer()
        self._saving.setSingleShot(True)
        self._saving.setInterval(500)
        self._saving.timeout.connect(self.write)
        self._normalizing = False

        exists = os.path.exists(self.path)
        stored = read_kconfig(self.path).get(CONFIG_GROUP, {})
        for name, (typ, default) in schema.entries.items():
            value = schema.parse(typ, stored[name]) if name in stored else default
            self.map.insert(name, value)
        self.map.valueChanged.connect(self._on_value_changed)
        self.first_run = not exists

    def import_raw(self, raw):
        """Apply raw KConfig strings (e.g. from the Plasma widget's config)."""
        count = 0
        for name, text in raw.items():
            if name in self.schema.entries:
                typ = self.schema.entries[name][0]
                self.map.insert(name, self.schema.parse(typ, text))
                count += 1
        self.write()
        return count

    def _on_value_changed(self, key, value):
        if self._normalizing or key not in self.schema.entries:
            return
        typ = self.schema.entries[key][0]
        norm = self.schema.normalize(typ, value)
        if norm != value and typ != "Color":
            self._normalizing = True
            self.map.insert(key, norm)
            self._normalizing = False
        self._saving.start()

    def write(self):
        self._saving.stop()
        lines = ["[" + CONFIG_GROUP + "]"]
        for name in sorted(self.schema.entries):
            typ, default = self.schema.entries[name]
            text = self.schema.serialize(typ, self.map.value(name))
            if text == self.schema.serialize(typ, default):
                continue  # like KConfig, only non-default values are stored
            lines.append(name + "=" + text)
        data = "\n".join(lines) + "\n"
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".plasmallmrc.", dir=os.path.dirname(self.path))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(data)
            os.chmod(tmp, 0o600)
            os.replace(tmp, self.path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise


# --------------------------------------------------------------------------
# Flatpak
# --------------------------------------------------------------------------

FLATPAK_INFO = "/.flatpak-info"


def in_flatpak():
    return os.path.exists(FLATPAK_INFO)


def flatpak_app_path():
    """Host path of the sandbox's /app, from the [Instance] app-path key."""
    return read_kconfig(FLATPAK_INFO).get("Instance", {}).get("app-path", "")


def use_host_xdg_dirs():
    """Point XDG data/config/state dirs at the host's instead of ~/.var/app.

    Commands run on the host and compute paths like
    ${XDG_DATA_HOME:-$HOME/.local/share}/plasmallm; QML reads and writes the
    same files directly, so both sides must agree on where they are.
    """
    home = os.path.expanduser("~")
    for var, default in (("XDG_DATA_HOME", ".local/share"),
                         ("XDG_CONFIG_HOME", ".config"),
                         ("XDG_STATE_HOME", ".local/state")):
        os.environ[var] = os.environ.get("HOST_" + var) or os.path.join(home, default)


# --------------------------------------------------------------------------
# Commands for the Plasma5Support "executable" engine shim
# --------------------------------------------------------------------------

class CommandRunner(QObject):
    """Runs `sh -c <command>` like Plasma5Support's executable engine.

    Each DataSource is an owner; a (owner, command) pair runs at most once at a
    time, and stop() kills it, as disconnecting a source does in Plasma.
    Inside a Flatpak, commands run on the host via flatpak-spawn, and paths
    under the bundled data dir are translated between sandbox and host.
    """

    finished = Signal(str, str, "QVariantMap")  # owner, command, data

    def __init__(self, path_map=None):
        super().__init__()
        self._procs = {}
        self._next_owner = 0
        self._path_map = path_map  # (sandbox_prefix, host_prefix) or None

    @Slot(result=str)
    def newOwner(self):
        self._next_owner += 1
        return str(self._next_owner)

    def _to_host(self, text):
        return text.replace(self._path_map[0], self._path_map[1]) if self._path_map else text

    def _from_host(self, text):
        return text.replace(self._path_map[1], self._path_map[0]) if self._path_map else text

    @Slot(str, str)
    def start(self, owner, command):
        key = (owner, command)
        if key in self._procs:
            return
        proc = QProcess(self)
        if in_flatpak():
            program, args = "flatpak-spawn", ["--host", "--watch-bus", "/bin/sh", "-c", self._to_host(command)]
        else:
            program, args = "/bin/sh", ["-c", command]
        proc.finished.connect(lambda code, status: self._finished(key, proc, code, status))
        proc.errorOccurred.connect(lambda error: self._failed(key, proc, error))
        self._procs[key] = proc
        proc.start(program, args)

    def _finished(self, key, proc, code, status):
        if self._procs.get(key) is not proc:
            return
        del self._procs[key]
        data = {
            "exit code": code,
            "exit status": 0 if status == QProcess.ExitStatus.NormalExit else 1,
            "stdout": self._from_host(bytes(proc.readAllStandardOutput()).decode("utf-8", "replace")),
            "stderr": self._from_host(bytes(proc.readAllStandardError()).decode("utf-8", "replace")),
        }
        proc.deleteLater()
        self.finished.emit(key[0], key[1], data)

    def _failed(self, key, proc, error):
        if error == QProcess.ProcessError.FailedToStart:
            self._finished(key, proc, 127, QProcess.ExitStatus.CrashExit)

    @Slot(str, str)
    def stop(self, owner, command):
        proc = self._procs.pop((owner, command), None)
        if proc is None:
            return
        # SIGTERM first: flatpak-spawn forwards it to the host process.
        proc.finished.connect(proc.deleteLater)
        proc.terminate()
        QTimer.singleShot(2000, proc, proc.kill)


# --------------------------------------------------------------------------
# Host object, exposed to QML as the StandaloneHost context property
# --------------------------------------------------------------------------

class Host(QObject):
    def __init__(self, config, package_dir, version, show_config_on_start, runner):
        super().__init__()
        self._runner = runner
        self._config = config
        self._package_dir = package_dir
        self._version = version
        self._show_config_on_start = show_config_on_start

    @Property(QObject, constant=True)
    def commandRunner(self):
        return self._runner

    @Property(QObject, constant=True)
    def configuration(self):
        return self._config.map

    @Property(str, constant=True)
    def version(self):
        return self._version

    @Property(QUrl, constant=True)
    def mainScript(self):
        return QUrl.fromLocalFile(os.path.join(self._package_dir, "contents", "ui", "main.qml"))

    @Property(QUrl, constant=True)
    def configModel(self):
        return QUrl.fromLocalFile(os.path.join(self._package_dir, "contents", "config", "config.qml"))

    @Property(QUrl, constant=True)
    def uiDir(self):
        return QUrl.fromLocalFile(os.path.join(self._package_dir, "contents", "ui") + "/")

    @Property(QUrl, constant=True)
    def stateFile(self):
        """Window geometry etc. (QSettings ini), kept out of the config file."""
        state_home = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
        return QUrl.fromLocalFile(os.path.join(state_home, "plasmallmstaterc"))

    @Property(bool, constant=True)
    def showConfigOnStart(self):
        return self._show_config_on_start

    @Slot(result="QStringList")
    def configKeys(self):
        return list(self._config.schema.entries)

    @Slot()
    def writeConfig(self):
        self._config.write()


def set_translation_domain(engine, domain):
    """Give i18n() the applet's catalog, as plasmashell does per applet.

    Importing org.kde.plasma.core installs a KLocalizedQmlContext as the root
    context object; its translationDomain is reachable unqualified from QML.
    This must run before any QML that calls i18n() is created.
    """
    component = QQmlComponent(engine)
    component.setData(("import QtQml\nimport org.kde.plasma.core\n"
                       "QtObject { Component.onCompleted: translationDomain = %s }"
                       % json.dumps(domain)).encode(), QUrl())
    obj = component.create()
    if obj is None:
        print("plasmallm: cannot set translation domain: " + component.errorString(), file=sys.stderr)
    else:
        obj.deleteLater()


def main():
    parser = argparse.ArgumentParser(description="PlasmaLLM standalone window")
    parser.add_argument("--import-plasma-config", action="store_true",
                        help="copy settings from the PlasmaLLM panel widget, then start")
    parser.add_argument("--configure", action="store_true", help="open the settings window on start")
    parser.add_argument("--config-file", help="config file to use (default: ~/.config/plasmallmrc)")
    opts, qt_args = parser.parse_known_args()

    data_dir = find_data_dir()
    path_map = None
    if in_flatpak():
        use_host_xdg_dirs()
        app_path = flatpak_app_path()
        if app_path:
            path_map = (data_dir, app_path + data_dir[len("/app"):]) if data_dir.startswith("/app/") else None
    package_dir = os.path.join(data_dir, "package")
    qml_dir = os.path.join(data_dir, "qml")

    # KI18n finds catalogs under $XDG_DATA_DIRS/locale; make sure ours is searched.
    share_dir = os.path.dirname(data_dir)
    data_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    if share_dir not in data_dirs.split(":"):
        os.environ["XDG_DATA_DIRS"] = share_dir + ":" + data_dirs

    with open(os.path.join(package_dir, "metadata.json"), encoding="utf-8") as f:
        version = json.load(f)["KPlugin"].get("Version", "")

    QCoreApplication.setApplicationName("plasmallm")
    QCoreApplication.setApplicationVersion(version)
    if not os.environ.get("QT_QUICK_CONTROLS_STYLE"):
        QQuickStyle.setStyle("org.kde.desktop")
    app = QApplication([sys.argv[0]] + qt_args)
    app.setApplicationDisplayName("PlasmaLLM")
    app.setDesktopFileName(APP_ID)
    app.setWindowIcon(QIcon.fromTheme("dialog-messages"))
    signal.signal(signal.SIGINT, lambda *_: app.quit())

    schema = ConfigSchema(os.path.join(package_dir, "contents", "config", "main.xml"))
    config = Configuration(schema, opts.config_file or os.path.join(config_home(), "plasmallmrc"))
    if opts.import_plasma_config or config.first_run:
        raw = find_plasma_applet_config()
        if raw:
            n = config.import_raw(raw)
            print("plasmallm: imported %d settings from the Plasma widget" % n, file=sys.stderr)
        elif opts.import_plasma_config:
            print("plasmallm: no PlasmaLLM widget config found in " + PLASMA_APPLETSRC, file=sys.stderr)
        elif config.first_run:
            config.write()
    app.aboutToQuit.connect(config.write)

    engine = QQmlApplicationEngine()
    engine.addImportPath(qml_dir)  # shims shadow org.kde.plasma.plasmoid/configuration
    runner = CommandRunner(path_map)
    host = Host(config, package_dir, version, opts.configure, runner)
    # A context property rather than qmlRegisterSingletonInstance: registering
    # a PySide type breaks resolution of some KDE QML types (e.g. qqc2-desktop-style's ScrollBar).
    QQmlEngine.setObjectOwnership(host, QQmlEngine.CppOwnership)
    engine.rootContext().setContextProperty("StandaloneHost", host)

    set_translation_domain(engine, I18N_DOMAIN)
    engine.load(QUrl.fromLocalFile(os.path.join(qml_dir, "StandaloneWindow.qml")))
    if not engine.rootObjects():
        sys.exit(1)

    # Let Python see SIGINT while the Qt event loop runs.
    tick = QTimer()
    tick.start(250)
    tick.timeout.connect(lambda: None)

    rc = app.exec()
    del engine
    sys.exit(rc)


if __name__ == "__main__":
    main()
