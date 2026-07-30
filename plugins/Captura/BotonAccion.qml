//  Un botón de la rejilla de acciones del editor.
//
//  Existe porque los ocho botones del pie eran ocho bloques de cuarenta líneas
//  idénticos salvo el icono, el texto y lo que hacen. Trescientos cincuenta
//  líneas para nueve acciones, y cada una nueva era copiar y pegar el bloque
//  entero — que es exactamente como se cuelan las diferencias tontas.
//
//  Además el pie ya no daba de sí: ocho botones con nombre pedían 1207 píxeles
//  en una island de 1000, y eso estiraba la columna entera y aplastaba la ficha
//  de la derecha. Medido antes de moverlos.

import QtQuick
import QtQuick.Layouts
import "../../core"

Rectangle {
    id: boton

    property string texto: ""
    property int icono: 0
    //  Encendido: el botón dice que eso ya está puesto, como «Resaltar clics»
    //  cuando los clics ya se resaltan.
    property bool activo: false
    //  Y de aviso, para lo que va a quitar cosas.
    property bool peligro: false
    property bool disponible: true

    signal pulsado()

    Layout.fillWidth: true
    Layout.preferredHeight: 30
    radius: 8
    opacity: disponible ? 1 : 0.4
    color: activo ? (peligro ? Theme.red : Theme.blue)
         : raton.containsMouse && disponible ? Theme.surfaceHi : Theme.surface
    border.width: 1
    border.color: activo ? "transparent" : Qt.rgba(1, 1, 1, 0.08)

    Behavior on color { ColorAnimation { duration: 110 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 6
        spacing: 6

        IconGlyph {
            text: String.fromCodePoint(boton.icono)
            color: boton.activo ? "#ffffff" : Theme.ink
            font.pixelSize: 13
            Layout.alignment: Qt.AlignVCenter
        }

        IslandLabel {
            text: boton.texto
            color: boton.activo ? "#ffffff" : Theme.ink
            font.pixelSize: 10
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        enabled: boton.disponible
        cursorShape: Qt.PointingHandCursor
        onClicked: boton.pulsado()
    }
}
