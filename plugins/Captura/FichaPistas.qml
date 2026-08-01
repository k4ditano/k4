//  Las pistas de audio del vídeo.
//
//  Se graban por separado —sistema y micro— para poder equilibrarlas después:
//  mezclarlas al grabar sería irreversible. Lo que se toque aquí se aplica al
//  renderizar.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: fichaPistas

    //  El reproductor del editor: solo puede sacar una pista a la vez, y
    //  aquí se elige cuál estás oyendo.
    required property var reproductor

    Layout.fillWidth: true
    Layout.bottomMargin: 4
    spacing: 3
    visible: Editor.pistasAudio.length > 0

    IslandLabel {
        text: Idioma.t("Audio")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    Repeater {
        model: Editor.pistasAudio

        delegate: RowLayout {
            id: filaPista
            required property var modelData

            Layout.fillWidth: true
            spacing: 6

            //  Silenciar, y de paso decir cuál estás oyendo:
            //  el reproductor solo puede sacar una pista a la
            //  vez, así que pulsar el nombre cambia de monitor.
            MediaButton {
                glyph: String.fromCodePoint(
                    filaPista.modelData.mudo ? 0xF0581 : 0xF057E)
                glyphSize: 13
                glyphColor: filaPista.modelData.mudo
                    ? Theme.dim : Theme.ink
                onActivated: Editor.fijarPista(
                    filaPista.modelData.i,
                    { mudo: !filaPista.modelData.mudo })
            }

            IslandLabel {
                Layout.preferredWidth: 62
                text: filaPista.modelData.titulo.length > 0
                    ? filaPista.modelData.titulo
                    : Idioma.t("Pista ") + (filaPista.modelData.i + 1)
                color: fichaPistas.reproductor.pistaAudio === filaPista.modelData.i
                    ? Theme.ink : Theme.muted
                font.pixelSize: 10
                elide: Text.ElideRight

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fichaPistas.reproductor.fijarPistaAudio(filaPista.modelData.i)
                }
            }

            // El volumen, de 0 a 2: subir el doble es lo que
            // hace falta cuando el micro quedó bajo.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: Theme.track
                opacity: filaPista.modelData.mudo ? 0.4 : 1

                Rectangle {
                    width: parent.width
                        * Math.min(1, filaPista.modelData.volumen / 2)
                    height: parent.height
                    radius: parent.radius
                    color: Theme.blue
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    cursorShape: Qt.PointingHandCursor

                    function poner(x) {
                        const v = Math.max(0, Math.min(2,
                            x / Math.max(1, width) * 2))
                        Editor.fijarPista(filaPista.modelData.i,
                                           { volumen: Math.round(v * 20) / 20 })
                    }
                    onPressed: function (ev) { poner(ev.x) }
                    onPositionChanged: function (ev) {
                        if (pressed) poner(ev.x)
                    }
                }
            }

            IslandLabel {
                Layout.preferredWidth: 30
                horizontalAlignment: Text.AlignRight
                text: Math.round(filaPista.modelData.volumen * 100) + "%"
                color: Theme.dim
                font.pixelSize: 9
            }
        }
    }
}
