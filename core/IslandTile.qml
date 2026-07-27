//  Tarjeta pulsable del centro de control.
//
//  Unifica el tacto de todo el panel: aclarado al pasar por encima y un
//  hundimiento corto al pulsar, que es lo que hace que un botón de macOS se
//  sienta físico. Sin esto cada tarjeta reaccionaba a su manera —o no
//  reaccionaba— y el conjunto parecía una lista de rectángulos.

import QtQuick

Rectangle {
    id: tile

    property bool activa: false          // estado encendido, no pulsación
    property color colorBase: Theme.surface
    property color colorActiva: Theme.surfaceHi
    property bool pulsable: true
    property alias hovered: raton.containsMouse

    signal pulsada()

    radius: 16
    color: activa ? colorActiva
        : (raton.containsMouse && pulsable ? Theme.surfaceHi : colorBase)

    // El hundimiento es sutil a propósito: a 0,97 se nota en la mano y no
    // salta a la vista, que es justo lo que se busca.
    scale: raton.pressed && pulsable ? 0.97 : 1

    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    // borde interior tenue: da profundidad sin dibujar una caja
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, raton.containsMouse && tile.pulsable ? 0.09 : 0.04)
    }

    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        enabled: tile.pulsable
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.pulsada()
    }
}
