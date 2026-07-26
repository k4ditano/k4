import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var tray: null

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 22
        anchors.rightMargin: 22
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
}
