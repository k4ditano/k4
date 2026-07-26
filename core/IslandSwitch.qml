// Interruptor tipo macOS

import QtQuick

Rectangle {
    id: control

    property bool checked: false
    signal toggled()

    implicitWidth: 40
    implicitHeight: 24
    radius: 12
    color: checked ? Theme.green : Theme.surfaceHi

    Behavior on color { ColorAnimation { duration: 180 } }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        color: "#ffffff"
        anchors.verticalCenter: parent.verticalCenter
        x: control.checked ? parent.width - width - 3 : 3

        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: control.toggled()
    }
}
