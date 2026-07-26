// Visualizador de 4 barras

import QtQuick
import "../core"
import "../services"

Item {
    id: viz

    property bool active: Media.isPlaying
    property color barColor: Theme.ink

    implicitWidth: 17
    implicitHeight: 14

    Row {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2.5

        Repeater {
            model: 4

            delegate: Rectangle {
                required property int index
                readonly property var restHeights: [9, 13, 6, 11]
                width: 2.5
                radius: 1.25
                color: viz.barColor
                height: restHeights[index]
                anchors.bottom: parent.bottom

                SequentialAnimation on height {
                    running: viz.active
                    loops: Animation.Infinite
                    NumberAnimation { to: 4 + (index % 2 === 0 ? 8 : 4); duration: 320 + index * 85; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 3; duration: 280 + index * 65; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 11 - index; duration: 300 + index * 40; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 4; duration: 260 + index * 55; easing.type: Easing.InOutSine }
                }
            }
        }
    }
}
