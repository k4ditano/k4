//  Un bloque de la línea de tiempo, arrastrable y estirable.
//
//  Mientras dura el gesto se edita EN LOCAL, y el modelo se escribe al soltar.
//  No es una preferencia, es obligatorio: estos bloques son delegados de un
//  Repeater sobre un array normal, y escribir el modelo reasigna el array
//  entero —es la única forma de que QML emita el cambio—, lo que destruye y
//  recrea todos los delegados. Destruido el bloque, muerto el MouseArea que
//  tenía el agarre: el arrastre movía un píxel y se cortaba, porque el primer
//  evento ya mataba a quien escuchaba.
//
//  Con el estado local, el bloque que arrastras es siempre el mismo objeto; el
//  modelo se entera una vez, al final, y la recreación ocurre cuando ya nadie
//  tiene nada agarrado.

import QtQuick
import "../../core"

Rectangle {
    id: bloque

    property real t0: 0
    property real t1: 1
    property real total: 1
    property bool elegido: false
    property color tono: Theme.blue

    // El mínimo que puede durar. Por debajo de esto el bloque sería más
    // pequeño que sus propias asas y no habría forma de agarrarlo.
    readonly property real minimo: 0.4

    //  Si además se puede sacar de su fila y llevar a otra.
    //
    //  Solo tiene sentido donde las filas quieren decir algo apilado, o sea en
    //  las capas: mover un zoom «a otra fila» no significa nada, porque el zoom
    //  es uno solo. `pasoFila` es lo que mide una fila con su hueco, que el
    //  bloque no puede saber por sí mismo.
    property bool porFilas: false
    property real pasoFila: 29

    signal cambiado(real nuevoT0, real nuevoT1)
    signal cambiadoDeFila(int filas)
    signal soltado()
    signal pulsado()

    // El estado del gesto en curso. Solo manda mientras `editando`.
    property bool editando: false
    property real vT0: 0
    property real vT1: 0
    property real vY: 0

    readonly property real eT0: editando ? vT0 : t0
    readonly property real eT1: editando ? vT1 : t1

    x: parent.width * (eT0 / Math.max(0.001, total))
    width: Math.max(4, parent.width * ((eT1 - eT0) / Math.max(0.001, total)))
    radius: 4
    color: elegido ? tono : Qt.rgba(tono.r, tono.g, tono.b, 0.35)

    //  Sale de su fila con `transform` y no con `y`: la `y` la pone la pista y
    //  escribirla a mano pelearía con ella. Y con `z` por encima, o al pasar por
    //  encima de la fila vecina se metería debajo y parecería que se ha soltado.
    transform: Translate { y: bloque.vY }
    z: bloque.vY !== 0 ? 20 : 0

    Behavior on color { ColorAnimation { duration: 140 } }

    function px2t(px) { return px / Math.max(1, parent.width) * total }

    //  El instante que hay bajo el ratón, en tiempo de la PISTA.
    //
    //  Aquí estaba el fallo que hacía que arrastrar moviera un píxel y parara:
    //  el `MouseArea` vive dentro del bloque, así que su `ev.x` va en
    //  coordenadas del bloque. Y como el bloque se recoloca en cuanto cambia
    //  `t0`, el puntero se quedaba siempre en el mismo punto relativo y el
    //  desplazamiento se anulaba a sí mismo.
    //
    //  Sumando `x` —lo que el bloque lleva recorrido dentro de la pista— sale
    //  la posición absoluta del puntero, que es la única que no se mueve bajo
    //  los pies.
    function enPista(dentro) { return px2t(x + dentro) }

    function encaja(v, min, max) { return Math.max(min, Math.min(max, v)) }

    // ── mover ─────────────────────────────────────────────────────
    MouseArea {
        id: cuerpo

        //  Sin `anchors.fill`, con ancho y alto: un elemento anclado no se
        //  puede arrastrar. Aquí no arrastramos el elemento, pero la costumbre
        //  se mantiene por si algún día se hace.
        width: bloque.width
        height: bloque.height

        //  La línea de tiempo puede acabar dentro de algo desplazable, y
        //  entonces el ancestro se queda el gesto en cuanto detecta
        //  movimiento. Con esto no.
        preventStealing: true
        drag.filterChildren: true

        cursorShape: Qt.SizeAllCursor
        hoverEnabled: true

        property real anclaT: 0
        property real t0Ini: 0
        property real duracion: 0
        property real yIni: 0
        property bool arrastrando: false

        //  En coordenadas de la VENTANA para el eje vertical, por lo mismo que
        //  `enPista` para el horizontal: el bloque se despega con el propio
        //  arrastre y en sus coordenadas el puntero se queda quieto.
        function fuera(ev) { return mapToItem(null, 0, ev.y).y }

        onPressed: function (ev) {
            bloque.pulsado()
            anclaT = bloque.enPista(ev.x)
            t0Ini = bloque.t0
            duracion = bloque.t1 - bloque.t0
            yIni = fuera(ev)
            bloque.vT0 = bloque.t0
            bloque.vT1 = bloque.t1
            bloque.vY = 0
            bloque.editando = true
            arrastrando = false
        }

        onPositionChanged: function (ev) {
            if (!pressed)
                return
            arrastrando = true
            // El bloque se mueve entero: la duración no cambia al desplazarlo.
            let nuevo = t0Ini + (bloque.enPista(ev.x) - anclaT)
            nuevo = bloque.encaja(nuevo, 0, bloque.total - duracion)
            bloque.vT0 = nuevo
            bloque.vT1 = nuevo + duracion
            if (bloque.porFilas)
                bloque.vY = fuera(ev) - yIni
        }

        onReleased: {
            //  Los dos ejes a la vez, y a propósito: en un editor mover algo de
            //  fila y de instante en el mismo gesto es lo normal, y obligar a
            //  hacerlo en dos pasos se nota.
            //
            //  Primero el modelo y luego soltar el estado local: así el binding
            //  ya encuentra el valor nuevo y el bloque no da un salto atrás.
            if (arrastrando) {
                const filas = bloque.porFilas
                    ? Math.round(bloque.vY / Math.max(1, bloque.pasoFila)) : 0
                bloque.cambiado(bloque.vT0, bloque.vT1)
                if (filas !== 0)
                    bloque.cambiadoDeFila(filas)
                bloque.soltado()
            }
            bloque.vY = 0
            bloque.editando = false
        }

        //  Sin `onWheel` a propósito.
        //
        //  Aquí la rueda cambiaba el nivel del zoom. Dejó de tener sentido en
        //  cuanto la línea de tiempo se pudo recorrer: la rueda es para moverse,
        //  y un bloque que se la quedara haría que la línea se atascara cada vez
        //  que el puntero pasara por encima de algo. El nivel se cambia con la
        //  rueda sobre el vídeo, que además es donde se ve el efecto.
    }

    // ── estirar ───────────────────────────────────────────────────
    //
    //  Diez píxeles de asa, no cuatro. Acertar en una franja de cuatro píxeles
    //  arrastrando es pedir una puntería que nadie tiene por qué tener; es la
    //  misma lección del crisol de la mazmorra.
    Component {
        id: asa

        MouseArea {
            property bool esIzquierda: true

            width: 10
            height: bloque.height
            x: esIzquierda ? -3 : bloque.width - 7
            preventStealing: true
            cursorShape: Qt.SizeHorCursor
            hoverEnabled: true

            onPressed: {
                bloque.pulsado()
                bloque.vT0 = bloque.t0
                bloque.vT1 = bloque.t1
                bloque.editando = true
            }

            onPositionChanged: function (ev) {
                if (!pressed)
                    return
                // Lo mismo que el cuerpo: en tiempo de la pista, no del bloque.
                const t = bloque.encaja(bloque.enPista(x + ev.x), 0, bloque.total)
                if (esIzquierda)
                    bloque.vT0 = Math.min(t, bloque.vT1 - bloque.minimo)
                else
                    bloque.vT1 = Math.max(t, bloque.vT0 + bloque.minimo)
            }

            onReleased: {
                bloque.cambiado(bloque.vT0, bloque.vT1)
                bloque.soltado()
                bloque.editando = false
            }

            // Marca de agarre, solo cuando el bloque está elegido: en los demás
            // sería ruido.
            Rectangle {
                visible: bloque.elegido
                anchors.centerIn: parent
                width: 2
                height: parent.height * 0.5
                radius: 1
                color: Theme.ink
                opacity: parent.containsMouse ? 1 : 0.55
            }
        }
    }

    Loader { sourceComponent: asa; onLoaded: item.esIzquierda = true }
    Loader { sourceComponent: asa; onLoaded: item.esIzquierda = false }
}
