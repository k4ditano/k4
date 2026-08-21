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

            //  Limpiar el ruido de la pista al renderizar: el
            //  soplido del micro fuera, la voz intacta. La previa
            //  no lo enseña —el reproductor no filtra— y por eso
            //  la escoba se queda encendida, para que se sepa.
            MediaButton {
                glyph: String.fromCodePoint(0xF00E2)   // md-broom
                glyphSize: 13
                glyphColor: filaPista.modelData.limpia
                    ? Theme.green : Theme.dim
                onActivated: Editor.fijarPista(
                    filaPista.modelData.i,
                    { limpia: !filaPista.modelData.limpia })
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

            // El volumen, hasta `Editor.volumenMaximo`: un micro que quedó
            // lejos necesita bastante más del doble, y el tope lo pone quien
            // escucha, no nosotros.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: Theme.track
                opacity: filaPista.modelData.mudo ? 0.4 : 1

                Rectangle {
                    width: parent.width
                        * Math.min(1, filaPista.modelData.volumen
                                      / Editor.volumenMaximo)
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
                        const tope = Editor.volumenMaximo
                        const v = Math.max(0, Math.min(tope,
                            x / Math.max(1, width) * tope))
                        Editor.fijarPista(filaPista.modelData.i,
                                           { volumen: Math.round(v * 20) / 20 })
                    }
                    onPressed: function (ev) { poner(ev.x) }
                    onPositionChanged: function (ev) {
                        if (pressed) poner(ev.x)
                    }
                }
            }

            //  Ámbar por encima del 100 %: ahí se AMPLIFICA, y eso Qt no sabe
            //  hacerlo —recorta—, así que de ahí para arriba el número solo se
            //  cumple en el fichero que sale. De 0 a 100 la previa ya lo aplica
            //  y se oye subir y bajar mientras lo mueves.
            IslandLabel {
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
                text: Math.round(filaPista.modelData.volumen * 100) + "%"
                color: filaPista.modelData.volumen > 1 ? Theme.yellow : Theme.dim
                font.pixelSize: 9
            }

            //  El pico de la pista, medido del fichero: rojo satura, ámbar
            //  va justo, verde respira. Vacío mientras se mide.
            IslandLabel {
                readonly property var nivel:
                    Editor.nivelesPistas[filaPista.modelData.i]
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
                visible: nivel !== undefined
                text: nivel !== undefined
                    ? nivel.pico.toFixed(1) + " dB" : ""
                color: nivel === undefined ? Theme.dim
                     : nivel.pico > -1 ? Theme.red
                     : nivel.pico > -6 ? Theme.yellow : Theme.green
                font.pixelSize: 9
            }
        }
    }
}
