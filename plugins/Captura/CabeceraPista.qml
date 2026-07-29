//  El nombre de una pista, a la izquierda de la línea de tiempo.
//
//  Es el sitio donde uno busca qué capas hay y en qué orden van, así que además
//  de decir el nombre lleva los botones de subir, bajar y quitar. Salen al pasar
//  el ratón por encima: en veintiséis píxeles de alto, tres botones permanentes
//  no dejarían sitio para leer de qué capa se trata.

import QtQuick
import "../../core"

Rectangle {
    id: cabecera

    property string texto: ""
    property int glifo: 0
    property color tono: Theme.blue
    property bool elegida: false

    // Las pistas fijas —vídeo y zoom— no se suben ni se bajan ni se quitan.
    property bool conBotones: false
    property bool puedeSubir: true
    property bool puedeBajar: true

    signal pulsada()
    signal subir()
    signal bajar()
    signal quitar()

    radius: 6
    color: elegida ? Qt.rgba(tono.r, tono.g, tono.b, 0.22)
        : (raton.containsMouse ? Theme.surfaceHi : Theme.surface)

    Behavior on color { ColorAnimation { duration: 110 } }

    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cabecera.pulsada()
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 7
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5
        // Al asomar los botones, el nombre se aparta en vez de quedar debajo.
        visible: !cabecera.conBotones || !raton.containsMouse

        IconGlyph {
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(cabecera.glifo)
            color: cabecera.tono
            font.pixelSize: 12
        }

        IslandLabel {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 22
            text: cabecera.texto
            color: cabecera.elegida ? Theme.ink : Theme.muted
            font.pixelSize: 10
            elide: Text.ElideMiddle
        }
    }

    // ── subir, bajar, quitar ──────────────────────────────────────
    Row {
        anchors.centerIn: parent
        spacing: 2
        visible: cabecera.conBotones && raton.containsMouse

        Repeater {
            model: [
                { glifo: 0x000F005D, accion: "subir"  },   // md-arrow_up
                { glifo: 0x000F0045, accion: "bajar"  },   // md-arrow_down
                { glifo: 0x000F0156, accion: "quitar" }    // md-close
            ]

            delegate: Rectangle {
                id: boton
                required property var modelData

                width: 24
                height: 20
                radius: 5
                color: botonRaton.containsMouse
                    ? (modelData.accion === "quitar" ? "#3a1416" : Theme.surfaceHi)
                    : "transparent"

                readonly property bool activo: modelData.accion === "subir"
                    ? cabecera.puedeSubir
                    : (modelData.accion === "bajar" ? cabecera.puedeBajar : true)

                opacity: activo ? 1 : 0.3

                IconGlyph {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(boton.modelData.glifo)
                    color: boton.modelData.accion === "quitar"
                        ? Theme.red : Theme.ink
                    font.pixelSize: 12
                }

                MouseArea {
                    id: botonRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: boton.activo
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (boton.modelData.accion === "subir")       cabecera.subir()
                        else if (boton.modelData.accion === "bajar")  cabecera.bajar()
                        else                                          cabecera.quitar()
                    }
                }
            }
        }
    }
}
