/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../memory.js" as Memory

ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    property var phrases: []
    property int editIndex: -1
    readonly property bool atCap: phrases.length >= Memory.MAX_PHRASES

    Component.onCompleted: refresh()

    function refresh() {
        phrases = Memory.parseStored(cfg_memoryPhrases);
        if (editIndex >= phrases.length) {
            editIndex = -1;
        }
    }

    function commit(newList) {
        cfg_memoryPhrases = Memory.serialize(newList);
        refresh();
    }

    function addPhrase() {
        if (atCap) return;
        var res = Memory.addPhrase(phrases, newPhraseField.text);
        if (!res.added) return;
        newPhraseField.text = "";
        commit(res.list);
    }

    QQC2.CheckBox {
        text: i18n("Ask before running")
        checked: !cfg_toolsEditMemoryAutoRun
        onCheckedChanged: if (_initialized) cfg_toolsEditMemoryAutoRun = !checked
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true

        QQC2.Label {
            text: i18n("Saved phrases:")
            font.bold: true
            Layout.fillWidth: true
        }

        QQC2.Label {
            text: phrases.length + " / " + Memory.MAX_PHRASES
            font: Kirigami.Theme.smallFont
            color: atCap ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
        }
    }

    QQC2.Label {
        visible: phrases.length === 0
        text: i18n("Nothing remembered yet. The assistant can save phrases with its edit_memory tool, or add them below.")
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    Repeater {
        model: root.phrases.length

        delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                visible: root.editIndex !== index
                text: (index + 1) + ". " + root.phrases[index]
                elide: Text.ElideRight
                Layout.fillWidth: true
                QQC2.ToolTip.text: root.phrases[index]
                QQC2.ToolTip.visible: truncated && hovered
                QQC2.ToolTip.delay: 500
            }

            QQC2.TextField {
                id: editField
                visible: root.editIndex === index
                Layout.fillWidth: true
                text: root.phrases[index]
                maximumLength: Memory.MAX_PHRASE_LENGTH
                onAccepted: save()
                Keys.onEscapePressed: root.editIndex = -1
                function save() {
                    var normalized = Memory.normalizePhrase(editField.text);
                    if (!normalized) {
                        root.editIndex = -1;
                        return;
                    }
                    var next = root.phrases.slice();
                    next[index] = normalized;
                    root.editIndex = -1;
                    root.commit(next);
                }
            }

            QQC2.ToolButton {
                visible: root.editIndex !== index
                icon.name: "document-edit"
                QQC2.ToolTip.text: i18n("Edit")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 500
                onClicked: root.editIndex = index
            }

            QQC2.ToolButton {
                visible: root.editIndex === index
                icon.name: "dialog-ok"
                QQC2.ToolTip.text: i18n("Save")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 500
                onClicked: editField.save()
            }

            QQC2.ToolButton {
                icon.name: "edit-delete"
                QQC2.ToolTip.text: i18n("Remove")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 500
                onClicked: {
                    var next = root.phrases.slice();
                    next.splice(index, 1);
                    root.editIndex = -1;
                    root.commit(next);
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            id: newPhraseField
            Layout.fillWidth: true
            placeholderText: atCap ? i18n("Memory is full") : i18n("Add a phrase…")
            enabled: !atCap
            maximumLength: Memory.MAX_PHRASE_LENGTH
            onAccepted: root.addPhrase()
        }

        QQC2.ToolButton {
            icon.name: "list-add"
            enabled: !atCap && Memory.normalizePhrase(newPhraseField.text).length > 0
            QQC2.ToolTip.text: i18n("Add")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
            onClicked: root.addPhrase()
        }
    }
}
