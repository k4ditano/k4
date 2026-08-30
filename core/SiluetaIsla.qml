//  La forma de la island: el cuerpo redondeado y las dos esquinas invertidas
//  que lo funden con el borde de la pantalla.
//
//  Vivía suelta dentro de `shell.qml`. Sale a su propio fichero porque ahora la
//  dibujan DOS sitios: la barra de verdad y la previsualización de Ajustes, que
//  no sería una previsualización si dibujara otra cosa — un rectángulo azul
//  redondeado no es esta forma, y lo que se quiere enseñar es precisamente cómo
//  queda.
//
//  Ojo con los tamaños pequeños: hace falta `2·(ala + radio)` a lo largo del
//  borde para que el trazado se cierre. Con menos, la curva de un extremo
//  empieza antes de que acabe la del otro, el recorrido se cruza y sale un
//  rectángulo; y si `ala + radio` llega justo a la mitad, las dos curvas del
//  fondo se juntan en punta y sale un champiñón. Por eso los radios se acotan
//  por el LARGO y no solo por el hondo.

import QtQuick
import QtQuick.Shapes

Shape {
    id: silueta

    //  Cuánto muerde cada esquina invertida hacia dentro.
    property real ala: Theme.wing

    //  El redondeo de las dos esquinas del fondo.
    property real cuerpoRadio: 20

    property color relleno: Theme.islandBg

    //  ── el mismo trazado en los cuatro bordes ────────────────────
    //
    //  El trazado se escribe UNA vez en coordenadas de BORDE: `u` corre a lo
    //  largo del borde al que se pega y `v` se mete hacia dentro de la
    //  pantalla. Cada lado solo cambia cómo se llevan esas dos a la caja del
    //  item, con `px()` y `py()`.
    //
    //  Escribir cuatro trazados sería tener cuatro siluetas que se separan en
    //  cuanto alguien toque una, y este fichero existe justo porque la barra y
    //  su croquis tienen que dibujar lo mismo.
    //
    //  Y se mapea por COORDENADA, no con una transformada del item, que fue el
    //  primer intento y se veía roto: `layer.enabled` —que hace falta para el
    //  MSAA de las alas— rasteriza a un búfer del tamaño del ITEM, así que en
    //  los laterales, donde el largo es el alto, el trazado se salía de la caja
    //  por la derecha y se recortaba ANTES de girarlo. Quedaba un pegote.
    property string lado: "arriba"        // arriba · abajo · izquierda · derecha

    //  `reflejada` era el caso especial del borde de abajo, de cuando solo
    //  había dos lados. Se queda porque lo usan la barra y el croquis, y manda
    //  sobre `lado` para no romperle nada a quien ya lo pone.
    property bool reflejada: false

    readonly property string _lado: reflejada ? "abajo" : lado
    readonly property bool _vertical: _lado === "izquierda" || _lado === "derecha"

    //  En los laterales el largo es el ALTO del item y el hondo su ancho: la
    //  caja no gira, gira el marco en el que está escrito el trazado.
    readonly property real _largo: _vertical ? height : width
    readonly property real _hondo: _vertical ? width : height

    // CurveRenderer suaviza mejor, pero descarta las esquinas invertidas (las
    // alas), así que se antialiasa con MSAA.
    antialiasing: true
    layer.enabled: true
    layer.samples: 8
    layer.smooth: true

    ShapePath {
        id: trazo

        fillColor: silueta.relleno
        strokeWidth: 0
        strokeColor: "transparent"

        readonly property real w: silueta._largo
        readonly property real h: silueta._hondo
        //  Acotados por el largo además de por el hondo: ver la nota de arriba.
        readonly property real g: Math.max(0, Math.min(silueta.ala, trazo.h / 2,
                                                       trazo.w / 6))
        readonly property real r: Math.max(0, Math.min(silueta.cuerpoRadio,
                                                       trazo.h / 2,
                                                       trazo.w / 3 - trazo.g))

        //  (u, v) del marco de borde → la caja del item.
        //
        //    arriba     (u, v)
        //    abajo      (u, h − v)      espejo, lo que había
        //    izquierda  (v, u)          el borde pasa a ser el eje Y
        //    derecha    (h − v, u)
        function px(u, v) {
            if (silueta._lado === "izquierda")
                return v
            if (silueta._lado === "derecha")
                return trazo.h - v
            return u
        }
        function py(u, v) {
            if (silueta._vertical)
                return u
            return silueta._lado === "abajo" ? trazo.h - v : v
        }

        //  Dos de los cuatro mapeos dan la vuelta al plano —el espejo de abajo
        //  y la transpuesta de la izquierda— y con el plano girado un arco en
        //  el sentido del reloj sale abombado al revés: las alas dejaban de
        //  morder hacia dentro y el cuerpo se comía sus esquinas. Así que el
        //  sentido de los cuatro arcos se invierte con el mapeo.
        readonly property bool inv: silueta._lado === "abajo"
                                    || silueta._lado === "izquierda"
        readonly property int haciaDentro: inv ? PathArc.Counterclockwise
                                               : PathArc.Clockwise
        readonly property int haciaFuera: inv ? PathArc.Clockwise
                                              : PathArc.Counterclockwise

        startX: trazo.px(0, 0)
        startY: trazo.py(0, 0)

        // esquina invertida del principio
        PathArc {
            x: trazo.px(trazo.g, trazo.g)
            y: trazo.py(trazo.g, trazo.g)
            radiusX: trazo.g
            radiusY: trazo.g
            direction: trazo.haciaDentro
        }

        PathLine {
            x: trazo.px(trazo.g, trazo.h - trazo.r)
            y: trazo.py(trazo.g, trazo.h - trazo.r)
        }

        // la del fondo, del mismo lado
        PathArc {
            x: trazo.px(trazo.g + trazo.r, trazo.h)
            y: trazo.py(trazo.g + trazo.r, trazo.h)
            radiusX: trazo.r
            radiusY: trazo.r
            direction: trazo.haciaFuera
        }

        PathLine {
            x: trazo.px(trazo.w - trazo.g - trazo.r, trazo.h)
            y: trazo.py(trazo.w - trazo.g - trazo.r, trazo.h)
        }

        // la del fondo, del otro
        PathArc {
            x: trazo.px(trazo.w - trazo.g, trazo.h - trazo.r)
            y: trazo.py(trazo.w - trazo.g, trazo.h - trazo.r)
            radiusX: trazo.r
            radiusY: trazo.r
            direction: trazo.haciaFuera
        }

        PathLine {
            x: trazo.px(trazo.w - trazo.g, trazo.g)
            y: trazo.py(trazo.w - trazo.g, trazo.g)
        }

        // esquina invertida del final
        PathArc {
            x: trazo.px(trazo.w, 0)
            y: trazo.py(trazo.w, 0)
            radiusX: trazo.g
            radiusY: trazo.g
            direction: trazo.haciaDentro
        }

        PathLine { x: trazo.px(0, 0); y: trazo.py(0, 0) }
    }
}
