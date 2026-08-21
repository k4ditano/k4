//  Número de daño que sube y se desvanece. Se crea uno por golpe y se destruye
//  solo al terminar la animación: son efímeros y no merecen un modelo.

import QtQuick
import "../../core"

Text {
    id: numero
    textFormat: Text.PlainText

    property string texto: ""
    property bool critico: false

    text: (critico ? "¡" + texto + "!" : texto)
    color: critico ? "#ffd60a" : Theme.ink
    font.family: Theme.uiFont
    font.pixelSize: critico ? 18 : 14
    font.weight: critico ? Font.Bold : Font.DemiBold
    style: Text.Outline
    styleColor: "#000000"

    ParallelAnimation {
        running: true

        NumberAnimation {
            target: numero
            property: "y"
            to: numero.y - (numero.critico ? 54 : 40)
            duration: 700
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: numero
            property: "opacity"
            from: 1
            to: 0
            duration: 700
            easing.type: Easing.InQuad
        }

        onFinished: numero.destroy()
    }
}
