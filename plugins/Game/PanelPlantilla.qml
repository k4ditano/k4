//  La plantilla: quién sale al campo, quién está por desbloquear y con qué.
//
//  Pulsar un héroe lo mete o lo saca del equipo, y eso reinicia la partida:
//  no se puede cambiar de gente a mitad de una pelea.

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
        Layout.preferredHeight: 16
        spacing: 8

        IslandLabel {
            text: Idioma.t("Equipo ") + Game.plantilla.length + "/" + Game.huecosPlantilla
            color: Theme.muted
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }

        IslandLabel {
            text: Idioma.t("pulsa para meter o sacar · cambiar reinicia la partida")
            color: Theme.dim
            font.pixelSize: 9
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        IslandLabel {
            text: Game.desbloqueados.length + "/" + Game.clases.length + Idioma.t(" héroes")
            color: "#c78fff"
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
    }

    GridView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        cellWidth: Math.floor(width / 4)
        cellHeight: 96
        model: Game.clases
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: hueco
            required property var modelData
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight

            readonly property bool tengo: Game.estaDesbloqueado(modelData.id)
            readonly property bool dentro: Game.enPlantilla(modelData.id)
            readonly property var datos: Game.datosHeroe(modelData.id)

            IslandTile {
                anchors.fill: parent
                anchors.margins: 4
                activa: hueco.dentro
                colorActiva: Theme.surfaceHi
                pulsable: hueco.tengo
                border.width: hueco.dentro ? 2 : 0
                border.color: Theme.green
                onPulsada: Game.alternarEnPlantilla(hueco.modelData.id)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 1

                    Image {
                        source: "assets/heroes/" + hueco.modelData.sprite + ".png"
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        Layout.alignment: Qt.AlignHCenter
                        fillMode: Image.PreserveAspectFit
                        smooth: false
                        opacity: hueco.tengo ? 1 : 0.25
                    }

                    IslandLabel {
                        text: hueco.modelData.nombre
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: hueco.tengo ? Theme.ink : Theme.dim
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    IslandLabel {
                        visible: hueco.tengo
                        text: Idioma.t("nivel ") + hueco.datos.nivel
                        color: "#c78fff"
                        font.pixelSize: 9
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    IslandLabel {
                        visible: hueco.tengo
                        text: hueco.modelData.papel
                        color: Theme.muted
                        font.pixelSize: 8
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // lo que falta para tenerlo
                    IslandLabel {
                        visible: !hueco.tengo
                        text: Game.textoReto(hueco.modelData.reto)
                        color: Theme.muted
                        font.pixelSize: 8
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        visible: !hueco.tengo
                        Layout.fillWidth: true
                        Layout.preferredHeight: 3
                        radius: 1.5
                        color: Theme.islandBg

                        Rectangle {
                            width: parent.width * Game.progresoReto(hueco.modelData.reto)
                            height: parent.height
                            radius: parent.radius
                            color: "#ffd60a"
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
