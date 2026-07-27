//  Logros: metas largas, en familias escalonadas.
//
//  Se ordenan por lo cerca que están de caer, así que arriba siempre hay algo
//  a tiro y abajo queda lo que da para meses.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: panel

    spacing: 6

    readonly property var ordenados: {
        const lista = Logros.definicion.slice()
        lista.sort(function (a, b) {
            const ha = Game.logrosHechos.indexOf(a.id) !== -1
            const hb = Game.logrosHechos.indexOf(b.id) !== -1
            if (ha !== hb) return ha ? 1 : -1      // lo hecho, al final
            return Logros.progresoDe(b, Game) - Logros.progresoDe(a, Game)
        })
        return lista
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 16
        spacing: 8

        IslandLabel {
            text: Game.logrosHechos.length + " / " + Logros.definicion.length + " logros"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        IslandLabel {
            text: "dan reliquias y cofres al caer"
            color: Theme.dim
            font.pixelSize: 9
            Layout.fillWidth: true
        }
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 3
        model: panel.ordenados
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: fila
            required property var modelData
            readonly property bool hecho: Game.logrosHechos.indexOf(modelData.id) !== -1
            readonly property real progreso: Logros.progresoDe(modelData, Game)

            width: ListView.view.width
            height: 34
            radius: 8
            color: hecho ? "#14301a" : Theme.surface
            border.width: hecho ? 1 : 0
            border.color: Theme.green

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 9

                IconGlyph {
                    text: String.fromCodePoint(fila.hecho ? 0xF012C : 0xF0BC2)
                    color: fila.hecho ? Theme.green : Theme.dim
                    font.pixelSize: 13
                    Layout.preferredWidth: 16
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        IslandLabel {
                            text: fila.modelData.nombre
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: fila.hecho ? Theme.green : Theme.ink
                        }

                        IslandLabel {
                            text: fila.modelData.desc
                            color: Theme.muted
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 3
                        radius: 1.5
                        color: Theme.islandBg

                        Rectangle {
                            width: parent.width * fila.progreso
                            height: parent.height
                            radius: parent.radius
                            color: fila.hecho ? Theme.green : "#ffd60a"
                        }
                    }
                }

                IslandLabel {
                    text: Logros.textoProgreso(fila.modelData, Game)
                    color: Theme.dim
                    font.pixelSize: 9
                    Layout.alignment: Qt.AlignVCenter
                }

                RowLayout {
                    spacing: 3
                    Layout.alignment: Qt.AlignVCenter

                    IconGlyph {
                        text: String.fromCodePoint(0xF0BC2)
                        color: "#c78fff"
                        font.pixelSize: 9
                    }

                    IslandLabel {
                        text: Game.cifra(fila.modelData.reliquias)
                        color: "#c78fff"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
