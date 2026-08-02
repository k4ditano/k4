//  La lista de lo copiado.
//
//  Se teclea directamente para filtrar —sin pulsar en ningún sitio, como en el
//  lanzador— y cada fila enseña de qué es: enlace, color, orden, ruta, código
//  o imagen. Lo fijado sube arriba y no caduca.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    // Sin esto hay que hacer clic antes de poder escribir: la raíz de la
    // island se queda el foco y la superficie tarda en recibirlo.
    FocoInicial { id: foco; objetivo: entrada }
    Component.onCompleted: foco.reclamar()

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        // ── búsqueda ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF0349)
                color: Theme.muted
                font.pixelSize: 15
                Layout.alignment: Qt.AlignVCenter
            }

            TextInput {
                id: entrada
                cursorDelegate: IslandCursor {}
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                text: view.plugin.query
                onTextEdited: {
                    view.plugin.query = text
                    view.plugin.index = 0
                }

                color: Theme.ink
                font.pixelSize: 15
                font.family: Theme.uiFont
                selectByMouse: true
                selectionColor: Theme.blue
                cursorVisible: true
                verticalAlignment: TextInput.AlignVCenter
                focus: true
                activeFocusOnTab: true
                clip: true

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: entrada.text.length === 0
                    text: Idioma.t("Buscar en el portapapeles…")
                    color: Theme.dim
                    font.pixelSize: 15
                }

                Keys.onPressed: function (ev) {
                    if (ev.key === Qt.Key_Escape) {
                        view.plugin.close()
                        ev.accepted = true
                    } else if (ev.key === Qt.Key_Down) {
                        view.plugin.mover(1); ev.accepted = true
                    } else if (ev.key === Qt.Key_Up) {
                        view.plugin.mover(-1); ev.accepted = true
                    } else if (ev.key === Qt.Key_PageDown) {
                        view.plugin.mover(6); ev.accepted = true
                    } else if (ev.key === Qt.Key_PageUp) {
                        view.plugin.mover(-6); ev.accepted = true
                    } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                        view.plugin.elegir(); ev.accepted = true
                    } else if (ev.key === Qt.Key_Delete) {
                        view.plugin.borrarActual(); ev.accepted = true
                    } else if (ev.modifiers & Qt.ControlModifier
                               && ev.key === Qt.Key_P) {
                        view.plugin.fijarActual(); ev.accepted = true
                    }
                }
            }

            IslandLabel {
                text: view.plugin.count + (view.plugin.count === 1 ? Idioma.t(" copia") : Idioma.t(" copias"))
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                Layout.preferredWidth: vaciar.implicitWidth + 20
                Layout.preferredHeight: 20
                radius: 10
                color: vaciarMouse.containsMouse ? Theme.red : Theme.surfaceHi
                visible: Clipboard.count > 0

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: vaciar
                    anchors.centerIn: parent
                    text: Idioma.t("Vaciar")
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: vaciarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Clipboard.limpiar()
                }
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── la lista ──────────────────────────────────────────────
        ListView {
            //  La barra de la casa: se ve solo si hay más de lo que cabe.
            ScrollBar.vertical: IslandScrollBar {}
            id: filas
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3
            model: view.plugin.lista
            currentIndex: view.plugin.index
            highlightMoveDuration: 130
            boundsBehavior: Flickable.StopAtBounds

            // que el seleccionado quede siempre a la vista al moverse con las
            // flechas, sin saltar la lista entera
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: fila
                required property var modelData
                required property int index

                readonly property bool elegida: index === view.plugin.index
                readonly property bool esImagen: modelData.tipo === "imagen"

                width: ListView.view.width
                height: 48
                radius: 9
                color: elegida ? Theme.surfaceHi
                    : (filaMouse.containsMouse ? Theme.surface : "transparent")

                Behavior on color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 9

                    // la miniatura vale más que cualquier icono
                    Image {
                        visible: fila.esImagen
                        source: fila.esImagen ? "file://" + fila.modelData.ruta : ""
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    IconGlyph {
                        visible: !fila.esImagen
                        text: String.fromCodePoint(
                            fila.modelData.etiqueta === "enlace" ? 0xF0339
                            : fila.modelData.etiqueta === "color" ? 0xF0765
                            : fila.modelData.etiqueta === "orden" ? 0xF018D
                            : fila.modelData.etiqueta === "ruta" ? 0xF024B
                            : fila.modelData.etiqueta === "código" ? 0xF0169
                            : 0xF0219)
                        color: fila.elegida ? Theme.ink : Theme.muted
                        font.pixelSize: 17
                        Layout.preferredWidth: 30
                        Layout.alignment: Qt.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        IslandLabel {
                            text: Clipboard.titulo(fila.modelData)
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: 6

                            IslandLabel {
                                visible: (fila.modelData.etiqueta || "").length > 0
                                text: fila.modelData.etiqueta
                                color: Theme.blue
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            IslandLabel {
                                visible: fila.modelData.lineas > 1
                                text: fila.modelData.lineas + Idioma.t(" líneas")
                                color: Theme.dim
                                font.pixelSize: 11
                            }

                            IslandLabel {
                                text: Clipboard.tamaño(fila.modelData.bytes)
                                color: Theme.dim
                                font.pixelSize: 11
                            }
                        }
                    }

                    // una muestra del color: leer "#ff453a" no es verlo
                    Rectangle {
                        visible: fila.modelData.etiqueta === "color"
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        radius: 4
                        color: fila.modelData.etiqueta === "color"
                            ? fila.modelData.resumen.trim() : "transparent"
                        border.width: 1
                        border.color: "#33ffffff"
                    }

                    IslandLabel {
                        text: Clipboard.hace(fila.modelData.cuando)
                        color: Theme.dim
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }

                    MediaButton {
                        glyph: String.fromCodePoint(0xF0403)
                        glyphSize: 13
                        glyphColor: fila.modelData.fijado ? "#ffd60a" : Theme.dim
                        opacity: fila.modelData.fijado || fila.elegida
                            || filaMouse.containsMouse ? 1 : 0
                        onActivated: Clipboard.fijar(fila.modelData.id)
                        Layout.alignment: Qt.AlignVCenter

                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    MediaButton {
                        glyph: Theme.ico.close
                        glyphSize: 12
                        glyphColor: Theme.dim
                        opacity: fila.elegida || filaMouse.containsMouse ? 1 : 0
                        onActivated: Clipboard.borrar(fila.modelData.id)
                        Layout.alignment: Qt.AlignVCenter

                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                }

                MouseArea {
                    id: filaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    z: -1
                    onClicked: {
                        view.plugin.index = fila.index
                        view.plugin.elegir()
                    }
                }
            }
        }

        // ── ayuda y vacío ─────────────────────────────────────────
        IslandLabel {
            Layout.fillWidth: true
            visible: view.plugin.count === 0
            text: Clipboard.count === 0
                ? Idioma.t("Todavía no has copiado nada")
                : Idioma.t("Nada que coincida con la búsqueda")
            color: Theme.muted
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
        }

        IslandLabel {
            Layout.fillWidth: true
            visible: view.plugin.count > 0
            text: Idioma.t("intro copia · supr borra · ctrl+p fija · esc cierra")
            color: Theme.dim
            font.pixelSize: 9
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
