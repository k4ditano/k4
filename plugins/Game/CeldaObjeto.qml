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

    readonly property bool usable: objeto ? Game.algunoPuede(objeto) : true
    property alias encima: raton.containsMouse

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
            // deja libre la banda de abajo, donde vive la insignia de rareza
            anchors.verticalCenterOffset: -4
            opacity: celda.usable ? 1 : 0.35

            // Tamaño nativo del sprite: un píxel del dibujo, un píxel de
            // pantalla. Es lo único que se ve exactamente como se dibujó;
            // cualquier aumento, por limpio que sea, solo agranda los bloques.
            width: 32
            height: 32
            source: celda.objeto
                ? "assets/objetos/i" + String(celda.objeto.icono).padStart(2, "0") + ".png"
                : ""
            fillMode: Image.PreserveAspectFit
            smooth: false
        }

        // candado: aún no tienes nivel para ponértelo
        IconGlyph {
            visible: celda.objeto !== null && !celda.usable
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 2
            text: Theme.ico.lock
            color: Theme.red
            font.pixelSize: 10
        }

        // El nivel, abajo a la izquierda. Solo el número: el nombre del grado
        // no cabe en una celda de 46 y además es redundante, porque el borde
        // de la celda ya va del color de la rareza.
        Rectangle {
            visible: celda.objeto !== null
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: nivelTexto.implicitWidth + 7
            height: 12
            radius: 6
            color: "#cc000000"

            IslandLabel {
                id: nivelTexto
                anchors.centerIn: parent
                text: Items.nivelDe(celda.objeto)
                color: celda.rareza ? celda.rareza.color : Theme.dim
                font.pixelSize: 8
                font.weight: Font.Bold
            }
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
