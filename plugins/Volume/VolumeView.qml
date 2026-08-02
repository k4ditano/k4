import QtQuick
import QtQuick.Layouts
import K4 as K4
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

        K4.Medidor {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            valor: Audio.volume
            maximo: 100
            tono: Audio.muted ? Theme.muted : Theme.ink
            duracion: 140
        }

        IslandLabel {
            text: Audio.muted ? "—" : Audio.volume + "%"
            color: Theme.muted
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 30
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
