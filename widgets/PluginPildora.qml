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
        model: Indicadores.lista
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
                IslandLabel {
                    text: modelData.texto
                    color: Theme.muted
                    font.pixelSize: 11
                    font.weight: Font.Medium
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
}
