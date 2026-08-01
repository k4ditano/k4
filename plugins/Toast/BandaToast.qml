//  El toast en modo banda: cuando la island la tiene otro plugin de verdad
//  —el juego abierto, el editor a medias— la notificación ya no se la roba.
//  Sale como una cápsula propia pegada al borde de la island (debajo si la
//  barra vive arriba, encima si vive abajo) y convive con lo que haya.
//
//  Misma vida que el toast de siempre: caduca sola, el ratón encima la
//  sostiene, clic va a la aplicación y la ✕ la descarta.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4.Ventana {
    id: ventana

    nombre: "k4-toast-banda"
    zonaActiva: capsula

    readonly property bool abajo: K4.Isla.posicion === "abajo"
    readonly property var aviso: Notifs.latest

    Rectangle {
        id: capsula

        readonly property int alto: 56

        x: K4.Isla.rect.x + (K4.Isla.rect.ancho - width) / 2
        y: ventana.abajo ? K4.Isla.rect.y - alto - 8
                         : K4.Isla.rect.y + K4.Isla.rect.alto + 8
        width: Math.min(420, contenido.implicitWidth + 84)
        height: alto
        radius: 16
        color: Theme.islandBg
        border.width: 1
        border.color: Theme.surfaceHi

        //  Entra deslizándose desde la island, como si asomara de ella.
        opacity: 0
        Component.onCompleted: entrada.start()

        ParallelAnimation {
            id: entrada
            NumberAnimation { target: capsula; property: "opacity"; to: 1; duration: 180 }
            NumberAnimation {
                target: capsula; property: "y"
                from: ventana.abajo ? K4.Isla.rect.y - 20
                                    : K4.Isla.rect.y + K4.Isla.rect.alto - 20
                to: ventana.abajo ? K4.Isla.rect.y - capsula.alto - 8
                                  : K4.Isla.rect.y + K4.Isla.rect.alto + 8
                duration: 260
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
        }

        //  El ratón encima la sostiene, como al toast de siempre.
        HoverHandler {
            onHoveredChanged: hovered ? Notifs.holdToast() : Notifs.resumeToast()
        }

        Row {
            id: contenido
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Image {
                anchors.verticalCenter: parent.verticalCenter
                source: Notifs.iconFor(ventana.aviso)
                width: 26; height: 26
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 52
                sourceSize.height: 52
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                IslandLabel {
                    text: ventana.aviso ? ventana.aviso.summary
                                        : Idioma.t("Notificación")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    width: Math.min(290, implicitWidth)
                }

                IslandLabel {
                    visible: text.length > 0
                    text: ventana.aviso ? ventana.aviso.body : ""
                    color: Theme.muted
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    width: Math.min(290, implicitWidth)
                }
            }
        }

        //  Clic en el cuerpo: a la aplicación, como el toast grande.
        MouseArea {
            anchors.fill: parent
            anchors.rightMargin: 40
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Notifs.activate(ventana.aviso)
                Notifs.dismissToast()
            }
        }

        MediaButton {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            glyph: Theme.ico.close
            glyphSize: 13
            glyphColor: Theme.muted
            onActivated: Notifs.dismissToast()
        }
    }
}
