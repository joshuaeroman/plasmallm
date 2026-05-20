/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kcmutils
import "profiles.js" as Profiles

SimpleKCM {
    id: basePage
    
    readonly property var rootItem: basePage

    // Declared here because Plasma injects all cfg_ properties onto every config page.
    // By centralizing them in this base component, we avoid duplication and console warnings.

    property bool _switchingProfile: false
    property bool _initialized: false

    Component.onCompleted: {
        // Use a timer to ensure all child components have finished their own onCompleted
        // and any initial bindings have settled.
        Qt.callLater(() => { _initialized = true; });
    }

    Timer {
        id: captureDebounce
        interval: 250
        repeat: false
        onTriggered: {
            if (!_initialized || _switchingProfile) return;
            var profiles = Profiles.loadProfilesRaw(cfg_profiles);
            var active = Profiles.getActive(profiles, cfg_activeProfileId);
            if (!active) return;
            var updated = Profiles.captureFromKCM(active, basePage);
            for (var i = 0; i < profiles.length; i++) {
                if (profiles[i].id === updated.id) {
                    profiles[i] = updated;
                    break;
                }
            }
            var newBlob = JSON.stringify(profiles);
            if (cfg_profiles !== newBlob) {
                cfg_profiles = newBlob;
            }
        }
    }

    function triggerCapture() {
        if (!_initialized || _switchingProfile) return;
        captureDebounce.restart();
    }

    property string cfg_apiEndpoint
    property string cfg_apiEndpointDefault
    property string cfg_apiType
    property string cfg_apiTypeDefault
    property string cfg_providerName
    property string cfg_providerNameDefault
    property string cfg_modelName
    property string cfg_modelNameDefault
    property string cfg_apiKey
    property string cfg_apiKeyDefault
    property int cfg_temperature
    property int cfg_temperatureDefault
    property int cfg_maxTokens
    property int cfg_maxTokensDefault
    property string cfg_reasoningEffort
    property string cfg_reasoningEffortDefault
    property int cfg_thinkingBudget
    property int cfg_thinkingBudgetDefault
    property bool cfg_showThoughts
    property bool cfg_showThoughtsDefault
    property bool cfg_usesResponsesAPI
    property bool cfg_usesResponsesAPIDefault
    property string cfg_geminiApiVariant
    property string cfg_geminiApiVariantDefault
    property string cfg_geminiAuthMethod
    property string cfg_geminiAuthMethodDefault
    property string cfg_geminiVertexAuthType
    property string cfg_geminiVertexAuthTypeDefault
    property string cfg_geminiProjectId
    property string cfg_geminiProjectIdDefault
    property string cfg_geminiLocation
    property string cfg_geminiLocationDefault
    property int cfg_chatSpacing
    property int cfg_chatSpacingDefault
    property bool cfg_useCustomUserColor
    property bool cfg_useCustomUserColorDefault
    property color cfg_userColor
    property color cfg_userColorDefault
    property bool cfg_useCustomAssistantColor
    property bool cfg_useCustomAssistantColorDefault
    property color cfg_assistantColor
    property color cfg_assistantColorDefault
    property bool cfg_useCustomFont
    property bool cfg_useCustomFontDefault
    property string cfg_customFontFamily
    property string cfg_customFontFamilyDefault
    property int cfg_customFontSize
    property int cfg_customFontSizeDefault
    property bool cfg_useCustomCodeFont
    property bool cfg_useCustomCodeFontDefault
    property string cfg_customCodeFontFamily
    property string cfg_customCodeFontFamilyDefault
    property int cfg_customCodeFontSize
    property int cfg_customCodeFontSizeDefault
    property bool cfg_useCustomThoughtsFont
    property bool cfg_useCustomThoughtsFontDefault
    property string cfg_customThoughtsFontFamily
    property string cfg_customThoughtsFontFamilyDefault
    property int cfg_customThoughtsFontSize
    property int cfg_customThoughtsFontSizeDefault
    property string cfg_customSystemPrompt
    property string cfg_customSystemPromptDefault
    property bool cfg_resizeImageAttachments
    property bool cfg_resizeImageAttachmentsDefault
    property bool cfg_saveChatHistory
    property bool cfg_saveChatHistoryDefault
    property string cfg_chatSaveFormat
    property string cfg_chatSaveFormatDefault
    property bool cfg_autoShareCommandOutput
    property bool cfg_autoShareCommandOutputDefault
    property bool cfg_autoRunCommands
    property bool cfg_autoRunCommandsDefault
    property bool cfg_showProviderInTitle
    property bool cfg_showProviderInTitleDefault
    property bool cfg_sysInfoOS
    property bool cfg_sysInfoOSDefault
    property bool cfg_sysInfoShell
    property bool cfg_sysInfoShellDefault
    property bool cfg_sysInfoHostname
    property bool cfg_sysInfoHostnameDefault
    property bool cfg_sysInfoKernel
    property bool cfg_sysInfoKernelDefault
    property bool cfg_sysInfoDesktop
    property bool cfg_sysInfoDesktopDefault
    property bool cfg_sysInfoUser
    property bool cfg_sysInfoUserDefault
    property bool cfg_sysInfoCPU
    property bool cfg_sysInfoCPUDefault
    property bool cfg_sysInfoMemory
    property bool cfg_sysInfoMemoryDefault
    property bool cfg_sysInfoGPU
    property bool cfg_sysInfoGPUDefault
    property bool cfg_sysInfoDisk
    property bool cfg_sysInfoDiskDefault
    property bool cfg_sysInfoNetwork
    property bool cfg_sysInfoNetworkDefault
    property bool cfg_sysInfoLocale
    property bool cfg_sysInfoLocaleDefault
    property bool cfg_xdgMigrationDone
    property bool cfg_xdgMigrationDoneDefault
    property bool cfg_sysInfoDateTime
    property bool cfg_sysInfoDateTimeDefault
    property string cfg_gatheredSysInfo
    property string cfg_gatheredSysInfoDefault
    property int cfg_apiKeyVersion
    property int cfg_apiKeyVersionDefault
    property string cfg_apiKeysFallback
    property string cfg_apiKeysFallbackDefault
    property bool cfg_apiKeyMigrated
    property bool cfg_apiKeyMigratedDefault
    property int cfg_autoClearMode
    property int cfg_autoClearModeDefault
    property int cfg_autoClearSeconds
    property int cfg_autoClearSecondsDefault
    property int cfg_autoClearMinutes
    property int cfg_autoClearMinutesDefault
    property string cfg_lastClosedTimestamp
    property string cfg_lastClosedTimestampDefault
    property string cfg_availableModels
    property string cfg_availableModelsDefault
    property bool cfg_enableWebSearch
    property bool cfg_enableWebSearchDefault

    property bool cfg_enableNativeGoogleSearch
    property bool cfg_enableNativeGoogleSearchDefault

    property bool cfg_enableNativeCodeExecution
    property bool cfg_enableNativeCodeExecutionDefault
    property string cfg_webSearchProvider
    property string cfg_webSearchProviderDefault
    property string cfg_searxngUrl
    property string cfg_searxngUrlDefault
    property string cfg_searxngApiKey
    property string cfg_searxngApiKeyDefault
    property int cfg_searxngApiKeyVersion
    property int cfg_searxngApiKeyVersionDefault
    property string cfg_ollamaApiKey
    property string cfg_ollamaApiKeyDefault
    property string cfg_ollamaSearchApiKey
    property string cfg_ollamaSearchApiKeyDefault
    property int cfg_ollamaApiKeyVersion
    property int cfg_ollamaApiKeyVersionDefault
    property int cfg_ollamaSearchApiKeyVersion
    property int cfg_ollamaSearchApiKeyVersionDefault
    property bool cfg_webSearchMigrated
    property bool cfg_webSearchMigratedDefault
    property string cfg_openaiLastProvider
    property string cfg_openaiLastProviderDefault
    property string cfg_openaiLastEndpoint
    property string cfg_openaiLastEndpointDefault
    property string cfg_profiles
    property string cfg_profilesDefault
    property string cfg_activeProfileId
    property string cfg_activeProfileIdDefault
    property int cfg_profilesSchemaVersion
    property int cfg_profilesSchemaVersionDefault
    property bool cfg_useCommandTool
    property bool cfg_useCommandToolDefault
    property bool cfg_pin
    property bool cfg_pinDefault
    property string cfg_tasks
    property string cfg_tasksDefault
    property bool cfg_useSessionMultiplexer
    property bool cfg_useSessionMultiplexerDefault
    property string cfg_sessionMultiplexer
    property string cfg_sessionMultiplexerDefault
    property string cfg_sessionName
    property string cfg_sessionNameDefault

    property bool cfg_showIconProfile
    property bool cfg_showIconProfileDefault
    property bool cfg_showIconTasks
    property bool cfg_showIconTasksDefault
    property bool cfg_showIconAuto
    property bool cfg_showIconAutoDefault
    property bool cfg_showIconHistory
    property bool cfg_showIconHistoryDefault
    property bool cfg_showIconCopy
    property bool cfg_showIconCopyDefault
    property bool cfg_showIconClear
    property bool cfg_showIconClearDefault
    property bool cfg_showIconSettings
    property bool cfg_showIconSettingsDefault
    property bool cfg_showIconPin
    property bool cfg_showIconPinDefault

    property bool cfg_enableTools
    property bool cfg_enableToolsDefault

    property bool cfg_toolsReadFileEnabled
    property bool cfg_toolsReadFileEnabledDefault
    property bool cfg_toolsReadFileAutoRun
    property bool cfg_toolsReadFileAutoRunDefault
    property bool cfg_toolsWriteFileEnabled
    property bool cfg_toolsWriteFileEnabledDefault
    property bool cfg_toolsWriteFileAutoRun
    property bool cfg_toolsWriteFileAutoRunDefault
    property bool cfg_toolsListDirEnabled
    property bool cfg_toolsListDirEnabledDefault
    property bool cfg_toolsListDirAutoRun
    property bool cfg_toolsListDirAutoRunDefault
    property bool cfg_toolsHttpGetEnabled
    property bool cfg_toolsHttpGetEnabledDefault
    property bool cfg_toolsHttpGetAutoRun
    property bool cfg_toolsHttpGetAutoRunDefault
    property bool cfg_toolsHttpRequestEnabled
    property bool cfg_toolsHttpRequestEnabledDefault
    property bool cfg_toolsHttpRequestAutoRun
    property bool cfg_toolsHttpRequestAutoRunDefault
    property bool cfg_toolsSearchFilesEnabled
    property bool cfg_toolsSearchFilesEnabledDefault
    property bool cfg_toolsSearchFilesAutoRun
    property bool cfg_toolsSearchFilesAutoRunDefault
    property bool cfg_toolsGetClipboardEnabled
    property bool cfg_toolsGetClipboardEnabledDefault
    property bool cfg_toolsGetClipboardAutoRun
    property bool cfg_toolsGetClipboardAutoRunDefault
    property bool cfg_toolsSetClipboardEnabled
    property bool cfg_toolsSetClipboardEnabledDefault
    property bool cfg_toolsSetClipboardAutoRun
    property bool cfg_toolsSetClipboardAutoRunDefault
    property bool cfg_toolsNotifyEnabled
    property bool cfg_toolsNotifyEnabledDefault
    property bool cfg_toolsNotifyAutoRun
    property bool cfg_toolsNotifyAutoRunDefault
    property bool cfg_toolsOpenUrlEnabled
    property bool cfg_toolsOpenUrlEnabledDefault
    property bool cfg_toolsOpenUrlAutoRun
    property bool cfg_toolsOpenUrlAutoRunDefault
    property string cfg_toolsPathWhitelist
    property string cfg_toolsPathWhitelistDefault
    property int cfg_toolsReadMaxBytes
    property int cfg_toolsReadMaxBytesDefault
    property int cfg_toolsWriteMaxBytes
    property int cfg_toolsWriteMaxBytesDefault
    property int cfg_toolsHttpMaxBytes
    property int cfg_toolsHttpMaxBytesDefault
    property string cfg_customTools
    property string cfg_customToolsDefault
}
