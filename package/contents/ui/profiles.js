.pragma library

/**
 * Profile schema:
 * {
 *   id: string,
 *   name: string,
 *   apiType: string,
 *   apiEndpoint: string,
 *   providerName: string,
 *   modelName: string,
 *   usesResponsesAPI: bool,
 *   temperature: int,
 *   maxTokens: int,
 *   reasoningEffort: string,
 *   thinkingBudget: int,
 *   showThoughts: bool,
 *   geminiApiVariant: string,
 *   geminiAuthMethod: string,
 *   geminiVertexAuthType: string,
 *   geminiProjectId: string,
 *   geminiLocation: string,
 *   openaiLastProvider: string,
 *   openaiLastEndpoint: string,
 *   enableNativeGoogleSearch: bool,
 *   enableNativeCodeExecution: bool,
 *   systemPrompt: string
 * }
 */

// Default system prompt template. Mirrors package/contents/config/main.xml and
// api.js. main.qml calls setDefaultSystemPromptTemplate(Api.DEFAULT_SYSTEM_PROMPT_TEMPLATE)
// at startup so the two can never drift.
var defaultSystemPromptTemplate = "You are a helpful assistant embedded in the user's Linux desktop.\n" +
    "\n" +
    "## System\n" +
    "{{system_info}}\n" +
    "\n" +
    "General-purpose assistant. Keep responses short (~1 paragraph) unless more detail is needed to properly answer. Be concise and conversational. Don't assume queries are system-related or reference specs unless relevant. " +
    "Always use the `~` alias instead of absolute paths when referring to the user's home directory in tool calls or text.\n" +
    "\n" +
    "{{session_multiplexer}}\n" +
    "{{approval_mode}}\n" +
    "{{tools}}\n" +
    "{{driving_instructions}}";

function setDefaultSystemPromptTemplate(tpl) {
    if (tpl && String(tpl).trim().length > 0)
        defaultSystemPromptTemplate = String(tpl);
}

function systemPromptTemplateDefault() {
    return defaultSystemPromptTemplate;
}

const PROFILE_FIELDS = [
    "apiType", "apiEndpoint", "providerName", "modelName", "usesResponsesAPI",
    "temperature", "maxTokens", "reasoningEffort", "thinkingBudget", "showThoughts",
    "geminiApiVariant", "geminiAuthMethod", "geminiVertexAuthType", "geminiProjectId",
    "geminiLocation", "openaiLastProvider", "openaiLastEndpoint",
    "enableNativeGoogleSearch", "enableNativeCodeExecution",
    "systemPrompt", "localizeSystemPrompt",
    "useCommandTool", "autoRunCommands", "autoShareCommandOutput",
    "enableWebSearch", "webSearchProvider", "searxngUrl", "exaSearchType",
    "enableTools", "enableDesktopAutomation",
    "toolsReadFileEnabled", "toolsReadFileAutoRun",
    "toolsWriteFileEnabled", "toolsWriteFileAutoRun",
    "toolsListDirEnabled", "toolsListDirAutoRun",
    "toolsHttpGetEnabled", "toolsHttpGetAutoRun",
    "toolsHttpRequestEnabled", "toolsHttpRequestAutoRun",
    "toolsSearchFilesEnabled", "toolsSearchFilesAutoRun",
    "toolsGetClipboardEnabled", "toolsGetClipboardAutoRun",
    "toolsSetClipboardEnabled", "toolsSetClipboardAutoRun",
    "toolsNotifyEnabled", "toolsNotifyAutoRun",
    "toolsOpenUrlEnabled", "toolsOpenUrlAutoRun",
    "toolsPathWhitelist",
    "toolsReadMaxBytes", "toolsWriteMaxBytes", "toolsHttpMaxBytes",
    "toolsInstructions",
    "tasks", "customTools",
    "compactionEnabled", "compactionProfileId", "compactionTriggerMode",
    "compactionThresholdChars", "compactionThresholdTurns", "compactionKeepRecentTurns", "compactionInstructions"
];

// Defaults mirror package/contents/config/main.xml so incomplete profiles
// never leave sticky values from the previously-active profile.
const PROFILE_DEFAULTS = {
    apiType: "openai",
    apiEndpoint: "http://localhost:11434/v1",
    providerName: "",
    modelName: "",
    usesResponsesAPI: false,
    temperature: 70,
    maxTokens: 2048,
    reasoningEffort: "off",
    thinkingBudget: 4096,
    showThoughts: true,
    geminiApiVariant: "legacy",
    geminiAuthMethod: "aistudio",
    geminiVertexAuthType: "apikey",
    geminiProjectId: "",
    geminiLocation: "global",
    openaiLastProvider: "",
    openaiLastEndpoint: "",
    enableNativeGoogleSearch: false,
    enableNativeCodeExecution: false,
    localizeSystemPrompt: false,
    useCommandTool: true,
    autoRunCommands: false,
    autoShareCommandOutput: false,
    enableWebSearch: false,
    webSearchProvider: "ollama",
    searxngUrl: "",
    exaSearchType: "auto",
    enableTools: true,
    enableDesktopAutomation: false,
    toolsReadFileEnabled: true,
    toolsReadFileAutoRun: false,
    toolsWriteFileEnabled: true,
    toolsWriteFileAutoRun: false,
    toolsListDirEnabled: true,
    toolsListDirAutoRun: false,
    toolsHttpGetEnabled: true,
    toolsHttpGetAutoRun: false,
    toolsHttpRequestEnabled: true,
    toolsHttpRequestAutoRun: false,
    toolsSearchFilesEnabled: true,
    toolsSearchFilesAutoRun: false,
    toolsGetClipboardEnabled: true,
    toolsGetClipboardAutoRun: false,
    toolsSetClipboardEnabled: true,
    toolsSetClipboardAutoRun: false,
    toolsNotifyEnabled: true,
    toolsNotifyAutoRun: false,
    toolsOpenUrlEnabled: true,
    toolsOpenUrlAutoRun: false,
    toolsPathWhitelist: '["$HOME"]',
    toolsReadMaxBytes: 204800,
    toolsWriteMaxBytes: 1048576,
    toolsHttpMaxBytes: 524288,
    toolsInstructions: "{}",
    tasks: "",
    customTools: '[{"name":"echo","description":"Echoes back the message provided.","commandTemplate":"echo {message}","requireSuperuser":false,"autoRun":false}]',
    compactionEnabled: false,
    compactionProfileId: "active",
    compactionTriggerMode: "chars",
    compactionThresholdChars: 20000,
    compactionThresholdTurns: 2,
    compactionKeepRecentTurns: 4,
    compactionInstructions: "Summarize this conversation. Be very concise and use shorthand and abbreviations when possible. No prose. Retain important specifics when brief. For larger specifics like logs, use of restore_context/recall_attachment tool will work instead. Cite every item with a msgId or msgId range, e.g. [1], [3-6], [2,7-10]\n\nWhen a previous compaction exists, use it as a starting point. Be conservative about removing things; update and merge new information rather than discarding established context unless subsequent messages prove it entirely out of scope. Always persist all attached files across compaction cycles.\n\nStructure:\n# Key Topics\n<...>\n# User Goals\n<...>\n# Agent Goals\n<...>\n# Decisions\n<...>\n# Current Status\n<...>\n# Attachments\n- example.txt - brief description of its contents [msgId]"
};

// Live getter so PROFILE_DEFAULTS always mirrors the current default template
// even after main.qml syncs it from Api.DEFAULT_SYSTEM_PROMPT_TEMPLATE.
Object.defineProperty(PROFILE_DEFAULTS, "systemPrompt", {
    get: function() { return systemPromptTemplateDefault(); },
    enumerable: true,
    configurable: true
});

function fieldValue(profile, field) {
    if (profile && profile[field] !== undefined)
        return profile[field];
    if (PROFILE_DEFAULTS.hasOwnProperty(field))
        return PROFILE_DEFAULTS[field];
    return undefined;
}

function loadProfilesRaw(raw) {
    if (!raw) return [];
    try {
        return JSON.parse(raw);
    } catch (e) {
        console.error("Failed to parse profiles JSON:", e);
        return [];
    }
}

function loadProfiles(config) {
    return loadProfilesRaw(config.profiles);
}

function saveProfiles(config, profiles) {
    config.profiles = JSON.stringify(profiles);
}

function getActive(profiles, activeId) {
    if (!profiles || !Array.isArray(profiles)) return null;
    return profiles.find(p => p.id === activeId) || null;
}

function generateId() {
    return "p_" + Math.random().toString(36).substring(2, 11);
}

function createProfile(name, seed = {}) {
    let p = {
        id: generateId(),
        name: name
    };
    PROFILE_FIELDS.forEach(f => {
        if (seed[f] !== undefined) {
            p[f] = seed[f];
        } else if (seed["cfg_" + f] !== undefined) {
            p[f] = seed["cfg_" + f];
        } else if (PROFILE_DEFAULTS.hasOwnProperty(f)) {
            p[f] = PROFILE_DEFAULTS[f];
        }
    });
    return p;
}

function duplicateProfile(profile, newName) {
    let p = JSON.parse(JSON.stringify(profile));
    p.id = generateId();
    p.name = newName;
    // Ensure duplicated profile has every field so apply never leaves gaps.
    PROFILE_FIELDS.forEach(f => {
        if (p[f] === undefined && PROFILE_DEFAULTS.hasOwnProperty(f))
            p[f] = PROFILE_DEFAULTS[f];
    });
    return p;
}

/**
 * Writes profile fields onto top-level Plasmoid.configuration.
 * Always writes every PROFILE_FIELDS entry (profile value or default) so
 * switching profiles never leaves sticky params from the previous profile.
 * Does NOT update activeProfileId or the profiles blob.
 */
function applyToConfig(profile, config) {
    if (!profile) return;
    PROFILE_FIELDS.forEach(f => {
        var v = fieldValue(profile, f);
        if (v !== undefined)
            config[f] = v;
    });
}

function applyToKCM(profile, page) {
    if (!profile) return;
    PROFILE_FIELDS.forEach(f => {
        var v = fieldValue(profile, f);
        if (v !== undefined)
            page["cfg_" + f] = v;
    });
}

/**
 * Reads top-level fields from Plasmoid.configuration into a profile object.
 * Returns a new profile object with the updated fields. Always writes every
 * PROFILE_FIELDS entry so the blob stays complete.
 */
function captureFromConfig(profile, config) {
    if (!profile) return null;
    let p = JSON.parse(JSON.stringify(profile));
    PROFILE_FIELDS.forEach(f => {
        if (config[f] !== undefined) {
            p[f] = config[f];
        } else if (p[f] === undefined && PROFILE_DEFAULTS.hasOwnProperty(f)) {
            p[f] = PROFILE_DEFAULTS[f];
        }
    });
    return p;
}

function captureFromKCM(profile, page) {
    if (!profile) return null;
    let p = JSON.parse(JSON.stringify(profile));
    PROFILE_FIELDS.forEach(f => {
        if (page["cfg_" + f] !== undefined) {
            p[f] = page["cfg_" + f];
        } else if (p[f] === undefined && PROFILE_DEFAULTS.hasOwnProperty(f)) {
            p[f] = PROFILE_DEFAULTS[f];
        }
    });
    return p;
}

function setActive(profiles, id) {
    if (!profiles || !Array.isArray(profiles)) return id;
    if (profiles.find(p => p.id === id)) return id;
    if (profiles.length > 0) return profiles[0].id;
    return "";
}

function renameProfile(profiles, id, newName) {
    let p = profiles.find(p => p.id === id);
    if (p) p.name = newName;
    return profiles;
}

function deleteProfile(profiles, id) {
    return profiles.filter(p => p.id !== id);
}

/** Backfill missing PROFILE_FIELDS on every profile with defaults. */
function backfillProfiles(profiles) {
    if (!profiles || !Array.isArray(profiles)) return profiles || [];
    profiles.forEach(p => {
        PROFILE_FIELDS.forEach(f => {
            if (p[f] === undefined && PROFILE_DEFAULTS.hasOwnProperty(f))
                p[f] = PROFILE_DEFAULTS[f];
        });
    });
    return profiles;
}
