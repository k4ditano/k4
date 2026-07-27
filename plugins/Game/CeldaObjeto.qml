//  Celda de la rejilla de inventario: icono, borde de rareza e insignia.
//
//  Se puede arrastrar para reordenar. Mientras se arrastra la celda se
//  levanta —escala y sombra— para que se vea cuál llevas en la mano.

import QtQuick
import "../../core"
import "../../services"

Item {
    id: celda

    property var objeto: null
    property int posicion: -1
    property bool arrastrando: caja.Drag.active

    signal pulsado()
    signal secundario()
    signal soltadoEn(int destino)

    readonly property var rareza: objeto ? Items.rarezaDe(objeto.rareza) : null

    // ── zona de recepción: acepta la pieza que venga de otra celda
    DropArea {
        anchors.fill: parent
        onDropped: function (caida) {
            if (caida.source && caida.source.origen !== undefined)
                celda.soltadoEn(caida.source.origen)
        }
    }

    Rectangle {
        id: caja
        anchors.fill: parent
        radius: 9
        color: celda.arrastrando ? Theme.surfaceHi
            : (raton.containsMouse ? Theme.surfaceHi : Theme.surface)
        border.width: celda.objeto ? (celda.arrastrando ? 2 : 1) : 0
        border.color: celda.rareza ? celda.rareza.color : "transparent"
        scale: celda.arrastrando ? 1.12 : 1
        z: celda.arrastrando ? 50 : 0

        property int origen: celda.posicion

        Behavior on color { ColorAnimation { duration: 110 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        Drag.active: raton.drag.active
        Drag.source: caja
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        Image {
            anchors.centerIn: parent
            width: parent.width * 0.62
            height: width
            source: celda.objeto
                ? "assets/objetos/i" + String(celda.objeto.icono).padStart(2, "0") + ".png"
                : ""
            fillMode: Image.PreserveAspectFit
            smooth: false
        }

        // el grado, abajo a la izquierda
        InsigniaRareza {
            visible: celda.objeto !== null
            rareza: celda.objeto ? celda.objeto.rareza : 0
            compacta: true
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 3
        }

        MouseArea {
            id: raton
            anchors.fill: parent
            hoverEnabled: true
            enabled: celda.objeto !== null
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            drag.target: caja
            drag.axis: Drag.XAndYAxis

            onClicked: function (raton) {
                if (raton.button === Qt.RightButton)
                    celda.secundario()
                else
                    celda.pulsado()
            }

            onReleased: {
                if (caja.Drag.active)
                    caja.Drag.drop()
                // vuelve a su hueco: la rejilla decide dónde va, no el ratón
                caja.x = 0
                caja.y = 0
            }
        }
    }
}
