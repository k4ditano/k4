//  La forma de la island: el cuerpo redondeado y las dos esquinas invertidas
//  que lo funden con el borde de la pantalla.
//
//  Vivía suelta dentro de `shell.qml`. Sale a su propio fichero porque ahora la
//  dibujan DOS sitios: la barra de verdad y la previsualización de Ajustes, que
//  no sería una previsualización si dibujara otra cosa — un rectángulo azul
//  redondeado no es esta forma, y lo que se quiere enseñar es precisamente cómo
//  queda.
//
//  Ojo con los tamaños pequeños: hace falta `2·(ala + radio)` de ancho para que
//  el trazado se cierre. Con menos, la curva derecha empieza antes de que acabe
//  la izquierda, el recorrido se cruza y sale un rectángulo; y si `ala + radio`
//  llega justo a la mitad, las dos curvas de abajo se juntan en punta y sale un
//  champiñón. Por eso los radios se acotan por el ANCHO y no solo por el alto.

import QtQuick
import QtQuick.Shapes

Shape {
    id: silueta

    //  Cuánto muerde cada esquina invertida hacia dentro.
    property real ala: Theme.wing

    //  El redondeo de las dos esquinas de abajo.
    property real cuerpoRadio: 20

    property color relleno: Theme.islandBg

    //  Con la barra abajo se refleja entera: las alas pasan a fundirse con el
    //  borde inferior sin tocar ni un punto del trazado.
    property bool reflejada: false

    // CurveRenderer suaviza mejor, pero descarta las esquinas invertidas (las
    // alas), así que se antialiasa con MSAA.
    antialiasing: true
    layer.enabled: true
    layer.samples: 8
    layer.smooth: true

    transform: Scale {
        origin.y: silueta.height / 2
        yScale: silueta.reflejada ? -1 : 1
    }

    ShapePath {
        id: trazo

        fillColor: silueta.relleno
        strokeWidth: 0
        strokeColor: "transparent"

        readonly property real w: silueta.width
        readonly property real h: silueta.height
        //  Acotados por el ancho además de por el alto: ver la nota de arriba.
        readonly property real g: Math.max(0, Math.min(silueta.ala, trazo.h / 2,
                                                       trazo.w / 6))
        readonly property real r: Math.max(0, Math.min(silueta.cuerpoRadio,
                                                       trazo.h / 2,
                                                       trazo.w / 3 - trazo.g))

        startX: 0
        startY: 0

        // esquina invertida izquierda
        PathArc {
            x: trazo.g
            y: trazo.g
            radiusX: trazo.g
            radiusY: trazo.g
            direction: PathArc.Clockwise
        }

        PathLine { x: trazo.g; y: trazo.h - trazo.r }

        // inferior izquierda
        PathArc {
            x: trazo.g + trazo.r
            y: trazo.h
            radiusX: trazo.r
            radiusY: trazo.r
            direction: PathArc.Counterclockwise
        }

        PathLine { x: trazo.w - trazo.g - trazo.r; y: trazo.h }

        // inferior derecha
        PathArc {
            x: trazo.w - trazo.g
            y: trazo.h - trazo.r
            radiusX: trazo.r
            radiusY: trazo.r
            direction: PathArc.Counterclockwise
        }

        PathLine { x: trazo.w - trazo.g; y: trazo.g }

        // esquina invertida derecha
        PathArc {
            x: trazo.w
            y: 0
            radiusX: trazo.g
            radiusY: trazo.g
            direction: PathArc.Clockwise
        }

        PathLine { x: 0; y: 0 }
    }
}
