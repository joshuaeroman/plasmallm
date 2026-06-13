/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var token = "";
var isSessionActive = false;
var lastDesktopMoveTime = 0;
var lastZoom = "tight";
var dbusBus = null;
var screenshotPathCallback = null;
var activeContextUuid = "";
var openWindowsList = [];

function getActiveContext() {
    return activeContextUuid;
}

function getOpenWindows() {
    return openWindowsList;
}

function init(bus, pathCallback) {
    dbusBus = bus;
    if (pathCallback) {
        screenshotPathCallback = pathCallback;
    }
}

function getNewScreenshotPath() {
    if (screenshotPathCallback) {
        return screenshotPathCallback();
    }
    return "";
}

function isDriverActive(callback) {
    if (!dbusBus) {
        if (callback) callback(false);
        return;
    }
    dbusBus.asyncCall({
        service: "org.freedesktop.DBus",
        path: "/org/freedesktop/DBus",
        iface: "org.freedesktop.DBus",
        member: "NameHasOwner",
        arguments: ["com.joshuaroman.plasmallm.DesktopDriver"]
    }, function(reply) {
        var active = false;
        var replyObj = reply;
        if (replyObj && replyObj.values && replyObj.values.length > 0) {
            active = replyObj.values[0].value || replyObj.values[0];
        } else if (replyObj && replyObj.value !== undefined) {
            active = replyObj.value;
        }
        if (callback) callback(active === true || active === "true");
    }, function(err) {
        if (callback) callback(false);
    });
}

function stopSession(callback) {
    if (!dbusBus) {
        if (callback) callback({error: "DBus not initialized"});
        return;
    }
    dbusBus.asyncCall({
        service: "com.joshuaroman.plasmallm.DesktopDriver",
        path: "/com/joshuaroman/plasmallm/DesktopDriver",
        iface: "com.joshuaroman.plasmallm.DesktopDriver",
        member: "StopSession",
        arguments: []
    }, function() {
        token = "";
        isSessionActive = false;
        if (callback) callback(null);
    }, function(err) {
        token = "";
        isSessionActive = false;
        if (callback) callback(err);
    });
}

function startSession(clientToken, callback) {
    if (!dbusBus) {
        if (callback) callback({error: "DBus not initialized"});
        return;
    }
    // Perform handshake over DBus
    dbusBus.asyncCall({
        service: "com.joshuaroman.plasmallm.DesktopDriver",
        path: "/com/joshuaroman/plasmallm/DesktopDriver",
        iface: "com.joshuaroman.plasmallm.DesktopDriver",
        member: "StartSession",
        arguments: [clientToken || ""]
    }, function() {
        var args = Array.prototype.slice.call(arguments);
        var success = false;
        var r_token = "";
        
        if (args.length > 0 && args[0] !== null && typeof args[0] === 'object') {
            var replyObj = args[0];
            if (replyObj.isError) {
                if (callback) callback({error: "DBus Error: " + replyObj.error.message});
                return;
            }
            if (replyObj.values && replyObj.values.length >= 3) {
                success = replyObj.values[0];
                r_token = replyObj.values[2].value || replyObj.values[2];
            } else if (replyObj.values && replyObj.values.length >= 2) {
                success = replyObj.values[0];
                r_token = replyObj.values[1].value || replyObj.values[1];
            } else if (replyObj.value) {
                success = replyObj.value;
            }
        } else if (args.length === 1 && Array.isArray(args[0])) {
            if (args[0].length >= 3) {
                success = args[0][0];
                r_token = args[0][2];
            } else if (args[0].length >= 2) {
                success = args[0][0];
                r_token = args[0][1];
            }
        } else if (args.length >= 3) {
            success = args[0];
            r_token = args[2];
        } else if (args.length >= 2) {
            success = args[0];
            r_token = args[1];
        }

        if (success === true && typeof r_token === "string" && r_token.length > 0) {
            token = r_token;
            
            // Check if the session is already active (authorized)
            dbusBus.asyncCall({
                service: "com.joshuaroman.plasmallm.DesktopDriver",
                path: "/com/joshuaroman/plasmallm/DesktopDriver",
                iface: "com.joshuaroman.plasmallm.DesktopDriver",
                member: "IsSessionActive",
                arguments: []
            }, function(activeReply) {
                var active = false;
                var replyObj = activeReply;
                if (replyObj && replyObj.values && replyObj.values.length > 0) {
                    active = replyObj.values[0].value || replyObj.values[0];
                } else if (replyObj && replyObj.value !== undefined) {
                    active = replyObj.value;
                }
                
                isSessionActive = true;
                if (callback) callback(null, token, active);
            }, function(err) {
                isSessionActive = true;
                if (callback) callback(null, token, false);
            });
        } else {
            if (callback) callback({error: "Session denied or invalid token received. Args: " + JSON.stringify(args)});
        }
    }, function(err) {
        if (callback) callback({error: "DBus Error: " + err.message});
    });
}

function executeCommand(method, params, callback) {
    if (!dbusBus) {
        if (callback) callback({error: "DBus not initialized"});
        return;
    }
    if (!isSessionActive || token === "") {
        if (callback) callback({error: "No active desktop automation session. Call StartSession first."});
        return;
    }

    var payload = {
        jsonrpc: "2.0",
        method: method,
        params: params,
        id: 1
    };

    dbusBus.asyncCall({
        service: "com.joshuaroman.plasmallm.DesktopDriver",
        path: "/com/joshuaroman/plasmallm/DesktopDriver",
        iface: "com.joshuaroman.plasmallm.DesktopDriver",
        member: "ExecuteCommand",
        arguments: [token, JSON.stringify(payload)]
    }, function() {
        if (callback) {
            var args = Array.prototype.slice.call(arguments);
            var replyStr = "";
            if (args.length > 0 && args[0] !== null && typeof args[0] === 'object') {
                var replyObj = args[0];
                if (replyObj.isError) {
                    console.error("PlasmaLLM DriverManager: DBus Error in replyObj:", replyObj.error.message);
                    callback("DBus Error: " + replyObj.error.message);
                    return;
                }
                replyStr = replyObj.value || (replyObj.values && replyObj.values[0] ? (replyObj.values[0].value || replyObj.values[0]) : "");
            } else {
                replyStr = args[0];
            }
            try {
                var json = JSON.parse(replyStr);
                if (json.status === "error" || json.error) {
                    console.error("PlasmaLLM DriverManager: command reported error:", json.message || json.error || "Unknown error");
                    callback(json.message || json.error || "Unknown error");
                } else {
                    if (json.status === "success") {
                        if (json.operating_context_uuid !== undefined) {
                            activeContextUuid = json.operating_context_uuid;
                        }
                        var wins = json.windows_summary || json.windows;
                        if (wins !== undefined) {
                            openWindowsList = wins;
                        }
                    }
                    callback(null, json);
                }
            } catch(e) {
                console.error("PlasmaLLM DriverManager: JSON parse error:", e.message, "raw response args:", JSON.stringify(args));
                callback("Failed to parse driver response: " + e.message + "\nRaw: " + JSON.stringify(args));
            }
        }
    }, function(err) {
        if (callback) callback({error: "DBus Error: " + err.message});
    });
}

function checkDriverSession(callback, keepTokenIfInactive) {
    if (!dbusBus) {
        if (!keepTokenIfInactive) {
            isSessionActive = false;
            token = "";
        }
        if (callback) callback(false);
        return;
    }
    if (token === "") {
        if (!keepTokenIfInactive) {
            isSessionActive = false;
        }
        if (callback) callback(false);
        return;
    }
    if (!isSessionActive && !keepTokenIfInactive) {
        if (callback) callback(false);
        return;
    }
    dbusBus.asyncCall({
        service: "com.joshuaroman.plasmallm.DesktopDriver",
        path: "/com/joshuaroman/plasmallm/DesktopDriver",
        iface: "com.joshuaroman.plasmallm.DesktopDriver",
        member: "IsSessionActive",
        arguments: []
    }, function() {
        var args = Array.prototype.slice.call(arguments);
        var active = false;
        if (args.length > 0 && args[0] !== null && typeof args[0] === 'object') {
            var replyObj = args[0];
            if (replyObj.isError) {
                if (!keepTokenIfInactive) {
                    isSessionActive = false;
                    token = "";
                }
                if (callback) callback(false);
                return;
            }
            if (replyObj.values && replyObj.values.length > 0) {
                active = replyObj.values[0].value || replyObj.values[0];
            } else if (replyObj.value !== undefined) {
                active = replyObj.value;
            }
        } else if (args.length === 1 && Array.isArray(args[0])) {
            active = args[0][0];
        } else if (args.length > 0) {
            active = args[0];
        }
        
        var isAct = (active === true || active === "true");
        if (isAct) {
            isSessionActive = true;
        } else {
            if (!keepTokenIfInactive) {
                isSessionActive = false;
                token = "";
            }
        }
        if (callback) callback(isAct);
    }, function(err) {
        if (!keepTokenIfInactive) {
            isSessionActive = false;
            token = "";
        }
        if (callback) callback(false);
    });
}

// NOTE: The string below uses template literals (backticks). Any internal markdown backticks MUST be escaped as \` to avoid syntax errors in the QML JS engine.
function getDrivingInstructions() {
    if (!isSessionActive) return "";
    return `
## Desktop Automation
Interact with the user's desktop (0-1000 coordinate scale).

### COORDINATES
1. **Coordinate Scale**: All coordinates are normalized on a scale from 0 to 1000.
   - \`(0, 0)\` is the Top-Left corner.
   - \`(1000, 1000)\` is the Bottom-Right corner.
   - \`(500, 500)\` is the Exact Center.
2. **Operating Context**: After calling \`DesktopSetOperatingContext\`, coordinates (0-1000) shift entirely relative to the target window:
   - \`nx=0\` is Left edge, \`nx=500\` is Center, \`nx=1000\` is Right edge.
   - \`ny=0\` is Top edge, \`ny=500\` is Center, \`ny=1000\` is Bottom edge.
3. **Requirement**: You MUST always specify both \`nx\` and \`ny\` coordinates for mouse actions. Do not omit them, and do not use any other coordinate keys.

### WORKSPACE OBSERVATION & CONTEXT
- **Get Desktop State**: Call \`DesktopGetState\` to retrieve a visual screenshot and the simplified textual accessibility tree of interactive elements (buttons, inputs, links, tabs).
- **Set Operating Context**: If you are focused on a single application window (e.g. driving a web browser or text editor), you MUST call \`DesktopSetOperatingContext(uuid=...)\`. This:
  1. Filters subsequent accessibility tree nodes to just that window.
  2. Crops visual screenshot feedback to just that window.
  3. Maps all coordinates relative to the window's geometry. Clicks and movements will automatically adapt if the window is resized or relocated by the user.
- **Global Context**: Call \`DesktopResetContext\` to clear the window focus boundaries and return to the global full-screen mode.

### WINDOWS & SCROLLING CONTROL
- **Window Management**: Call \`DesktopWindowControl(uuid=..., action=...)\` to focus/restore, minimize, maximize, close, or resize/reposition windows.
- **Scrolling**: Call \`DesktopScroll(direction=...)\` to scroll pages or scrollable areas. Provide coordinates \`nx\` and \`ny\` to hover over the target scroll container first.

### RETRIEVING TEXT SELECTION
- **Read selection**: To inspect highlighted text on the screen, call \`DesktopReadSelection\` which executes a copy keystroke sequence and reads the clipboard buffer back in a single turn.

### VISUAL REASONING & OBSERVE MANDATE
In your response/thoughts before calling any tool, explicitly write:
1. **High-Level Plan**: Overall sequence of steps to achieve the goal.
2. **Screen Analysis**: Active windows, applications, visible menus, buttons, fields, labels, and their coordinates.
3. **Intent**: The exact next objective.
4. **Path Verification**: Why you chose the coordinates/tool. Check math against edge rulers.
5. **Comparison**: The changes between previous and current screen state.

### INPUT SAFETY
- **No key appending**: Use 'fill_text' / 'type' for literal text only. Do not add '\\n' or '<enter>'.
- **Submission**: Type text first, then call \`DesktopInput\` with \`action="press", key="enter"\`.
- **Keyboard shortcuts**: \`DesktopInput(action="press", key="...")\` does not require moving the mouse first.

### ESCAPE HATCH (CANCEL ACTION)
If you realize while generating your arguments that you chose the wrong coordinates, include the exact string \`__CANCEL__\` anywhere in your text to safely abort the action.

### REQUIRED THINKING PARAMETERS
When calling any tool, you must include these parameters:
- \`observation\`: What you see on the screen.
- \`pending_tasks\`: What remains to be done.
- \`planned_actions\`: Specific next actions.
`;
}
