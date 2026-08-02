//  El cursor de la casa, con estela.
//
//  Va de `cursorDelegate` en cualquier campo de texto: quien lo coloca es el
//  campo —le fija x, y y alto—, y aquí solo se decide cómo se pinta. El mismo
//  efecto que deja el cursor de k4term al moverse, para que escribir en la
//  island se sienta igual en la terminal y en el resto.
//
//      TextInput { cursorDelegate: K4.Estela {} }
//
//  Con `IslandCursor` de core no hace falta ni nombrar el color.
//
//  El rastro se APUNTA, no se interpola: lo que se quiere enseñar es por dónde
//  ha pasado de verdad, con su aceleración, y eso una animación declarativa no
//  lo sabe. De ahí el latido y de ahí que no haya un `Behavior on x`.

import QtQuick

Item {
    id: raiz

    //  Cuántos fantasmas deja. 0 lo apaga y queda un cursor normal.
    property int largo: 8
    property color color: Tema.tinta
    property int grosor: 2
    //  El parpadeo de siempre, pero solo cuando está parado: un cursor que se
    //  apaga a media carrera corta la estela por el medio.
    property bool parpadeo: true

    width: grosor

    //  En coordenadas del campo, que es donde viven los fantasmas: el propio
    //  cursor se mueve, así que apuntar posiciones relativas a él no valdría.
    //
    //  Se inicializan a mano y no con un enlace a x/y: con el enlace, el
    //  cursor se plantaría en el destino antes del primer latido y el primer
    //  movimiento saldría sin estela.
    property real pintadoX: 0
    property real pintadoY: 0
    property var fantasmas: []
    property bool moviendose: false

    Component.onCompleted: {
        pintadoX = x
        pintadoY = y
    }

    onXChanged: latido.start()
    onYChanged: latido.start()
    onLargoChanged: if (largo === 0) fantasmas = []

    Timer {
        id: latido
        interval: 16
        repeat: true
        onTriggered: {
            const dx = Math.abs(raiz.x - raiz.pintadoX)
            const dy = Math.abs(raiz.y - raiz.pintadoY)
            const anterior = { x: raiz.pintadoX, y: raiz.pintadoY }

            //  Cuanto más lejos, más rápido: así saltar al final de la línea
            //  no se arrastra y mover una letra sigue siendo suave. Un salto
            //  enorme es otro sitio, no un movimiento: ahí se planta.
            const alto = Math.max(1, raiz.height)
            const lejos = (dx + dy) / alto
            const paso = Math.min(0.35 + lejos * 0.06, 0.75)

            if (dy > alto * 12) {
                raiz.pintadoX = raiz.x
                raiz.pintadoY = raiz.y
            } else {
                raiz.pintadoX += (raiz.x - raiz.pintadoX) * paso
                raiz.pintadoY += (raiz.y - raiz.pintadoY) * paso
            }

            //  A menos de medio píxel ya está en su sitio. Parar aquí es lo
            //  que evita dejar un temporizador de 60 por segundo encendido
            //  para siempre en una barra que casi siempre está quieta.
            const quieto = Math.abs(raiz.pintadoX - raiz.x) < 0.5
                        && Math.abs(raiz.pintadoY - raiz.y) < 0.5
            if (quieto) {
                raiz.pintadoX = raiz.x
                raiz.pintadoY = raiz.y
            }

            let rastro = raiz.fantasmas.slice()
            if (raiz.largo > 0) {
                if (quieto) {
                    //  Parado, la estela se recoge sola: uno menos por latido
                    //  hasta vaciarse. Nada de seguir apuntando la posición
                    //  quieta, que eso deja el rastro pegado al cursor para
                    //  siempre y el latido no para nunca.
                    rastro.shift()
                } else {
                    rastro.push(anterior)
                    if (rastro.length > raiz.largo)
                        rastro = rastro.slice(rastro.length - raiz.largo)
                }
            } else {
                rastro = []
            }
            raiz.fantasmas = rastro
            raiz.moviendose = !quieto || rastro.length > 0

            if (!raiz.moviendose)
                latido.stop()
        }
    }

    //  Los fantasmas, del más viejo al más nuevo y cada vez más presentes.
    //  Van antes que el cursor para que él quede encima. Se colocan restando
    //  la posición del cursor porque son hijos suyos y él se mueve.
    Repeater {
        model: raiz.fantasmas

        delegate: Rectangle {
            required property var modelData
            required property int index
            x: modelData.x - raiz.x
            y: modelData.y - raiz.y
            width: raiz.grosor
            height: raiz.height
            color: raiz.color
            opacity: (index + 1) / Math.max(1, raiz.fantasmas.length) * 0.35
        }
    }

    Rectangle {
        id: barra
        x: raiz.pintadoX - raiz.x
        y: raiz.pintadoY - raiz.y
        width: raiz.grosor
        height: raiz.height
        color: raiz.color

        //  Quieto parpadea; moviéndose, entero. Y al dejar de moverse vuelve a
        //  entero antes de empezar: si no, el primer parpadeo puede pillarlo
        //  apagado justo al parar de escribir.
        opacity: 1
        SequentialAnimation on opacity {
            running: raiz.parpadeo && !raiz.moviendose
            loops: Animation.Infinite
            alwaysRunToEnd: false
            PauseAnimation { duration: 530 }
            NumberAnimation { to: 0; duration: 90 }
            PauseAnimation { duration: 440 }
            NumberAnimation { to: 1; duration: 90 }
        }
        onOpacityChanged: if (raiz.moviendose && opacity !== 1) opacity = 1
    }
}
