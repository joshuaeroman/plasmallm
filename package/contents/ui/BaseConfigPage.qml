/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kcmutils

SimpleKCM {
    // Declared here because Plasma injects all cfg_ properties onto every config page.
    // By centralizing them in this base component, we avoid duplication and console warnings.

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
    property int cfg_chatSpacing
    property int cfg_chatSpacingDefault
    property string cfg_customSystemPrompt
    property string cfg_customSystemPromptDefault
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
}
