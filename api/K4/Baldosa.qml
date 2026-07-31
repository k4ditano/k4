//  La tarjeta pulsable del centro de control.
//
//  Unifica el tacto: se aclara al pasar por encima y se hunde un pelo al
//  pulsar, que es lo que hace que un botón se sienta físico. El 0,97 del
//  hundimiento es a propósito — se nota en la mano sin saltar a la vista.

import QtQuick

Rectangle {
    id: baldosa

    property bool activa: false          // encendida, que no es lo mismo que pulsada
    property color colorBase: Tema.superficie
    property color colorActiva: Tema.superficieAlta
    property bool pulsable: true
    property alias encima: raton.containsMouse

    signal pulsada()

    radius: 16
    color: activa ? colorActiva
        : (raton.containsMouse && pulsable ? Tema.superficieAlta : colorBase)

    scale: raton.pressed && pulsable ? 0.97 : 1

    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale {
        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
    }

    //  Borde interior tenue: da profundidad sin dibujar una caja.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1,
            raton.containsMouse && baldosa.pulsable ? 0.09 : 0.04)
    }

    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        enabled: baldosa.pulsable
        cursorShape: Qt.PointingHandCursor
        onClicked: baldosa.pulsada()
    }
}
