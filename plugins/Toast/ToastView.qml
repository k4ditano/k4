import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            Layout.alignment: Qt.AlignVCenter
            radius: 19
            color: Theme.surface

            IconGlyph {
                anchors.centerIn: parent
                text: Theme.ico.bell
                color: Theme.ink
                font.pixelSize: 17
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 6

                IslandLabel {
                    text: Notifs.latest ? Notifs.latest.summary : "Notificación"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                IslandLabel {
                    text: Notifs.latest ? Notifs.latest.appName : ""
                    color: Theme.muted
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.maximumWidth: 90
                }
            }

            IslandLabel {
                Layout.fillWidth: true
                text: Notifs.latest ? Notifs.latest.body : ""
                color: Theme.muted
                font.pixelSize: 11
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
            }
        }

        MediaButton {
            glyph: Theme.ico.close
            glyphSize: 14
            glyphColor: Theme.muted
            onActivated: Notifs.dismissToast()
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
