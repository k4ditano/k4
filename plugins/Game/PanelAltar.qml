//  El altar: lo que se compra con reliquias y queda para siempre.
//
//  Es la progresión que sobrevive a la muerte, junto con el equipo. Las
//  reliquias salen de morir y de desguazar lo que no sirve.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: panel

    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 22
        spacing: 8

        IconGlyph {
            text: String.fromCodePoint(0xF0BC2)
            color: "#c78fff"
            font.pixelSize: 14
            Layout.alignment: Qt.AlignVCenter
        }

        IslandLabel {
            text: Game.cifra(Game.reliquias) + Idioma.t(" reliquias")
            font.pixelSize: 13
            font.weight: Font.DemiBold
            Layout.alignment: Qt.AlignVCenter
        }

        IslandLabel {
            text: Idioma.t("de morir y de desguazar")
            color: Theme.dim
            font.pixelSize: 9
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }
    }

    Repeater {
        model: Game.metaDef

        delegate: Rectangle {
            id: mejora
            required property var modelData
            readonly property int precio: Game.costeMeta(modelData.id)
            readonly property bool asequible: Game.reliquias >= precio

            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 9
            color: metaMouse.containsMouse && asequible ? Theme.surfaceHi : Theme.surface
            border.width: asequible ? 1 : 0
            border.color: "#c78fff"

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 11
                anchors.rightMargin: 11
                spacing: 9

                IconGlyph {
                    text: String.fromCodePoint(mejora.modelData.glifo)
                    color: mejora.asequible ? "#c78fff" : Theme.dim
                    font.pixelSize: 15
                    Layout.preferredWidth: 18
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    RowLayout {
                        spacing: 6

                        IslandLabel {
                            text: mejora.modelData.nombre
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        IslandLabel {
                            text: Idioma.t("nv ") + Game.meta[mejora.modelData.id]
                            color: Theme.dim
                            font.pixelSize: 9
                        }
                    }

                    IslandLabel {
                        text: mejora.modelData.desc
                        color: Theme.muted
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                IconGlyph {
                    text: String.fromCodePoint(0xF0BC2)
                    color: mejora.asequible ? "#c78fff" : Theme.dim
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignVCenter
                }

                IslandLabel {
                    text: Game.cifra(mejora.precio)
                    color: mejora.asequible ? "#c78fff" : Theme.dim
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            MouseArea {
                id: metaMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: mejora.asequible ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: Game.comprarMeta(mejora.modelData.id)
            }
        }
    }

    Item { Layout.fillHeight: true }

    // ── resumen de la carrera
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 30
        spacing: 0

        Repeater {
            model: [
                { e: "mejor oleada", v: Game.mejorOleada + "" },
                { e: "partidas",     v: Game.partidas + "" },
                { e: "en la bolsa",  v: Game.bolsa.length + "" },
                { e: "cofres",       v: Game.cofres + "" }
            ]

            delegate: ColumnLayout {
                id: dato
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 0

                IslandLabel {
                    text: dato.modelData.v
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }

                IslandLabel {
                    text: dato.modelData.e
                    color: Theme.dim
                    font.pixelSize: 9
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
            }
        }
    }
}
