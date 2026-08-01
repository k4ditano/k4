//  Lo que se dice en el vídeo, en segmentos con sus tiempos.
//
//  Es lo que llena el hueco de la ficha cuando no hay nada elegido, que es la
//  mayor parte del tiempo. Cada línea lleva a su instante al pulsarla y se
//  convierte en rótulo con el botón: ese puente es lo que hace que la
//  transcripción sirva para algo más que subtitular.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

ColumnLayout {
    id: fichaTrans

    required property var view

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.topMargin: 8
    spacing: 4

    IslandLabel {
        text: Idioma.t("Transcripción")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    //  El estado, cuando hay algo que decir. Aquí es donde
    //  aparece el mandato de instalación si falta whisper: son
    //  1,4 GB entre binario y modelo y eso no se descarga solo.
    IslandLabel {
        visible: text.length > 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: {
            const e = Editor.estadoTranscripcion
            if (e === "comprobando") return Idioma.t("Comprobando…")
            if (e === "extrayendo")  return Idioma.t("Sacando el audio…")
            if (e === "transcribiendo") return Idioma.t("Escuchando… esto tarda")
            if (e === "fallo") return Idioma.t("No se pudo transcribir")
            if (e === "falta")
                return Editor.faltaTranscripcion === "modelo"
                    ? Idioma.t("Falta el modelo de voz")
                    : Idioma.t("Falta whisper.cpp")
            return ""
        }
        color: Editor.estadoTranscripcion === "fallo"
            ? Theme.red : Theme.muted
        font.pixelSize: 10
    }

    Rectangle {
        visible: Editor.estadoTranscripcion === "falta"
        Layout.fillWidth: true
        Layout.preferredHeight: comoTexto.implicitHeight + 16
        radius: 8
        color: Theme.surface

        IslandLabel {
            id: comoTexto
            anchors.fill: parent
            anchors.margins: 8
            text: Editor.comoInstalar
            color: Theme.muted
            font.pixelSize: 9
            font.family: "monospace"
            wrapMode: Text.WrapAnywhere
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            //  Pulsar lo copia: nadie va a teclear a mano una
            //  URL de Hugging Face de ciento y pico caracteres.
            onClicked: K4.Sistema.copiar(Editor.comoInstalar)
        }
    }

    Rectangle {
        visible: Editor.transcripcion.length === 0
            && Editor.estadoTranscripcion === ""
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: 13
        color: transRaton.containsMouse ? Theme.surfaceHi
                                        : Theme.surface

        RowLayout {
            anchors.centerIn: parent
            spacing: 5

            IconGlyph {
                text: String.fromCodePoint(0xF036C)  // md-microphone
                color: Theme.blue
                font.pixelSize: 12
            }

            IslandLabel {
                text: Idioma.t("Transcribir")
                font.pixelSize: 10
            }
        }

        MouseArea {
            id: transRaton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Editor.transcribir()
        }
    }

    //  Toda la transcripción de golpe, con estilo de subtítulo.
    //
    //  Segmento a segmento ya se podía —el botón de cada línea—,
    //  pero para poner subtítulos a un vídeo entero eso son
    //  cuarenta clics. Salen como capas normales: si alguna
    //  frase queda mal, se retoca sola.
    Rectangle {
        visible: Editor.transcripcion.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 24 : 0
        radius: 12
        color: quemarRaton.containsMouse ? Theme.surfaceHi
                                         : Theme.surface

        RowLayout {
            anchors.centerIn: parent
            spacing: 5

            IconGlyph {
                text: String.fromCodePoint(0xF0A17)   // md-subtitles_outline
                color: Theme.muted
                font.pixelSize: 12
            }

            IslandLabel {
                text: Idioma.t("Quemar los ")
                      + Editor.transcripcion.length
                      + Idioma.t(" como subtítulos")
                color: Theme.muted
                font.pixelSize: 10
            }
        }

        MouseArea {
            id: quemarRaton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Editor.quemarTranscripcion()
        }
    }

    ListView {
        //  La barra de la casa: sale sola si hay más de lo que cabe.
        ScrollBar.vertical: IslandScrollBar {}
        visible: Editor.transcripcion.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        model: Editor.transcripcion
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: linea
            required property var modelData

            //  El segmento que suena ahora, resaltado: es lo que
            //  convierte la lista en algo que se puede seguir
            //  mientras el vídeo corre.
            readonly property bool ahora: fichaTrans.view.segundos >= modelData.t0
                && fichaTrans.view.segundos <= modelData.t1

            width: ListView.view.width
            height: cuerpo.implicitHeight + 12
            radius: 7
            color: ahora ? Qt.rgba(10 / 255, 132 / 255, 1, 0.18)
                : (lineaRaton.containsMouse ? Theme.surface
                                            : "transparent")

            RowLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 6

                IslandLabel {
                    Layout.preferredWidth: 28
                    text: linea.modelData.t0.toFixed(1)
                    color: Theme.dim
                    font.pixelSize: 9
                }

                IslandLabel {
                    id: cuerpo
                    Layout.fillWidth: true
                    text: linea.modelData.texto
                    color: linea.ahora ? Theme.ink : Theme.muted
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }

                //  De lo dicho a un rótulo, con sus mismos
                //  tiempos. El puente que hace que esto valga
                //  para más que subtitular.
                MediaButton {
                    glyph: String.fromCodePoint(0xF0284)
                    glyphSize: 12
                    glyphColor: Theme.green
                    onActivated: Editor.rotuloDesde(linea.modelData)
                }
            }

            MouseArea {
                id: lineaRaton
                anchors.fill: parent
                anchors.rightMargin: 26
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: fichaTrans.view.irA(linea.modelData.t0)
            }
        }
    }
}
