/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

.import "tools/index.js" as ToolRegistry
.import "driverManager.js" as DriverManager

var TOOLS = {};

function formatToolDisplayName(name) {
    if (!name) return "";
    var words = name.split('_');
    for (var i = 0; i < words.length; i++) {
        var w = words[i];
        if (w === "http") w = "HTTP";
        else if (w === "url") w = "URL";
        else if (w === "dir") w = "Directory";
        else w = w.charAt(0).toUpperCase() + w.slice(1);
        words[i] = w;
    }
    return words.join(' ');
}

// Initialize TOOLS from registry to maintain backward compatibility
function _init() {
    var all = ToolRegistry.getAllTools();
    for (var i = 0; i < all.length; i++) {
        var t = all[i];
        TOOLS[t.name] = {
            name: t.name,
            displayName: t.displayName || formatToolDisplayName(t.name),
            description: t.description,
            longDescription: t.longDescription || t.description,
            parameters: t.parameters,
            sandboxed: t.sandboxed,
            sideEffect: t.sideEffect,
            outputScheme: t.outputScheme
        };
    }
}
_init();

var _customToolsCache = null;
var _lastCustomToolsJson = "";

function getCustomTools(config) {
    if (!config || !config.customTools) return [];
    
    // If it's already an array (e.g. if the QML engine auto-parsed it)
    if (Array.isArray(config.customTools)) {
        return config.customTools;
    }

    // If it's a string, try to parse it
    if (typeof config.customTools === "string") {
        if (config.customTools === _lastCustomToolsJson && _customToolsCache) {
            return _customToolsCache;
        }

        try {
            var parsed = JSON.parse(config.customTools);
            if (Array.isArray(parsed)) {
                _lastCustomToolsJson = config.customTools;
                _customToolsCache = parsed;
                return parsed;
            }
        } catch(e) {
            console.warn("PlasmaLLM: Failed to parse customTools JSON:", e);
        }
    }
    
    return [];
}

function parseTemplateParameters(template) {
    var re = /\{([^}]+)\}/g;
    var params = [];
    var match;
    while ((match = re.exec(template)) !== null) {
        if (params.indexOf(match[1]) === -1) {
            params.push(match[1]);
        }
    }
    return params;
}

function buildCustomScriptTool(scriptDef) {
    var params = parseTemplateParameters(scriptDef.commandTemplate || "");
    var schema = {
        type: "object",
        properties: {
            justification: { 
                type: "string", 
                description: "A brief 1 sentence justification for why you are trying to run this command." 
            }
        },
        required: ["justification"]
    };
    for (var i = 0; i < params.length; i++) {
        schema.properties[params[i]] = { type: "string" };
        schema.required.push(params[i]);
    }
    
    function escapeShellArg(arg) {
        return "'" + String(arg).replace(/'/g, "'\\''") + "'";
    }

    return {
        name: scriptDef.name,
        displayName: scriptDef.name,
        description: scriptDef.description,
        parameters: schema,
        sideEffect: true,
        sandboxed: false,
        execute: function(args, context) {
            var cmd = scriptDef.commandTemplate || "";
            for (var i = 0; i < params.length; i++) {
                var val = args[params[i]] !== undefined ? args[params[i]] : "";
                var escaped = escapeShellArg(val);
                cmd = cmd.replace(new RegExp("\\{" + params[i] + "\\}", "g"), escaped);
            }
            if (scriptDef.requireSuperuser) {
                cmd = "pkexec " + cmd;
            }
            context.exec(cmd, scriptDef.name, args);
        }
    };
}

function getTool(name, config) {
    var t = ToolRegistry.getTool(name);
    if (t) return t;
    if (config) {
        var custom = getCustomTools(config);
        for (var i = 0; i < custom.length; i++) {
            if (custom[i].name === name) {
                return buildCustomScriptTool(custom[i]);
            }
        }
    }
    return null;
}

function isTool(name, config) {
    if (TOOLS[name]) return true;
    if (config) {
        var custom = getCustomTools(config);
        for (var i = 0; i < custom.length; i++) {
            if (custom[i].name === name) {
                return true;
            }
        }
    }
    return false;
}

function getToolMetadata(name, config) {
    var t = TOOLS[name];
    if (t) return t;
    if (config) {
        var custom = getCustomTools(config);
        for (var i = 0; i < custom.length; i++) {
            if (custom[i].name === name) {
                var built = buildCustomScriptTool(custom[i]);
                return {
                    name: built.name,
                    displayName: built.displayName,
                    description: built.description,
                    longDescription: built.longDescription || built.description,
                    parameters: built.parameters,
                    sandboxed: built.sandboxed,
                    sideEffect: built.sideEffect,
                    outputScheme: built.outputScheme
                };
            }
        }
    }
    return null;
}

function getToolConfigUI(name) {
    return ToolRegistry.getToolConfigUI(name);
}

function getEnabledTools(config) {
    if (!config || !config.enableTools) return [];

    if (config.enableDesktopAutomation && DriverManager.isSessionActive) {
        var activeTools = [];
        if (config.useCommandTool) {
            activeTools.push("run_command");
        }
        activeTools.push("DesktopGetState");
        activeTools.push("DesktopSetOperatingContext");
        activeTools.push("DesktopResetContext");
        activeTools.push("DesktopScroll");
        activeTools.push("DesktopClick");
        activeTools.push("DesktopInput");
        activeTools.push("DesktopMoveMouse");
        activeTools.push("DesktopWindowControl");
        activeTools.push("DesktopReadSelection");
        return activeTools;
    }

    var enabled = [];

    var custom = getCustomTools(config);
    for (var i = 0; i < custom.length; i++) {
        enabled.push(custom[i].name);
    }

    if (config.useCommandTool) enabled.push("run_command");
    if (config.enableWebSearch && config.searchConfigured) enabled.push("web_search");
    if (config.toolsReadFileEnabled) enabled.push("read_file");
    if (config.toolsWriteFileEnabled) enabled.push("write_file");
    if (config.toolsListDirEnabled) enabled.push("list_dir");
    if (config.toolsHttpGetEnabled) enabled.push("http_get");
    if (config.toolsHttpRequestEnabled) enabled.push("http_request");
    if (config.toolsSearchFilesEnabled) enabled.push("search_files");
    if (config.toolsGetClipboardEnabled) enabled.push("get_clipboard");
    if (config.toolsSetClipboardEnabled) enabled.push("set_clipboard");
    if (config.toolsNotifyEnabled) enabled.push("notify");
    if (config.toolsOpenUrlEnabled) enabled.push("open_url");

    if (config.enableDesktopAutomation) {
        enabled.push("StartSession");
    }
    
    return enabled;
}

function isAutoRun(toolId, config) {
    if (config && config.sessionFullAutoMode) {
        return true;
    }
    if (config && config.sessionAutoMode) {
        if (toolId === "DesktopGetState" ||
            toolId === "DesktopSetOperatingContext" ||
            toolId === "DesktopResetContext" ||
            toolId === "DesktopScroll" ||
            toolId === "DesktopClick" ||
            toolId === "DesktopInput" ||
            toolId === "DesktopMoveMouse" ||
            toolId === "DesktopWindowControl" ||
            toolId === "DesktopReadSelection" ||
            toolId === "StartSession") {
            return true;
        }
    }
    switch (toolId) {
        case "web_search": return true;
        case "run_command": return config.autoRunCommands;
        case "read_file": return config.toolsReadFileAutoRun;
        case "write_file": return config.toolsWriteFileAutoRun;
        case "list_dir": return config.toolsListDirAutoRun;
        case "http_get": return config.toolsHttpGetAutoRun;
        case "http_request": return config.toolsHttpRequestAutoRun;
        case "search_files": return config.toolsSearchFilesAutoRun;
        case "get_clipboard": return config.toolsGetClipboardAutoRun;
        case "set_clipboard": return config.toolsSetClipboardAutoRun;
        case "notify": return config.toolsNotifyAutoRun;
        case "open_url": return config.toolsOpenUrlAutoRun;
    }
    var custom = getCustomTools(config);
    for (var i = 0; i < custom.length; i++) {
        if (custom[i].name === toolId) {
            return custom[i].autoRun === true;
        }
    }
    return false;
}

function getEnabledToolsMetadata(config) {
    var metadata = [];
    var enabled = getEnabledTools(config);
    for (var i = 0; i < enabled.length; i++) {
        var id = enabled[i];
        var meta = getToolMetadata(id, config);
        if (meta) {
            metadata.push(meta);
        }
    }
    return metadata;
}

function buildToolSchemas(config) {
    var schemas = [];
    var enabled = getEnabledTools(config);
    for (var i = 0; i < enabled.length; i++) {
        var toolId = enabled[i];
        var meta = getToolMetadata(toolId, config);
        if (meta) {
            schemas.push({
                type: "function",
                "function": {
                    name: meta.name,
                    description: meta.description,
                    parameters: meta.parameters
                }
            });
        }
    }
    return schemas;
}

function buildSystemPromptSection(config) {
    var enabled = getEnabledTools(config);
    if (enabled.length === 0) return "";

    var section = "\n## Tools\n";
    section += "The user has pre-authorized you to use the following tools. You can call them directly without asking for permission; the user has explicitly enabled each one.\n\n";
    section += "Auto-run tools execute immediately and return their result to you. Non-auto-run tools will pause for user approval before executing — you should still call them freely, the user will approve interactively.\n\n";
    section += "Enabled tools:\n";

    for (var i = 0; i < enabled.length; i++) {
        var id = enabled[i];
        var tool = getToolMetadata(id, config);
        if (!tool) continue;
        var auto = isAutoRun(id, config);
        var status = auto ? "auto-run" : "requires approval";
        
        var details = "";
        if (tool.sandboxed) {
            var whitelist = [];
            try {
                whitelist = JSON.parse(config.toolsPathWhitelist || "[]");
            } catch(e) {
                whitelist = [config.toolsPathWhitelist];
            }
            var whitelistStr = whitelist.join(", ");
            details = ". Access restricted to: " + whitelistStr;
        }
        if (id === "read_file") details += ". Max " + (config.toolsReadMaxBytes || 204800) + " bytes";
        if (id === "write_file") details += ". Max " + (config.toolsWriteMaxBytes || 1048576) + " bytes";
        if (id === "http_get" || id === "http_request") details += ". Max " + (config.toolsHttpMaxBytes || 524288) + " bytes response";

        section += "- " + tool.name + " (" + status + "): " + tool.longDescription + details + "\n";
    }
    
    section += "\n### Command Guidelines\n" +
        "When using tools that execute shell commands (like `run_command` or certain custom tools):\n" +
        "- Use `pkexec` instead of `sudo` for superuser privileges.\n" +
        "- Chain steps with `&&`.\n" +
        "- Use `kdialog` for user prompts; commands run non-interactively.\n" +
        "- NEVER install packages or modify system configuration without explicit user permission asked in plain text.\n" +
        "- For auto-run tools: Be conservative and prefer read-only commands. If an action is potentially disruptive, describe it in plain text and wait for explicit user approval before calling the tool.\n";

    return section;
}

function expandPath(path, paths) {
    if (!path) return "";
    var res = path;
    var home = paths.home || "";
    if (res.indexOf("~") === 0) {
        res = home + res.substring(1);
    } else if (res.indexOf("$HOME") === 0) {
        res = home + res.substring(5);
    } else if (res.indexOf("$XDG_DATA_HOME") === 0) {
        res = (paths.xdgData || (home + "/.local/share")) + res.substring(14);
    } else if (res.indexOf("$XDG_CONFIG_HOME") === 0) {
        res = (paths.xdgConfig || (home + "/.config")) + res.substring(16);
    } else if (res.indexOf("$XDG_CACHE_HOME") === 0) {
        res = (paths.xdgCache || (home + "/.cache")) + res.substring(15);
    } else if (res.indexOf("$XDG_RUNTIME_DIR") === 0) {
        res = (paths.xdgRuntime || "/tmp") + res.substring(16);
    }
    return res;
}

function contractPath(path, homePath) {
    if (!path || !homePath) return path;
    if (path === homePath) return "~";
    if (path.indexOf(homePath + "/") === 0) {
        return "~" + path.substring(homePath.length);
    }
    return path;
}

function contractAllPaths(text, homePath) {
    if (!text || !homePath) return text;
    var escapedHome = homePath.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    var re = new RegExp(escapedHome, 'g');
    return text.replace(re, "~");
}

function normalizePath(path) {
    if (!path) return "";
    var parts = path.split('/');
    var resolvedParts = [];
    var isAbsolute = path.charAt(0) === '/';
    
    for (var i = 0; i < parts.length; i++) {
        var part = parts[i];
        if (part === '.' || part === '') {
            continue;
        }
        if (part === '..') {
            if (resolvedParts.length > 0 && resolvedParts[resolvedParts.length - 1] !== '..') {
                resolvedParts.pop();
            } else if (!isAbsolute) {
                resolvedParts.push('..');
            }
        } else {
            resolvedParts.push(part);
        }
    }
    
    var prefix = isAbsolute ? "/" : "";
    return prefix + resolvedParts.join('/');
}

function isPathAllowed(path, whitelistStr, paths) {
    var expandedPath = expandPath(path, paths);
    expandedPath = normalizePath(expandedPath);
    expandedPath = expandedPath.replace(/\/+/g, "/").replace(/\/$/, "");
    if (!expandedPath) return false;
    
    var whitelist = [];
    try {
        whitelist = JSON.parse(whitelistStr || "[]");
    } catch(e) {
        whitelist = (whitelistStr || "").split("\n").filter(function(s) { return s.trim().length > 0; });
    }

    for (var i = 0; i < whitelist.length; i++) {
        var allowed = expandPath(whitelist[i].trim(), paths);
        allowed = normalizePath(allowed);
        allowed = allowed.replace(/\/+/g, "/").replace(/\/$/, "");
        if (!allowed) continue;

        if (expandedPath === allowed || expandedPath.indexOf(allowed + "/") === 0) {
            return true;
        }
    }
    return false;
}

