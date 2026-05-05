/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

BaseConfigPage {
    id: configPage

    property var availableFonts: Qt.fontFamilies()

    Kirigami.FormLayout {
        anchors.fill: parent

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Panel Title:")
            text: i18n("Show provider and model in title")
            checked: cfg_showProviderInTitle
            onCheckedChanged: cfg_showProviderInTitle = checked
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Chat Spacing: %1px", Math.round(chatSpacingSlider.value))
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Slider {
                id: chatSpacingSlider
                Layout.fillWidth: true
                from: 2
                to: 24
                stepSize: 1
                value: cfg_chatSpacing
                onValueChanged: cfg_chatSpacing = value
            }

            RowLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    text: i18n("Compact")
                    font: Kirigami.Theme.smallFont
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    text: i18n("Spacious")
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("UI Font:")
            text: i18n("Use custom UI font")
            checked: cfg_useCustomFont
            onCheckedChanged: cfg_useCustomFont = checked
        }

        RowLayout {
            Layout.fillWidth: true
            visible: cfg_useCustomFont

            QQC2.ComboBox {
                Layout.fillWidth: true
                model: availableFonts
                currentIndex: availableFonts.indexOf(cfg_customFontFamily) >= 0 ? availableFonts.indexOf(cfg_customFontFamily) : availableFonts.indexOf(Kirigami.Theme.defaultFont.family)
                onActivated: function(index) {
                    cfg_customFontFamily = availableFonts[index]
                }
                Component.onCompleted: {
                    if (cfg_customFontFamily === "") {
                        cfg_customFontFamily = Kirigami.Theme.defaultFont.family
                    }
                }
            }

            QQC2.SpinBox {
                from: 6
                to: 72
                value: cfg_customFontSize
                onValueModified: cfg_customFontSize = value
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Code Font:")
            text: i18n("Use custom code font")
            checked: cfg_useCustomCodeFont
            onCheckedChanged: cfg_useCustomCodeFont = checked
        }

        RowLayout {
            Layout.fillWidth: true
            visible: cfg_useCustomCodeFont

            QQC2.ComboBox {
                Layout.fillWidth: true
                model: availableFonts
                currentIndex: availableFonts.indexOf(cfg_customCodeFontFamily) >= 0 ? availableFonts.indexOf(cfg_customCodeFontFamily) : availableFonts.indexOf("monospace")
                onActivated: function(index) {
                    cfg_customCodeFontFamily = availableFonts[index]
                }
            }

            QQC2.SpinBox {
                from: 6
                to: 72
                value: cfg_customCodeFontSize
                onValueModified: cfg_customCodeFontSize = value
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Thoughts Font:")
            text: i18n("Use custom thoughts font")
            checked: cfg_useCustomThoughtsFont
            onCheckedChanged: cfg_useCustomThoughtsFont = checked
        }

        RowLayout {
            Layout.fillWidth: true
            visible: cfg_useCustomThoughtsFont

            QQC2.ComboBox {
                Layout.fillWidth: true
                model: availableFonts
                currentIndex: availableFonts.indexOf(cfg_customThoughtsFontFamily) >= 0 ? availableFonts.indexOf(cfg_customThoughtsFontFamily) : availableFonts.indexOf(Kirigami.Theme.smallFont.family)
                onActivated: function(index) {
                    cfg_customThoughtsFontFamily = availableFonts[index]
                }
                Component.onCompleted: {
                    if (cfg_customThoughtsFontFamily === "") {
                        cfg_customThoughtsFontFamily = Kirigami.Theme.smallFont.family
                    }
                }
            }

            QQC2.SpinBox {
                from: 6
                to: 72
                value: cfg_customThoughtsFontSize
                onValueModified: cfg_customThoughtsFontSize = value
            }
        }
    }
}
