//  La mano que asoma por el lateral de la island.
//
//  La pareja que lo hace posible: K4.Ventana —una superficie transparente a
//  pantalla completa por encima de todo— y K4.Isla.rect, la geometría real
//  de la island para anclarse a su borde al píxel. Con estas dos piezas,
//  cualquier cosa puede asomar, caerse o pasearse "fuera" de la barra.

import QtQuick
import K4 as K4

K4.Ventana {
    id: ventana

    nombre: "k4-efectos-mano"

    //  Solo la mano captura el ratón; el resto de la pantalla sigue siendo
    //  del escritorio. Sin esto, la ventana invisible se tragaría los clics.
    zonaActiva: mano

    required property var plugin

    Text {
        id: mano

        //  Pegada al borde derecho de la island, medio palmo por debajo del
        //  filo, mirando hacia fuera.
        x: K4.Isla.rect.x + K4.Isla.rect.ancho - 4
        y: K4.Isla.rect.y + 6
        text: "👋"
        font.pixelSize: 30
        rotation: -35

        //  Aparece con ganas y saluda sin parar.
        scale: 0
        Component.onCompleted: aparecer.start()

        NumberAnimation {
            id: aparecer
            target: mano
            property: "scale"
            to: 1
            duration: 380
            easing.type: Easing.OutBack
            easing.overshoot: 2.2
        }

        SequentialAnimation {
            running: true
            loops: Animation.Infinite
            NumberAnimation { target: mano; property: "rotation"; to: -10; duration: 260; easing.type: Easing.InOutQuad }
            NumberAnimation { target: mano; property: "rotation"; to: -50; duration: 260; easing.type: Easing.InOutQuad }
            NumberAnimation { target: mano; property: "rotation"; to: -10; duration: 260; easing.type: Easing.InOutQuad }
            NumberAnimation { target: mano; property: "rotation"; to: -35; duration: 220; easing.type: Easing.InOutQuad }
            PauseAnimation { duration: 900 }
        }

        //  Chocarle los cinco la esconde.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: ventana.plugin.manoFuera = false
        }
    }
}
