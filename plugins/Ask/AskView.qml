import QtQuick
import QtQuick.Controls
import "../../services"
import QtQuick.Layouts
import K4 as K4
import "../../core"

FadeIn {
    id: view

    required property var plugin

    property int focusAttempts: 0
    property string ampliada: ""     // imagen que se está viendo a tamaño grande

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

    // ── imagen a tamaño grande, por encima de la conversación
    Rectangle {
        id: visor
        anchors.fill: parent
        z: 10
        visible: view.ampliada.length > 0
        color: "#f2000000"
        radius: 12

        Image {
            anchors.fill: parent
            anchors.margins: 16
            anchors.bottomMargin: 40
            source: view.ampliada.length > 0 ? "file://" + view.ampliada : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        RowLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            spacing: 8

            Repeater {
                model: [
                    { t: "Guardar en Imágenes", a: "guardar" },
                    { t: "Abrir fuera",         a: "abrir" },
                    { t: "Cerrar",              a: "cerrar" }
                ]

                delegate: Rectangle {
                    id: boton
                    required property var modelData
                    Layout.preferredWidth: etiqueta.implicitWidth + 22
                    Layout.preferredHeight: 24
                    radius: 12
                    color: botonMouse.containsMouse ? Theme.blue : Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: 120 } }

                    IslandLabel {
                        id: etiqueta
                        anchors.centerIn: parent
                        text: boton.modelData.t
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: botonMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (boton.modelData.a === "guardar")
                                view.plugin.guardarImagen(view.ampliada)
                            else if (boton.modelData.a === "abrir")
                                view.plugin.abrirExterno(view.ampliada)
                            else
                                view.ampliada = ""
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: view.ampliada = ""
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
                text: Idioma.t("Preguntar")
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
                text: view.plugin.status === "thinking" ? Idioma.t("pensando…") : "esc"
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

            //  Apartar y olvidar, a la vista. Cerrar con Escape ya apartaba
            //  la conversación, pero un gesto que no se ve no existe: el −
            //  la deja esperando en la píldora y la ✕ la tira de verdad.
            MediaButton {
                visible: view.plugin.messages.length > 0
                glyph: String.fromCodePoint(0xEABA)
                glyphSize: 12
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.cerrarYOlvidar()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── conversación
        ListView {
            //  La barra de la casa: se ve solo si hay más de lo que cabe.
            ScrollBar.vertical: IslandScrollBar {}
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

                readonly property string imagen: modelData.imagen || ""

                Rectangle {
                    id: bubble
                    x: messageRow.mine ? messageRow.width - width : 0
                    width: messageRow.mine
                        ? Math.min(Math.max(messageText.implicitWidth + 28, miniatura.visible ? 190 : 0),
                                   messageRow.width * 0.78)
                        : messageRow.width
                    height: messageText.implicitHeight + (miniatura.visible ? miniatura.height + 8 : 0)
                        + (messageRow.mine ? 18 : 4)
                    radius: 14
                    color: messageRow.mine ? Theme.surfaceHi : "transparent"

                    // Formato de verdad: negrita, cursiva, código y enlaces
                    // pulsables. Antes se pedía a Codex que respondiera en
                    // texto plano justamente porque esto no existía.
                    TextEdit {
                        id: messageText
                        x: messageRow.mine ? 14 : 0
                        y: messageRow.mine ? 9 : 2
                        width: bubble.width - (messageRow.mine ? 28 : 0)
                        readOnly: true
                        selectByMouse: true
                        wrapMode: Text.WordWrap
                        textFormat: TextEdit.MarkdownText
                        color: messageRow.modelData.role === "error" ? Theme.red : Theme.ink
                        selectionColor: Theme.blue
                        font.family: Theme.uiFont
                        font.pixelSize: 14
                        opacity: messageRow.modelData.text.length > 0 ? 1 : 0.45
                        text: messageRow.modelData.text.length > 0 ? messageRow.modelData.text : "…"

                        onLinkActivated: function (enlace) {
                            K4.Sistema.lanzar(["xdg-open", enlace])
                        }

                        // el cursor avisa de que el enlace se puede pulsar
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            cursorShape: messageText.hoveredLink.length > 0
                                ? Qt.PointingHandCursor : Qt.IBeamCursor
                        }
                    }

                    // ── imagen adjunta o devuelta
                    Rectangle {
                        id: miniatura
                        visible: messageRow.imagen.length > 0
                        anchors.right: messageRow.mine ? parent.right : undefined
                        anchors.left: messageRow.mine ? undefined : parent.left
                        anchors.rightMargin: messageRow.mine ? 14 : 0
                        anchors.top: messageText.bottom
                        anchors.topMargin: 8
                        width: 160
                        height: 96
                        radius: 10
                        color: Theme.islandBg
                        clip: true
                        border.width: miniMouse.containsMouse ? 1 : 0
                        border.color: Theme.blue

                        Image {
                            anchors.fill: parent
                            source: messageRow.imagen.length > 0 ? "file://" + messageRow.imagen : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 320
                        }

                        // acciones, solo al pasar por encima
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 22
                            color: "#cc000000"
                            visible: miniMouse.containsMouse

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 12

                                Repeater {
                                    model: [
                                        { g: Theme.ico.search, t: "ampliar" },
                                        { g: 0xF0193,          t: "guardar" },
                                        { g: Theme.ico.forward, t: "abrir" }
                                    ]

                                    //  Item por fuera y la fila dentro: el
                                    //  MouseArea no puede colgar del layout.
                                    //  Un hijo directo es una celda más y el
                                    //  layout le impone la geometría, así que
                                    //  el `anchors.fill` no se aplicaba y —sin
                                    //  tamaño implícito— la zona quedaba en
                                    //  0×0: ni se iluminaban al pasar por
                                    //  encima ni hacían nada al pulsarlas.
                                    //  Mismo caso que JuegoPildora.
                                    delegate: Item {
                                        id: accion
                                        required property var modelData
                                        required property int index

                                        implicitWidth: filaAccion.implicitWidth
                                        implicitHeight: filaAccion.implicitHeight

                                        RowLayout {
                                            id: filaAccion
                                            anchors.fill: parent
                                            spacing: 3

                                            IconGlyph {
                                                text: typeof accion.modelData.g === "number"
                                                    ? String.fromCodePoint(accion.modelData.g)
                                                    : accion.modelData.g
                                                color: accionMouse.containsMouse ? Theme.blue : Theme.ink
                                                font.pixelSize: 10
                                            }

                                            IslandLabel {
                                                text: accion.modelData.t
                                                color: accionMouse.containsMouse ? Theme.blue : Theme.ink
                                                font.pixelSize: 9
                                            }
                                        }

                                        MouseArea {
                                            id: accionMouse
                                            anchors.fill: parent
                                            anchors.margins: -3
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (accion.index === 0)
                                                    view.ampliada = messageRow.imagen
                                                else if (accion.index === 1)
                                                    view.plugin.guardarImagen(messageRow.imagen)
                                                else
                                                    view.plugin.abrirExterno(messageRow.imagen)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: miniMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.ampliada = messageRow.imagen
                        }
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
                text: view.plugin.messages.length > 0 ? Idioma.t("Sigue preguntando…") : Idioma.t("Pregunta lo que quieras…")
                color: Theme.dim
                font.pixelSize: view.plugin.messages.length > 0 ? 15 : 19
            }

            TextInput {
                id: askInput
                cursorDelegate: IslandCursor {}
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
