//  El detalle de Sonido del centro de control, hermano de DetalleWifi y
//  DetalleBluetooth.
//
//  El azulejo de sonido sabía subir y bajar el volumen general y nada más:
//  para elegir por dónde sale o mirar la ganancia de un micro había que ir al
//  módulo de Sonido, cuando lo de al lado —la red, el Bluetooth— se abre aquí
//  mismo. La lista es la misma pieza que enseña el módulo, así que llegar por
//  un sitio o por otro da igual.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

IslandTile {
    required property var view

    Layout.fillWidth: true
    Layout.fillHeight: true
    pulsable: false
    visible: view.plugin.tab === "sonido"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        AparatosDeSonido {
            Layout.fillWidth: true
        }

        Item { Layout.fillHeight: true }

        IslandLabel {
            Layout.fillWidth: true
            text: Idioma.t("La marca del deslizador es el nivel natural del aparato: por encima se amplifica")
            color: Theme.dim
            font.pixelSize: 9
            wrapMode: Text.WordWrap
        }
    }
}
