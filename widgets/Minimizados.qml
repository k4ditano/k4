//  Los módulos apartados, en la píldora.
//
//  Una cápsula por cada cosa que dejaste a medias. En la píldora es solo aviso
//  —al acercar el ratón la island ya ha cambiado de vista—; en las vistas de
//  hover se pulsa y vuelve donde estaba.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: fila

    property bool interactive: false

    visible: Modulos.count > 0
    spacing: 5

    Repeater {
        model: Modulos.lista

        delegate: Rectangle {
            id: capsula
            required property var modelData

            Layout.preferredWidth: contenido.implicitWidth + (fila.interactive ? 16 : 10)
            Layout.preferredHeight: fila.interactive ? 22 : 17
            Layout.alignment: Qt.AlignVCenter
            radius: height / 2
            color: raton.containsMouse && fila.interactive
                ? Theme.surfaceHi : Theme.surface

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                id: contenido
                anchors.centerIn: parent
                spacing: 4

                IconGlyph {
                    visible: capsula.modelData.glifo > 0
                    text: capsula.modelData.glifo > 0
                        ? String.fromCodePoint(capsula.modelData.glifo) : ""
                    color: Theme.muted
                    font.pixelSize: fila.interactive ? 12 : 10
                }

                // En la píldora solo el icono y el detalle corto: el título
                // completo se lee al abrir, y aquí lo que importa es que algo
                // te está esperando.
                IslandLabel {
                    visible: capsula.modelData.detalle.length > 0
                    text: capsula.modelData.detalle
                    color: Theme.muted
                    font.pixelSize: fila.interactive ? 10 : 9
                    elide: Text.ElideRight
                    Layout.maximumWidth: fila.interactive ? 150 : 90
                }
            }

            MouseArea {
                id: raton
                anchors.fill: parent
                hoverEnabled: true
                enabled: fila.interactive
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: function (ev) {
                    // Con el botón de en medio se descarta sin abrirlo, que es
                    // lo que uno quiere cuando ya no le interesa.
                    if (ev.button === Qt.MiddleButton)
                        Modulos.quitar(capsula.modelData.id)
                    else
                        Modulos.restaurar(capsula.modelData.id)
                }
            }
        }
    }
}
