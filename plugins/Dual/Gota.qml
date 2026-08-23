//  Media barra, deslizándose pegada al borde de la pantalla.
//
//  No es una bolita que flota cerca del canto: es un TROZO DE BARRA con la
//  misma silueta que la island —esquinas invertidas que se funden con el
//  borde— que recorre el perímetro sin despegarse. Por eso lleva dos cosas
//  que una gota no necesita:
//
//  · el centro va a `grosor/2` del canto, para que el trozo quede a ras y no
//    a `margen` de distancia; y
//  · gira 90° en cada esquina, porque el lado fundido tiene que mirar SIEMPRE
//    hacia afuera. Si solo se orientara según hacia dónde viaja, al bajar por
//    el lateral enseñaría el canto redondeado a la pantalla y el fundido al
//    escritorio, que es justo del revés.

import QtQuick
import QtQuick.Shapes
import K4 as K4

Item {
    id: gota

    anchors.fill: parent

    //  -1 el trozo que se va por la izquierda, +1 el de la derecha.
    property int lado: -1

    property real salidaX: 0
    property real salidaY: 0
    property real finalX: 0
    property real finalY: 0

    //  0 arriba (en la barra) · 1 abajo (juntos). Lo mueve la escena POR
    //  ENLACE: asignarlo desde aquí lo rompería y el trozo se quedaría quieto.
    property real t: 0

    property bool mostrando: false
    visible: mostrando

    //  Las medidas del trozo: el alto de la barra plegada y lo que mide de
    //  largo la mitad que se desprende.
    property int largoTrozo: 96
    readonly property int ala: 16

    //  ── el trozo se estira y se afina al correr ──────────────────
    //
    //  Una gota que se desliza por un borde no viaja rígida: se alarga en el
    //  sentido de la marcha y adelgaza, y vuelve a engordar al frenar. Sin
    //  esto el trozo era un ladrillo que se trasladaba.
    //
    //  El seno vale 0 en los dos extremos y 1 por el medio, así que sale con el
    //  grosor EXACTO de la barra al partirse y al llegar —que es cuando tiene
    //  que empalmar con ella y con el dock— y solo se afina por el camino.
    readonly property real prisa: Math.sin(Math.PI * gota.t)
    readonly property real grosor: K4.Tema.altoPlegado * (1 - 0.45 * prisa)
    readonly property real largoAhora: gota.largoTrozo * (1 + 0.40 * prisa)

    //  El radio con el que dobla las esquinas.
    //
    //  Era 58 y despegaba el trozo del canto: una esquina redondeada corta por
    //  la diagonal, y con una cuadrática el centro se aleja del vértice justo
    //  un cuarto del radio —14 px con 58—, o sea que el trozo dejaba de ir a
    //  ras justo al doblar. Con 30 se queda en 7 y el giro sigue sin parecer un
    //  latigazo. A ras del todo solo se consigue con esquina en pico, y eso con
    //  una pieza de 34 de grosor se ve peor que el despegue.
    readonly property int codo: 30

    //  Lo hondo que llega el vientre a `d` píxeles del canto.
    //
    //  Lo necesita el puente: la pieza ya no es una banda de grosor constante
    //  sino un lomo que se afila en las puntas, así que un puente de grosor
    //  entero asoma por debajo de ella. Preguntándole a la propia curva, el
    //  puente nace justo con el fondo que tiene la pieza donde se meten.
    function fondoA(d) {
        //  Con la silueta de la barra el suelo es PLANO, así que a partir del
        //  arco de la esquina el fondo es el grosor entero. El puente nace
        //  metido más allá de ese arco, así que le toca el grosor completo y
        //  cierra a ras — que es lo que hacía falta para que al juntarse no
        //  asomara un rectángulo en medio.
        return gota.grosor
    }

    function arrancar() { mostrando = true }
    function parar() { mostrando = false }

    // ── el camino, por el perímetro ──────────────────────────────
    //
    //  El centro va siempre a medio grosor del canto, que es lo que deja el
    //  trozo a ras.
    readonly property real dentro: grosor / 2

    //  Las alturas salen de `dentro` y no de lo que pasen de fuera: al afinar,
    //  el centro tiene que acercarse al canto o el trozo se despegaría del
    //  borde justo cuando más deprisa va. En los extremos `dentro` vale medio
    //  grosor de barra, que es donde está el centro de la barra y el del dock.
    readonly property var puntos: {
        const bordeX = gota.lado < 0 ? gota.dentro : gota.width - gota.dentro
        const arriba = gota.dentro
        const abajo = gota.height - gota.dentro
        return [
            { x: gota.salidaX, y: arriba },
            { x: bordeX,       y: arriba },
            { x: bordeX,       y: abajo  },
            { x: gota.finalX,  y: abajo  }
        ]
    }

    function _len(a, b) { return Math.hypot(b.x - a.x, b.y - a.y) }

    function _haciaDe(a, b, d) {
        const l = gota._len(a, b)
        if (l < 0.001)
            return { x: a.x, y: a.y }
        return { x: a.x + (b.x - a.x) / l * d, y: a.y + (b.y - a.y) / l * d }
    }

    readonly property var tramos: {
        const p = gota.puntos
        const piezas = []
        let desde = p[0]

        for (let i = 1; i < p.length - 1; ++i) {
            const r = Math.min(gota.codo,
                               gota._len(p[i - 1], p[i]) / 2,
                               gota._len(p[i], p[i + 1]) / 2)
            const a = gota._haciaDe(p[i], p[i - 1], r)
            const b = gota._haciaDe(p[i], p[i + 1], r)
            piezas.push({ tipo: "recta", a: desde, b: a,
                          largo: gota._len(desde, a) })
            const aprox = (gota._len(a, p[i]) + gota._len(p[i], b)
                           + gota._len(a, b)) / 2
            piezas.push({ tipo: "codo", a: a, c: p[i], b: b, largo: aprox })
            desde = b
        }

        const fin = p[p.length - 1]
        piezas.push({ tipo: "recta", a: desde, b: fin,
                      largo: gota._len(desde, fin) })
        return piezas
    }

    readonly property real largoTotal: {
        let s = 0
        for (let i = 0; i < gota.tramos.length; ++i)
            s += gota.tramos[i].largo
        return Math.max(1, s)
    }

    //  Dónde está y CÓMO ESTÁ PUESTO al recorrer una fracción del camino.
    //
    //  El ángulo no sale de hacia dónde viaja: sale de cuántas esquinas lleva
    //  dobladas. Cada una son 90° hacia su lado, y dentro de la esquina se
    //  reparten poco a poco, así que el giro acompaña a la curva en vez de
    //  pegar un salto al entrar y otro al salir.
    function estadoEn(u) {
        const giro = gota.lado < 0 ? -90 : 90
        let resto = Math.max(0, Math.min(1, u)) * gota.largoTotal
        let esquinas = 0
        const ts = gota.tramos

        for (let i = 0; i < ts.length; ++i) {
            const tr = ts[i]
            const ultimo = i === ts.length - 1
            if (resto > tr.largo && !ultimo) {
                resto -= tr.largo
                if (tr.tipo === "codo")
                    esquinas += 1
                continue
            }
            const k = tr.largo < 0.001 ? 0 : Math.min(1, resto / tr.largo)
            if (tr.tipo === "recta")
                return { x: tr.a.x + (tr.b.x - tr.a.x) * k,
                         y: tr.a.y + (tr.b.y - tr.a.y) * k,
                         ang: esquinas * giro }
            const m = 1 - k
            return {
                x: m * m * tr.a.x + 2 * m * k * tr.c.x + k * k * tr.b.x,
                y: m * m * tr.a.y + 2 * m * k * tr.c.y + k * k * tr.b.y,
                ang: (esquinas + k) * giro
            }
        }
        const f = gota.puntos[gota.puntos.length - 1]
        return { x: f.x, y: f.y, ang: 2 * giro }
    }

    readonly property var ahora: gota.estadoEn(gota.t)

    //  Para que la escena pueda tender el cuello entre los dos: dónde está el
    //  canto que mira al otro trozo, y si va tumbado (por un borde horizontal)
    //  o de pie (bajando por el lateral).
    readonly property bool tumbado: Math.abs(Math.sin(gota.ahora.ang
                                                      * Math.PI / 180)) < 0.08

    // ── el trozo ─────────────────────────────────────────────────
    Item {
        id: pieza

        width: gota.largoAhora
        height: gota.grosor
        x: gota.ahora.x - width / 2
        y: gota.ahora.y - height / 2

        transform: Rotation {
            origin.x: pieza.width / 2
            origin.y: pieza.height / 2
            angle: gota.ahora.ang
        }

        Shape {
            anchors.fill: parent
            //  Las esquinas invertidas piden MSAA o salen con dientes.
            antialiasing: true
            layer.enabled: true
            layer.samples: 8
            layer.smooth: true

            ShapePath {
                id: trazo
                fillColor: K4.Tema.fondo
                strokeWidth: 0
                strokeColor: "transparent"

                readonly property real w: pieza.width
                readonly property real h: pieza.height

                //  LA MISMA SILUETA QUE LA BARRA, no una forma propia.
                //
                //  Llegué a darle un vientre curvo de una sola pieza para que
                //  pareciera más una gota, y trajo dos problemas: al crecer la
                //  barra se notaba el cambio de curvatura —son radios
                //  distintos— y el puente ya no cerraba contra una curva, así
                //  que al juntarse arriba asomaba un rectángulo en medio.
                //
                //  Lo líquido no lo da una forma distinta: lo dan el ala y el
                //  radio ENCOGIÉNDOSE con la marcha. En reposo valen justo lo
                //  que valen en la barra, así que el relevo es invisible; a
                //  toda velocidad el ala casi desaparece y los extremos se
                //  vuelven semicírculos.
                readonly property real g: Math.min(
                    gota.ala * (1 - 0.75 * gota.prisa),
                    trazo.h / 2, trazo.w / 6)
                readonly property real r: Math.min(32, trazo.h / 2,
                                                   trazo.w / 2 - trazo.g)

                startX: 0
                startY: 0

                PathArc {
                    x: trazo.g; y: trazo.g
                    radiusX: trazo.g; radiusY: trazo.g
                    direction: PathArc.Clockwise
                }
                PathLine { x: trazo.g; y: trazo.h - trazo.r }
                PathArc {
                    x: trazo.g + trazo.r; y: trazo.h
                    radiusX: trazo.r; radiusY: trazo.r
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: trazo.w - trazo.g - trazo.r; y: trazo.h }
                PathArc {
                    x: trazo.w - trazo.g; y: trazo.h - trazo.r
                    radiusX: trazo.r; radiusY: trazo.r
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: trazo.w - trazo.g; y: trazo.g }
                PathArc {
                    x: trazo.w; y: 0
                    radiusX: trazo.g; radiusY: trazo.g
                    direction: PathArc.Clockwise
                }
                PathLine { x: 0; y: 0 }
            }
        }
    }
}
