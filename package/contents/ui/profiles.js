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
    "enableWebSearch", "webSearchProvider", "searxngUrl",
    "enableTools",
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
        }
    });
    return p;
}

function duplicateProfile(profile, newName) {
    let p = JSON.parse(JSON.stringify(profile));
    p.id = generateId();
    p.name = newName;
    return p;
}

/**
 * Writes profile fields onto top-level Plasmoid.configuration.
 * Does NOT update activeProfileId or the profiles blob.
 */
function applyToConfig(profile, config) {
    if (!profile) return;
    PROFILE_FIELDS.forEach(f => {
        if (profile[f] !== undefined) {
            config[f] = profile[f];
        }
    });
}

function applyToKCM(profile, page) {
    if (!profile) return;
    PROFILE_FIELDS.forEach(f => {
        if (profile[f] !== undefined) {
            page["cfg_" + f] = profile[f];
        }
    });
}

/**
 * Reads top-level fields from Plasmoid.configuration into a profile object.
 * Returns a new profile object with the updated fields.
 */
function captureFromConfig(profile, config) {
    if (!profile) return null;
    let p = JSON.parse(JSON.stringify(profile));
    PROFILE_FIELDS.forEach(f => {
        if (config[f] !== undefined) {
            p[f] = config[f];
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
