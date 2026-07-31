import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: view
    spacing: 8

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
                cursorShape: Qt.PointingHandCursor
                onClicked: Indicadores.invocado(modelData.id)
            }
        }
    }
}
