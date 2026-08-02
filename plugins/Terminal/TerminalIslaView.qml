//  La terminal dentro de la island.
//
//  Aquí no se emula nada: lo que se pinta es la rejilla que manda
//  k4term-isla, ya resuelta por el VT de ghostty, y lo que se teclea se le
//  devuelve tal cual. La vista es una ventana a una sesión que vive fuera —
//  por eso cerrarla no para nada y volver a abrirla te deja donde estabas.
//
//  Del teclado: mientras está abierta se lo queda entero, como el lanzador o
//  la pregunta a la IA. ESC cierra, que es la convención de la casa; si algún
//  día hace falta mandar un ESC de verdad a la sesión, será con otra tecla.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: vista

    required property var plugin

    readonly property var marco: plugin.marco

    //  La misma fuente que la terminal de ventana: es monoespaciada de
    //  verdad, así que el ancho de celda sale de medir una eme.
    //
    //  Medida la mide el plugin, no esta vista, aunque la use ella para todo:
    //  con ella decide él el alto de la island y con ella se calcula aquí
    //  cuántas filas caben, y esos dos números TIENEN que salir del mismo
    //  sitio. Cuando no lo hacían —18 allí, 17 aquí— la island pedía una fila
    //  más de las que tenía y no volvía a crecer nunca.
    readonly property int cuerpo: plugin.cuerpo
    readonly property real anchoCelda: plugin.anchoCelda
    readonly property real altoLinea: plugin.altoLinea
    readonly property int margen: 14

    //  La casa con virgulilla y sin más de tres tramos: en un pie de diez
    //  píxeles, una ruta entera no se lee, se estorba.
    function corto(ruta) {
        const casa = String(ruta).replace(/^\/home\/[^/]+/, "~")
        const partes = casa.split("/").filter(function (x) { return x.length > 0 })
        if (partes.length <= 3)
            return casa
        return (casa.charAt(0) === "~" ? "" : "…/") + partes.slice(-3).join("/")
    }

    //  Cuántas columnas y filas caben de verdad. Se le dice a la sesión, que
    //  es quien redimensiona el PTY: la shell tiene que saber su ancho o
    //  parte las líneas donde no toca.
    readonly property int cols: Math.max(20, Math.floor((width - margen * 2) / anchoCelda))
    readonly property int filas: Math.max(4, Math.floor((height - margen * 2) / altoLinea))

    //  Dónde estás dentro del historial, tal cual lo cuenta la sesión: la fila
    //  por la que empieza lo que se ve y cuántas hay en total.
    readonly property int arriba: marco ? marco.scroll[0] : 0
    readonly property int historial: marco ? Math.max(1, marco.scroll[1]) : 1
    readonly property real recorrido: Math.min(1, filas / historial)
    readonly property real asomado: arriba / historial

    onColsChanged: medir.restart()
    onFilasChanged: medir.restart()
    Component.onCompleted: {
        plugin.mandar({ que: "medida", cols: cols, filas: filas })
        plugin.mandar({ que: "pinta" })
        forzarFoco.start()
        pintadoX = destinoX
        pintadoY = destinoY
    }


    Timer {
        id: medir
        interval: 60
        onTriggered: vista.plugin.mandar({ que: "medida", cols: vista.cols,
                                           filas: vista.filas })
    }

    //  El foco llega un pelo después de que la island se abra; sin esta
    //  espera las primeras teclas se pierden.
    Timer {
        id: forzarFoco
        interval: 60
        onTriggered: campo.forceActiveFocus()
    }

    //  ── la rejilla ────────────────────────────────────────────────────
    //
    //  Un terminal NO es texto encadenado: es una cuadrícula de celdas
    //  iguales, y cada tramo va en la columna que le toca. Que se pinte por
    //  columna y no por ancho natural no es una manía —es la única forma de
    //  que cuadre—: en cuanto aparece un glifo que no mide lo mismo que los
    //  demás (los marcos de las cajas de claude, un icono de la Nerd Font, un
    //  espacio duro), encadenar avances desplaza la línea a la derecha
    //  mientras el cursor, que sí va por columna, se queda donde debe. El
    //  resultado era exactamente eso: el cursor «se iba» respecto del texto.
    //
    //  Así que el ancho del glifo se usa para elegir el dibujo y la REJILLA
    //  decide dónde va. Cada fila es un lienzo y cada tramo se ancla en
    //  `(columna - 1) * anchoCelda`, así que un tramo torcido no arrastra a
    //  los de después.
    Column {
        id: rejilla
        x: vista.margen
        y: vista.margen
        spacing: 0

        Repeater {
            model: vista.marco ? vista.marco.filas : []

            delegate: Item {
                required property var modelData
                width: vista.width - vista.margen * 2
                height: vista.altoLinea

                Repeater {
                    model: parent.modelData

                    delegate: Item {
                        required property var modelData
                        //  Su sitio en la rejilla, no donde acabara el vecino.
                        x: (modelData.c - 1) * vista.anchoCelda
                        width: modelData.t.length * vista.anchoCelda
                        height: vista.altoLinea

                        Rectangle {
                            anchors.fill: parent
                            color: modelData.b
                            visible: modelData.b !== String(Theme.islandBg)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.t
                            color: modelData.f
                            font.family: plugin.fuente
                            font.pixelSize: vista.cuerpo
                            //  El bit 0x02 del VT es la negrita.
                            font.weight: (modelData.n & 0x02) ? Font.Bold : Font.Normal
                            font.italic: (modelData.n & 0x04) !== 0
                            font.underline: (modelData.n & 0x08) !== 0
                            font.strikeout: (modelData.n & 0x40) !== 0
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }
    }

    //  ── el cursor y su estela ─────────────────────────────────────────
    //
    //  El cursor va aparte de las filas: es de la sesión, no del texto. Y no
    //  se teletransporta, se desliza dejando rastro — la misma estela que la
    //  ventana, con la misma curva, porque son la misma terminal y no se
    //  entendería que una tuviera el efecto y la otra no.
    //
    //  Cuántos fantasmas lo dice la sesión, que lee los ajustes de k4term:
    //  aquí no se decide nada, solo se pinta.
    //
    //  Nada de `Behavior on x`: lo que se quiere enseñar es el camino REAL,
    //  con su aceleración, así que se guarda por dónde ha pasado en vez de
    //  interpolarlo al pintar. Por eso hay un latido en vez de una animación.
    readonly property real destinoX: margen + (marco ? (marco.cursor[0] - 1) : 0) * anchoCelda
    readonly property real destinoY: margen + (marco ? (marco.cursor[1] - 1) : 0) * altoLinea

    //  Se inicializan a mano y no con un enlace a `destino`: un enlace haría
    //  que el cursor se plantara en el destino ANTES del primer latido, y ese
    //  primer movimiento —el único que se ve al abrir— saldría sin estela.
    property real pintadoX: 0
    property real pintadoY: 0
    property var fantasmas: []

    onDestinoXChanged: latido.start()
    onDestinoYChanged: latido.start()

    Timer {
        id: latido
        interval: 16
        repeat: true
        onTriggered: {
            const dx = Math.abs(vista.destinoX - vista.pintadoX)
            const dy = Math.abs(vista.destinoY - vista.pintadoY)
            const anterior = { x: vista.pintadoX, y: vista.pintadoY }

            //  Cuanto más lejos, más rápido: así un salto de línea no se
            //  arrastra y mover una letra sigue siendo suave. Y un salto
            //  enorme es una pantalla nueva, no un movimiento: ahí se planta.
            const lejos = (dx + dy) / Math.max(1, vista.altoLinea)
            const paso = Math.min(0.35 + lejos * 0.06, 0.75)
            const enorme = dy > vista.altoLinea * 12

            if (enorme) {
                vista.pintadoX = vista.destinoX
                vista.pintadoY = vista.destinoY
            } else {
                vista.pintadoX += (vista.destinoX - vista.pintadoX) * paso
                vista.pintadoY += (vista.destinoY - vista.pintadoY) * paso
            }

            //  A menos de medio píxel ya está en su sitio. Dejar de latir
            //  aquí es lo que evita quemar un temporizador para siempre.
            const quieto = Math.abs(vista.pintadoX - vista.destinoX) < 0.5
                        && Math.abs(vista.pintadoY - vista.destinoY) < 0.5
            if (quieto) {
                vista.pintadoX = vista.destinoX
                vista.pintadoY = vista.destinoY
            }

            let rastro = vista.fantasmas.slice()
            if (vista.plugin.estela > 0) {
                if (quieto) {
                    //  Parado, la estela se recoge sola: uno menos por latido
                    //  hasta vaciarse. Nada de seguir apuntando la posición
                    //  quieta —eso deja el rastro pegado al cursor para
                    //  siempre y el latido no para nunca.
                    rastro.shift()
                } else {
                    rastro.push(anterior)
                    if (rastro.length > vista.plugin.estela)
                        rastro = rastro.slice(rastro.length - vista.plugin.estela)
                }
            } else {
                rastro = []
            }
            vista.fantasmas = rastro

            if (quieto && rastro.length === 0)
                latido.stop()
        }
    }

    //  Los fantasmas, del más viejo al más nuevo y cada vez más presentes.
    //  Van antes que el cursor para que él quede encima.
    Repeater {
        model: vista.fantasmas

        delegate: Rectangle {
            required property var modelData
            required property int index
            x: modelData.x
            y: modelData.y
            width: 2
            height: vista.altoLinea
            color: Theme.ink
            opacity: (index + 1) / Math.max(1, vista.fantasmas.length) * 0.35
        }
    }

    Rectangle {
        visible: vista.marco !== null
        x: vista.pintadoX
        y: vista.pintadoY
        width: 2
        height: vista.altoLinea
        color: Theme.ink
        opacity: 0.9
    }

    //  Un receptor de teclas sin pintar nada: la traducción de tecla a bytes
    //  la hace la sesión, que para eso lleva el codificador de ghostty
    //  dentro. Aquí solo se decide si es texto o si tiene nombre.
    //  La rueda mueve el historial de la sesión, que es quien lo guarda. Tres
    //  líneas por muesca, como en todas partes.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function (rueda) {
            const pasos = rueda.angleDelta.y > 0 ? 3 : -3
            vista.plugin.mandar({ que: "rueda", lineas: -pasos })
            rueda.accepted = true
        }
    }

    //  Y la barrita de la casa, la misma pieza que el resto de la island: aquí
    //  no se le puede colgar de un Flickable —la rejilla no lo es, el historial
    //  vive en la sesión— así que se le dan `size` y `position` a mano con lo
    //  que dice el marco. Sale sola cuando hay algo que recorrer y se desvanece
    //  al parar, como en todas partes.
    IslandScrollBar {
        id: barra

        orientation: Qt.Vertical
        anchors.right: parent.right
        anchors.rightMargin: 4
        y: vista.margen
        height: vista.height - vista.margen * 2

        size: vista.recorrido
        position: vista.asomado

        //  Arrastrarla también mueve la sesión. Al agarrarla, Qt escribe en
        //  `position` y de paso rompe el enlace con el marco; por eso se vuelve
        //  a atar al soltar, que si no la barra se queda muerta a partir del
        //  primer arrastre y no lo avisa nadie.
        onPressedChanged: {
            if (pressed) {
                arrastre.start()
            } else {
                arrastre.stop()
                position = Qt.binding(function () { return vista.asomado })
            }
        }

        //  A tirones y no en cada píxel: la sesión solo sabe moverse en
        //  relativo, así que cada latido recalcula lo que falta desde donde
        //  está de verdad. Con eso el error no se acumula aunque los marcos
        //  lleguen tarde.
        Timer {
            id: arrastre
            interval: 50
            repeat: true
            onTriggered: {
                const destino = Math.round(barra.position * vista.historial)
                const salto = destino - vista.arriba
                if (salto !== 0)
                    vista.plugin.mandar({ que: "rueda", lineas: salto })
            }
        }
    }

    Item {
        id: campo
        focus: true
        anchors.fill: parent

        readonly property var nombres: ({})

        Keys.onPressed: function (e) {
            const mods = {
                shift: (e.modifiers & Qt.ShiftModifier) !== 0,
                control: (e.modifiers & Qt.ControlModifier) !== 0,
                alt: (e.modifiers & Qt.AltModifier) !== 0
            }

            const conNombre = function (nombre) {
                vista.plugin.mandar(Object.assign({ que: "tecla", nombre: nombre }, mods))
                e.accepted = true
            }

            switch (e.key) {
            case Qt.Key_Escape:       vista.plugin.cerrar(); e.accepted = true; return
            case Qt.Key_Return:
            case Qt.Key_Enter:        return conNombre("enter")
            case Qt.Key_Backspace:    return conNombre("backspace")
            case Qt.Key_Tab:          return conNombre("tab")
            case Qt.Key_Backtab:      return conNombre("tab")
            case Qt.Key_Up:           return conNombre("up")
            case Qt.Key_Down:         return conNombre("down")
            case Qt.Key_Left:         return conNombre("left")
            case Qt.Key_Right:        return conNombre("right")
            case Qt.Key_Home:         return conNombre("home")
            case Qt.Key_End:          return conNombre("end")
            case Qt.Key_PageUp:       return conNombre("pageup")
            case Qt.Key_PageDown:     return conNombre("pagedown")
            case Qt.Key_Delete:       return conNombre("delete")
            case Qt.Key_Insert:       return conNombre("insert")
            }

            if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F12)
                return conNombre("f" + (e.key - Qt.Key_F1 + 1))

            //  Lo demás va como texto. Qt ya entrega el carácter de control
            //  cuando se pulsa Ctrl+algo, así que un Ctrl+C llega hecho.
            if (e.text.length > 0) {
                vista.plugin.mandar({ que: "texto", valor: e.text })
                e.accepted = true
            }
        }
    }

    //  Pie discreto: dónde estás, que es lo que uno mira, y el recordatorio
    //  de salida en pequeño a la derecha. Con el mismo margen que la rejilla,
    //  que la island tiene las esquinas redondeadas y lo que se pega al borde
    //  se sale por debajo del recorte.
    IslandLabel {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: vista.margen
        anchors.bottomMargin: 6
        text: vista.marco && vista.marco.cwd ? vista.corto(vista.marco.cwd) : ""
        color: Theme.muted
        font.pixelSize: 10
    }

    IslandLabel {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: vista.margen
        anchors.bottomMargin: 6
        text: Idioma.t("ESC cierra")
        color: Theme.dim
        font.pixelSize: 10
    }
}
