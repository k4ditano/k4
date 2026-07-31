//  Botón redondo de un solo glifo: los de reproducción, y cualquier acción
//  que quepa en un icono.
//
//  `activo: false` no lo esconde, lo apaga al 28 % y deja de responder — que
//  es lo que hay que hacer con «canción anterior» cuando no hay anterior.

import QtQuick

Item {
    id: control

    property string glifo
    property int tamano: 18
    property color color: Tema.tinta
    property bool activo: true

    signal pulsado()

    implicitWidth: tamano + 16
    implicitHeight: tamano + 12
    opacity: activo ? (raton.containsMouse ? 0.65 : 1) : 0.28

    Behavior on opacity { NumberAnimation { duration: 120 } }

    Glifo {
        anchors.centerIn: parent
        text: control.glifo
        color: control.color
        font.pixelSize: control.tamano
    }

    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: control.activo
        onClicked: control.pulsado()
    }

    scale: raton.pressed ? 0.88 : 1
    Behavior on scale {
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
}
