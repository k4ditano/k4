//  Deslizador con etiqueta y valor. Trabaja en enteros o con decimales según
//  `step`, y avisa solo cuando el valor cambia de verdad.

import QtQuick
import QtQuick.Layouts

Item {
    id: control

    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 100
    property real step: 1
    property string suffix: ""

    signal moved(real value)

    implicitHeight: 38

    readonly property real ratio: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    function quantise(fraction) {
        const raw = from + Math.max(0, Math.min(1, fraction)) * (to - from)
        const snapped = Math.round(raw / step) * step
        // step decimal → redondeo a esa precisión, si no arrastra 0.30000000004
        const decimals = step < 1 ? String(step).split(".")[1].length : 0
        return parseFloat(snapped.toFixed(decimals))
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IslandLabel {
                text: control.label
                color: Theme.muted
                font.pixelSize: 11
                Layout.fillWidth: true
            }

            IslandLabel {
                text: control.value + control.suffix
                color: Theme.ink
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 16

            Rectangle {
                id: track
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: mouse.containsMouse || mouse.pressed ? 6 : 4
                radius: height / 2
                color: Theme.track

                Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                Rectangle {
                    width: track.width * control.ratio
                    height: parent.height
                    radius: parent.radius
                    color: Theme.ink

                    Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                }
            }

            Rectangle {
                x: track.width * control.ratio - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: mouse.pressed ? 14 : 12
                height: width
                radius: width / 2
                color: Theme.ink

                Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function apply(mouseX) {
                    const next = control.quantise(mouseX / track.width)
                    if (next !== control.value)
                        control.moved(next)
                }

                onPressed: function (event) { apply(event.x) }
                onPositionChanged: function (event) { if (pressed) apply(event.x) }
            }
        }
    }
}
