//  El interruptor de la barra: encendido verde, muñequilla que se desliza.
//
//  Ojo con una cosa: NO cambia solo. Emite `alternado()` y el estado lo pone
//  quien manda —normalmente tu plugin, después de guardar—. Así nunca se ve
//  encendido algo que en realidad falló.

import QtQuick

Rectangle {
    id: control

    property bool marcado: false
    signal alternado()

    implicitWidth: 40
    implicitHeight: 24
    radius: 12
    color: marcado ? Tema.verde : Tema.superficieAlta

    Behavior on color { ColorAnimation { duration: 180 } }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        color: "#ffffff"
        anchors.verticalCenter: parent.verticalCenter
        x: control.marcado ? parent.width - width - 3 : 3

        Behavior on x {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: control.alternado()
    }
}
