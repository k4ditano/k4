//  La rejilla del centro de aplicaciones.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    readonly property int celdaAncho: 128
    readonly property int celdaAlto: 104

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ── el buscador ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 12
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                IconGlyph {
                    text: ""  // fa-search
                    color: Theme.muted
                    font.pixelSize: 15
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextInput {
                        id: entrada
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 16
                        focus: true
                        clip: true
                        selectByMouse: true
                        selectionColor: Theme.blue
                        text: view.plugin.busqueda

                        onTextEdited: {
                            view.plugin.busqueda = text
                            view.plugin.seleccion = 0
                        }

                        Keys.onPressed: function (ev) {
                            if (ev.key === Qt.Key_Escape)
                                view.plugin.cerrar()
                            else if (ev.key === Qt.Key_Return
                                     || ev.key === Qt.Key_Enter)
                                view.plugin.lanzarSeleccion()
                            else if (ev.key === Qt.Key_Right)
                                view.plugin.mover(1, 0)
                            else if (ev.key === Qt.Key_Left)
                                view.plugin.mover(-1, 0)
                            else if (ev.key === Qt.Key_Down)
                                view.plugin.mover(0, 1)
                            else if (ev.key === Qt.Key_Up)
                                view.plugin.mover(0, -1)
                            else
                                return
                            ev.accepted = true
                        }

                        IslandLabel {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: entrada.text.length === 0
                            text: Idioma.t("Buscar aplicaciones")
                            color: Theme.dim
                            font.pixelSize: 16
                        }
                    }
                }

                IslandLabel {
                    text: view.plugin.lista.length
                    color: Theme.muted
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }

        // ── la rejilla ────────────────────────────────────────────
        K4.Rodillo {
            Layout.fillWidth: true
            Layout.fillHeight: true
            muesca: view.celdaAlto

            Flow {
                width: parent.width
                spacing: 4

                Repeater {
                    model: view.plugin.lista

                    delegate: IslandTile {
                        id: celda
                        required property var modelData
                        required property int index

                        width: view.celdaAncho
                        height: view.celdaAlto

                        //  La elegida con el teclado lleva borde azul, no solo
                        //  el fondo claro: el fondo claro ya lo pone el ratón
                        //  al pasar y las dos cosas se confundían — no se sabía
                        //  qué iba a abrir el Enter.
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.blue
                            visible: celda.index === view.plugin.seleccion
                        }
                        //  Una apagada no se abre, pero sí se puede pulsar:
                        //  el clic lleva a Ajustes, que es lo que hace falta.
                        onPulsada: modelData.habilitado
                            ? view.plugin.lanzar(modelData.id)
                            : view.plugin.lanzar("settings")

                        //  La chincheta: pone o quita esta aplicación de la
                        //  franja del centro de control. Solo al pasar por
                        //  encima —o si ya está puesta, siempre—, que si no
                        //  la rejilla se llena de iconos que no son la app.
                        IconGlyph {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            z: 2
                            text: String.fromCodePoint(0xF0403)   // md-pin
                            font.pixelSize: 13
                            visible: celda.encima
                                || Settings.esAccesoDirecto(celda.modelData.id)
                            color: Settings.esAccesoDirecto(celda.modelData.id)
                                ? Theme.blue : Theme.dim
                            rotation: Settings.esAccesoDirecto(celda.modelData.id)
                                ? 0 : 45

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Settings.alternarAcceso(celda.modelData.id)
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            IconGlyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: String.fromCodePoint(celda.modelData.glifo)
                                font.pixelSize: 30
                                color: celda.modelData.habilitado
                                    ? (celda.modelData.disponible ? Theme.ink
                                                                  : Theme.red)
                                    : Theme.dim
                            }

                            IslandLabel {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: view.celdaAncho - 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: celda.modelData.nombre
                                font.pixelSize: 11
                                color: celda.modelData.habilitado ? Theme.ink
                                                                  : Theme.dim
                            }
                        }
                    }
                }
            }
        }
    }

    //  El foco al buscador en cuanto se abre: se abre para escribir.
    FocoInicial { id: foco; objetivo: entrada }
    Component.onCompleted: foco.reclamar()
}
