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
    property int cuantos: 0             // 0 = no está agrupada
    property bool arrastrable: true
    property string grupoClave: ""
    property bool modoFusion: false
    signal alCrisol()
    property bool arrastrando: caja.Drag.active

    signal pulsado()
    signal secundario()
    signal soltadoEn(int destino)
    signal soltadoGrupo(string clave)

    readonly property bool usable: objeto ? Game.algunoPuede(objeto) : true
    property alias encima: raton.containsMouse

    readonly property var rareza: objeto ? Items.rarezaDe(objeto.rareza) : null

    // ── zona de recepción: acepta la pieza que venga de otra celda
    DropArea {
        anchors.fill: parent
        onDropped: function (caida) {
            if (!caida.source)
                return
            // agrupado se mueve el grupo; suelto, la pieza
            if (caida.source.grupoClave && caida.source.grupoClave.length > 0)
                celda.soltadoGrupo(caida.source.grupoClave)
            else if (caida.source.origen !== undefined)
                celda.soltadoEn(caida.source.origen)
        }
    }

    Rectangle {
        id: caja
        // Sin anchors, y no es un descuido: un elemento anclado NO se puede
        // arrastrar. El ancla manda sobre x e y, así que drag.target movía la
        // caja y el ancla la devolvía en el mismo fotograma. Por eso no
        // funcionaba ni reordenar ni soltar en el crisol.
        width: parent.width
        height: parent.height
        radius: 9
        color: celda.arrastrando ? Theme.surfaceHi
            : (raton.containsMouse ? Theme.surfaceHi : Theme.surface)
        border.width: celda.objeto ? (celda.arrastrando ? 2 : 1) : 0
        border.color: celda.rareza ? celda.rareza.color : "transparent"
        scale: celda.arrastrando ? 1.12 : 1
        z: celda.arrastrando ? 50 : 0

        property int origen: celda.posicion
        // el crisol necesita la pieza en sí, no su posición
        property var objetoRef: celda.objeto
        property string grupoClave: celda.grupoClave

        Behavior on color { ColorAnimation { duration: 110 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        Drag.active: celda.arrastrable && raton.drag.active
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
            // baja si el badge de nuevo le ocupa la esquina
            anchors.topMargin: celda.objeto && celda.objeto.nuevo ? 15 : 2
            anchors.rightMargin: 2
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

        // ── cuántas iguales hay
        Rectangle {
            visible: celda.cuantos > 1
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: cuantasTexto.implicitWidth + 8
            height: 12
            radius: 6
            color: "#cc000000"

            IslandLabel {
                id: cuantasTexto
                anchors.centerIn: parent
                text: "×" + celda.cuantos
                color: Theme.ink
                font.pixelSize: 8
                font.weight: Font.Bold
            }
        }

        // ── recién salido de un cofre
        Rectangle {
            visible: celda.objeto !== null && celda.objeto.nuevo === true
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 2
            width: nuevoTexto.implicitWidth + 8
            height: 11
            radius: 5
            color: "#30d158"
            z: 3

            IslandLabel {
                id: nuevoTexto
                anchors.centerIn: parent
                text: Idioma.t("NUEVO")
                color: "#06210d"
                font.pixelSize: 7
                font.weight: Font.Bold
            }

            SequentialAnimation on opacity {
                running: parent.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }

        MouseArea {
            id: raton
            anchors.fill: parent
            hoverEnabled: true

            // pasar por encima ya es haberlo visto
            onContainsMouseChanged: {
                if (containsMouse && celda.objeto && celda.objeto.nuevo)
                    Game.vistoObjeto(celda.objeto.id)
            }
            enabled: celda.objeto !== null
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            drag.target: celda.arrastrable ? caja : null
            drag.axis: Drag.XAndYAxis
            // La rejilla es un Flickable y se queda con el gesto en cuanto
            // detecta desplazamiento vertical: sin esto, arrastrar una pieza
            // hacia abajo desplaza la lista en vez de mover la pieza.
            drag.filterChildren: true
            preventStealing: true

            onClicked: function (raton) {
                // Con el crisol abierto, pulsar mete la pieza. Arrastrar
                // también vale, pero obligar a arrastrar sesenta veces es
                // castigar al que solo quiere fundir repetidos.
                if (celda.modoFusion && raton.button !== Qt.RightButton) {
                    celda.alCrisol()
                    return
                }
                if (raton.button === Qt.RightButton)
                    celda.secundario()
                else
                    celda.pulsado()
            }

            onReleased: {
                if (caja.Drag.active)
                    caja.Drag.drop()
                // vuelve a su sitio: sin ancla que la recoloque, hay que
                // devolverla a mano tanto si soltó como si no
                caja.x = 0
                caja.y = 0
                // vuelve a su hueco: la rejilla decide dónde va, no el ratón
                caja.x = 0
                caja.y = 0
            }
        }
    }
}
