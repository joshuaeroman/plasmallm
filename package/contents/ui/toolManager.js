/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

.import "tools/index.js" as ToolRegistry
.import "driverManager.js" as DriverManager
.import "skills.js" as Skills

var TOOLS = {};

// Tools whose results stay expanded by default (rich formatted output or
// image payloads). An explicit entry in toolsCollapseResults overrides this.
var DEFAULT_EXPANDED_TOOLS = [
    "web_search",
    "StartSession",
    "DesktopGetState",
    "DesktopSetOperatingContext",
    "DesktopResetContext",
    "DesktopScroll",
    "DesktopClick",
    "DesktopInput",
    "DesktopMoveMouse",
    "DesktopWindowControl",
    "DesktopReadSelection"
];

function toolIconName(toolName) {
    switch (toolName) {
        case "run_command": return "utilities-terminal";
        case "web_search": return "browser-search";
        case "read_file": return "document-open";
        case "write_file": return "document-save";
        case "list_dir": return "folder-open";
        case "skill": return "applications-education";
        case "http_get": return "download";
        case "http_request": return "network-wired";
        case "search_files": return "system-search";
        case "get_clipboard": return "edit-paste";
        case "set_clipboard": return "edit-copy";
        case "notify": return "notifications";
        case "open_url": return "internet-services";
        case "edit_memory": return "document-edit";
    }
    return "services";
}

/** One-line descriptor for a finished tool result (icon label / collapsed pill). */
function resultLabel(toolName, args, home) {
    var label = toolName || "";
    args = args || {};
    home = home || "$HOME";
    if (args.path) {
        label += ": " + contractPath(args.path, home);
    } else if (args.url) {
        label += ": " + args.url;
    } else if (args.query) {
        label += ": " + args.query;
    } else if (args.command) {
        label += ": " + args.command;
    } else if (args.text) {
        label += ": " + args.text;
    } else if (args.target) {
        label += ": " + args.target;
    } else if (toolName === "skill" && args.name) {
        label += ": " + args.name;
    }
    return label;
}

/**
 * Whether a successful plain tool result should start collapsed as a small
 * pill. Precedence:
 *   1. explicit entry in the toolsCollapseResults JSON map ("what user says goes")
 *   2. a custom script tool's own collapseResult field
 *   3. defaults — collapsed for ordinary tools, expanded for DEFAULT_EXPANDED_TOOLS
 */
function parseCollapseMap(mapJson) {
    if (!mapJson) return {};
    try {
        var parsed = typeof mapJson === "string" ? JSON.parse(mapJson) : mapJson;
        return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : {};
    } catch (e) {
        return {};
    }
}

function shouldCollapseResult(toolName, collapseMapJson, customToolsJson) {
    if (!toolName) return false;
    var map = parseCollapseMap(collapseMapJson);
    if (map.hasOwnProperty(toolName)) return !!map[toolName];
    if (customToolsJson) {
        try {
            var customs = typeof customToolsJson === "string" ? JSON.parse(customToolsJson) : customToolsJson;
            if (Array.isArray(customs)) {
                for (var i = 0; i < customs.length; i++) {
                    if (customs[i] && customs[i].name === toolName && customs[i].collapseResult !== undefined) {
                        return !!customs[i].collapseResult;
                    }
                }
            }
        } catch (e) {}
    }
    for (var d = 0; d < DEFAULT_EXPANDED_TOOLS.length; d++) {
        if (DEFAULT_EXPANDED_TOOLS[d] === toolName) return false;
    }
    return true;
}

/** Writes one explicit preference into the collapse map and returns the JSON string. */
function setToolCollapsed(mapJson, toolName, collapsed) {
    var map = parseCollapseMap(mapJson);
    map[toolName] = !!collapsed;
    return JSON.stringify(map);
}

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
    if (config.skillsEnabled && config.toolsSkillEnabled) enabled.push("skill");
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
    if (config.toolsEditMemoryEnabled) enabled.push("edit_memory");
    if (config.compactionEnabled) {
        enabled.push("restore_context");
        enabled.push("recall_attachment");
    }

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
        case "restore_context": return true;
        case "recall_attachment": return true;
        case "skill": return config.toolsSkillAutoRun !== undefined ? config.toolsSkillAutoRun : true;
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
        case "edit_memory": return config.toolsEditMemoryAutoRun;
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
            // Advertise available skills inside the skill tool's schema
            // description so models see the list at tool-selection time. Clone first — meta may be the shared registry object, and
            // mutating it would leak XML into the settings UI and prompt text.
            if (config && config.skillsEnabled && id === "skill") {
                var clone = {};
                for (var k in meta) {
                    if (meta.hasOwnProperty(k)) clone[k] = meta[k];
                }
                clone.description = Skills.embedSkillsIndex(
                    meta.description,
                    Skills.filterEnabledSkills(config.loadedSkills || [], config.skillsDisabledList)
                );
                meta = clone;
            }
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

function getToolInstruction(name, config, i18nFn) {
    if (config && config.toolsInstructions) {
        try {
            var map = typeof config.toolsInstructions === "string" ? JSON.parse(config.toolsInstructions) : config.toolsInstructions;
            if (map && map[name] && typeof map[name] === "string" && map[name].trim().length > 0) {
                return map[name].trim();
            }
        } catch(e) {}
    }
    var tool = getToolMetadata(name, config);
    var raw = tool ? (tool.longDescription || tool.description || "") : "";
    if (config && config.localizeSystemPrompt && raw.length > 0) {
        return _tr(i18nFn, config, raw);
    }
    return raw;
}

function _tr(i18nFn, config, str) {
    var fn = (typeof i18nFn === "function") ? i18nFn : ((config && typeof config.i18n === "function") ? config.i18n : (typeof i18n === "function" ? i18n : null));
    if (fn) {
        var args = Array.prototype.slice.call(arguments, 2);
        return fn.apply(null, args);
    }
    var res = str;
    for (var i = 3; i < arguments.length; i++) {
        res = res.replace(new RegExp("%" + (i - 2), "g"), arguments[i]);
    }
    return res;
}

function buildSystemPromptSection(config, i18nFn) {
    var enabled = getEnabledTools(config);
    if (enabled.length === 0) return "";
    var loc = config && config.localizeSystemPrompt;

    var section = "\n## " + (loc ? _tr(i18nFn, config, "Tools") : "Tools") + "\n";
    section += (loc
        ? _tr(i18nFn, config, "The user has pre-authorized you to use the following tools. You can call them directly without asking for permission; the user has explicitly enabled each one.")
        : "The user has pre-authorized you to use the following tools. You can call them directly without asking for permission; the user has explicitly enabled each one.") + "\n\n";
    section += (loc
        ? _tr(i18nFn, config, "Auto-run tools execute immediately and return their result to you. Non-auto-run tools will pause for user approval before executing — you should still call them freely, the user will approve interactively.")
        : "Auto-run tools execute immediately and return their result to you. Non-auto-run tools will pause for user approval before executing — you should still call them freely, the user will approve interactively.") + "\n\n";
    section += (loc ? _tr(i18nFn, config, "Enabled tools:") : "Enabled tools:") + "\n";

    for (var i = 0; i < enabled.length; i++) {
        var id = enabled[i];
        var tool = getToolMetadata(id, config);
        if (!tool) continue;
        var auto = isAutoRun(id, config);
        var status = loc
            ? (auto ? _tr(i18nFn, config, "auto-run") : _tr(i18nFn, config, "requires approval"))
            : (auto ? "auto-run" : "requires approval");
        
        var details = "";
        if (tool.sandboxed) {
            var whitelist = [];
            try {
                whitelist = JSON.parse(config.toolsPathWhitelist || "[]");
            } catch(e) {
                whitelist = [config.toolsPathWhitelist];
            }
            var whitelistStr = whitelist.join(", ");
            details = loc ? _tr(i18nFn, config, ". Access restricted to: %1", whitelistStr) : (". Access restricted to: " + whitelistStr);
        }
        if (id === "read_file") {
            var readMax = config.toolsReadMaxBytes || 204800;
            details += loc ? _tr(i18nFn, config, ". Max %1 bytes", readMax) : (". Max " + readMax + " bytes");
        }
        if (id === "write_file") {
            var writeMax = config.toolsWriteMaxBytes || 1048576;
            details += loc ? _tr(i18nFn, config, ". Max %1 bytes", writeMax) : (". Max " + writeMax + " bytes");
        }
        if (id === "http_get" || id === "http_request") {
            var httpMax = config.toolsHttpMaxBytes || 524288;
            details += loc ? _tr(i18nFn, config, ". Max %1 bytes response", httpMax) : (". Max " + httpMax + " bytes response");
        }

        var instruction = getToolInstruction(id, config, i18nFn);
        section += "- " + tool.name + " (" + status + "): " + instruction + details + "\n";
    }

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

// Catalog strings for xgettext extraction of built-in tool descriptions.
function _toolDescriptionsCatalog() {
    return [
        i18n("Execute a shell command on the user's system and return its output. Guidelines:\n- Use `pkexec` instead of `sudo` for any command requiring superuser privileges.\n- Chain steps with `&&`.\n- Commands run non-interactively. Never use commands that wait for user input (like `read`).\n- Use `kdialog` if you need to prompt the user for input or show a message box (e.g., `kdialog --inputbox \"Prompt\"`).\n- NEVER install packages, modify system configuration, reboot, or take any action that alters the system or disrupts the user without explicit permission.\n- When permission is needed, ask the user in plain text first.\n- For auto-run tools: Be conservative and prefer read-only commands. If an action is potentially disruptive, describe it in plain text and wait for explicit user approval before calling the tool.\n- You MUST prefer other, more specific tools (like read_file, write_file, search_files, etc.) if they can accomplish the task. Only use this tool if no other tool is suitable."),
        i18n("Read the contents of a file at the specified path. Access is restricted to allowed directories."),
        i18n("Write content to a file at the specified path. Access is restricted to allowed directories."),
        i18n("List the contents of a directory. Access is restricted to allowed directories."),
        i18n("Search for a pattern within files in a directory (recursive)."),
        i18n("Perform an HTTP GET request to a URL and return the response content."),
        i18n("Perform an HTTP request (POST, PUT, etc.) to a URL."),
        i18n("Get the current content of the system clipboard."),
        i18n("Set the content of the system clipboard."),
        i18n("Show a system notification."),
        i18n("Open a URL in the default application (e.g., web browser)."),
        i18n("Perform a web search to find current information, news, or specific facts."),
        i18n("Restore the full verbatim text and tool outputs of previously compacted messages by specifying the start and end message IDs from a cited message range.")
    ];
}

