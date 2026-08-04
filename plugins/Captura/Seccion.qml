//  Un apartado plegable de la ficha.
//
//  La ficha de una capa creció hasta ser una tira: para llegar a «Trazar
//  movimiento» había que desplazar todo el panel, y lo que se usa a diario
//  quedaba enterrado entre cosas que se tocan una vez y ya. Agrupar y plegar
//  arregla las dos: cada cosa está donde se la busca, y lo que no toques no
//  ocupa sitio.
//
//  `aplica` es distinto de `visible` a propósito: una sección que no le
//  corresponde a esta capa —el sonido de una imagen— desaparece entera,
//  cabecera incluida, en vez de quedarse abierta y vacía.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: seccion

    property string titulo: ""
    property bool abierta: true
    property bool aplica: true

    //  Los hijos van dentro de la caja, no colgando de la sección: si
    //  colgaran, plegarla no los escondería.
    default property alias contenido: caja.data

    visible: aplica
    Layout.fillWidth: true
    Layout.topMargin: 2
    spacing: 4

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 22
        radius: 6
        color: cabeceraRaton.containsMouse ? Theme.surface : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 6
            spacing: 5

            IconGlyph {
                //  El galón mira abajo cuando está abierta y a la derecha
                //  cuando no: es la convención de todas partes y no hay que
                //  explicarla.
                text: String.fromCodePoint(seccion.abierta ? 0xF0140 : 0xF0142)
                color: Theme.dim
                font.pixelSize: 11
            }

            IslandLabel {
                text: seccion.titulo
                color: Theme.dim
                font.pixelSize: 9
                font.capitalization: Font.AllUppercase
                font.weight: Font.DemiBold
            }

            Item { Layout.fillWidth: true }
        }

        MouseArea {
            id: cabeceraRaton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: seccion.abierta = !seccion.abierta
        }
    }

    ColumnLayout {
        id: caja
        visible: seccion.abierta
        Layout.fillWidth: true
        Layout.bottomMargin: seccion.abierta ? 4 : 0
        spacing: 4
    }
}
