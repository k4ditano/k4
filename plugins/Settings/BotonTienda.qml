//  El botón de la tienda: instalar, actualizar, quitar, cancelar.
//
//  Existe como pieza propia porque son once en la misma vista y hay tres
//  tratos distintos —el normal, el que resalta la acción principal y el que
//  avisa de que borra—. Repetir eso once veces es como acaban discrepando.

import QtQuick
import K4 as K4
import "../../core"

K4.Baldosa {
    id: boton

    property string texto: ""
    property bool resalta: false      //  la acción principal del grupo
    property bool peligro: false      //  la que borra algo
    property bool habilitado: true

    signal pulsado()

    implicitWidth: etiqueta.implicitWidth + 22
    implicitHeight: 26
    radius: 13
    pulsable: habilitado
    opacity: habilitado ? 1 : 0.45

    colorBase: resalta ? Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, 0.22)
                       : Theme.track

    onPulsada: if (habilitado) boton.pulsado()

    IslandLabel {
        id: etiqueta
        anchors.centerIn: parent
        text: boton.texto
        textFormat: Text.PlainText
        color: boton.peligro ? Theme.red
             : boton.resalta ? Theme.blue : Theme.muted
        font.pixelSize: 10
    }
}
