//  La gota: la barra deja caer una gota que al llegar abajo se estrella contra
//  el canto y se extiende hasta ser el dock. Y de vuelta, la que sube se
//  estrella contra el canto de ARRIBA y se extiende hasta ser la barra.
//
//  Lo pidieron con estas palabras —«the island bar stays there but causes a
//  drop to drop and form the dock»— y es mejor idea que el viaje para el uso
//  diario: dura un segundo en vez de tres, y es el único de los dos que se
//  entiende también con la barra puesta, porque no cuenta un traslado sino un
//  desprendimiento.
//
//  Todo sale de un solo número, `t`, que va de 0 —en la barra— a 1 —extendida
//  en el suelo— y se recorre al revés para volver. Tres tramos:
//
//    0 … corte      la barra y la gota, pegadas.
//    corte … suelo  el viaje, acelerando: el recorrido va con el cuadrado del
//                   tiempo, que es lo que hace algo que se suelta.
//    suelo … 1      el canto de abajo: se aplasta contra él y se extiende de
//                   golpe hasta ser exactamente la semilla del dock.
//
//  Y EL PRIMER TRAMO NO ES SIEMPRE EL MISMO. La regla es una sola —la gota
//  viaja hasta que choca con algo— y arriba hay dos cosas distintas contra las
//  que chocar:
//
//   · si la barra sigue puesta («las dos a la vez»), hay DEPÓSITO. Bajando la
//     gota nace de él —se hincha bajo su canto, se descuelga y el cuello que la
//     sujeta adelgaza hasta romperse— y subiendo lo alcanza y se deja absorber
//     por ese mismo cuello. La subida es la bajada del revés, literalmente.
//   · si la barra se ha ido, arriba solo queda el CANTO DE LA PANTALLA, y contra
//     un canto lo que se hace es estrellarse: la gota llega lanzada y se
//     extiende contra él igual que se extendió contra el de abajo. Ese charco YA
//     es la barra, con su ancho y su silueta, y por eso la island puede aparecer
//     debajo sin que se vea el cambio.
//
//  Haciendo siempre lo primero, la subida sin barra se quedaba a treinta y
//  cuatro píxeles del borde —el canto de abajo de una island que no estaba— y
//  la barra crecía después, sola, sin nada que la empujara. Y haciendo siempre
//  lo segundo, con la barra puesta el charco se pintaba encima de ella y le
//  tapaba el reloj medio segundo.
//
//  La animación es LINEAL y las curvas se hacen a mano. Con una sola easing no
//  salen las tres cosas —el hinchado es lento, el viaje acelera y el golpe
//  frena— y encadenar tres animaciones sería tener el reparto del tiempo en
//  tres sitios, con tres sitios donde se descuadren entre sí.
//
//  Esta ventana no reserva sitio y solo existe mientras hay gota: pasa por
//  encima de las ventanas sin recolocar nada.

import QtQuick
import QtQuick.Shapes
import K4 as K4

K4.Ventana {
    id: caida

    required property var plugin

    nombre: "k4-dual-gota"
    encima: true

    //  En la pantalla de la barra de la que cuelga, no en la que el compositor
    //  prefiera: si no, la gota cae en un monitor y el dock sale en otro.
    pantalla: caida.plugin.pantalla

    //  Existe SOLO mientras haya gota — más el rato de más que pide el relevo.
    //
    //  Con `visible` atado únicamente a lo que dice el plugin, la ventana se iba
    //  en el mismo fotograma en que el dock empieza a crecer, y entonces el
    //  relevo no tapaba nada porque ya no había nada que lo pintara. Y dejarla
    //  puesta no es una opción: es una superficie a pantalla completa por ENCIMA
    //  del dock, así que se queda delante y el dock deja de responder al ratón
    //  (la misma mordida que cuenta Escena.qml).
    property bool sostener: false
    visible: caida.plugin.gotaFuera || caida.sostener

    //  Se salta las reservas ajenas: tiene que pintar SOBRE la franja de la
    //  barra —de ahí sale la gota, y contra ahí vuelve—, no debajo. Sin esto la
    //  ventana empieza donde acaba la barra y el charco de arriba se dibujaría
    //  34 px por debajo del canto contra el que dice estrellarse.
    reserva: -1

    zonaActiva: nada

    Item { id: nada; width: 0; height: 0 }

    // ── de dónde a dónde ────────────────────────────────────────
    //
    //  El centro de la barra y su canto de abajo, congelados con el resto del
    //  origen: mientras la barra se recoge su rect se escapa, y el cuello
    //  quedaría colgando de un sitio en el que ya no hay barra.
    readonly property real xBarra: caida.plugin.origenX
    readonly property real yBarra: caida.plugin.origenY
        + K4.Tema.altoPlegado / 2

    //  Y dónde acaba abajo: el centro de la semilla del dock, a ras del borde.
    //  La semilla sale donde vaya a salir el dock —su alineación, ver
    //  `alineacionDock`— así que con la barra y el dock en puntos distintos la
    //  gota viaja en diagonal, hacia donde la llaman, en vez de estrellarse a un
    //  palmo de donde va a nacer el dock. Con los dos en el mismo sitio, que es
    //  lo de fábrica, no se desvía ni un píxel.
    readonly property real xSuelo: caida.plugin.centroDock(caida.width,
                                                           caida.plugin.anchoLleno)

    //  La semilla: el ancho y el grosor con los que el dock —y la barra— empiezan
    //  a crecer. Los dos charcos tienen que acabar EXACTAMENTE ahí o el relevo
    //  se ve. Y son los mismos: `anchoSemilla` de la barra son estos mismos
    //  píxeles menos las dos alas.
    readonly property real rxFin: caida.plugin.largoTrozo
    readonly property real ryFin: K4.Tema.altoPlegado / 2

    //  Lo gorda que llega a ser colgando. Sale del grosor de la barra —es de ahí
    //  de donde sale la masa— y no de una medida propia: con la barra fina, una
    //  gota de tamaño fijo parecía un globo atado a un hilo.
    readonly property real radio: K4.Tema.altoPlegado * 0.72

    //  Y lo que se descuelga antes de romperse.
    //
    //  Estaba en 1.55 radios y el cuello no se llegaba a ver: la gota seguía
    //  solapada con la barra hasta el último instante del tramo, así que el hilo
    //  aparecía y se partía en la misma décima. Con 2.8 la gota se despega de
    //  verdad y quedan treinta y pico píxeles de cuello estirándose, que es lo
    //  que hay que ver antes de que ceda.
    readonly property real hondo: caida.radio * 2.8

    // ── el reloj ────────────────────────────────────────────────
    property real t: 0

    //  Y en qué sentido va. Se apunta a mano y no se lee del modo porque tiene
    //  que sobrevivir al relevo: cuando la gota llega arriba el modo ya es
    //  "creciendo", y en `t: 0` la forma de embestir es el charco entero
    //  mientras que la de bajar es nada.
    property bool sube: false

    //  Lo único que de verdad cambia la escena: si lo de arriba es un canto
    //  contra el que estrellarse o un depósito en el que fundirse. Volviendo con
    //  la barra puesta no hay nada que reconstruir, así que la subida es la
    //  bajada del revés y no hay charco ninguno.
    readonly property bool embiste: caida.sube && !caida.plugin.ambasActiva

    readonly property real tCorte: caida.plugin.gotaCorte
    readonly property real tSuelo: caida.plugin.gotaSuelo

    // ── las curvas, a mano ──────────────────────────────────────
    function _lim(v) { return Math.max(0, Math.min(1, v)) }
    function _mezcla(a, b, k) { return a + (b - a) * k }

    //  Colgando pasan dos cosas y NO a la vez: primero se abomba y después se
    //  descuelga. Con el mismo exponente para las dos, la gota crecía y bajaba
    //  al mismo tiempo y parecía que la barra escupía una bola en vez de
    //  rezumarla.
    function _hincha(u) { return Math.pow(u, 0.55) }
    function _cuelga(u) { return Math.pow(u, 1.7) }

    //  Cada tramo empieza justo donde acaba el anterior —de ahí que sean
    //  funciones y no valores: los extremos se piden por su nombre, `_rxCae(1)`,
    //  en vez de copiarse a mano y descuadrarse a la primera que se toque una.
    function _rxCuelga(h) { return caida.radio * (0.05 + 0.95 * h) }
    function _ryCuelga(h) { return caida._rxCuelga(h) * (1 + 0.18 * h) }

    //  Viajando se estira y se afina, en proporción a lo deprisa que va.
    function _rxCae(p) { return caida.radio * (1 - 0.30 * p) }
    function _ryCae(p) { return caida.radio * 1.18 * (1 + 0.62 * p) }

    //  El recorrido, con el cuadrado del tiempo. La pizca de recta se come el
    //  frenazo del arranque: la gota YA venía moviéndose cuando el tramo empieza
    //  —descolgándose, o saliendo del charco— y un cuadrado puro la paraba en
    //  seco antes de volver a acelerarla.
    function _gravedad(u) { return 0.18 * u + 0.82 * u * u }

    //  El golpe: llega, se pasa un poco y vuelve. Es OutBack escrito a mano
    //  porque hace falta el VALOR, no una animación — y acaba exactamente en 1,
    //  que es lo que deja el charco clavado en la semilla a la que releva.
    function _atras(u) {
        const s = 1.28
        const k = u - 1
        return k * k * ((s + 1) * k + s) + 1
    }

    // ── dónde empieza y acaba cada viaje ────────────────────────
    //
    //  Bajando viaja el FONDO de la gota y acaba en el canto de abajo; subiendo
    //  viaja el LOMO y acaba en el de arriba. Atando el centro en vez del borde
    //  que va por delante, al aplastarse contra el canto el grosor menguaba y la
    //  gota se despegaba de él justo al asentarse.
    readonly property real fondoSalida: caida.yBarra
        + caida.hondo + caida._ryCuelga(1)
    readonly property real techoSalida: caida.height - 2 * caida._ryCae(1)

    // ── la forma, entera, en un sitio ───────────────────────────
    //
    //  Un solo objeto y no ocho properties con el mismo `if` repetido ocho
    //  veces: son tres tramos por dos sentidos, y con cada magnitud por su lado
    //  la primera vez que se toque un tramo se queda uno sin tocar.
    //
    //  `arriba` y `abajo` son lo afilada que va por cada punta. Lo afilado es
    //  SIEMPRE la punta de atrás —de donde tiran, o por donde vino— así que
    //  bajando afila arriba y subiendo afila abajo. `plano` es cuánto de sus
    //  cantos son rectos en vez de curvos: una elipse de 174×34 no es la píldora
    //  a la que releva, y al entregar el testigo asomaban sus esquinas un par de
    //  fotogramas. Estrellándose se aplana por los dos lados —que es lo que hace
    //  un charco— y de paso acaba con la silueta exacta que le toca.
    readonly property var ahora: caida.forma(caida.t, caida.embiste)

    function forma(t, embiste) {
        const uCorte = caida._lim(t / caida.tCorte)
        const uCae = caida._lim((t - caida.tCorte)
                                / (caida.tSuelo - caida.tCorte))
        const uChoque = caida._lim((t - caida.tSuelo) / (1 - caida.tSuelo))

        //  ── el canto de abajo ─────────────────────────────────
        //
        //  El mismo tramo en los dos sentidos: subiendo es este del revés, o sea
        //  el charco recogiéndose y estirándose para salir disparado.
        if (t >= caida.tSuelo) {
            const p = caida._atras(uChoque)
            const ry = caida._mezcla(caida._ryCae(1), caida.ryFin, p)
            const punta = 0.85 * Math.pow(1 - uChoque, 1.6)
            return {
                rx: caida._mezcla(caida._rxCae(1), caida.rxFin, p),
                ry: ry,
                x: caida.xSuelo,
                y: caida.height - ry,
                arriba: embiste ? 0 : punta,
                abajo: embiste ? punta : 0,
                plano: uChoque * 0.55,
                cuello: 0
            }
        }

        //  ── el viaje ──────────────────────────────────────────
        if (t >= caida.tCorte) {
            if (embiste) {
                //  Lo que viaja es el lomo, y llega ACELERANDO: el reloj de este
                //  tramo corre de 1 a 0, así que el tiempo transcurrido es
                //  `1 - uCae` y la gravedad se aplica sobre él. Frenando en vez
                //  de acelerar, la gota se posaba en el canto de arriba en vez
                //  de embestirlo, y entonces el charco no tenía por qué salir.
                const marcha = 1 - uCae
                const prisa = 1 - 0.30 * Math.sin(Math.PI * uCae)
                const ry = caida._ryCae(prisa)
                return {
                    rx: caida._rxCae(prisa), ry: ry,
                    x: caida._mezcla(caida.xSuelo, caida.xBarra,
                                     caida._gravedad(marcha)),
                    y: caida.techoSalida * (1 - caida._gravedad(marcha)) + ry,
                    arriba: 0, abajo: 0.55 + 0.30 * marcha,
                    plano: 0, cuello: 0
                }
            }
            const ry = caida._ryCae(uCae)
            return {
                rx: caida._rxCae(uCae), ry: ry,
                x: caida._mezcla(caida.xBarra, caida.xSuelo,
                                 caida._gravedad(uCae)),
                y: caida._mezcla(caida.fondoSalida, caida.height,
                                 caida._gravedad(uCae)) - ry,
                arriba: 0.55 + 0.30 * uCae, abajo: 0,
                plano: 0, cuello: 0
            }
        }

        //  ── el canto de arriba, subiendo ──────────────────────
        //
        //  El mismo golpe que abajo, del revés: aquí el reloj también corre de 1
        //  a 0, así que el charco progresa con `1 - uCorte`. Al llegar a cero
        //  mide exactamente la semilla de la barra, con su misma silueta, y por
        //  eso la island puede aparecer debajo sin que se vea el cambio.
        if (embiste) {
            const p = caida._atras(1 - uCorte)
            const ry = caida._mezcla(caida._ryCae(1), caida.ryFin, p)
            return {
                rx: caida._mezcla(caida._rxCae(1), caida.rxFin, p),
                ry: ry,
                x: caida.xBarra,
                y: ry,
                arriba: 0, abajo: 0.85 * Math.pow(uCorte, 1.6),
                plano: (1 - uCorte) * 0.55,
                cuello: 0
            }
        }

        //  ── colgando de la barra, bajando ─────────────────────
        //
        //  El centro sale directo: el fondo es `yBarra + hondo·cuelga + ry` y al
        //  restarle el propio `ry` para centrarlo, el grosor se va solo.
        const h = caida._hincha(uCorte)
        return {
            rx: caida._rxCuelga(h), ry: caida._ryCuelga(h),
            x: caida.xBarra,
            y: caida.yBarra + caida.hondo * caida._cuelga(uCorte),
            arriba: 0.55 * h, abajo: 0,
            plano: 0, cuello: uCorte
        }
    }

    // ── el cuello ───────────────────────────────────────────────
    //
    //  Lo que la sujeta a la barra, lo que la suelta — y lo que la recoge al
    //  volver, si la barra sigue ahí. Solo falta cuando la gota embiste, que
    //  entonces no hay depósito del que colgar.
    //
    //  Mismo truco que el puente de Escena.qml —una cuadrática cuyo control se
    //  despeja para que la curva pase por la cintura— pero de pie. Los tres
    //  anchos adelgazan a ritmos distintos y eso es todo el efecto: la boca
    //  aguanta —el agua sigue pegada a la barra—, el pie la sigue, y la CINTURA
    //  se va antes que las dos, que es lo que abre el reloj de arena y lo que
    //  acaba partiéndose.
    readonly property real cuelloU: caida.ahora.cuello
    readonly property real bocaCuello:
        caida.radio * 0.80 * Math.pow(1 - caida.cuelloU, 0.55)
    readonly property real cinturaCuello:
        caida.radio * 0.62 * Math.pow(1 - caida.cuelloU, 1.15)
    readonly property real pieCuello:
        caida.radio * 0.70 * Math.pow(1 - caida.cuelloU, 0.80)

    //  Muerde en la barra en vez de apoyarse en su canto: el canto es la línea
    //  recta de la silueta, y un cuello que nace exactamente ahí deja una junta
    //  visible en cuanto el antialias de los dos bordes no coincide.
    readonly property real bocaY: caida.yBarra - 4

    //  Despejado de la cuadrática: el punto medio de una curva de Bézier de
    //  segundo grado es (P0 + 2C + P2)/4, así que para que pase por la cintura
    //  el control se va al doble de lejos por el otro lado.
    readonly property real mandoCuello:
        (4 * caida.cinturaCuello - caida.bocaCuello - caida.pieCuello) / 2

    // ── el dibujo ───────────────────────────────────────────────
    //
    //  Las dos piezas en un solo Shape y del mismo color: se solapan a
    //  propósito —el cuello acaba en el CENTRO de la gota, metido dentro— y
    //  siendo opacas y del mismo color no hay junta que ver.
    //
    //  Sin capa propia: aquí no hay esquinas invertidas, que es lo que pide MSAA
    //  en los trozos del viaje; solo curvas, y esas ya las suaviza el Shape.
    Shape {
        anchors.fill: parent
        antialiasing: true

        //  La gota. Cuadráticas y no arcos elípticos: un arco pide acertar con
        //  el sentido del barrido y aquí la forma cambia de proporción en cada
        //  fotograma, así que un signo mal puesto se ve una vez de cada diez.
        //  Una cuadrática no tiene sentido que equivocar.
        ShapePath {
            id: trazoGota
            fillColor: K4.Tema.fondo
            strokeWidth: 0
            strokeColor: "transparent"

            readonly property real gx: caida.ahora.x
            readonly property real gy: caida.ahora.y
            readonly property real rx: caida.ahora.rx
            readonly property real ry: caida.ahora.ry

            //  Los dos tramos rectos: sin aplastar miden cero y las rectas son
            //  degeneradas, así que la forma es exactamente la elipse de antes.
            readonly property real llano: rx * caida.ahora.plano

            //  El control de cada mitad: en la esquina cuando esa punta no está
            //  afilada —lo que da un cuarto de elipse— y casi en el eje cuando
            //  lo está, que es lo que le saca el pico.
            readonly property real mandoAltoX:
                rx * (1 - 0.92 * caida.ahora.arriba)
            readonly property real mandoAltoY:
                gy - ry * (1 - 0.06 * caida.ahora.arriba)
            readonly property real mandoBajoX:
                rx * (1 - 0.92 * caida.ahora.abajo)
            readonly property real mandoBajoY:
                gy + ry * (1 - 0.06 * caida.ahora.abajo)

            startX: trazoGota.gx - trazoGota.rx
            startY: trazoGota.gy

            PathQuad {
                x: trazoGota.gx - trazoGota.llano
                y: trazoGota.gy + trazoGota.ry
                controlX: trazoGota.gx - trazoGota.mandoBajoX
                controlY: trazoGota.mandoBajoY
            }
            PathLine {
                x: trazoGota.gx + trazoGota.llano
                y: trazoGota.gy + trazoGota.ry
            }
            PathQuad {
                x: trazoGota.gx + trazoGota.rx; y: trazoGota.gy
                controlX: trazoGota.gx + trazoGota.mandoBajoX
                controlY: trazoGota.mandoBajoY
            }
            PathQuad {
                x: trazoGota.gx + trazoGota.llano
                y: trazoGota.gy - trazoGota.ry
                controlX: trazoGota.gx + trazoGota.mandoAltoX
                controlY: trazoGota.mandoAltoY
            }
            PathLine {
                x: trazoGota.gx - trazoGota.llano
                y: trazoGota.gy - trazoGota.ry
            }
            PathQuad {
                x: trazoGota.gx - trazoGota.rx; y: trazoGota.gy
                controlX: trazoGota.gx - trazoGota.mandoAltoX
                controlY: trazoGota.mandoAltoY
            }
        }

        //  El cuello. Vive solo mientras hay algo que sujetar: se corta en pixel
        //  y medio de cintura y no en 0 porque por debajo de eso el relleno ya no
        //  cubre un pixel entero y lo que se ve es una hebra a puntitos. Cortar
        //  ahí es además lo que hace que PAREZCA que se rompe: se parte cuando
        //  todavía se ve, no cuando ya no queda nada.
        //
        //  Roto, se dibuja DEGENERADO —todo en la boca, sin área— en vez de
        //  esconderse: un ShapePath no tiene `visible`, y meterlo y sacarlo con
        //  un Loader reconstruye el trazado entero a media animación.
        ShapePath {
            id: trazoCuello
            fillColor: K4.Tema.fondo
            strokeWidth: 0
            strokeColor: "transparent"

            readonly property bool vivo: !caida.embiste
                && caida.t < caida.tCorte && caida.cinturaCuello > 1.5
            readonly property real gx: caida.ahora.x
            readonly property real boca: vivo ? caida.bocaCuello : 0
            readonly property real pie: vivo ? caida.pieCuello : 0
            readonly property real mando: vivo ? caida.mandoCuello : 0
            readonly property real abajo: vivo ? caida.ahora.y : caida.bocaY
            readonly property real medio: (caida.bocaY + abajo) / 2

            startX: trazoCuello.gx - trazoCuello.boca
            startY: caida.bocaY

            PathLine {
                x: trazoCuello.gx + trazoCuello.boca; y: caida.bocaY
            }
            PathQuad {
                x: trazoCuello.gx + trazoCuello.pie; y: trazoCuello.abajo
                controlX: trazoCuello.gx + trazoCuello.mando
                controlY: trazoCuello.medio
            }
            PathLine {
                x: trazoCuello.gx - trazoCuello.pie; y: trazoCuello.abajo
            }
            PathQuad {
                x: trazoCuello.gx - trazoCuello.boca; y: caida.bocaY
                controlX: trazoCuello.gx - trazoCuello.mando
                controlY: trazoCuello.medio
            }
        }
    }

    // ── el reparto del tiempo ───────────────────────────────────
    NumberAnimation {
        id: viaje
        target: caida
        property: "t"

        //  Lineal a propósito: las curvas están en la forma, no aquí.
        duration: caida.plugin.gotaDura
        easing.type: Easing.Linear

        onFinished: {
            //  Primero se avisa —y con eso empieza a crecer el dock, o la barra—
            //  y el charco se queda un rato MÁS, tapando ese arranque.
            const embestia = caida.embiste
            caida.plugin.viajeTerminado()

            //  Bajando basta con un parpadeo: el charco acaba con la forma y el
            //  tamaño EXACTOS de la semilla del dock, así que no hay hueco que
            //  tapar, solo un cambio de manos que confirmar. Quedándose más se
            //  pintaría negro sobre los iconos, que con 560 ms de OutCubic salen
            //  enseguida.
            //
            //  Embistiendo hay que aguantar más: la island aparece DEBAJO del
            //  charco y tarda lo suyo en alcanzarlo —440 ms de ancho y 400 de
            //  grosor, las dos curvas del host— y hasta que no lo pasa, quitar
            //  el charco es enseñar una barra a medio hacer. Volviendo a una
            //  barra que nunca se fue no hay nada que tapar, y aguantar de más
            //  es taparle el reloj.
            relevo.interval = embestia ? 260 : 140
            relevo.restart()
        }
    }

    Timer {
        id: relevo
        onTriggered: caida.sostener = false
    }

    //  Y el aviso de que el cuello se ha roto, que es lo que manda a la barra
    //  recogerse (o darse por enterada con un tirón). Un temporizador y no un
    //  `onTChanged`: es un instante del reparto, no una propiedad de la forma, y
    //  vigilarlo por fotograma es JavaScript sesenta veces por segundo para
    //  responder una vez.
    Timer {
        id: corte
        interval: Math.round(caida.plugin.gotaDura * caida.plugin.gotaCorte)
        onTriggered: caida.plugin.desprendida()
    }

    Connections {
        target: caida.plugin

        //  Solo con SU efecto puesto: los modos son los mismos para las dos
        //  escenas (ver Escena.qml).
        enabled: caida.plugin.esGota

        //  El charco sale cuando el plugin dice, no cuando cambia el modo: en la
        //  recogida espera a que el dock esté casi encima de él.
        function onGotaFueraChanged() {
            if (!caida.plugin.gotaFuera
                || caida.plugin.modo !== "recogiendo")
                return
            relevo.stop()
            caida.sostener = true
            caida.sube = true
            caida.t = 1
        }

        function onModoChanged() {
            const m = caida.plugin.modo

            if (m === "bajando") {
                //  Si se vuelve a disparar antes de que venza el relevo, la gota
                //  ya está en pantalla y no hay que quitarla.
                relevo.stop()
                caida.sostener = true
                caida.sube = false
                caida.t = 0
                viaje.to = 1
                viaje.restart()
                corte.restart()

            } else if (m === "subiendo") {
                //  La gota ya está puesta desde la recogida: aquí solo se le da
                //  salida. Y no hay corte que avisar — subiendo no se rompe
                //  ningún cuello, porque subiendo no hay cuello.
                viaje.to = 0
                viaje.restart()
            }
        }
    }
}
