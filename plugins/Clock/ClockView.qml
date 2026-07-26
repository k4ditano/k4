import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var tray: null

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 0
        anchors.bottomMargin: Notifs.recent.length > 0 ? 12 : 0
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 68
            spacing: 12

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: false
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter

                IslandLabel {
                    text: Clock.date.toLocaleDateString(Theme.locale, "dddd")
                    color: Theme.muted
                    font.pixelSize: 11
                    font.capitalization: Font.Capitalize
                }

                IslandLabel {
                    text: Clock.date.toLocaleDateString(Theme.locale, "d MMMM")
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }

            Item { Layout.fillWidth: true }

            IslandLabel {
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                font.pixelSize: 30
                font.weight: Font.Light
                Layout.alignment: Qt.AlignVCenter
            }

            // La island ya está desplegada y quieta: aquí sí se puede pinchar.
            TrayRow {
                max: 5
                iconSize: 16
                interactive: true
                Layout.leftMargin: 4
                Layout.alignment: Qt.AlignVCenter
                onMenuRequested: if (view.tray) view.tray.toggle()
            }
        }

        // Lo que acaba de llegar, sin tener que abrir el panel.
        NotifStrip {
            max: 3
            Layout.fillWidth: true
        }
    }
}
