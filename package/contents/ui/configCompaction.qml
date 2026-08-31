/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils
import org.kde.plasma.workspace.dbus as DBus

import "api.js" as Api
import "wallet.js" as Wallet
import "walletCore.js" as WalletCore
import "contextCompactor.js" as ContextCompactor
import "profiles.js" as Profiles

BaseConfigPage {
    id: configPage

    title: i18n("Context Compaction")

    property var profilesList: []

    onCfg_profilesChanged: {
        profilesList = Profiles.loadProfilesRaw(cfg_profiles);
        syncProfileCombo();
    }

    property string testStatusMessage: ""
    property int testStatusType: Kirigami.MessageType.Information
    property bool testInProgress: false
    property string testResponseContent: ""

    readonly property string defaultInstructions:
        "Summarize this conversation. Be very concise and use shorthand and abbreviations when possible. No prose. Retain important specifics when brief. For larger specifics like logs, use of restore_context/recall_attachment tool will work instead. Cite every item with a msgId or msgId range, e.g. [1], [3-6], [2,7-10]\n\n" +
        "When a previous compaction exists, use it as a starting point. Be conservative about removing things; update and merge new information rather than discarding established context unless subsequent messages prove it entirely out of scope. Always persist all attached files across compaction cycles.\n\n" +
        "Structure:\n" +
        "# Key Topics\n<...>\n" +
        "# User Goals\n<...>\n" +
        "# Agent Goals\n<...>\n" +
        "# Decisions\n<...>\n" +
        "# Current Status\n<...>\n" +
        "# Attachments\n- example.txt - brief description of its contents [msgId]"

    readonly property string defaultSampleTranscript:
        "[1] Role: user\nContent: Can you inspect my production server at 192.168.1.100? Users are reporting intermittent 502 Bad Gateway errors and high latency on the API gateway.\n\n" +
        "[2] Role: assistant\nTool Calls:\n  - run_command({\"command\":\"uptime && free -h && journalctl -u api-gateway -n 30 --no-pager\"})\n\n" +
        "[3] Role: tool\nTool Call ID: call_01\nOutput:\n14:22:10 up 45 days, 4 users, load average: 8.42, 6.15, 4.30\nMem: Total 16Gi, Used 15.2Gi, Free 210Mi, Buff/Cache 590Mi, Swap Used 3.8Gi\n-- Logs begin Mon 2026-08-01 --\nAug 15 14:21:40 srv-prod kernel: [1948212.112] Out of memory: Killed process 31204 (node /opt/app/server.js) total-vm:4210452kB, anon-rss:3890212kB\nAug 15 14:21:45 srv-prod systemd[1]: api-gateway.service: Main process exited, code=killed, status=9/KILL\nAug 15 14:21:46 srv-prod systemd[1]: api-gateway.service: Scheduled restart job, restart counter is at 14.\n\n" +
        "[4] Role: assistant\nContent: The server is experiencing memory exhaustion (15.2Gi/16Gi used + 3.8Gi swap). The Linux kernel OOM-killer terminated the Node.js API process (/opt/app/server.js). Let's take a heap snapshot or inspect the event listeners to find the source of the memory leak.\n\n" +
        "[5] Role: user\nContent: Check /opt/app/services/eventBus.ts and /opt/app/services/websocketManager.ts. We recently added telemetry streaming there.\n\n" +
        "[6] Role: assistant\nTool Calls:\n  - read_file({\"path\":\"/opt/app/services/eventBus.ts\"})\n  - read_file({\"path\":\"/opt/app/services/websocketManager.ts\"})\n\n" +
        "[7] Role: tool\nTool Call ID: call_02\nOutput:\n// /opt/app/services/eventBus.ts\nimport { EventEmitter } from 'events';\nexport const globalBus = new EventEmitter();\nglobalBus.setMaxListeners(0); // unlimited listeners\nexport function registerClientListener(clientId: string, callback: (event: any) => void) {\n    // BUG: Listener added on every socket reconnect but never removed on disconnect\n    globalBus.on('telemetry_tick', callback);\n}\n\n" +
        "[8] Role: assistant\nContent: Found the memory leak in `/opt/app/services/eventBus.ts`. `registerClientListener` attaches a listener on each client reconnection without ever unregistering it on disconnect. Over time, thousands of closure references accumulate in the EventEmitter.\n\n" +
        "[9] Role: user\nContent: Fix the leak in eventBus.ts by returning an unsubscribe cleanup function, and update websocketManager.ts to call it on socket close. Then run typecheck and test.\n\n" +
        "[10] Role: assistant\nTool Calls:\n  - write_file({\"path\":\"/opt/app/services/eventBus.ts\",\"content\":\"import { EventEmitter } from 'events';\\nexport const globalBus = new EventEmitter();\\nglobalBus.setMaxListeners(100);\\nexport function registerClientListener(clientId: string, callback: (event: any) => void): () => void {\\n    globalBus.on('telemetry_tick', callback);\\n    return () => globalBus.off('telemetry_tick', callback);\\n}\"})\n  - run_command({\"command\":\"cd /opt/app && pnpm test && pnpm build\"})\n\n" +
        "[11] Role: tool\nTool Call ID: call_03\nOutput:\n✓ services/eventBus.test.ts (4 tests passed)\n✓ services/websocketManager.test.ts (8 tests passed)\nBuild completed in 3.42s. Artifact generated in /opt/app/dist.\n\n" +
        "[12] Role: assistant\nContent: Fixed the leak in `/opt/app/services/eventBus.ts`. All 12 unit tests pass and the production bundle is rebuilt in `/opt/app/dist`.\n\n" +
        "[13] Role: user\nContent: Next, let's fix the Nginx reverse proxy configuration. We need proxy_read_timeout set to 300s for large reports, and proxy_buffers increased to 16 32k in /etc/nginx/conf.d/api.conf.\n\n" +
        "[14] Role: assistant\nTool Calls:\n  - write_file({\"path\":\"/etc/nginx/conf.d/api.conf\",\"content\":\"upstream api_cluster {\\n    server 127.0.0.1:3000 max_fails=3 fail_timeout=10s;\\n    keepalive 32;\\n}\\nserver {\\n    listen 80;\\n    server_name api.example.com;\\n    location / {\\n        proxy_pass http://api_cluster;\\n        proxy_http_version 1.1;\\n        proxy_set_header Connection '';\\n        proxy_set_header Host $host;\\n        proxy_set_header X-Real-IP $remote_addr;\\n        proxy_read_timeout 300s;\\n        proxy_connect_timeout 10s;\\n        proxy_buffers 16 32k;\\n        proxy_buffer_size 64k;\\n    }\\n}\"})\n  - run_command({\"command\":\"nginx -t && systemctl reload nginx\"})\n\n" +
        "[15] Role: tool\nTool Call ID: call_04\nOutput:\nnginx: the configuration file /etc/nginx/nginx.conf syntax is ok\nnginx: configuration file /etc/nginx/nginx.conf test is successful\nNginx service reloaded successfully.\n\n" +
        "[16] Role: assistant\nContent: Nginx configuration updated with `proxy_read_timeout 300s` and `proxy_buffers 16 32k`. Config validated and reloaded without downtime.\n\n" +
        "[17] Role: user\nContent: We also have a pending database migration for session expirations. Check /opt/app/prisma/migrations/20260815_sessions/migration.sql and apply it to the PostgreSQL cluster on port 5432.\n\n" +
        "[18] Role: assistant\nTool Calls:\n  - read_file({\"path\":\"/opt/app/prisma/migrations/20260815_sessions/migration.sql\"})\n  - run_command({\"command\":\"psql -h 127.0.0.1 -p 5432 -U app_user -d production_db -f /opt/app/prisma/migrations/20260815_sessions/migration.sql\"})\n\n" +
        "[19] Role: tool\nTool Call ID: call_05\nOutput:\nBEGIN\nALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '30 days');\nCREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_expires_at ON user_sessions(expires_at);\nCOMMIT\nMigration completed successfully (execution time: 142ms).\n\n" +
        "[20] Role: assistant\nContent: Database migration applied cleanly: added `expires_at` column and concurrent index `idx_sessions_expires_at` on `user_sessions` table.\n\n" +
        "[21] Role: user\nContent: Now create an automated zero-downtime deployment script in /opt/app/scripts/deploy_prod.sh. It must take a pre-deploy PostgreSQL dump to /mnt/backups/pre_deploy.sql, pull latest dist, restart api-gateway.service, and poll http://127.0.0.1:3000/api/health up to 10 times before succeeding.\n\n" +
        "[22] Role: assistant\nTool Calls:\n  - write_file({\"path\":\"/opt/app/scripts/deploy_prod.sh\",\"content\":\"#!/bin/bash\\nset -eo pipefail\\necho '1. Backing up database...'\\npg_dump -h 127.0.0.1 -p 5432 -U app_user production_db > /mnt/backups/pre_deploy.sql\\necho '2. Restarting service...'\\nsystemctl restart api-gateway.service\\necho '3. Polling healthcheck...'\\nfor i in {1..10}; do\\n    if curl -sf http://127.0.0.1:3000/api/health | grep -q 'ok'; then\\n        echo 'Deploy successful!'\\n        exit 0\\n    fi\\n    sleep 2\\ndone\\necho 'Healthcheck failed!' >&2\\nexit 1\"})\n  - run_command({\"command\":\"chmod +x /opt/app/scripts/deploy_prod.sh\"})\n\n" +
        "[23] Role: tool\nTool Call ID: call_06\nOutput:\nFile /opt/app/scripts/deploy_prod.sh created with execute permissions (chmod 755).\n\n" +
        "[24] Role: assistant\nContent: Deployment script created at `/opt/app/scripts/deploy_prod.sh`. It includes pre-deployment DB backup to `/mnt/backups/pre_deploy.sql` and health check verification with automatic retry.\n\n" +
        "[25] Role: user\nContent: Fantastic work. Two strict operational rules to remember for future conversations: 1) Never execute migrations without taking a backup first. 2) Never deploy to production on Fridays after 2:00 PM."

    property string sampleTranscript: defaultSampleTranscript

    readonly property var profileChoices: {
        var list = [{ id: "active", name: i18n("(Active Chat Profile)") }];
        for (var i = 0; i < profilesList.length; i++) {
            var p = profilesList[i];
            var label = p.name || (p.providerName ? p.providerName + " (" + (p.modelName || "") + ")" : i18n("Unnamed Profile"));
            list.push({ id: p.id, name: label, profile: p });
        }
        return list;
    }

    readonly property var selectedProfileData: {
        var targetId = cfg_compactionProfileId || "active";
        if (targetId === "active" || !targetId) {
            return {
                id: "active",
                name: i18n("Active Chat Profile"),
                providerName: cfg_providerName || "Default",
                modelName: cfg_modelName || "",
                apiEndpoint: cfg_apiEndpoint || "",
                apiType: cfg_apiType || "openai",
                geminiApiVariant: cfg_geminiApiVariant || "",
                geminiAuthMethod: cfg_geminiAuthMethod || "",
                geminiProjectId: cfg_geminiProjectId || "",
                geminiLocation: cfg_geminiLocation || "",
                geminiVertexAuthType: cfg_geminiVertexAuthType || "",
                usesResponsesAPI: !!cfg_usesResponsesAPI
            };
        }
        for (var i = 0; i < profilesList.length; i++) {
            if (profilesList[i].id === targetId)
                return profilesList[i];
        }
        return {
            id: "active",
            name: i18n("Active Chat Profile (Fallback)"),
            providerName: cfg_providerName || "Default",
            modelName: cfg_modelName || "",
            apiEndpoint: cfg_apiEndpoint || "",
            apiType: cfg_apiType || "openai",
            geminiApiVariant: cfg_geminiApiVariant || "",
            geminiAuthMethod: cfg_geminiAuthMethod || "",
            geminiProjectId: cfg_geminiProjectId || "",
            geminiLocation: cfg_geminiLocation || "",
            geminiVertexAuthType: cfg_geminiVertexAuthType || "",
            usesResponsesAPI: !!cfg_usesResponsesAPI
        };
    }

    function syncProfileCombo() {
        var targetId = cfg_compactionProfileId || "active";
        for (var i = 0; i < profileChoices.length; i++) {
            if (profileChoices[i].id === targetId) {
                if (profileCombo && profileCombo.currentIndex !== i)
                    profileCombo.currentIndex = i;
                return;
            }
        }
        if (profileCombo && profileCombo.currentIndex !== 0)
            profileCombo.currentIndex = 0;
    }

    function fallbackMap() {
        return WalletCore.parseFallbackMap(cfg_apiKeysFallback);
    }

    function loadProfileKey(profile, callback) {
        var pid = (!profile || profile.id === "active") ? cfg_activeProfileId : profile.id;
        var apiType = (!profile || profile.id === "active") ? cfg_apiType : (profile.apiType || "openai");
        var providerName = (!profile || profile.id === "active") ? cfg_providerName : (profile.providerName || "");
        var endpoint = (!profile || profile.id === "active") ? cfg_apiEndpoint : (profile.apiEndpoint || "");
        var geminiAuth = (!profile || profile.id === "active") ? cfg_geminiAuthMethod : (profile.geminiAuthMethod || "");
        var slot = Api.currentKeySlot(pid, apiType, providerName, endpoint, geminiAuth);
        var extras = Api.legacyKeySlots(pid, apiType, providerName, endpoint, geminiAuth);
        var cfgKey = (!profile || profile.id === "active") ? (cfg_apiKey || "") : "";
        Wallet.readKey(DBus, slot, extras, fallbackMap(), cfgKey, function(res) {
            // readKey already walks extras + fallbackMap + cfgKey.
            callback((res && res.key) || "");
        });
    }

    function testCompactionConnection() {
        var prof = selectedProfileData;
        var ep = (prof.apiEndpoint || "").trim();
        var model = (prof.modelName || "").trim();

        if (!ep || !model) {
            testResponseContent = "";
            testStatusMessage = i18n("Selected profile does not have an endpoint URL or model configured.");
            testStatusType = Kirigami.MessageType.Error;
            return;
        }

        testInProgress = true;
        testResponseContent = "";
        testStatusMessage = i18n("Testing compaction call using '%1'…", prof.name || prof.modelName);
        testStatusType = Kirigami.MessageType.Information;

        loadProfileKey(prof, function(key) {
            var transcriptToSend = configPage.sampleTranscript || configPage.defaultSampleTranscript;

            ContextCompactor.compactHistory({
                apiType: Api.resolvedApiType(
                    prof.apiType || "openai",
                    prof.geminiApiVariant,
                    prof.geminiAuthMethod,
                    prof.geminiVertexAuthType),
                endpoint: ep,
                apiKey: key,
                model: model,
                geminiApiVariant: Api.clampGeminiApiVariant(
                    prof.geminiApiVariant,
                    prof.geminiAuthMethod,
                    prof.geminiVertexAuthType),
                geminiAuthMethod: prof.geminiAuthMethod,
                geminiProjectId: prof.geminiProjectId,
                geminiLocation: prof.geminiLocation,
                geminiVertexAuthType: prof.geminiVertexAuthType,
                usesResponsesAPI: prof.usesResponsesAPI,
                providerName: prof.providerName,
                transcript: transcriptToSend,
                instructions: cfg_compactionInstructions || defaultInstructions
            }, function(err, summary) {
                testInProgress = false;
                if (err) {
                    testResponseContent = "";
                    testStatusMessage = i18n("Compaction test failed: %1", err);
                    testStatusType = Kirigami.MessageType.Error;
                } else {
                    testResponseContent = summary || "";
                    testStatusMessage = i18n("Compaction test succeeded!");
                    testStatusType = Kirigami.MessageType.Positive;
                }
            });
        });
    }

    onCfg_compactionProfileIdChanged: if (_initialized) syncProfileCombo()

    Component.onCompleted: {
        profilesList = Profiles.loadProfilesRaw(cfg_profiles);
        syncProfileCombo();
        Qt.callLater(function() {
            _initialized = true;
        });
    }

    Kirigami.FormLayout {
        id: formLayout
        width: Math.min(parent.width, Kirigami.Units.gridUnit * 32)
        Layout.maximumWidth: Kirigami.Units.gridUnit * 32

        QQC2.CheckBox {
            id: compactionEnabledBox
            Kirigami.FormData.label: i18n("Context Compaction:")
            text: i18n("Enable context compaction")
            checked: cfg_compactionEnabled
            onToggled: cfg_compactionEnabled = checked
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            text: i18n("Dramatically reduces token usage and speeds up responses in long conversations by compressing older turns into a dense background summary. Keeps your chats lightweight and cost-effective while your full history remains visible.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Compaction Profile")
            visible: compactionEnabledBox.checked
            Layout.fillWidth: true
        }

        QQC2.ComboBox {
            id: profileCombo
            Kirigami.FormData.label: i18n("Model Profile:")
            visible: compactionEnabledBox.checked
            Layout.fillWidth: true
            model: configPage.profileChoices
            textRole: "name"
            onActivated: function(index) {
                if (index >= 0 && index < configPage.profileChoices.length) {
                    cfg_compactionProfileId = configPage.profileChoices[index].id;
                }
            }
        }

        QQC2.Label {
            visible: compactionEnabledBox.checked
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            text: {
                var p = configPage.selectedProfileData;
                return i18n("Provider: %1  |  Model: %2\nEndpoint: %3",
                    p.providerName || "Default",
                    p.modelName || i18n("None"),
                    p.apiEndpoint || i18n("None"));
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Trigger Thresholds")
            visible: compactionEnabledBox.checked
            Layout.fillWidth: true
        }

        QQC2.ComboBox {
            id: triggerModeCombo
            Kirigami.FormData.label: i18n("Trigger Condition:")
            visible: compactionEnabledBox.checked
            Layout.fillWidth: true
            model: [
                { id: "chars", name: i18n("By Character Count") },
                { id: "turns", name: i18n("By Turn Count") },
                { id: "both", name: i18n("Whichever comes first (Chars or Turns)") }
            ]
            textRole: "name"
            currentIndex: {
                var m = cfg_compactionTriggerMode || "chars";
                if (m === "turns") return 1;
                if (m === "both") return 2;
                return 0;
            }
            onActivated: function(index) {
                if (index === 1) cfg_compactionTriggerMode = "turns";
                else if (index === 2) cfg_compactionTriggerMode = "both";
                else cfg_compactionTriggerMode = "chars";
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Character threshold:")
            visible: compactionEnabledBox.checked && (cfg_compactionTriggerMode !== "turns")
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: thresholdCharsSpin
                from: 2000
                to: 200000
                stepSize: 1000
                value: cfg_compactionThresholdChars || 20000
                editable: true
                onValueModified: cfg_compactionThresholdChars = value
            }

            QQC2.Label {
                text: i18n("chars (~%1 tokens)", Math.round(thresholdCharsSpin.value / 4))
                color: Kirigami.Theme.disabledTextColor
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Turn count interval:")
            visible: compactionEnabledBox.checked && (cfg_compactionTriggerMode === "turns" || cfg_compactionTriggerMode === "both")
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: thresholdTurnsSpin
                from: 1
                to: 50
                stepSize: 1
                value: cfg_compactionThresholdTurns || 2
                editable: true
                onValueModified: cfg_compactionThresholdTurns = value
            }

            QQC2.Label {
                text: thresholdTurnsSpin.value === 1 ? i18n("turn (compacts after every turn)") : i18n("turns")
                color: Kirigami.Theme.disabledTextColor
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Keep recent turns:")
            visible: compactionEnabledBox.checked
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                from: 1
                to: 20
                stepSize: 1
                value: cfg_compactionKeepRecentTurns || 4
                editable: true
                onValueModified: cfg_compactionKeepRecentTurns = value
            }

            QQC2.Label {
                text: i18n("full turns kept verbatim and uncompacted")
                color: Kirigami.Theme.disabledTextColor
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Compaction Instructions")
            visible: compactionEnabledBox.checked
            Layout.fillWidth: true
        }

        QQC2.TextArea {
            id: instructionsArea
            Kirigami.FormData.label: i18n("Instructions template:")
            visible: compactionEnabledBox.checked
            Layout.fillWidth: true
            Layout.minimumHeight: 140
            wrapMode: TextEdit.Wrap
            text: cfg_compactionInstructions || configPage.defaultInstructions
            onTextChanged: cfg_compactionInstructions = text
        }

        QQC2.Button {
            text: i18n("Reset to Default Instructions")
            icon.name: "edit-undo"
            visible: compactionEnabledBox.checked
            onClicked: {
                cfg_compactionInstructions = configPage.defaultInstructions;
                instructionsArea.text = configPage.defaultInstructions;
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Diagnostic & Testing")
            visible: compactionEnabledBox.checked
            Layout.fillWidth: true
        }

        QQC2.Label {
            visible: compactionEnabledBox.checked
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            text: i18n("Test compaction against your selected model profile using the sample transcript below:")
        }

        ColumnLayout {
            visible: compactionEnabledBox.checked
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    Layout.fillWidth: true
                    text: i18n("Sample Conversation Transcript:")
                    font.bold: true
                }

                QQC2.Button {
                    text: i18n("Reset Sample")
                    icon.name: "edit-undo"
                    display: QQC2.AbstractButton.TextBesideIcon
                    visible: sampleTranscriptArea.text !== configPage.defaultSampleTranscript
                    onClicked: {
                        configPage.sampleTranscript = configPage.defaultSampleTranscript;
                        sampleTranscriptArea.text = configPage.defaultSampleTranscript;
                    }
                }
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 5
                Layout.maximumHeight: Kirigami.Units.gridUnit * 8

                QQC2.TextArea {
                    id: sampleTranscriptArea
                    wrapMode: TextEdit.Wrap
                    text: configPage.sampleTranscript
                    font: Kirigami.Theme.smallFont
                    selectByMouse: true
                    onTextChanged: configPage.sampleTranscript = text
                }
            }
        }

        RowLayout {
            visible: compactionEnabledBox.checked
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: configPage.testInProgress ? i18n("Testing…") : i18n("Test Compaction Connection")
                icon.name: "network-connect"
                enabled: !configPage.testInProgress
                onClicked: configPage.testCompactionConnection()
            }

            QQC2.BusyIndicator {
                running: configPage.testInProgress
                visible: configPage.testInProgress
                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.2
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: configPage.testStatusType
            text: configPage.testStatusMessage
            visible: configPage.testStatusMessage.length > 0 && !configPage.testInProgress
            showCloseButton: true
            onVisibleChanged: {
                if (!visible) configPage.testStatusMessage = "";
            }
        }

        ColumnLayout {
            visible: compactionEnabledBox.checked && configPage.testResponseContent.length > 0
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: i18n("Model Summary Response:")
                font.bold: true
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 6
                Layout.maximumHeight: Kirigami.Units.gridUnit * 12

                QQC2.TextArea {
                    readOnly: true
                    wrapMode: TextEdit.Wrap
                    text: configPage.testResponseContent
                    selectByMouse: true
                    font: Kirigami.Theme.smallFont
                }
            }
        }
    }
}
