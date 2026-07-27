//  El grupo: cada héroe con sus cuatro huecos de equipo y lo que suma.
//  Pulsar un hueco ocupado devuelve la pieza a la bolsa.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

RowLayout {
    id: panel

    spacing: 8

    Repeater {
        model: Game.clases

        delegate: Rectangle {
            id: tarjeta
            required property var modelData

            readonly property var puesto: Game.equipo[modelData.id] || ({})
            readonly property var stats: Game.statsDe({ clase: modelData.id })

            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Theme.surface

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

                        IslandLabel {
                            text: tarjeta.modelData.papel
                            color: Theme.muted
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                // ── lo que da ahora mismo
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0

                    Repeater {
                        model: [
                            { e: "daño", v: Game.cifra(tarjeta.stats.daño), c: "#ff9f0a" },
                            { e: "vida", v: Game.cifra(tarjeta.stats.vida), c: Theme.green },
                            { e: "arm",  v: Game.cifra(tarjeta.stats.armadura), c: "#6ccce4" }
                        ]

                        delegate: ColumnLayout {
                            id: dato
                            required property var modelData
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
