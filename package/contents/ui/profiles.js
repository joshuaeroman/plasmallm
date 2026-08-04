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
 *   enableNativeCodeExecution: bool
 * }
 */

const PROFILE_FIELDS = [
    "apiType", "apiEndpoint", "providerName", "modelName", "usesResponsesAPI",
    "temperature", "maxTokens", "reasoningEffort", "thinkingBudget", "showThoughts",
    "geminiApiVariant", "geminiAuthMethod", "geminiVertexAuthType", "geminiProjectId",
    "geminiLocation", "openaiLastProvider", "openaiLastEndpoint",
    "enableNativeGoogleSearch", "enableNativeCodeExecution",
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
    "tasks", "customTools"
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
    tasks: "",
    customTools: '[{"name":"echo","description":"Echoes back the message provided.","commandTemplate":"echo {message}","requireSuperuser":false,"autoRun":false}]'
};

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
