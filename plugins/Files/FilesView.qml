//  La lista de ficheros encontrados.
//
//  Cada fila dice de qué es por el icono y el color, dónde está por la ruta
//  acortada, y cuánto ocupa y cuándo se tocó por última vez, que suele ser lo
//  que distingue el fichero que buscas de los otros seis con el mismo nombre.

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

                text: Archivos.consulta
                onTextEdited: {
                    Archivos.consulta = text
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
                clip: true

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: entrada.text.length === 0
                    text: Idioma.t("Buscar archivos y carpetas…")
                    color: Theme.dim
                    font.pixelSize: 15
                }

                Keys.onPressed: function (ev) {
                    const ctrl = (ev.modifiers & Qt.ControlModifier) !== 0

                    if (ev.key === Qt.Key_Down) {
                        view.plugin.mover(1); ev.accepted = true
                    } else if (ev.key === Qt.Key_Up) {
                        view.plugin.mover(-1); ev.accepted = true
                    } else if (ev.key === Qt.Key_PageDown) {
                        view.plugin.mover(6); ev.accepted = true
                    } else if (ev.key === Qt.Key_PageUp) {
                        view.plugin.mover(-6); ev.accepted = true
                    } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                        if (ctrl) view.plugin.abrirDonde()
                        else view.plugin.elegir()
                        ev.accepted = true
                    } else if (ctrl && ev.key === Qt.Key_C) {
                        view.plugin.copiar(); ev.accepted = true
                    } else if (ev.key === Qt.Key_Tab) {
                        view.plugin.alternarAmbito(); ev.accepted = true
                    }
                }
            }

            // ── dónde buscar y qué
            Repeater {
                model: [
                    { id: "ambito", texto: "Todo el sistema" },
                    { id: "archivo", texto: "Solo archivos" },
                    { id: "dir", texto: "Solo carpetas" }
                ]

                delegate: Rectangle {
                    id: filtro
                    required property var modelData

                    readonly property bool puesto: modelData.id === "ambito"
                        ? Archivos.ambito === "sistema"
                        : Archivos.solo === modelData.id

                    Layout.preferredWidth: etiqueta.implicitWidth + 18
                    Layout.preferredHeight: 22
                    Layout.alignment: Qt.AlignVCenter
                    radius: 11
                    color: puesto ? Theme.blue
                        : (filtroRaton.containsMouse ? Theme.surfaceHi : Theme.surface)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    IslandLabel {
                        id: etiqueta
                        anchors.centerIn: parent
                        text: filtro.modelData.texto
                        color: filtro.puesto ? Theme.ink : Theme.muted
                        font.pixelSize: 10
                        font.weight: filtro.puesto ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: filtroRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (filtro.modelData.id === "ambito")
                                view.plugin.alternarAmbito()
                            else
                                view.plugin.alternarSolo(filtro.modelData.id)
                        }
                    }
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

        // ── resultados ────────────────────────────────────────────
        ListView {
            //  La barra de la casa: se ve solo si hay más de lo que cabe.
            ScrollBar.vertical: IslandScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: view.plugin.lista
            currentIndex: view.plugin.index
            boundsBehavior: Flickable.StopAtBounds

            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: fila
                required property var modelData
                required property int index

                readonly property bool elegida: index === view.plugin.index

                width: ListView.view.width
                height: 48
                radius: 9
                color: elegida ? Theme.surfaceHi
                    : (filaRaton.containsMouse ? Theme.surface : "transparent")

                Behavior on color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 9

                    IconGlyph {
                        text: String.fromCodePoint(Archivos.glifo(fila.modelData))
                        color: Archivos.tono(fila.modelData)
                        font.pixelSize: 18
                        Layout.preferredWidth: 22
                        Layout.alignment: Qt.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        IslandLabel {
                            text: fila.modelData.nombre
                            font.pixelSize: 14
                            font.weight: fila.elegida ? Font.DemiBold : Font.Normal
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }

                        IslandLabel {
                            text: Archivos.dondeEsta(fila.modelData.carpeta)
                            color: Theme.dim
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }

                    IslandLabel {
                        text: fila.modelData.esCarpeta
                            ? "carpeta" : Archivos.tamaño(fila.modelData.bytes)
                        color: Theme.muted
                        font.pixelSize: 11
                        Layout.preferredWidth: 70
                        horizontalAlignment: Text.AlignRight
                    }

                    IslandLabel {
                        text: Archivos.hace(fila.modelData.cuando)
                        color: Theme.dim
                        font.pixelSize: 11
                        Layout.preferredWidth: 60
                        horizontalAlignment: Text.AlignRight
                    }
                }

                MouseArea {
                    id: filaRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function (mouse) {
                        view.plugin.index = fila.index
                        if (mouse.button === Qt.RightButton)
                            view.plugin.abrirDonde()
                        else
                            view.plugin.elegir()
                    }
                }
            }
        }

        // ── pie ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IslandLabel {
                text: {
                    if (Archivos.consulta.trim().length < 2)
                        return Idioma.t("escribe al menos dos letras")
                    if (Archivos.buscando)
                        return Idioma.t("buscando…")
                    if (view.plugin.count === 0)
                        return Idioma.t("nada que coincida")
                    return view.plugin.count + Idioma.t(" de ") + Archivos.total
                        + " · " + Archivos.ms + " ms"
                }
                color: Theme.dim
                font.pixelSize: 9
            }

            Item { Layout.fillWidth: true }

            IslandLabel {
                text: Idioma.t("intro abre · ctrl+intro la carpeta · ctrl+c copia la ruta · tab cambia el ámbito")
                color: Theme.dim
                font.pixelSize: 9
            }
        }
    }
}
