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
            // sube un poco: la insignia de rareza vive abajo a la izquierda y
            // con el icono al doble de tamaño se le echaba encima
            anchors.verticalCenterOffset: -5
            opacity: celda.usable ? 1 : 0.35

            // Múltiplo entero del sprite (32 px): a 1,4 aumentos unos píxeles
            // salían dobles y otros no, y se veía sucio.
            readonly property int lado: 32
            width: lado * Math.max(1, Math.floor(parent.width * 0.92 / lado))
            height: width
            source: celda.objeto
                ? "assets/objetos/i" + String(celda.objeto.icono).padStart(2, "0") + ".png"
                : ""
            fillMode: Image.PreserveAspectFit
            smooth: false
        }

        // candado: aún no tienes nivel para ponértelo
        IconGlyph {
            visible: celda.objeto !== null && !celda.usable
            anchors.centerIn: parent
            text: Theme.ico.lock
            color: Theme.red
            font.pixelSize: 14
        }

        // el grado, abajo a la izquierda
        InsigniaRareza {
            visible: celda.objeto !== null
            rareza: celda.objeto ? celda.objeto.rareza : 0
            nivel: Items.nivelDe(celda.objeto)
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
