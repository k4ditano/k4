//  Una banda de la línea de tiempo, con sus bloques.
//
//  El fondo hace dos cosas a la vez y hay que separarlas bien: pulsar salta a
//  ese instante —que es lo que uno intenta sin pensarlo en cuanto ve una línea
//  de tiempo— y arrastrar en un hueco crea un bloque nuevo. Se distinguen por
//  la distancia recorrida, no por un modo aparte: si has movido más de doce
//  píxeles, querías dibujar.
//
//  El MouseArea del fondo va declarado PRIMERO a propósito. En QML gana el
//  último que se declara, así que los bloques quedan por encima y se los
//  pueden llevar ellos.

import QtQuick
import "../../core"

Rectangle {
    id: pista

    property var modelo: []
    property real total: 1
    property real cabezal: 0
    property int elegido: 0
    property color tono: Theme.blue

    // Si se pueden crear bloques arrastrando en un hueco.
    property bool creable: true

    //  Si sus bloques se pueden sacar de la fila y llevar a otra. Solo tiene
    //  sentido donde las filas son capas apiladas.
    property bool porFilas: false
    property real pasoFila: 29

    signal saltar(real t)
    signal elegir(int indice)
    signal editar(int id, real t0, real t1)
    signal soltar()
    signal crear(real t0, real t1)
    signal moverFila(int id, int filas)

    radius: 6
    color: Theme.surface

    function px2t(px) { return px / Math.max(1, width) * total }

    // ── el fondo ──────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        property real xIni: 0
        property bool dibujando: false

        onPressed: function (ev) {
            xIni = ev.x
            dibujando = false
            pista.saltar(pista.px2t(ev.x))
        }

        onPositionChanged: function (ev) {
            if (!pressed)
                return
            if (!dibujando && pista.creable && Math.abs(ev.x - xIni) > 12)
                dibujando = true
            if (dibujando)
                fantasma.pon(xIni, ev.x)
            else
                pista.saltar(pista.px2t(ev.x))
        }

        onReleased: function (ev) {
            if (!dibujando)
                return
            dibujando = false
            fantasma.visible = false
            const a = pista.px2t(Math.min(xIni, ev.x))
            const b = pista.px2t(Math.max(xIni, ev.x))
            // Menos de medio segundo no es un bloque, es un resbalón.
            if (b - a >= 0.5)
                pista.crear(a, b)
        }
    }

    // Lo que se va a crear, mientras lo dibujas.
    Rectangle {
        id: fantasma
        visible: false
        y: 5
        height: pista.height - 10
        radius: 4
        color: Qt.rgba(pista.tono.r, pista.tono.g, pista.tono.b, 0.25)
        border.width: 1
        border.color: pista.tono

        function pon(a, b) {
            x = Math.min(a, b)
            width = Math.abs(b - a)
            visible = true
        }
    }

    // ── los bloques ───────────────────────────────────────────────
    Repeater {
        model: pista.modelo

        delegate: BloqueTiempo {
            required property var modelData
            required property int index

            t0: modelData.t0
            t1: modelData.t1
            total: pista.total
            elegido: index === pista.elegido
            //  El audio se pinta en amarillo aunque comparta banda con una
            //  imagen: en la línea de tiempo lo que se busca es «dónde suena la
            //  música», y el color lo dice sin leer nada. Los momentos de zoom no
            //  tienen `tipo`, así que se quedan con el tono de la pista.
            tono: modelData.tipo === "audio" ? Theme.yellow : pista.tono

            y: 5
            height: pista.height - 10

            onPulsado: pista.elegir(index)
            porFilas: pista.porFilas
            pasoFila: pista.pasoFila

            onCambiado: function (a, b) { pista.editar(modelData.id, a, b) }
            onCambiadoDeFila: function (f) { pista.moverFila(modelData.id, f) }
            onSoltado: pista.soltar()
        }
    }

    // ── dónde va la reproducción ──────────────────────────────────
    Rectangle {
        x: pista.width * (pista.cabezal / Math.max(0.001, pista.total)) - 1
        width: 2
        height: pista.height
        color: Theme.ink
    }
}
