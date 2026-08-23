//  El dock: la MISMA silueta de la barra, del revés.
//
//  El trazado es el de `shell.qml` —esquinas invertidas que se funden con el
//  borde y el cuerpo redondeado por dentro—, reflejado en vertical igual que
//  hace la barra cuando el usuario la pone abajo. Así el de abajo no es "otro
//  widget": es la misma pieza mirándose en el espejo.
//
//  Y esta sí RESERVA SITIO: se queda, así que las ventanas se recolocan para
//  no quedar debajo. Las gotas mientras viajan no reservan nada.

import QtQuick
import QtQuick.Shapes
import K4 as K4

K4.Ventana {
    id: muelle

    required property var plugin

    nombre: "k4-dual-muelle"

    //  El dock vive en la capa `Top`, que es la de un panel: por encima de las
    //  ventanas normales pero por debajo de lo que se pone delante de todo.
    //  Con el cajón abierto sube a `Overlay`: lo que se está enseñando entonces
    //  ocupa media pantalla y tiene que quedar por encima de lo que haya, no
    //  compitiendo con ello.
    encima: muelle.cajon

    //  Teclado solo con el cajón abierto: mientras está, ESC lo cierra. Pedirlo
    //  siempre dejaría al escritorio sin teclas por un dock que casi nunca
    //  necesita ninguna.
    conTeclado: muelle.cajon

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function (ev) {
            if (ev.key === Qt.Key_Escape) {
                //  Se deshace lo último que se hizo: primero el menú, luego lo
                //  escrito, y solo con el cajón limpio se cierra. Cerrarlo de
                //  golpe con media búsqueda escrita obliga a empezar de cero.
                if (muelle.menuDe.length > 0)
                    muelle.menuDe = ""
                else if (muelle.busqueda.length > 0)
                    muelle.busqueda = ""
                else
                    muelle.cajon = false
                ev.accepted = true
                return
            }

            if (!muelle.cajon)
                return

            if (ev.key === Qt.Key_Backspace) {
                muelle.busqueda = muelle.busqueda.slice(0, -1)
                ev.accepted = true
                return
            }

            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                const l = muelle.listaCajon
                if (l.length > 0) {
                    muelle.plugin.abrir(l[0])
                    muelle.cajon = false
                }
                ev.accepted = true
                return
            }

            //  Cualquier tecla que escriba algo. Se descartan las de control
            //  —flechas, funciones— que llegan con texto vacío o de control.
            if (ev.text.length > 0 && ev.text.charCodeAt(0) >= 0x20) {
                muelle.busqueda += ev.text
                ev.accepted = true
            }
        }
    }

    // La misma pantalla por la que se fueron las gotas.
    pantalla: muelle.plugin.pantalla

    //  LA PANTALLA ENTERA, no una franja pegada abajo.
    //
    //  Lo pide el clic de fuera: para cerrar el cajón pulsando en cualquier
    //  sitio hay que RECIBIR ese clic, y una superficie solo recibe dentro de
    //  sí misma. Se probó con un cristal aparte a pantalla completa y no vale:
    //  el teclado en exclusiva es de una sola superficie y, mientras este panel
    //  lo tiene —lo necesita para escribir y para ESC—, el cristal no recibe ni
    //  un clic; y pidiéndolo «a demanda» el foco se pierde tras la primera
    //  tecla y ESC deja de cerrar. Una sola superficie no tiene ese problema.
    //
    //  Lo que se pierde al soltar el borde de arriba es poder reservar sitio
    //  —sin un borde libre el compositor ignora la reserva—, y eso lo hace
    //  ahora una franja aparte que no pinta ni recoge nada: ver `k4-dual-hueco`
    //  en el plugin.
    //
    //  `reserva: -1` no es reservar del revés: es saltarse las reservas de los
    //  demás para llegar de verdad a los cuatro bordes.
    pegadaArriba: true

    //  La ventana NO cambia de tamaño nunca, y eso no es un detalle.
    //
    //  Animando el alto lo animaba el compositor, y al cerrarse el cajón el
    //  dock entero subía con las aplicaciones y luego bajaba todo de golpe. Es
    //  el mismo error que ya mordió con la capa de la silueta: una superficie
    //  que cambia de tamaño cada fotograma no se comporta. La ventana quieta —y
    //  ahora, además, del tamaño de la pantalla—, y lo que se anima es la
    //  geometría de dentro.
    //
    //  De paso resuelve otra cosa: los iconos crecen hacia arriba al pasar el
    //  ratón y necesitan sitio físico fuera de la franja del dock o se cortan a
    //  ras del borde por mucho que se quite el recorte. Sitio hay de sobra.

    readonly property int alto: 62
    readonly property int ala: 16
    readonly property int hueco: 58
    readonly property int margen: 16
    readonly property int base: 38

    //  Hasta dónde llega la lupa.
    //
    //  Era 92 con huecos de 58: el vecino se llevaba casi la mitad del aumento
    //  y parecía que se resaltaban de dos en dos. A 46 —menos de un hueco— el
    //  de al lado se queda en un quinto y solo crece el que apuntas.
    readonly property int alcance: 46

    //  Y con el cajón abierto no hay lupa: lo que se está mirando es la
    //  rejilla, y ver la fila de abajo dando saltos al pasar por encima
    //  distrae de lo único que importa entonces.
    readonly property bool conLupa: dentro && !cajon

    readonly property var apps: plugin.apps

    //  Un hueco de más para el botón del cajón, y el separador entre medias.
    readonly property int anchoLleno: (apps.length + 1) * hueco + margen * 2 + 13

    //  Qué icono tiene el menú abierto, "" si ninguno.
    property string menuDe: ""

    //  Qué icono tiene abierto el selector de ventanas.
    property string selectorDe: ""

    //  ── el cajón de aplicaciones ─────────────────────────────────
    //
    //  Crece del propio dock hacia arriba en vez de abrir otro módulo. Así
    //  arrastrar de la rejilla al dock es un gesto dentro de la misma
    //  superficie, que es justo lo que hace falta para poder poner apps.
    property bool cajon: false
    readonly property int altoCajon: 420

    //  El ancho del cajón se congela AL ABRIRLO.
    //
    //  Sale del ancho del dock, y el dock cambia de ancho solo —las
    //  aplicaciones abiertas entran y salen—. Sin congelarlo, la rejilla se
    //  recolocaba entera mientras la estabas mirando porque alguien cerró una
    //  ventana en otra pantalla.
    property real anchoCajonFijo: 0
    onCajonChanged: {
        if (cajon)
            anchoCajonFijo = anchoLleno
        else
            busqueda = ""
    }

    //  ── escribir para filtrar ────────────────────────────────────
    //
    //  Con el cajón abierto, cualquier tecla empieza a buscar: no hay que ir a
    //  pinchar un campo primero. La barra sale de la nada por el centro, y la
    //  rejilla se filtra debajo SIN cambiar de alto — si el cajón encogiera con
    //  cada letra, escribir sería ver el panel dando saltos.
    property string busqueda: ""

    //  Sin tildes y en minúsculas, para que «edicion» encuentre «Edición».
    function _llano(t) {
        return String(t || "").toLowerCase()
            .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    }

    //  Lo que se enseña: todo, o lo que casa ORDENADO POR LO BIEN QUE CASA.
    //  Quien empieza por lo escrito va antes que quien solo lo contiene, que es
    //  lo que hace que el primer resultado sea el que uno tenía en la cabeza —y
    //  por tanto el que abre el Intro.
    readonly property var listaCajon: {
        const q = _llano(busqueda)
        if (q.length === 0)
            return K4.Apps.lista

        const casan = []
        for (let i = 0; i < K4.Apps.lista.length; ++i) {
            const a = K4.Apps.lista[i]
            const n = _llano(a.name)
            const donde = n.indexOf(q)
            if (donde < 0)
                continue
            casan.push({ app: a, peso: donde === 0 ? 0 : 1, nombre: n })
        }
        casan.sort(function (x, y) {
            if (x.peso !== y.peso)
                return x.peso - y.peso
            return x.nombre < y.nombre ? -1 : 1
        })
        return casan.map(function (x) { return x.app })
    }

    //  Rápida pero no seca: 380 ms saliendo con `OutCubic`. Con 620 se hacía
    //  larga —un cajón que se abre no es un viaje de un borde a otro— y con 320
    //  se abría de golpe.
    property real cajonAbierto: cajon ? 1 : 0
    Behavior on cajonAbierto {
        NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
    }

    //  0 = los dos trozos recién juntados · 1 = el dock entero.
    property real despliegue: 0

    //  Arranca EXACTAMENTE del tamaño de los dos trozos juntos: mismo ancho y
    //  mismo grosor. Así el relevo entre lo que aterriza y el dock no se ve
    //  —son la misma forma— y de ahí crece a lo ancho Y a lo alto.
    readonly property int semilla: plugin.largoTrozo * 2
    readonly property real anchoAhora: semilla
        + Math.max(0, (anchoLleno - semilla) * despliegue)
    //  El alto de la FRANJA del dock —la de los iconos—, sin el cajón.
    readonly property real altoDock: K4.Tema.altoPlegado
        + Math.max(0, (alto - K4.Tema.altoPlegado) * despliegue)

    //  Y el alto total de la silueta: el cajón no es un panel aparte, es el
    //  propio dock creciendo hacia arriba. Por eso no lleva borde ni fondo
    //  propios: es la misma pieza.
    readonly property real altoAhora: altoDock
        + altoCajon * cajonAbierto

    //  La reserva SIGUE al alto, no espera al final.
    //
    //  Reservando solo al terminar, el escritorio se recolocaba de golpe cuando
    //  el dock ya llevaba rato puesto: se veía desfasado. Siguiendo al alto
    //  animado, las ventanas acompañan al crecimiento — y como arranca justo en
    //  el grosor de la barra, que es lo que se acaba de soltar arriba, el
    //  relevo entre una reserva y otra sale a cero.
    //  Se reserva SOLO la franja del dock, nunca el cajón.
    //
    //  Siguiendo al alto total, abrir el cajón le quitaba 538 px al escritorio
    //  y las ventanas salían empujadas hacia arriba en vez de quedarse debajo.
    //  El cajón se pone DELANTE: por eso sube a la capa Overlay, y por eso no
    //  reserva ni un píxel.
    reserva: -1

    //  La zona de ratón es un item LISO, no la silueta.
    //
    //  La silueta lleva el espejo (`Scale` con yScale -1) para fundirse con el
    //  borde de abajo, y la región de entrada se calcula con la geometría del
    //  item. Con la escala negativa funcionaba igual, pero es de las cosas que
    //  uno no quiere tener que volver a comprobar: este item no pinta nada, no
    //  lleva transformadas y solo marca el rectángulo bueno.
    zonaActiva: zona

    //  Con un menú o el selector desplegado, la zona se agranda a toda la
    //  ventana: es lo que permite que un clic FUERA lo cierre. Sin eso, la
    //  región de entrada es la del dock y el clic de al lado ni llegaba — el
    //  menú se quedaba puesto hasta que pulsabas otra cosa del propio dock.
    //  El arrastre, mientras dura: de qué hueco salió y sobre cuál está.
    //
    //  Va aquí y no en la ranura porque lo tienen que leer TODAS: cada una se
    //  aparta para abrir el sitio donde va a caer.
    property int arrastreDesde: -1
    property int arrastreHasta: -1

    function soltarArrastre() {
        arrastreDesde = -1
        arrastreHasta = -1
        fantasma.fuente = null
    }

    readonly property bool hayDesplegable:
        menuDe.length > 0 || selectorDe.length > 0 || cajon

    Item {
        id: zona
        width: muelle.hayDesplegable ? muelle.width
            : Math.max(muelle.anchoAhora, muelle.cajon ? muelle.anchoLleno : 0)
        //  `altoAhora` ya lleva dentro lo que crece el cajón; sumarlo otra vez
        //  era pedir región de entrada de más.
        height: muelle.hayDesplegable ? muelle.height : muelle.altoAhora
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        visible: muelle.mostrando
    }

    //  El cazaclics. Va declarado ANTES que el resto a propósito: así queda
    //  debajo de todo y los iconos, el menú y el selector se llevan sus clics
    //  primero. Solo recoge lo que no coge nadie, que es «has pulsado fuera».
    MouseArea {
        anchors.fill: parent
        enabled: muelle.hayDesplegable
        visible: enabled
        onClicked: {
            muelle.menuDe = ""
            muelle.selectorDe = ""
            muelle.cajon = false
        }
    }

    //  La ventana NO se va nunca; lo que se apaga es su contenido.
    //
    //  Hyprland desvanece las capas al aparecer (`layersIn` hereda de `global`,
    //  que está activo), así que cada vez que esta ventana se creaba de nuevo
    //  el dock entraba TRANSLÚCIDO durante unos fotogramas — se veía el fondo
    //  a través del negro justo al empezar a crecer. Con la superficie siempre
    //  puesta no hay entrada que animar: aparece la forma, ya opaca.
    //
    //  Pero solo mientras hay modo dual. Con la barra arriba y el dock sin
    //  usar no hay razón para tener una superficie a pantalla completa puesta
    //  todo el día: se crea al empezar a bajar, dos segundos antes de que se
    //  pinte nada, así que la entrada que desvanece el compositor le pilla
    //  transparente y vacía.
    //
    //  No molesta estando: sin forma visible no reserva sitio ni recoge un
    //  solo clic, porque la zona activa ES la forma.
    visible: muelle.plugin.fuera || muelle.despliegue > 0.02
    readonly property bool mostrando: plugin.modo === "dock"
        || plugin.modo === "recogiendo" || despliegue > 0.02

    Shape {
        id: silueta

        visible: muelle.mostrando

        //  Las esquinas invertidas piden MSAA o salen con dientes.
        antialiasing: true
        layer.enabled: true
        layer.samples: 8
        layer.smooth: true

        //  TAMAÑO FIJO, el del dock entero. Lo que crece es el trazado de
        //  dentro, no este item.
        //
        //  Antes crecía el item, y con una capa MSAA encima eso significa
        //  reconstruir la textura en cada fotograma de los 760 ms del estirón:
        //  se veía el dock TRANSLÚCIDO mientras crecía, con el fondo de
        //  pantalla asomando a través del negro. Con el item quieto la textura
        //  se crea una vez y lo que se anima es geometría.
        width: muelle.anchoLleno
        height: muelle.alto + muelle.altoCajon
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        //  El espejo: la barra de arriba hace exactamente esto cuando el
        //  usuario la manda abajo.
        transform: Scale {
            origin.y: silueta.height / 2
            yScale: -1
        }

        ShapePath {
            id: trazo
            fillColor: K4.Tema.fondo
            strokeWidth: 0
            strokeColor: "transparent"

            readonly property real w: muelle.anchoAhora
            readonly property real h: muelle.altoAhora
            readonly property real r: Math.min(32, trazo.h / 2)
            readonly property real g: Math.min(muelle.ala, trazo.h / 2)

            //  Centrado dentro del item, que es más ancho. En vertical no hace
            //  falta: con el espejo, el y=0 del trazado ya cae en el borde de
            //  abajo de la pantalla, que es donde tiene que fundirse.
            readonly property real x0: (silueta.width - trazo.w) / 2

            startX: trazo.x0
            startY: 0

            PathArc {
                x: trazo.x0 + trazo.g; y: trazo.g
                radiusX: trazo.g; radiusY: trazo.g
                direction: PathArc.Clockwise
            }
            PathLine { x: trazo.x0 + trazo.g; y: trazo.h - trazo.r }
            PathArc {
                x: trazo.x0 + trazo.g + trazo.r; y: trazo.h
                radiusX: trazo.r; radiusY: trazo.r
                direction: PathArc.Counterclockwise
            }
            PathLine { x: trazo.x0 + trazo.w - trazo.g - trazo.r; y: trazo.h }
            PathArc {
                x: trazo.x0 + trazo.w - trazo.g; y: trazo.h - trazo.r
                radiusX: trazo.r; radiusY: trazo.r
                direction: PathArc.Counterclockwise
            }
            PathLine { x: trazo.x0 + trazo.w - trazo.g; y: trazo.g }
            PathArc {
                x: trazo.x0 + trazo.w; y: 0
                radiusX: trazo.g; radiusY: trazo.g
                direction: PathArc.Clockwise
            }
            PathLine { x: trazo.x0; y: 0 }
        }
    }

    //  Los iconos van FUERA del Shape: dentro heredarían el espejo y saldrían
    //  del revés.
    //  Este contenedor ocupa LA VENTANA ENTERA, no solo la franja del dock.
    //
    //  En Qt Quick, un hijo que se sale de los límites de su padre se DIBUJA
    //  —si no hay recorte— pero NO recibe ratón. El selector de ventanas y el
    //  menú del botón derecho cuelgan por encima de la fila de iconos, así que
    //  con el contenedor a la altura del dock se veían perfectamente y no se
    //  podían pulsar: el clic no llegaba a nadie.
    //
    //  La fila sigue pegada abajo; lo único que cambia es hasta dónde llegan
    //  los límites que reparten los clics.
    Item {
        id: capa
        anchors.fill: parent
        //  Sin recorte: un icono crecido tiene que poder asomar por encima
        //  del dock. Recortando, lo que sobraba se cortaba a ras del borde y
        //  quedaba raro — se veía media aplicación asomando por debajo.
        clip: false

        //  Los iconos entran tarde y se van PRONTO.
        //
        //  Con el desvanecido repartido por medio despliegue, al recogerse
        //  quedaban de fantasma casi 350 ms: medios iconos flotando mientras la
        //  forma de debajo ya se había encogido. Eso es lo que se veía como
        //  transparencias. Concentrándolo en el último 18 % desaparecen antes
        //  de que la forma se mueva de sitio, y lo que se recoge es masa
        //  limpia.
        opacity: Math.max(0, (muelle.despliegue - 0.82) / 0.18)

        Row {
            id: fila
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            height: muelle.altoDock
            spacing: 0

            Repeater {
                model: muelle.apps

                delegate: Item {
                    id: ranura
                    required property var modelData
                    required property int index

                    width: muelle.hueco
                    height: muelle.altoDock

                    //  Escondido mientras se arrastra, no atenuado: si se
                    //  quedara puesto, el hueco de al lado se le echaría encima
                    //  al apartarse y se verían dos iconos pisándose. La opacidad
                    //  no quita el ratón, así que este sigue llevando el arrastre.
                    opacity: raton.arrastrando ? 0 : 1

                    readonly property real centro:
                        x + width / 2 + parent.x
                    property real cerca: muelle.conLupa
                        ? Math.exp(-Math.pow((muelle.ratonX - centro)
                                             / muelle.alcance, 2))
                        : 0

                    Behavior on cerca {
                        NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                    }

                    //  Cuánto se aparta este hueco mientras se arrastra uno.
                    //
                    //  El que va en el dedo se corre hasta donde va a caer —y
                    //  ahí se queda atenuado, marcando el sitio—; los que hay
                    //  entre medias se apartan uno, que es lo que abre el
                    //  hueco. Nadie cambia de posición en la fila: es un
                    //  desplazamiento del dibujo, así que el modelo no se
                    //  toca y esta misma ranura sigue viva hasta que sueltes.
                    readonly property int corrimiento: {
                        const d = muelle.arrastreDesde
                        const h = muelle.arrastreHasta
                        //  El que va en el dedo NO se mueve de sitio: se
                        //  esconde, y lo que ves de él es el icono pegado al
                        //  puntero. Moverlo era peor de lo que parece —el
                        //  desplazamiento es un transform, y un transform
                        //  también corre las coordenadas que reparte su propio
                        //  ratón—: la posición del dedo salía movida por el
                        //  desplazamiento que ella misma había provocado, y el
                        //  icono caía una posición corta.
                        if (d < 0 || h < 0 || d === h || index === d)
                            return 0
                        if (d < h && index > d && index <= h)
                            return -muelle.hueco
                        if (d > h && index < d && index >= h)
                            return muelle.hueco
                        return 0
                    }

                    transform: Translate {
                        x: ranura.corrimiento
                        Behavior on x {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    //  ¿Está fijada o solo abierta? Lo segundo se va del dock
                    //  al cerrar la aplicación.
                    readonly property int cuantas:
                        muelle.plugin.ventanasDe(
                            muelle.plugin.idDe(modelData)).length
                    readonly property bool abierta: cuantas > 0

                    //  La divisoria entre las fijadas y las abiertas, en el
                    //  canto de la primera abierta: el mismo hilo tenue que la
                    //  del botón del cajón, para que se lea como el mismo
                    //  idioma y no como otro invento.
                    Rectangle {
                        visible: muelle.plugin.fijadas > 0
                            && ranura.index === muelle.plugin.fijadas
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: muelle.base * 0.7
                        color: K4.Tema.carril
                        opacity: 0.6
                    }

                    //  La insignia con cuántas ventanas hay, solo si hay
                    //  más de una: con una sola el número no dice nada y el
                    //  puntito de abajo ya lo cuenta.
                    Rectangle {
                        id: insignia
                        //  Por encima del icono: va declarada antes que él —para
                        //  tenerla junto al resto de adornos de la ranura— y sin
                        //  esto el icono se la comía.
                        z: 5
                        visible: ranura.cuantas > 1
                        //  Colgada del ICONO, no de la ranura: sube y crece
                        //  con él. Clavada al techo del hueco se quedaba
                        //  quieta mientras el icono se levantaba al pasar el
                        //  ratón, y el número acababa flotando lejos de su
                        //  aplicación.
                        anchors.right: icono.right
                        anchors.rightMargin: -4
                        anchors.top: icono.top
                        anchors.topMargin: -4
                        width: 17
                        height: 17
                        radius: 9
                        color: K4.Tema.azul
                        //  Entra creciendo desde nada: aparece al abrir la
                        //  segunda ventana, y un salto seco ahí se nota.
                        scale: ranura.cuantas > 1 ? 1 : 0
                        Behavior on scale {
                            NumberAnimation {
                                duration: 260
                                easing.type: Easing.OutBack
                                easing.overshoot: 2.2
                            }
                        }

                        K4.Etiqueta {
                            anchors.centerIn: parent
                            text: ranura.cuantas
                            color: "#ffffff"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    //  El puntito de «esto está abierto», como en macOS.
                    Rectangle {
                        visible: ranura.abierta
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        width: 4
                        height: 4
                        radius: 2
                        color: K4.Tema.tinta
                        opacity: 0.75
                    }

                    //  ── el rebote ────────────────────────────────────
                    //
                    //  Bota mientras el plugin diga que esta aplicación está
                    //  arrancando. Sube deprisa y cae frenando —`OutQuad`
                    //  subiendo, `InQuad` bajando— porque al revés parece un
                    //  muelle y no algo con peso; y cada bote llega un poco
                    //  menos alto, como un balón que pierde fuerza.
                    property real salto: 0

                    readonly property bool botando: muelle.plugin.botando.length > 0
                        && muelle.plugin.botando
                           === String(modelData.id || modelData.name || "")

                    SequentialAnimation {
                        running: ranura.botando
                        loops: Animation.Infinite
                        onStopped: ranura.salto = 0

                        NumberAnimation {
                            target: ranura; property: "salto"; to: 26
                            duration: 260; easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: ranura; property: "salto"; to: 0
                            duration: 240; easing.type: Easing.InQuad
                        }
                        NumberAnimation {
                            target: ranura; property: "salto"; to: 11
                            duration: 190; easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: ranura; property: "salto"; to: 0
                            duration: 170; easing.type: Easing.InQuad
                        }
                        PauseAnimation { duration: 260 }
                    }

                    K4.Icono {
                        id: icono

                        //  Crece de TAMAÑO, no con `scale`.
                        //
                        //  Escalando, lo que se agranda es una imagen ya
                        //  rasterizada a 38 px: se ve pixelada y con los bordes
                        //  sucios. Cambiando el tamaño, el icono se vuelve a
                        //  pedir al tema a la resolución que toca y sale limpio
                        //  a cualquier aumento.
                        width: muelle.base * (1 + 0.62 * ranura.cerca)
                        height: width

                        anchors.horizontalCenter: parent.horizontalCenter
                        //  Anclado abajo: al crecer se levanta del suelo del
                        //  dock en vez de crecer hacia los dos lados.
                        anchors.bottom: parent.bottom
                        //  El margen lleva el aumento del ratón MÁS el salto
                        //  del rebote: los dos levantan el icono del suelo del
                        //  dock, así que se suman en el mismo sitio en vez de
                        //  pelearse por la posición.
                        anchors.bottomMargin: 8 + 10 * ranura.cerca + ranura.salto
                        source: ranura.modelData && ranura.modelData.icon
                            && String(ranura.modelData.icon).length > 0
                            ? K4.Apps.icono(ranura.modelData.icon, true) : ""
                        //  El hueco de origen se atenúa mientras el icono va
                        //  con el ratón: así se ve dónde va a caer.
                        opacity: raton.arrastrando ? 0.3 : 1
                    }

                    K4.Etiqueta {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: icono.top
                        anchors.bottomMargin: 10 + 12 * ranura.cerca
                        text: ranura.modelData ? (ranura.modelData.name || "") : ""
                        color: K4.Tema.tinta
                        font.pixelSize: 11
                        opacity: ranura.cerca > 0.82 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    //  ── pulsar, arrastrar y menú ──────────────────
                    //
                    //  Arrastrando en horizontal se reordena EN VIVO: la lista
                    //  se toca mientras el dedo está abajo, así que se ve dónde
                    //  va a caer en vez de adivinarlo. Y sacándolo del dock
                    //  —más de medio dock hacia arriba o hacia abajo— se quita,
                    //  como en macOS.
                    MouseArea {
                        id: raton
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        property bool arrastrando: false
                        property real pulsadoX: 0
                        property real pulsadoY: 0

                        //  Qué tenía ESTE icono abierto justo antes de pulsar.
                        //
                        //  Al pulsar se cierra todo —hace falta, porque pulsar
                        //  un icono con el menú de otro puesto tiene que
                        //  quitarlo—, y sin recordarlo el segundo clic sobre el
                        //  mismo icono cerraba y volvía a abrir en el mismo
                        //  gesto: parecía que no hacía nada. Guardándolo, el
                        //  clic de vuelta es lo que se espera de él y cierra.
                        property bool teniaSelector: false
                        property bool teniaMenu: false

                        onPressed: function (ev) {
                            pulsadoX = ev.x
                            pulsadoY = ev.y
                            arrastrando = false
                            const id = muelle.plugin.idDe(ranura.modelData)
                            teniaSelector = muelle.selectorDe === id
                            teniaMenu = muelle.menuDe === id
                            muelle.menuDe = ""
                            muelle.selectorDe = ""
                        }

                        onPositionChanged: function (ev) {
                            if (!pressed || ev.buttons !== Qt.LeftButton)
                                return
                            //  Un umbral para no reordenar por un temblor al
                            //  pulsar: hasta 6 px sigue siendo un clic.
                            if (!arrastrando
                                    && Math.abs(ev.x - pulsadoX) < 6
                                    && Math.abs(ev.y - pulsadoY) < 6)
                                return
                            arrastrando = true

                            //  El icono viaja pegado al ratón. Sin eso no se
                            //  sabe qué se está moviendo ni dónde va a caer:
                            //  la fila se reordena bajo el dedo y el que
                            //  arrastras es indistinguible del resto.
                            //  Las dos cuentas se hacen A MANO, sin
                            //  `mapToItem`.
                            //
                            //  El hueco lleva encima el desplazamiento del
                            //  arrastre, y `mapToItem` lo tiene en cuenta: la
                            //  posición del puntero salía corrida por el propio
                            //  corrimiento y se realimentaba con su resultado,
                            //  así que el icono acababa una posición por detrás
                            //  de donde lo soltabas. `ranura.x` es la de la
                            //  fila y esa no se mueve.
                            const px = fila.x + ranura.x + ev.x
                            const py = capa.height - muelle.altoDock + ev.y
                            fantasma.x = px - fantasma.width / 2
                            fantasma.y = py - fantasma.height / 2
                            fantasma.fuente = ranura.modelData

                            //  El orden de verdad NO se toca hasta soltar.
                            //
                            //  Reordenando en vivo cambiaba el modelo, el
                            //  Repeater rehacía los huecos y con ellos moría
                            //  este mismo ratón a media pulsación: no llegaba
                            //  el `onReleased`, el icono pegado al puntero se
                            //  quedaba ahí para siempre y el arrastre no pasaba
                            //  de un sitio. Lo que se mueve mientras tanto es
                            //  el DIBUJO —cada hueco se aparta—, que es lo que
                            //  hay que ver, y el orden se aplica de una vez al
                            //  levantar el dedo.
                            muelle.arrastreDesde = ranura.index
                            muelle.arrastreHasta = Math.max(0, Math.min(
                                muelle.apps.length - 1,
                                Math.floor((ranura.x + ev.x) / muelle.hueco)))
                        }

                        onReleased: function (ev) {
                            const hasta = muelle.arrastreHasta
                            muelle.soltarArrastre()
                            if (!arrastrando)
                                return
                            arrastrando = false
                            //  ¿Se ha sacado del dock? Se mide EN EL HUECO, no
                            //  en la ventana.
                            //
                            //  En coordenadas de la ventana la cuenta dependía
                            //  de lo alta que fuese: con la ventana pegada
                            //  abajo, el hueco caía sobre los 476-538 px y
                            //  `p.y > 93` se cumplía siempre —cualquier
                            //  arrastre, aunque no salieras del dock, quitaba
                            //  la aplicación—. Aquí `ev.y` va de 0 al alto del
                            //  hueco, así que negativo es por arriba y pasado
                            //  el alto es por abajo, midan lo que midan la
                            //  ventana o la pantalla.
                            const fuera = ev.y < -muelle.alto * 0.5
                                || ev.y > muelle.alto * 1.5
                            if (fuera) {
                                muelle.plugin.quitarDelDock(
                                    muelle.plugin.idDe(ranura.modelData))
                                return
                            }
                            if (hasta >= 0 && hasta !== ranura.index)
                                muelle.plugin.moverEnDock(ranura.index, hasta)
                            else
                                muelle.plugin.guardarDock()
                        }

                        //  Red de seguridad: si el modelo cambia por otra cosa
                        //  —una aplicación que se abre o se cierra— este hueco
                        //  se rehace con el dedo abajo y no habrá `onReleased`.
                        //  Sin esto, el icono pegado al puntero se queda.
                        Component.onDestruction: if (arrastrando)
                            muelle.soltarArrastre()

                        onClicked: function (ev) {
                            if (arrastrando)
                                return
                            const id = muelle.plugin.idDe(ranura.modelData)
                            if (ev.button === Qt.RightButton) {
                                if (!teniaMenu)
                                    muelle.menuDe = id
                                return
                            }

                            //  Volver a pulsar el icono con su visor puesto lo
                            //  cierra, sin lanzar ni cambiar de ventana.
                            if (teniaSelector)
                                return

                            //  Si ya está abierta, se VA a ella; solo se lanza
                            //  otra cuando no hay ninguna. Y con varias, se
                            //  pregunta cuál: abrir la primera a ciegas acierta
                            //  la mitad de las veces.
                            const vs = muelle.plugin.ventanasDe(id)
                            if (vs.length === 0)
                                muelle.plugin.abrir(ranura.modelData)
                            else if (vs.length === 1)
                                muelle.plugin.enfocar(vs[0].direccion)
                            else
                                muelle.selectorDe = id
                        }
                    }

                    //  ── el selector de ventanas ──────────────────────
                    //
                    //  Sale del propio icono creciendo hacia arriba: nace de
                    //  donde has pulsado, que es lo que le dice al ojo de quién
                    //  son estas ventanas.
                    Item {
                        id: selector
                        readonly property bool puesto:
                            muelle.selectorDe.length > 0
                            && muelle.selectorDe
                               === muelle.plugin.idDe(ranura.modelData)

                        property real abierto: puesto ? 1 : 0
                        Behavior on abierto {
                            NumberAnimation {
                                duration: 240
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.1
                            }
                        }

                        visible: abierto > 0.01
                        //  Tantas tarjetas como ventanas, en horizontal.
                        width: cajaSel.width
                        height: cajaSel.height

                        //  Colgado de LA CAPA, no de la ranura, aunque se
                        //  declare aquí dentro.
                        //
                        //  Qt reparte los clics por el padre de verdad, no por
                        //  dónde está escrito: un hijo que se sale de su padre
                        //  se dibuja —si no hay recorte— pero no recibe ratón.
                        //  Colgando de una ranura de 58 px, este panel se veía
                        //  entero y no se podía pulsar ni una tarjeta. Se sigue
                        //  situando sobre su icono, con la cuenta de abajo.
                        parent: capa
                        z: 10
                        x: fila.x + ranura.x + ranura.width / 2 - width / 2
                        y: capa.height - muelle.altoDock - height - 8

                        readonly property var lista: muelle.plugin.ventanasDe(
                            muelle.plugin.idDe(ranura.modelData))

                        Rectangle {
                            id: cajaSel
                            //  El ancho lo mandan las tarjetas: en horizontal,
                            //  una lista de dos no tiene por qué medir lo mismo
                            //  que una de cinco.
                            width: Math.min(muelle.anchoLleno,
                                selector.lista.length * 216 + 20)
                            height: 166
                            radius: 16
                            //  El negro de la island, no el gris de superficie:
                            //  esto cuelga del dock y tiene que ser la misma
                            //  materia, no un cuadro claro pegado encima.
                            color: K4.Tema.fondo

                            //  Crece desde el borde de ABAJO —el que toca el
                            //  icono— para que se lea como que sale de él.
                            transform: Scale {
                                origin.x: cajaSel.width / 2
                                origin.y: cajaSel.height
                                xScale: 0.55 + 0.45 * selector.abierto
                                yScale: selector.abierto
                            }
                            opacity: selector.abierto

                            //  El pico que apunta al icono del que sale. Es un
                            //  cuadrado girado 45° con la mitad asomando por
                            //  debajo: más simple que un trazado y se suaviza
                            //  igual de bien.
                            Rectangle {
                                width: 14
                                height: 14
                                rotation: 45
                                color: cajaSel.color
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom
                                anchors.topMargin: -7
                                antialiasing: true
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Repeater {
                                    model: selector.lista

                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 208
                                        height: 146
                                        radius: 12
                                        clip: true

                                        //  El fondo SOLO de la señalada.
                                        //
                                        //  Antes las tarjetas llevaban un velo
                                        //  de base y otro más fuerte al pasar
                                        //  por encima: con las dos aclaradas,
                                        //  la diferencia entre una y otra era
                                        //  mínima y parecía que el ratón estaba
                                        //  sobre las dos. Sin base, lo que se
                                        //  aclara es lo que apuntas y nada más.
                                        color: sobreSel.containsMouse
                                            ? Qt.rgba(1, 1, 1, 0.16)
                                            : "transparent"
                                        Behavior on color {
                                            ColorAnimation { duration: 110 }
                                        }

                                        //  La ventana, ocupando la tarjeta
                                        //  entera: es lo que se viene a mirar.
                                        K4.Miniatura {
                                            id: mini
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            direccion: modelData.direccion
                                        }

                                        //  El icono de reserva, debajo: hasta
                                        //  que la captura tiene su primer
                                        //  fotograma —o si la ventana está en
                                        //  otro escritorio y no la hay— algo
                                        //  tiene que haber ahí.
                                        K4.Icono {
                                            visible: !mini.hasContent
                                            width: 44
                                            height: 44
                                            anchors.centerIn: parent
                                            source: ranura.modelData
                                                && ranura.modelData.icon
                                                && String(ranura.modelData.icon).length > 0
                                                ? K4.Apps.icono(
                                                    ranura.modelData.icon, true) : ""
                                        }

                                        //  El título ENCIMA de la miniatura, en
                                        //  una banda oscura: puesto debajo
                                        //  robaba a la ventana la mitad de la
                                        //  tarjeta, y es la ventana lo que hay
                                        //  que ver. La banda es lo que lo hace
                                        //  legible sobre lo que sea que haya
                                        //  detrás.
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 6
                                            height: 26
                                            color: Qt.rgba(0, 0, 0, 0.68)

                                            K4.Etiqueta {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                text: modelData.titulo
                                                color: K4.Tema.tinta
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }

                                        MouseArea {
                                            id: sobreSel
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                muelle.selectorDe = ""
                                                muelle.plugin.enfocar(
                                                    modelData.direccion)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    //  El menú del botón derecho. Va aquí, colgado del icono,
                    //  para que salga justo encima del que has pulsado.
                    Rectangle {
                        id: menuCaja
                        visible: muelle.menuDe.length > 0
                            && muelle.menuDe === muelle.plugin.idDe(ranura.modelData)
                        //  Colgado de la capa por lo mismo que el selector:
                        //  fuera de la ranura no llegan los clics.
                        parent: capa
                        z: 10
                        width: 190
                        height: filas.implicitHeight + 12
                        x: fila.x + ranura.x + ranura.width / 2 - width / 2
                        y: capa.height - muelle.altoDock - height - 6
                        radius: 14
                        //  Sin borde y con el negro de la island: en esta barra
                        //  nada lleva marco, y lo que cuelga del dock es la
                        //  misma materia que él, no un cuadro más claro encima.
                        color: K4.Tema.fondo

                        //  Y crece desde el borde de abajo, el que toca el
                        //  icono, igual que el selector de ventanas.
                        property real menuAbierto: visible ? 1 : 0
                        Behavior on menuAbierto {
                            NumberAnimation {
                                duration: 240
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.1
                            }
                        }
                        opacity: menuAbierto
                        transform: Scale {
                            origin.x: menuCaja.width / 2
                            origin.y: menuCaja.height
                            xScale: 0.55 + 0.45 * menuCaja.menuAbierto
                            yScale: menuCaja.menuAbierto
                        }

                        //  Su pico, apuntando al icono, igual que el selector.
                        Rectangle {
                            width: 14
                            height: 14
                            rotation: 45
                            color: menuCaja.color
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: -7
                            antialiasing: true
                        }

                        Column {
                            id: filas
                            anchors.centerIn: parent
                            width: parent.width - 12

                            Repeater {
                                //  La segunda opción cambia con lo que sea: a
                                //  una que solo está abierta no se le puede
                                //  «quitar del dock» —no está puesta—, lo que
                                //  se le hace es fijarla.
                                model: [
                                    { texto: K4.Idioma.t("Abrir"), quitar: false },
                                    {
                                        texto: muelle.plugin.estaFijada(
                                            muelle.plugin.idDe(ranura.modelData))
                                            ? K4.Idioma.t("Quitar del dock")
                                            : K4.Idioma.t("Mantener en el dock"),
                                        quitar: true
                                    }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    width: filas.width
                                    height: 32
                                    radius: 8
                                    //  Velo blanco: ver el porqué en las
                                    //  celdas del cajón.
                                    color: sobre.containsMouse
                                        ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                                    Behavior on color {
                                        ColorAnimation { duration: 110 }
                                    }

                                    K4.Etiqueta {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        text: modelData.texto
                                        color: modelData.quitar
                                            ? K4.Tema.rojo : K4.Tema.tinta
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        id: sobre
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const id = muelle.plugin.idDe(
                                                ranura.modelData)
                                            muelle.menuDe = ""
                                            if (modelData.quitar) {
                                                if (muelle.plugin.estaFijada(id))
                                                    muelle.plugin.quitarDelDock(id)
                                                else
                                                    muelle.plugin.ponerEnDock(id,
                                                        muelle.plugin.fijadas)
                                            } else
                                                muelle.plugin.abrir(
                                                    ranura.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            //  El separador, en su propio hueco estrecho: teniéndolo dentro
            //  del botón, el glifo quedaba descentrado en su posición porque
            //  compartía sitio con la raya.
            Item {
                width: 13
                height: muelle.altoDock

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: muelle.base * 0.7
                    color: K4.Tema.carril
                    opacity: 0.6
                }
            }

            //  El cajón de aplicaciones: no es una aplicación más, es la
            //  puerta a todas.
            Item {
                width: muelle.hueco
                height: muelle.altoDock

                //  El glifo, en una CAJA del tamaño de un icono.
                //
                //  Puesto a pelo con su `pixelSize`, un glifo no ocupa lo que
                //  mide la letra: la caja de texto lleva su propio aire arriba
                //  y abajo, así que salía más pequeño que los iconos y apoyado
                //  más abajo. Dándole la misma caja que ellos y centrándolo
                //  dentro, se alinea solo.
                K4.Glifo {
                    id: glifoCajon
                    width: muelle.base * (1 + 0.62 * cajonRaton.cerca)
                    height: width
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8 + 10 * cajonRaton.cerca
                    verticalAlignment: Text.AlignVCenter
                    //  md-apps, de la Nerd Font. `tools/glifos.py` lo encuentra
                    //  por nombre; de memoria salen mal.
                    text: String.fromCodePoint(0xF003B)
                    font.pixelSize: glifoCajon.height * 0.88
                    color: K4.Tema.tinta
                }

                K4.Etiqueta {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: glifoCajon.top
                    anchors.bottomMargin: 10
                    text: K4.Idioma.t("Aplicaciones")
                    color: K4.Tema.tinta
                    font.pixelSize: 11
                    opacity: (!muelle.cajon && cajonRaton.cerca > 0.82) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: cajonRaton
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: muelle.cajon = !muelle.cajon

                    readonly property real centro:
                        parent.x + parent.width / 2 + parent.parent.x
                    property real cerca: muelle.conLupa
                        ? Math.exp(-Math.pow((muelle.ratonX - centro)
                                             / muelle.alcance, 2))
                        : 0
                    Behavior on cerca {
                        NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                    }
                }
            }

        }
    }

    //  ── el panel del cajón ───────────────────────────────────────
    //
    //  Todas las aplicaciones del escritorio, no los módulos de la barra: el
    //  dock es para lo que abres a diario. De aquí se arrastra al dock para
    //  ponerlas, que es el gesto que todo el mundo prueba primero.
    Rectangle {
        id: panelCajon
        visible: muelle.cajonAbierto > 0.01
        opacity: muelle.cajonAbierto

        width: Math.max(320, muelle.anchoCajonFijo - 24)

        //  El alto ACOMPAÑA a la apertura, no es fijo.
        //
        //  Con alto fijo y anclado abajo, al cerrarse la ventana encogía y su
        //  borde de arriba iba comiéndose las filas: parecía que las
        //  aplicaciones se escapaban hacia arriba y luego se cerraba. Encogiendo
        //  con ella, el cajón se mete en el dock —que es de donde había salido—
        //  y la rejilla baja con él.
        height: muelle.altoCajon * muelle.cajonAbierto
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: muelle.altoDock

        //  Sin fondo ni borde: lo pinta la silueta del dock, del que esto es
        //  la parte de arriba. Con caja propia se veía como un panel flotando
        //  encima y con un marco gris que no es de la casa.
        color: "transparent"

        //  La divisoria entre la rejilla y la fila del dock: la misma idea que
        //  la vertical de antes del botón —un hilo tenue del color del carril—
        //  pero tumbada, y sin llegar a los bordes para que se lea como una
        //  separación y no como un marco.
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.82
            height: 1
            color: K4.Tema.carril
            opacity: 0.55
        }

        K4.Etiqueta {
            id: tituloCajon
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            text: K4.Idioma.t("Arrastra al dock la que quieras tener a mano")
            color: K4.Tema.apagado
            font.pixelSize: 11
            //  Se calla en cuanto se escribe: su sitio lo ocupa la búsqueda.
            opacity: muelle.busqueda.length > 0 ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }

        //  La barra de búsqueda: sale de la nada abriéndose por el centro, que
        //  es de donde nace todo en esta barra.
        Rectangle {
            id: buscador
            visible: escala > 0.01
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter

            property real escala: muelle.busqueda.length > 0 ? 1 : 0
            Behavior on escala {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            width: Math.min(parent.width - 40, 420)
            height: 30
            radius: height / 2
            color: K4.Tema.superficie

            transform: Scale {
                origin.x: buscador.width / 2
                origin.y: buscador.height / 2
                xScale: buscador.escala
                yScale: 0.4 + 0.6 * buscador.escala
            }

            K4.Etiqueta {
                anchors.centerIn: parent
                width: parent.width - 28
                text: muelle.busqueda
                color: K4.Tema.tinta
                font.pixelSize: 12
                elide: Text.ElideLeft
                horizontalAlignment: Text.AlignHCenter
                opacity: buscador.escala
            }
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 12
            anchors.topMargin: 38
            //  Un respiro sobre la fila del dock, que va justo debajo.
            anchors.bottomMargin: 14
            contentHeight: rejilla.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            //  La rejilla se reparte el ancho que tenga el cajón, que es el
            //  del dock en el momento de abrirlo.
            //
            //  Con la celda de ancho fijo, lo que sobraba al final de cada fila
            //  se quedaba en un margen mudo a la derecha: la rejilla no tenía
            //  nada que ver con el dock del que sale, y cambiaba de aspecto
            //  según cuántas aplicaciones tuvieras puestas. Ahora se cuentan
            //  las columnas que caben y se reparte el resto entre ellas, así
            //  que la última columna termina donde termina el dock.
            Flow {
                id: rejilla
                width: parent.width
                spacing: 4

                readonly property int minimo: 84
                readonly property int columnas: Math.max(1, Math.floor(
                    (width + spacing) / (minimo + spacing)))
                readonly property int anchoCelda: Math.floor(
                    (width - spacing * (columnas - 1)) / columnas)

                Repeater {
                    model: muelle.listaCajon

                    delegate: Item {
                        id: celda
                        required property var modelData
                        width: rejilla.anchoCelda
                        height: 80

                        //  El resalte de la celda bajo el ratón: muy tenue, lo
                        //  justo para saber cuál se está apuntando en una
                        //  rejilla de cincuenta iconos iguales.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 10
                            //  Un VELO BLANCO, no un color del tema.
                            //
                            //  `superficie` y `superficieAlta` se tiñen con el
                            //  ambiente de la barra, y sobre el negro de la
                            //  island la diferencia entre uno y otro es de dos
                            //  o tres niveles de gris: no se veía. Un blanco al
                            //  10 % aclara siempre, tiña lo que tiña el tema.
                            color: Qt.rgba(1, 1, 1, 0.10)
                            opacity: tirar.containsMouse ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: 110 }
                            }
                        }

                        K4.Icono {
                            id: icoCelda
                            width: 38
                            height: 38
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            source: celda.modelData && celda.modelData.icon
                                && String(celda.modelData.icon).length > 0
                                ? K4.Apps.icono(celda.modelData.icon, true) : ""
                            opacity: tirar.arrastrando ? 0.35 : 1
                        }

                        K4.Etiqueta {
                            anchors.top: icoCelda.bottom
                            anchors.topMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 6
                            text: celda.modelData ? (celda.modelData.name || "") : ""
                            color: K4.Tema.apagado
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        MouseArea {
                            id: tirar
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            property bool arrastrando: false
                            property real desdeY: 0

                            onPressed: function (ev) {
                                desdeY = ev.y
                                arrastrando = false
                            }

                            onPositionChanged: function (ev) {
                                if (!pressed)
                                    return
                                //  Solo cuenta como arrastre si baja: el cajón
                                //  está encima del dock, así que ponerla es
                                //  literalmente tirar de ella hacia abajo.
                                if (ev.y - desdeY > 10)
                                    arrastrando = true
                                const p = mapToItem(muelle.contentItem, ev.x, ev.y)
                                fantasma.x = p.x - fantasma.width / 2
                                fantasma.y = p.y - fantasma.height / 2
                                fantasma.fuente = arrastrando
                                    ? celda.modelData : null
                            }

                            onReleased: function (ev) {
                                fantasma.fuente = null
                                const suelta = arrastrando
                                arrastrando = false
                                if (!suelta) {
                                    //  Sin arrastrar, un clic la abre y ya.
                                    muelle.plugin.abrir(celda.modelData)
                                    muelle.cajon = false
                                    return
                                }
                                const p = mapToItem(muelle.contentItem, ev.x, ev.y)
                                //  ¿Ha caído sobre el dock?
                                if (p.y < muelle.height - muelle.alto - 4)
                                    return
                                muelle.plugin.ponerEnDock(
                                    muelle.plugin.idDe(celda.modelData),
                                    Math.floor((p.x - (muelle.width
                                        - muelle.anchoLleno) / 2 - muelle.margen)
                                        / muelle.hueco))
                            }
                        }
                    }
                }
            }
        }
    }

    //  Lo que se ve viajando con el dedo mientras se arrastra.
    K4.Icono {
        id: fantasma
        property var fuente: null
        visible: fuente !== null
        width: 48
        height: 48
        //  Por encima de todo lo del dock, que es lo que se está moviendo.
        z: 10
        opacity: 0.92
        source: fuente && fuente.icon && String(fuente.icon).length > 0
            ? K4.Apps.icono(fuente.icon, true) : ""
    }

    property real ratonX: -9999
    property bool dentro: false

    //  Solo la FRANJA del dock, no la ventana entera.
    //
    //  Está por encima de todo, y un MouseArea con `hoverEnabled` se queda el
    //  hover aunque no acepte botones: llenando la zona —que crece con el menú
    //  y el selector— se tragaba el de las filas del menú y las tarjetas del
    //  selector, y ninguna se iluminaba al pasar por encima. Los clics sí
    //  pasaban, por el `NoButton`, así que el fallo se veía solo en el
    //  resaltado. Aquí abajo no estorba a nadie y es donde hace falta: lo único
    //  que sale de él es la lupa de los iconos.
    //  Todo el ancho de la ventana y solo el alto de la franja. El ancho
    //  importa porque `ratonX` se compara con el centro de cada hueco, y ese
    //  está medido en la ventana: con el sensor más estrecho y centrado, las
    //  dos cuentas salían de orígenes distintos y la lupa se agrandaba un
    //  icono al lado del que señalabas.
    MouseArea {
        width: muelle.width
        height: muelle.altoDock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: muelle.dentro = true
        onExited: muelle.dentro = false
        onPositionChanged: function (ev) { muelle.ratonX = ev.x }
    }
}
