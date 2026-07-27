//  Indicador del juego para la píldora: oleada actual y aviso de cofres.
//
//  En la píldora es solo indicador —al acercar el ratón la island ya ha
//  cambiado de vista, así que un clic ahí no llega nunca—; en las vistas de
//  hover se puede pulsar para abrir la mazmorra.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: indicador

    property bool interactive: false
    signal abrir()

    visible: Game.cargado && (interactive || Settings.juegoEnPildora)
    spacing: 4

    IconGlyph {
        text: String.fromCodePoint(Game.viva ? 0xF04E5 : 0xF068B)   // espada o lápida
        color: Game.viva ? Theme.muted : Theme.red
        font.pixelSize: 11
        Layout.alignment: Qt.AlignVCenter
    }

    IslandLabel {
        text: Game.oleada
        color: Theme.muted
        font.pixelSize: 11
        font.weight: Font.Medium
        Layout.alignment: Qt.AlignVCenter
    }

    // punto morado: hay cofres esperando
    Rectangle {
        visible: Game.cofres > 0
        Layout.preferredWidth: 5
        Layout.preferredHeight: 5
        Layout.alignment: Qt.AlignVCenter
        radius: 2.5
        color: "#c78fff"

        SequentialAnimation on opacity {
            running: Game.cofres > 0
            loops: Animation.Infinite
            NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -3
        enabled: indicador.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: indicador.abrir()
    }
}
