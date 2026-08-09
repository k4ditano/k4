//  Una cifra en bits: la moneda y el número.
//
//  Existe porque meter el icono DENTRO de una `K4.Etiqueta` —«\u{F0830}» y
//  el número en la misma cadena— sale mal: la etiqueta usa la fuente de
//  texto, el icono entra por sustitución desde la Nerd Font y sus métricas no
//  cuadran, así que la moneda y el primer dígito se dibujan encima. En
//  pantalla se leía «🪙0» donde ponía 30, y «🪙5» donde ponía 25.
//
//  Con el icono en su `K4.Glifo` —que sí usa la fuente de iconos— y el número
//  aparte, cada uno mide lo suyo.

import QtQuick
import K4 as K4

Row {
    id: self

    property int valor: 0
    property int tam: 10
    property color color: "#e8b45a"
    //  Para «cuesta 400» frente a «tienes 400»: el mismo trozo sirve para las
    //  dos cosas y solo cambia el tono.
    property bool apagado: false

    spacing: 2

    K4.Glifo {
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F0830}"
        font.pixelSize: self.tam
        color: self.apagado ? Qt.darker(self.color, 1.8) : self.color
    }

    K4.Etiqueta {
        anchors.verticalCenter: parent.verticalCenter
        text: self.valor
        font.pixelSize: self.tam
        color: self.apagado ? Qt.darker(self.color, 1.8) : self.color
    }
}
