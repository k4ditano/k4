//  El nombre de una pista, a la izquierda de la línea de tiempo.
//
//  Es el sitio donde uno busca qué capas hay y en qué orden van, así que además
//  se arrastra para reordenarlas. Había flechas de subir y bajar y sobraban: el
//  gesto natural al ver una lista de capas es coger una y moverla, no buscar un
//  botón. Las flechas siguen existiendo para mover un ELEMENTO de banda, que es
//  otra cosa, y viven en la ficha de la derecha con la selección delante.
//
//  Mientras dura el arrastre la fila se despega y sigue al puntero; el hueco al
//  que va se marca en la lista. El modelo se escribe al soltar, y no antes: como
//  en los bloques de la línea de tiempo, reordenar destruye los delegados y con
//  ellos el MouseArea que tenía el agarre.

import QtQuick
import "../../core"

Rectangle {
    id: cabecera

    property string texto: ""
    property int glifo: 0
    property color tono: Theme.blue
    property bool elegida: false
    property bool visiblePista: true
    property bool bloqueada: false
    property bool solo: false
    property bool esVideo: false

    // Las pistas fijas —vídeo y zoom— no se reordenan.
    property bool arrastrable: false
    property int alto: 26

    signal pulsada()
    // Cuántas filas se ha movido, hacia arriba en negativo.
    signal reordenada(int filas)
    signal alternarVisible()
    signal alternarBloqueo()
    signal alternarSolo()

    property bool arrastrando: false
    property real deltaY: 0

    y: 0
    z: arrastrando ? 20 : 0
    radius: 6
    color: elegida ? Qt.rgba(tono.r, tono.g, tono.b, 0.22)
        : (raton.containsMouse ? Theme.surfaceHi : Theme.surface)
    opacity: arrastrando ? 0.9 : 1

    Behavior on color { ColorAnimation { duration: 110 } }

    // Se despega con `transform` y no con `y`: la fila la coloca un layout, y
    // escribir `y` a mano pelearía con él en cada paso.
    transform: Translate { y: cabecera.arrastrando ? cabecera.deltaY : 0 }

    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: cabecera.arrastrable
            ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
            : Qt.PointingHandCursor

        property real yIni: 0
        property bool movido: false

        //  En coordenadas de la ventana, no de la fila: la fila se despega con
        //  el propio arrastre y en sus coordenadas el puntero se queda quieto.
        //  Es la misma trampa de los bloques de la línea de tiempo.
        function fuera(ev) { return mapToItem(null, 0, ev.y).y }

        onPressed: function (ev) {
            yIni = fuera(ev)
            movido = false
        }

        onPositionChanged: function (ev) {
            if (!pressed || !cabecera.arrastrable)
                return
            const d = fuera(ev) - yIni
            if (!movido && Math.abs(d) < 5)
                return
            movido = true
            cabecera.arrastrando = true
            cabecera.deltaY = d
        }

        onReleased: {
            if (!movido) {
                cabecera.pulsada()
                return
            }
            // Media fila de margen: pasado el centro de la vecina, se cambia.
            const filas = Math.round(cabecera.deltaY / (cabecera.alto + 3))
            cabecera.arrastrando = false
            cabecera.deltaY = 0
            if (filas !== 0)
                cabecera.reordenada(filas)
        }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 7
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        IconGlyph {
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(cabecera.glifo)
            color: cabecera.tono
            font.pixelSize: 12
        }

        IslandLabel {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 58 - (cabecera.arrastrable ? 18 : 0)
            text: cabecera.texto
            color: cabecera.elegida ? Theme.ink : Theme.muted
            font.pixelSize: 10
            elide: Text.ElideMiddle
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: cabecera.arrastrable ? 20 : 5
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        IconGlyph {
            text: String.fromCodePoint(cabecera.visiblePista ? 0xF0208 : 0xF0209)
            color: cabecera.visiblePista ? Theme.muted : Theme.dim
            font.pixelSize: 11
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: cabecera.alternarVisible()
            }
        }

        IconGlyph {
            text: String.fromCodePoint(cabecera.bloqueada ? 0xF033E : 0xF033F)
            color: cabecera.bloqueada ? Theme.orange : Theme.muted
            font.pixelSize: 11
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: cabecera.alternarBloqueo()
            }
        }

        IconGlyph {
            visible: !cabecera.esVideo
            text: String.fromCodePoint(0xF04CE) // md-star
            color: cabecera.solo ? Theme.yellow : Theme.dim
            font.pixelSize: 10
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: cabecera.alternarSolo()
            }
        }
    }

    //  El asa, solo al pasar por encima: dice que esto se puede coger, que es
    //  lo único que hacía falta decir.
    IconGlyph {
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        visible: cabecera.arrastrable && (raton.containsMouse || cabecera.arrastrando)
        text: String.fromCodePoint(0x000F01DD)     // md-drag_vertical
        color: Theme.dim
        font.pixelSize: 13
    }
}
