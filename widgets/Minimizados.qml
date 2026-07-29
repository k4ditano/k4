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

            // El hueco de la aspa se reserva siempre, aunque solo se dibuje al
            // pasar por encima: si no, la cápsula pega un salto de ancho justo
            // cuando vas a pulsarla y el aspa se te escapa.
            Layout.preferredWidth: contenido.implicitWidth + (fila.interactive ? 38 : 10)
            Layout.preferredHeight: fila.interactive ? 22 : 17
            Layout.alignment: Qt.AlignVCenter
            radius: height / 2
            color: raton.containsMouse && fila.interactive
                ? Theme.surfaceHi : Theme.surface

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                id: contenido
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: fila.interactive ? 8 : 5
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
                    if (ev.button === Qt.MiddleButton)
                        Modulos.quitar(capsula.modelData.id)
                    else
                        Modulos.restaurar(capsula.modelData.id)
                }
            }

            //  La aspa para descartar, al pasar por encima.
            //
            //  El botón de en medio también vale, pero eso no lo adivina nadie:
            //  sin algo que se vea, lo que dejaste a medias se queda ahí para
            //  siempre y no hay forma obvia de quitarlo.
            Rectangle {
                visible: fila.interactive && (raton.containsMouse || aspaRaton.containsMouse)
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 2
                width: 16
                height: 16
                radius: 8
                color: aspaRaton.containsMouse ? Theme.red : Theme.surfaceHi

                IconGlyph {
                    anchors.centerIn: parent
                    text: Theme.ico.close
                    color: Theme.ink
                    font.pixelSize: 10
                }

                MouseArea {
                    id: aspaRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Modulos.quitar(capsula.modelData.id)
                }
            }
        }
    }
}
