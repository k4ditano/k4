//  El grupo: cada héroe con sus cuatro huecos de equipo y lo que suma.
//  Pulsar un hueco ocupado devuelve la pieza a la bolsa.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

RowLayout {
    id: panel

    property var plugin: null

    spacing: 8

    Repeater {
        model: Game.plantilla.map(function (c) { return Game.claseDe(c) })

        delegate: Rectangle {
            id: tarjeta
            required property var modelData

            readonly property var puesto: Game.equipo[modelData.id] || ({})
            readonly property var permanente: Game.datosHeroe(modelData.id)
            readonly property var stats: Game.statsDe({
                clase: modelData.id, nivel: permanente.nivel
            })
            readonly property var siguiente: Game.proximaHabilidad(modelData.id, permanente.nivel)

            readonly property bool elegido: panel.plugin
                && panel.plugin.heroeElegido === modelData.id

            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Theme.surface
            // el que vienes de pulsar en el campo, marcado
            border.width: elegido ? 1 : 0
            border.color: Theme.blue

            Behavior on border.width { NumberAnimation { duration: 150 } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 9
                spacing: 5

                // ── quién es
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 7

                    Image {
                        source: "assets/heroes/" + tarjeta.modelData.sprite + ".png"
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        fillMode: Image.PreserveAspectFit
                        smooth: false
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        IslandLabel {
                            text: tarjeta.modelData.nombre
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            IslandLabel {
                                text: Idioma.t("nv ") + tarjeta.permanente.nivel
                                color: "#c78fff"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            IslandLabel {
                                text: tarjeta.modelData.papel
                                color: Theme.muted
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                // ── experiencia hacia el siguiente nivel
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 3
                    radius: 1.5
                    color: Theme.islandBg

                    Rectangle {
                        width: parent.width * Math.min(1, tarjeta.permanente.exp
                            / Math.max(1, Game.expParaNivel(tarjeta.permanente.nivel)))
                        height: parent.height
                        radius: parent.radius
                        color: "#c78fff"
                    }
                }

                // ── lo que da ahora mismo
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0

                    Repeater {
                        // Cinco cifras y no tres: con daño y defensa
                        // desdoblados, enseñar solo el total escondía justo lo
                        // que hay que decidir. Se ocultan las que estén a cero
                        // para que un tanque puro no arrastre columnas vacías.
                        model: [
                            { e: "fís",  v: Game.cifra(tarjeta.stats.daño),
                              c: "#ff9f0a", ver: tarjeta.stats.daño >= 1 },
                            { e: "mág",  v: Game.cifra(tarjeta.stats.dañoMag),
                              c: "#bf5af2", ver: tarjeta.stats.dañoMag >= 1 },
                            { e: "vida", v: Game.cifra(tarjeta.stats.vida),
                              c: Theme.green, ver: true },
                            { e: "arm",  v: Game.cifra(tarjeta.stats.armadura),
                              c: "#6ccce4", ver: tarjeta.stats.armadura >= 1 },
                            { e: "res",  v: Game.cifra(tarjeta.stats.resistencia),
                              c: "#5ac8fa", ver: tarjeta.stats.resistencia >= 1 }
                        ]

                        delegate: ColumnLayout {
                            id: dato
                            required property var modelData
                            visible: modelData.ver
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: 0

                            IslandLabel {
                                text: dato.modelData.v
                                color: dato.modelData.c
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                                Layout.fillWidth: true
                            }

                            IslandLabel {
                                text: dato.modelData.e
                                color: Theme.dim
                                font.pixelSize: 8
                                horizontalAlignment: Text.AlignHCenter
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                // ── habilidades: las que sabe y la que viene
                Repeater {
                    model: tarjeta.modelData.habilidades

                    delegate: RowLayout {
                        id: hab
                        required property var modelData
                        readonly property bool sabida: tarjeta.permanente.nivel >= modelData.nivel

                        Layout.fillWidth: true
                        spacing: 6
                        opacity: hab.sabida ? 1 : 0.4

                        IconGlyph {
                            text: String.fromCodePoint(hab.modelData.glifo)
                            color: hab.sabida ? "#ffd60a" : Theme.dim
                            font.pixelSize: 11
                            Layout.preferredWidth: 14
                        }

                        IslandLabel {
                            text: hab.modelData.nombre
                            font.pixelSize: 10
                            font.weight: hab.sabida ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        IslandLabel {
                            text: hab.sabida ? "" : Idioma.t("nv ") + hab.modelData.nivel
                            color: Theme.dim
                            font.pixelSize: 9
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.surfaceHi
                }

                // ── los cuatro huecos
                Repeater {
                    model: Items.huecos

                    delegate: ObjetoFila {
                        id: hueco
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 28

                        objeto: tarjeta.puesto[modelData.id] || null
                        vacio: modelData.nombre
                        onPulsado: {
                            if (objeto)
                                Game.quitar(tarjeta.modelData.id, hueco.modelData.id)
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
