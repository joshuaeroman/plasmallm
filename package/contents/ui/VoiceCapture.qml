/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtMultimedia

/**
 * Audio capture for hold-to-talk voice notes.
 * Primary path: Qt Multimedia MediaRecorder.
 * Fallback: pw-record / ffmpeg / arecord via shell (wired by host via shell* functions).
 */
Item {
    id: voiceCapture

    property int maxSeconds: 60
    property string outputDir: ""  // absolute path, e.g. ~/.local/share/plasmallm/voice
    property string shellOutputDir: "${XDG_DATA_HOME:-$HOME/.local/share}/plasmallm/voice"

    readonly property bool recording: _phase === "recording"
    readonly property bool available: _qtAvailable || _shellFallbackAvailable
    readonly property string statusText: _statusText

    // Host sets these if shell fallback is desired (main.qml executable helpers).
    property var shellStartFn: null   // function(filePath, shellFilePath) -> pid or ""
    property var shellStopFn: null    // function(pid, filePath) -> void  (async: host emits shellRecordingFinished)
    property bool shellFallbackAvailable: true

    signal recordingFinished(string filePath, string format)
    signal recordingFailed(string message)
    signal recordingCanceled()

    property string _phase: "idle" // idle | recording | stopping
    property bool _cancelRequested: false
    property string _pendingPath: ""
    property string _pendingFormat: "wav"
    property string _backend: "" // "qt" | "shell"
    property string _shellPid: ""
    property string _statusText: ""
    property bool _qtAvailable: false
    property bool _shellFallbackAvailable: false
    property bool _intentionalStop: false
    // Wall-clock when recording entered "recording" (ms since epoch).
    property real _startedAtMs: 0
    // Reject stops shorter than this (ms) — filters accidental press/release races.
    // Keep at or below holdMinMs (250) so intentional short PTT still sends.
    property int minDurationMs: 200
    // Host can read elapsed while recording/stopping.
    readonly property int elapsedMs: _startedAtMs > 0
        ? Math.max(0, Math.floor(Date.now() - _startedAtMs))
        : 0

    MediaDevices {
        id: mediaDevices
    }

    CaptureSession {
        id: captureSession
        audioInput: AudioInput {
            id: audioInput
        }
        recorder: MediaRecorder {
            id: mediaRecorder
            quality: MediaRecorder.NormalQuality
            // Prefer uncompressed Wave for STT compatibility (OpenRouter/OpenAI).
            // Audio codec is left to the backend; file container is the important part.
            mediaFormat {
                fileFormat: MediaFormat.Wave
            }
            onRecorderStateChanged: voiceCapture._onRecorderStateChanged()
            onErrorOccurred: function(error, errorString) {
                console.warn("PlasmaLLM VoiceCapture Qt error:", error, errorString);
                if (voiceCapture._backend === "qt" && voiceCapture._phase !== "idle") {
                    // Fall back to shell recorder if Qt capture fails at start.
                    if (voiceCapture._phase === "recording"
                            && voiceCapture.shellFallbackAvailable
                            && typeof voiceCapture.shellStartFn === "function"
                            && !voiceCapture._intentionalStop) {
                        console.warn("PlasmaLLM VoiceCapture: falling back to shell recorder");
                        maxDurationTimer.stop();
                        voiceCapture._phase = "idle";
                        voiceCapture._backend = "";
                        if (voiceCapture._startShell())
                            return;
                    }
                    voiceCapture._fail(errorString || i18n("Microphone recording failed"));
                }
            }
        }
    }

    Timer {
        id: maxDurationTimer
        interval: Math.max(5, voiceCapture.maxSeconds) * 1000
        repeat: false
        onTriggered: {
            if (voiceCapture._phase === "recording") {
                voiceCapture.stop();
            }
        }
    }

    Component.onCompleted: {
        _refreshAvailability();
    }

    function _refreshAvailability() {
        _qtAvailable = mediaDevices.audioInputs && mediaDevices.audioInputs.length > 0;
        _shellFallbackAvailable = shellFallbackAvailable;
        if (!_qtAvailable && !_shellFallbackAvailable) {
            _statusText = i18n("No microphone found");
        } else {
            _statusText = "";
        }
    }

    function _localPathFromUrl(url) {
        var s = "" + url;
        if (s.indexOf("file://") === 0)
            s = s.substring(7);
        // Decode percent-encoding lightly for spaces
        try {
            s = decodeURIComponent(s);
        } catch (e) {}
        return s;
    }

    function _formatFromPath(path) {
        var p = String(path || "");
        var dot = p.lastIndexOf(".");
        if (dot < 0)
            return "wav";
        var ext = p.substring(dot + 1).toLowerCase();
        if (ext === "wave")
            return "wav";
        if (ext === "mpeg" || ext === "mpga")
            return "mp3";
        if (ext === "mp4")
            return "m4a";
        return ext || "wav";
    }

    function _pickOutputPath(preferredExt) {
        var ext = preferredExt || "wav";
        var stamp = Date.now().toString(36) + "_" + Math.random().toString(36).substring(2, 8);
        var base = outputDir && outputDir.length > 0
            ? outputDir
            : "/tmp/plasmallm_voice";
        return base + "/note_" + stamp + "." + ext;
    }

    function _pickShellOutputPath(preferredExt) {
        var ext = preferredExt || "wav";
        var stamp = Date.now().toString(36) + "_" + Math.random().toString(36).substring(2, 8);
        var base = shellOutputDir && shellOutputDir.length > 0
            ? shellOutputDir
            : "${XDG_DATA_HOME:-$HOME/.local/share}/plasmallm/voice";
        return base + "/note_" + stamp + "." + ext;
    }

    function start() {
        if (_phase !== "idle")
            return false;

        _refreshAvailability();
        _cancelRequested = false;
        _intentionalStop = false;
        _shellPid = "";
        _pendingPath = "";
        _pendingFormat = "wav";

        if (_qtAvailable) {
            return _startQt();
        }
        if (_shellFallbackAvailable && typeof shellStartFn === "function") {
            return _startShell();
        }
        recordingFailed(i18n("No microphone available"));
        return false;
    }

    function _startQt() {
        _backend = "qt";
        _pendingFormat = "wav";
        _pendingPath = _pickOutputPath(_pendingFormat);
        try {
            mediaRecorder.outputLocation = Qt.resolvedUrl("file://" + _pendingPath);
        } catch (e) {
            mediaRecorder.outputLocation = "file://" + _pendingPath;
        }
        _phase = "recording";
        _startedAtMs = Date.now();
        _statusText = i18n("Recording…");
        maxDurationTimer.restart();
        try {
            mediaRecorder.record();
        } catch (recErr) {
            console.warn("PlasmaLLM VoiceCapture record() threw:", recErr);
            _phase = "idle";
            _startedAtMs = 0;
            if (_shellFallbackAvailable && typeof shellStartFn === "function") {
                return _startShell();
            }
            recordingFailed(i18n("Could not start recording: %1", recErr.message || String(recErr)));
            return false;
        }
        // If recorder immediately reports an error/stopped without content, fallback is handled in errorOccurred.
        return true;
    }

    function _startShell() {
        _backend = "shell";
        _pendingFormat = "wav";
        var shellPath = _pickShellOutputPath("wav");
        // Host maps shell path → absolute path for later base64; use placeholder absolute.
        _pendingPath = shellPath.replace("${XDG_DATA_HOME:-$HOME/.local/share}",
            (outputDir && outputDir.indexOf("/plasmallm/voice") > 0)
                ? outputDir.substring(0, outputDir.indexOf("/plasmallm/voice"))
                : "");
        // Prefer host-provided absolute path derivation via return value.
        var started = shellStartFn(shellPath, shellPath);
        if (!started) {
            _phase = "idle";
            _backend = "";
            recordingFailed(i18n("Could not start shell audio recorder (install pw-record or ffmpeg)"));
            return false;
        }
        if (typeof started === "object") {
            _shellPid = started.pid || "";
            if (started.filePath)
                _pendingPath = started.filePath;
            else if (started.shellPath)
                _pendingPath = started.shellPath;
        } else {
            _shellPid = String(started);
        }
        _phase = "recording";
        _startedAtMs = Date.now();
        _statusText = i18n("Recording…");
        maxDurationTimer.restart();
        return true;
    }

    /**
     * Stop and keep the clip for transcription.
     * If recording is shorter than minDurationMs, cancel instead (no STT).
     * Returns: "stopping" | "canceled" | "ignored"
     */
    function stop() {
        if (_phase !== "recording")
            return "ignored";

        var elapsed = _startedAtMs > 0 ? (Date.now() - _startedAtMs) : 0;
        if (elapsed < minDurationMs) {
            // Too short — drop the clip rather than send silence to STT.
            cancel();
            return "canceled";
        }

        _intentionalStop = true;
        _cancelRequested = false;
        _phase = "stopping";
        _statusText = i18n("Processing…");
        maxDurationTimer.stop();

        if (_backend === "qt") {
            try {
                mediaRecorder.stop();
            } catch (e) {
                _fail(i18n("Failed to stop recording"));
                return "ignored";
            }
        } else if (_backend === "shell") {
            if (typeof shellStopFn === "function") {
                shellStopFn(_shellPid, _pendingPath);
                // Host will call notifyShellFinished / notifyShellFailed
            } else {
                _fail(i18n("Shell recorder stop is not configured"));
                return "ignored";
            }
        }
        return "stopping";
    }

    function cancel() {
        if (_phase === "idle")
            return;
        _cancelRequested = true;
        _intentionalStop = false;
        maxDurationTimer.stop();
        if (_phase === "recording" || _phase === "stopping") {
            if (_backend === "qt") {
                try {
                    if (mediaRecorder.recorderState === MediaRecorder.RecordingState
                            || mediaRecorder.recorderState === MediaRecorder.PausedState) {
                        mediaRecorder.stop();
                    }
                } catch (e) {}
                _cleanupFile(_pendingPath);
                _resetIdle();
                recordingCanceled();
            } else if (_backend === "shell") {
                if (typeof shellStopFn === "function") {
                    shellStopFn(_shellPid, _pendingPath);
                }
                _cleanupFile(_pendingPath);
                _resetIdle();
                recordingCanceled();
            } else {
                _resetIdle();
                recordingCanceled();
            }
        }
    }

    // Called by host after shell stop completes successfully.
    function notifyShellFinished(filePath) {
        if (_backend !== "shell")
            return;
        if (_cancelRequested) {
            _cleanupFile(filePath || _pendingPath);
            _resetIdle();
            recordingCanceled();
            return;
        }
        var path = filePath || _pendingPath;
        var fmt = _formatFromPath(path);
        _resetIdle();
        recordingFinished(path, fmt);
    }

    function notifyShellFailed(message) {
        if (_backend !== "shell")
            return;
        if (_cancelRequested) {
            _resetIdle();
            recordingCanceled();
            return;
        }
        _fail(message || i18n("Shell recording failed"));
    }

    function _onRecorderStateChanged() {
        if (_backend !== "qt")
            return;
        if (mediaRecorder.recorderState !== MediaRecorder.StoppedState)
            return;
        if (_phase !== "stopping" && _phase !== "recording")
            return;

        if (_cancelRequested) {
            _cleanupFile(_localPathFromUrl(mediaRecorder.actualLocation) || _pendingPath);
            _resetIdle();
            recordingCanceled();
            return;
        }

        // Intentional stop (user release or max duration)
        if (!_intentionalStop && _phase === "recording") {
            // Unexpected stop — treat as failure and try shell fallback next time
            var err = mediaRecorder.errorString || i18n("Recording stopped unexpectedly");
            _fail(err);
            return;
        }

        var loc = mediaRecorder.actualLocation;
        var path = loc && loc.toString().length > 0 ? _localPathFromUrl(loc) : _pendingPath;
        if (!path || path.length === 0) {
            _fail(i18n("Recording produced no file"));
            return;
        }
        var fmt = _formatFromPath(path);
        _resetIdle();
        recordingFinished(path, fmt);
    }

    function _fail(message) {
        maxDurationTimer.stop();
        var path = _pendingPath;
        if (_backend === "qt") {
            var loc = mediaRecorder.actualLocation;
            if (loc && loc.toString().length > 0)
                path = _localPathFromUrl(loc);
        }
        _cleanupFile(path);
        _resetIdle();
        recordingFailed(message || i18n("Recording failed"));
    }

    function _resetIdle() {
        _phase = "idle";
        _backend = "";
        _shellPid = "";
        _pendingPath = "";
        _cancelRequested = false;
        _intentionalStop = false;
        _startedAtMs = 0;
        _statusText = "";
    }

    function _cleanupFile(path) {
        // Deletion is done by host executable; signal path via optional property for host.
        if (path && path.length > 0)
            voiceCapture.pendingCleanupPath = path;
    }

    property string pendingCleanupPath: ""

}
