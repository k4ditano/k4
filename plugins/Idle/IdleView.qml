import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var tray: null
    property int shown: 0

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 9
        anchors.rightMargin: 11
        spacing: 8

        Artwork {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            visible: Media.isPlaying
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            spacing: 4
            Layout.fillWidth: false
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: Workspaces.list

                delegate: Rectangle {
                    required property var modelData
                    Layout.preferredWidth: modelData.focused ? 18 : 6
                    Layout.preferredHeight: 6
                    Layout.alignment: Qt.AlignVCenter
                    radius: 3
                    color: modelData.focused ? Theme.ink : Theme.track

                    Behavior on Layout.preferredWidth {
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }

                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }

        IslandLabel {
            text: Qt.formatDateTime(Clock.date, "HH:mm")
            font.pixelSize: 12
            font.weight: Font.Medium
            color: Media.hasPlayer ? Theme.ink : Theme.muted
            Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        Visualizer {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: 12
            visible: Media.isPlaying
        }

        // ── bandeja: indicadores, y atajo al módulo completo
        RowLayout {
            visible: Tray.count > 0
            spacing: 4
            Layout.leftMargin: Media.isPlaying ? 2 : 0
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: Tray.sorted.slice(0, view.shown)

                delegate: Image {
                    required property var modelData
                    source: modelData.icon
                    sourceSize.width: 28
                    sourceSize.height: 28
                    fillMode: Image.PreserveAspectFit
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    Layout.alignment: Qt.AlignVCenter
                    opacity: modelData.status === 2 ? 1 : 0.85

                    // NeedsAttention: late, que para eso lo pide
                    SequentialAnimation on opacity {
                        running: modelData.status === 2
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
            }

            IslandLabel {
                visible: Tray.count > view.shown
                text: "+" + (Tray.count - view.shown)
                color: Theme.muted
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            // Se traga el clic para que no llegue al fondo (que abriría el
            // centro de control) y despliega la bandeja entera.
            MouseArea {
                anchors.fill: parent
                anchors.margins: -3
                cursorShape: Qt.PointingHandCursor
                onClicked: if (view.tray) view.tray.toggle()
            }
        }
    }
}
