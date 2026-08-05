//  Indicador del juego para la píldora: oleada actual y aviso de cofres.
//
//  En la píldora es solo indicador —al acercar el ratón la island ya ha
//  cambiado de vista, así que un clic ahí no llega nunca—; en las vistas de
//  hover se puede pulsar para abrir la mazmorra.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

//  La raíz es un Item y no el propio RowLayout, y de ahí depende que se pueda
//  pulsar. Un MouseArea colgado directamente de un layout es una celda más: el
//  layout le impone la geometría y se lleva por delante el x/y/width/height que
//  se le ponga a mano, así que con tamaño implícito cero acababa midiendo 0×0 y
//  no había dónde pulsar —el clic seguía hasta el fondo de la island, que abre
//  el centro de control—. Quitar los anchors calló el aviso de Qt pero no
//  arregló esto: dentro de un layout tampoco vale colocarse a mano. Metiendo la
//  fila en un Item, el que va en la celda es el Item y el MouseArea queda fuera
//  del alcance del layout, que es donde tiene que estar.
Item {
    id: indicador

    property bool interactive: false
    signal abrir()

    visible: Settings.juegoActivo && Game.cargado
        && (interactive || Settings.juegoEnPildora)

    implicitWidth: fila.implicitWidth
    implicitHeight: fila.implicitHeight

    RowLayout {
        id: fila
        anchors.fill: parent
        spacing: 4

        IconGlyph {
        text: String.fromCodePoint(Game.viva ? 0xF04E5 : 0xF068B)   // espada o lápida
        color: Game.viva ? Theme.muted : Theme.red
        font.pixelSize: 11
        Layout.alignment: Qt.AlignVCenter
    }

        IslandLabel {
            text: (Game.pausada ? "⏸ " : "") + Game.oleada
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
    }

    //  Tres píxeles de propina por cada lado: el dibujo es diminuto y apuntarle
    //  exacto con el ratón es un peaje que no pinta nada aquí.
    MouseArea {
        anchors.fill: parent
        anchors.margins: -3
        enabled: indicador.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: indicador.abrir()
    }
}
