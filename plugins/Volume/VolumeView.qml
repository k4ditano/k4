import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 10

        IconGlyph {
            text: Audio.muted ? Theme.ico.volOff
                : Audio.volume > 45 ? Theme.ico.volHigh : Theme.ico.volMed
            color: Audio.muted ? Theme.muted : Theme.ink
            font.pixelSize: 15
            Layout.alignment: Qt.AlignVCenter
        }

        Rectangle {
            id: track
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            Layout.alignment: Qt.AlignVCenter
            radius: 2
            color: Theme.track

            Rectangle {
                width: track.width * Math.max(0, Math.min(100, Audio.volume)) / 100
                height: parent.height
                radius: 2
                color: Audio.muted ? Theme.muted : Theme.ink

                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }

        IslandLabel {
            text: Audio.muted ? "—Idioma.t(" : Audio.volume + ")%"
            color: Theme.muted
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 30
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
