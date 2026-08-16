/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

RowLayout {
    id: rootPicker

    property string modelName: ""
    property var availableModels: []
    property bool fetchInProgress: false
    property bool fetchVisible: true
    property bool fetchEnabled: true
    property string fetchTooltip: i18n("Refresh model list")
    property bool editable: true
    property string placeholderText: i18n("Select or enter a model")
    property int maxPopupHeight: Kirigami.Units.gridUnit * 20

    signal fetchRequested()
    signal modelSelected(string model)

    spacing: Kirigami.Units.smallSpacing

    function syncIndex() {
        if (!modelCombo) return;
        var list = modelCombo.displayModels || [];
        var name = rootPicker.modelName || "";
        var idx = list.indexOf(name);
        if (idx >= 0 && modelCombo.currentIndex !== idx) {
            modelCombo.currentIndex = idx;
        } else if (idx < 0 && list.length > 0 && modelCombo.currentIndex !== 0) {
            modelCombo.currentIndex = 0;
        }
    }

    onModelNameChanged: syncIndex()
    onAvailableModelsChanged: syncIndex()

    QQC2.ComboBox {
        id: modelCombo
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        Layout.minimumWidth: Kirigami.Units.gridUnit * 8
        editable: false

        readonly property var displayModels: {
            var list = (rootPicker.availableModels && Array.isArray(rootPicker.availableModels)) 
                ? rootPicker.availableModels.slice() : [];
            if (rootPicker.modelName && rootPicker.modelName.length > 0 && list.indexOf(rootPicker.modelName) === -1) {
                list.unshift(rootPicker.modelName);
            }
            return list;
        }

        model: displayModels
        enabled: !rootPicker.fetchInProgress

        displayText: {
            if (rootPicker.modelName && rootPicker.modelName.length > 0)
                return rootPicker.modelName;
            if (currentIndex >= 0 && currentIndex < displayModels.length)
                return displayModels[currentIndex];
            return rootPicker.placeholderText;
        }

        onDisplayModelsChanged: rootPicker.syncIndex()

        popup: QQC2.Popup {
            width: modelCombo.width
            implicitHeight: Math.min(modelContentColumn.implicitHeight + (padding * 2),
                                     rootPicker.maxPopupHeight)
            padding: Kirigami.Units.smallSpacing

            onOpened: {
                modelSearchField.text = "";
                modelListView.currentIndex = modelCombo.currentIndex;
                modelSearchField.forceActiveFocus();
            }

            ColumnLayout {
                id: modelContentColumn
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                Kirigami.SearchField {
                    id: modelSearchField
                    Layout.fillWidth: true
                    placeholderText: rootPicker.editable ? i18n("Search or type custom model…") : i18n("Search models…")
                    Keys.onDownPressed: modelListView.forceActiveFocus()
                    Keys.onReturnPressed: {
                        var term = modelSearchField.text.trim();
                        if (modelListView.count > 0) {
                            var pick = modelListView.model[0];
                            rootPicker.modelName = pick;
                            rootPicker.modelSelected(pick);
                            modelCombo.currentIndex = modelCombo.displayModels.indexOf(pick);
                            modelCombo.popup.close();
                        } else if (rootPicker.editable && term.length > 0) {
                            rootPicker.modelName = term;
                            rootPicker.modelSelected(term);
                            modelCombo.popup.close();
                        }
                    }
                }

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    background: null

                    ListView {
                        id: modelListView
                        clip: true
                        model: modelCombo.displayModels.filter(function(m) {
                            return modelSearchField.text.length === 0
                                || String(m).toLowerCase().indexOf(modelSearchField.text.toLowerCase()) !== -1;
                        })
                        delegate: QQC2.ItemDelegate {
                            width: ListView.view.width
                            text: modelData
                            highlighted: ListView.isCurrentItem || modelData === rootPicker.modelName
                            onClicked: {
                                rootPicker.modelName = modelData;
                                rootPicker.modelSelected(modelData);
                                modelCombo.currentIndex = modelCombo.displayModels.indexOf(modelData);
                                modelCombo.popup.close();
                            }
                        }
                    }
                }

                // Custom model acceptance prompt if search filter yielded 0 matches and editable is true
                QQC2.Button {
                    Layout.fillWidth: true
                    visible: rootPicker.editable && modelSearchField.text.trim().length > 0 && modelListView.count === 0
                    text: i18n("Use \"%1\"", modelSearchField.text.trim())
                    icon.name: "list-add"
                    onClicked: {
                        var custom = modelSearchField.text.trim();
                        rootPicker.modelName = custom;
                        rootPicker.modelSelected(custom);
                        modelCombo.popup.close();
                    }
                }
            }
        }
    }

    QQC2.Button {
        id: refreshButton
        icon.name: "view-refresh"
        visible: rootPicker.fetchVisible
        enabled: rootPicker.fetchEnabled && !rootPicker.fetchInProgress
        display: QQC2.AbstractButton.IconOnly
        QQC2.ToolTip.text: rootPicker.fetchInProgress ? i18n("Fetching…") : rootPicker.fetchTooltip
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        QQC2.ToolTip.visible: hovered
        onClicked: rootPicker.fetchRequested()
    }
}
