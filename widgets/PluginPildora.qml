//  Los indicadores que aportan los plugins por K4.Pildora.
//
//  Va en las tres vistas de la píldora, con el mismo trato que la grabación o
//  la mazmorra: en reposo solo se mira —al acercar el ratón la island ya ha
//  cambiado a reloj o reproductor— y es en esas donde se pincha. Sin
//  `interactive` no hay ratón, y así no se traga un clic que la vista de
//  reposo no puede atender.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: view
    spacing: 8

    property bool interactive: false

    Repeater {
        model: Indicadores.reparto.muestra
        delegate: Item {
            required property var modelData
            visible: modelData.visible !== false
            implicitWidth: contenido.implicitWidth + 6
            implicitHeight: contenido.implicitHeight + 4

            RowLayout {
                id: contenido
                anchors.fill: parent
                spacing: 4

                IconGlyph {
                    text: String.fromCodePoint(modelData.glifo)
                    color: modelData.color || Theme.muted
                    font.pixelSize: 11
                }
                //  Con tope y recortado por el final. El tope lo pone el
                //  servicio y no este fichero, porque es el mismo número con el
                //  que estima el hueco a reservar: separarlos es reservar para
                //  un texto que no se dibuja.
                //
                //  Cuántos indicadores caben también lo decide él; aquí solo se
                //  pintan los que manda.
                IslandLabel {
                    text: modelData.texto
                    color: Theme.muted
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.maximumWidth: Indicadores.topeTexto
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: view.interactive
                visible: view.interactive
                cursorShape: Qt.PointingHandCursor
                onClicked: Indicadores.invocado(modelData.id)
            }
        }
    }

    //  Los que no caben, en una cápsula.
    //
    //  No se pincha: no llevaría a ningún sitio concreto —son varios— y la
    //  píldora en reposo no atiende el ratón de todas formas. Está para que la
    //  fila no mienta cuando se queda corta.
    Rectangle {
        visible: Indicadores.reparto.ocultos > 0
        Layout.preferredWidth: Indicadores.anchoResumen
        Layout.preferredHeight: 18
        Layout.alignment: Qt.AlignVCenter
        radius: height / 2
        color: Theme.surface

        IslandLabel {
            anchors.centerIn: parent
            text: "+" + Indicadores.reparto.ocultos
            color: Theme.muted
            font.pixelSize: 10
            font.weight: Font.Medium
        }
    }
}
