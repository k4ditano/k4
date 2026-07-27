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

        // Indicadores nada más: aquí no se puede pinchar, porque al acercar el
        // ratón la island ya ha cambiado a la vista de reloj o de reproductor.
        // Es en esas donde la fila es pulsable.
        JuegoPildora { Layout.alignment: Qt.AlignVCenter }

        TrayRow {
            max: view.shown
            iconSize: 14
            interactive: false
            Layout.leftMargin: Media.isPlaying ? 2 : 0
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
