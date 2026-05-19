
const Profiles = {
    PROFILE_FIELDS: [
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
    ],
    loadProfiles: (config) => JSON.parse(config.profiles || "[]"),
    saveProfiles: (config, profiles) => { config.profiles = JSON.stringify(profiles); }
};

const ToolManager = {
    getCustomTools: (config) => JSON.parse(config.customTools || "[]")
};

function runMigration(Plasmoid) {
    // Migration: v2 -> v3 (Tools Overhaul)
    if (Plasmoid.configuration.profilesSchemaVersion === 2) {
        var profiles = Profiles.loadProfiles(Plasmoid.configuration);
        var toolPrefixes = [
            "ReadFile", "WriteFile", "ListDir", "HttpGet", "HttpRequest", 
            "SearchFiles", "GetClipboard", "SetClipboard", "Notify", "OpenUrl"
        ];
        
        profiles.forEach(p => {
            p.enableTools = true;
            p.useCommandTool = true;
            p.autoRunCommands = false;
            
            toolPrefixes.forEach(prefix => {
                p["tools" + prefix + "Enabled"] = true;
                p["tools" + prefix + "AutoRun"] = false;
            });
            
            if (p.customTools) {
                try {
                    var ct = typeof p.customTools === "string" ? JSON.parse(p.customTools) : p.customTools;
                    if (Array.isArray(ct)) {
                        ct.forEach(tool => { tool.autoRun = false; });
                        p.customTools = (typeof p.customTools === "string") ? JSON.stringify(ct) : ct;
                    }
                } catch(e) {}
            }
        });
        Profiles.saveProfiles(Plasmoid.configuration, profiles);
        
        // Also update global config
        Plasmoid.configuration.enableTools = true;
        Plasmoid.configuration.useCommandTool = true;
        Plasmoid.configuration.autoRunCommands = false;
        toolPrefixes.forEach(prefix => {
            Plasmoid.configuration["tools" + prefix + "Enabled"] = true;
            Plasmoid.configuration["tools" + prefix + "AutoRun"] = false;
        });
        
        var ctGlobal = ToolManager.getCustomTools(Plasmoid.configuration);
        ctGlobal.forEach(tool => { tool.autoRun = false; });
        Plasmoid.configuration.customTools = JSON.stringify(ctGlobal);

        Plasmoid.configuration.profilesSchemaVersion = 3;
    }
}

// Test cases
const Plasmoid = {
    configuration: {
        profilesSchemaVersion: 2,
        enableTools: false,
        enableWebSearch: false,
        autoRunCommands: true,
        profiles: JSON.stringify([
            { id: "p1", name: "Profile 1", enableTools: false, enableWebSearch: false, autoRunCommands: true },
            { id: "p2", name: "Profile 2", enableTools: true, enableWebSearch: true, autoRunCommands: true }
        ]),
        customTools: JSON.stringify([{ name: "echo", autoRun: true }])
    }
};

console.log("Before migration:", JSON.stringify(Plasmoid.configuration, null, 2));
runMigration(Plasmoid);
console.log("After migration:", JSON.stringify(Plasmoid.configuration, null, 2));

// Assertions
const config = Plasmoid.configuration;
const profiles = JSON.parse(config.profiles);

if (config.enableTools !== true) throw new Error("Global enableTools should be true");
if (config.autoRunCommands !== false) throw new Error("Global autoRunCommands should be false");
if (config.profilesSchemaVersion !== 3) throw new Error("profilesSchemaVersion should be 3");

profiles.forEach(p => {
    if (p.enableTools !== true) throw new Error(`Profile ${p.id} enableTools should be true`);
    if (p.autoRunCommands !== false) throw new Error(`Profile ${p.id} autoRunCommands should be false`);
    if (p.id === "p1" && p.enableWebSearch !== false) throw new Error(`Profile ${p.id} enableWebSearch should be preserved as false`);
    if (p.id === "p2" && p.enableWebSearch !== true) throw new Error(`Profile ${p.id} enableWebSearch should be preserved as true`);
    if (p.toolsReadFileEnabled !== true) throw new Error(`Profile ${p.id} toolsReadFileEnabled should be true`);
    if (p.toolsReadFileAutoRun !== false) throw new Error(`Profile ${p.id} toolsReadFileAutoRun should be false`);
});

const ct = JSON.parse(config.customTools);
if (ct[0].autoRun !== false) throw new Error("Custom tool autoRun should be false");

console.log("Migration test passed!");
