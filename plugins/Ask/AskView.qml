import QtQuick
import QtQuick.Layouts
import "../../core"

FadeIn {
    id: view

    required property var plugin

    property int focusAttempts: 0

    Component.onCompleted: {
        focusAttempts = 0
        focusTimer.start()
        Qt.callLater(function () { askInput.forceActiveFocus() })
    }

    // La layer surface tarda en recibir el foco de teclado: se reintenta unas
    // cuantas veces en vez de dar por hecho que llegó a la primera.
    Timer {
        id: focusTimer
        interval: 140
        onTriggered: {
            if (!view.plugin.open)
                return

            askInput.forceActiveFocus()
            if (!askInput.activeFocus && view.focusAttempts < 6) {
                view.focusAttempts += 1
                restart()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        spacing: 10

        // ── cabecera: qué se envía y control de la sesión
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 22
            spacing: 8

            IconGlyph {
                text: Theme.ico.ask
                color: Theme.muted
                font.pixelSize: 15
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: "Preguntar"
                color: Theme.muted
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter
            }

            Repeater {
                model: [
                    { key: "image", on: view.plugin.image.length > 0, attached: true,
                      glyph: Theme.ico.shot, label: "captura" },
                    { key: "selection",
                      on: view.plugin.selection.length > 0 || view.plugin.selectionCandidate.length > 0,
                      attached: view.plugin.selection.length > 0,
                      glyph: Theme.ico.selection,
                      label: view.plugin.selection.length > 0
                          ? view.plugin.preview(view.plugin.selection)
                          : "adjuntar: " + view.plugin.preview(view.plugin.selectionCandidate) }
                ]

                delegate: Rectangle {
                    id: attachmentChip
                    required property var modelData
                    visible: modelData.on
                    Layout.preferredWidth: Math.min(chipRow.implicitWidth + 18, 260)
                    Layout.preferredHeight: 20
                    Layout.alignment: Qt.AlignVCenter
                    radius: 10
                    color: attachmentChip.modelData.attached
                        ? (attachmentMouse.containsMouse ? Theme.track : Theme.surfaceHi)
                        : (attachmentMouse.containsMouse ? Theme.surfaceHi : "transparent")
                    border.width: attachmentChip.modelData.attached ? 0 : 1
                    border.color: Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        id: chipRow
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 5

                        IconGlyph {
                            text: attachmentChip.modelData.glyph
                            color: attachmentChip.modelData.attached ? Theme.ink : Theme.muted
                            font.pixelSize: 11
                            Layout.alignment: Qt.AlignVCenter
                        }

                        IslandLabel {
                            text: attachmentChip.modelData.label
                            color: attachmentChip.modelData.attached ? Theme.ink : Theme.muted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        IconGlyph {
                            text: attachmentChip.modelData.attached ? Theme.ico.close : "⇥"
                            color: attachmentMouse.containsMouse ? Theme.ink : Theme.dim
                            font.pixelSize: attachmentChip.modelData.attached ? 11 : 10
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    // clic: adjunta lo ofrecido, o quita lo ya adjuntado
                    MouseArea {
                        id: attachmentMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (attachmentChip.modelData.key === "image")
                                view.plugin.image = ""
                            else if (attachmentChip.modelData.attached)
                                view.plugin.selection = ""
                            else
                                view.plugin.attach()
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // acciones sobre la conversación
            Repeater {
                model: [
                    { key: "new", glyph: Theme.ico.ask, label: "nueva" },
                    { key: "copy", glyph: Theme.ico.copy, label: "copiar" }
                ]

                delegate: Rectangle {
                    id: actionChip
                    required property var modelData
                    visible: view.plugin.messages.length > 0
                    Layout.preferredWidth: actionRow.implicitWidth + 18
                    Layout.preferredHeight: 20
                    Layout.alignment: Qt.AlignVCenter
                    radius: 10
                    color: actionMouse.containsMouse ? Theme.track : Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        id: actionRow
                        anchors.centerIn: parent
                        spacing: 5

                        IconGlyph {
                            text: actionChip.modelData.glyph
                            color: Theme.muted
                            font.pixelSize: 11
                        }

                        IslandLabel {
                            text: actionChip.modelData.label
                            color: Theme.muted
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (actionChip.modelData.key === "new")
                                view.plugin.newConversation()
                            else
                                view.plugin.copyAnswer()
                        }
                    }
                }
            }

            IslandLabel {
                text: view.plugin.status === "thinking" ? "pensando…" : "esc"
                color: Theme.dim
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter

                SequentialAnimation on opacity {
                    running: view.plugin.status === "thinking"
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 620; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                }
            }
        }

        // ── conversación
        ListView {
            id: conversationList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: view.plugin.messages.length > 0
            clip: true
            spacing: 12
            model: view.plugin.messages
            boundsBehavior: Flickable.StopAtBounds

            onCountChanged: Qt.callLater(function () { conversationList.positionViewAtEnd() })
            onContentHeightChanged: Qt.callLater(function () { conversationList.positionViewAtEnd() })

            delegate: Item {
                id: messageRow
                required property var modelData
                readonly property bool mine: modelData.role === "user"
                width: ListView.view.width
                height: bubble.height

                Rectangle {
                    id: bubble
                    x: messageRow.mine ? messageRow.width - width : 0
                    width: messageRow.mine
                        ? Math.min(messageText.implicitWidth + 28, messageRow.width * 0.78)
                        : messageRow.width
                    height: messageText.implicitHeight + (messageRow.mine ? 18 : 4)
                    radius: 14
                    color: messageRow.mine ? Theme.surfaceHi : "transparent"

                    TextEdit {
                        id: messageText
                        x: messageRow.mine ? 14 : 0
                        y: messageRow.mine ? 9 : 2
                        width: bubble.width - (messageRow.mine ? 28 : 0)
                        readOnly: true
                        selectByMouse: true
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        color: messageRow.modelData.role === "error" ? Theme.red : Theme.ink
                        selectionColor: Theme.blue
                        font.family: Theme.uiFont
                        font.pixelSize: 14
                        opacity: messageRow.modelData.text.length > 0 ? 1 : 0.45
                        text: messageRow.modelData.text.length > 0 ? messageRow.modelData.text : "…"
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 1
            color: Theme.surfaceHi
            visible: view.plugin.messages.length > 0
        }

        // ── entrada, siempre abajo para poder seguir preguntando
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 34

            IslandLabel {
                anchors.verticalCenter: parent.verticalCenter
                visible: view.plugin.query.length === 0
                text: view.plugin.messages.length > 0 ? "Sigue preguntando…" : "Pregunta lo que quieras…"
                color: Theme.dim
                font.pixelSize: view.plugin.messages.length > 0 ? 15 : 19
            }

            TextInput {
                id: askInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.ink
                font.family: Theme.uiFont
                font.pixelSize: view.plugin.messages.length > 0 ? 15 : 19
                focus: true
                activeFocusOnTab: true
                clip: true
                selectByMouse: true
                cursorVisible: true
                selectionColor: Theme.blue
                text: view.plugin.query
                onTextEdited: view.plugin.query = text

                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Escape) {
                        view.plugin.close()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        view.plugin.send()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Tab) {
                        view.plugin.attach()   // adjunta el texto seleccionado
                        event.accepted = true
                    }
                }
            }
        }
    }
}
