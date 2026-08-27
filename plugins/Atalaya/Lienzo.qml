//  El plano: una ventana a pantalla completa donde vive todo lo demás.
//
//  ── tres capas, y el orden importa ───────────────────────────────
//
//    1. La TRAMA (`trama.frag`): el suelo. Un fondo que se mueve y se agranda
//       con la cámara, y que es lo que convierte esto en un canvas en vez de
//       en un fondo negro con cosas encima.
//    2. El PLANO: las tarjetas, dibujadas planas y sin doblar.
//    3. La LENTE (`lente.frag`): coge lo anterior ya pintado y lo dobla de una
//       vez.
//
//  Que la lente sea un paso aparte es la decisión de la que cuelga el resto.
//  La primera versión inclinaba cada tarjeta por su cuenta para fingir la
//  curvatura y se veía lo que era: rectángulos girados. Un ojo de pez no gira
//  cosas, dobla la imagen — así que hay que tener imagen primero. A cambio, la
//  curvatura es continua, los colores se separan en los bordes y la luz cae
//  hacia las esquinas, que son las tres cosas que hacen que el ojo se crea que
//  hay un cristal delante.
//
//  ── dos espacios, y la cámara entre ellos ────────────────────────
//
//  El PLANO es donde se reparten las ventanas y sus unidades son píxeles a
//  escala 1 —una celda mide un monitor—. La PANTALLA es lo que se ve. Entre
//  uno y otro, `camX`/`camY`/`escala`. La lente NO entra en esa cuenta: actúa
//  después, sobre píxeles ya pintados, que es justo lo que la deja quieta en
//  el cristal mientras el plano desfila por detrás.
//
//  ── el ratón, todo por un sitio ──────────────────────────────────
//
//  Un único `MouseArea` a pantalla completa, y qué tarjeta hay debajo se
//  calcula. Con la lente puesta hay un paso más: el puntero está en la imagen
//  DOBLADA, así que antes de buscar hay que deshacer el doblez (`aLienzo`).
//  Sale la misma cuenta que hace el shader, y tiene que ser la misma o el
//  ratón señalaría un sitio y pulsaría otro.

import QtQuick
import K4 as K4
import "lente.js" as Lente

K4.Ventana {
    id: capa

    required property var plugin

    nombre: "k4-atalaya"
    pantalla: plugin.monitor
    capa: "encima"

    //  El teclado, mientras esté delante.
    //
    //  Y a diferencia de un juego, esto NO se ata a `K4.Isla.aLaVista`: la
    //  island no pinta nada de aquí, así que si está retirada —el modo oculto
    //  es un ajuste, no una avería— no dice nada sobre esta ventana, y atarlo
    //  dejaría el selector sin ESC justo en ese modo. La red de seguridad es
    //  el `guardian` de más abajo, que es la que de verdad hace falta.
    conTeclado: plugin.abierto
    zonaActiva: raton

    // ── cámara ────────────────────────────────────────────────────
    property real camX: 0
    property real camY: 0
    property real escala: 1

    //  0 = cada ventana en su sitio real · 1 = repartidas por el plano.
    property real apertura: (plugin.abierto || cayendo) ? 1 : 0
    //  Cayendo sobre una: la vista se va hacia una tarjeta y se apaga.
    property bool cayendo: false

    //  Y mientras cae, las demás se apartan.
    //
    //  No es adorno: al acercarse a una ventana, las vecinas crecen también
    //  —están en el mismo plano— y acaban entrando en el encuadre por los
    //  bordes justo cuando la elegida iba a quedarse sola. Echándolas hacia
    //  fuera, el camino queda despejado y de paso se lee como lo que es: todo
    //  lo demás apartándose para dejar pasar a una.
    property real expulsion: cayendo ? 1 : 0
    Behavior on expulsion { NumberAnimation { duration: 300; easing.type: Easing.InCubic } }

    //  Cuánto dobla la lente. Nace con la apertura porque el escritorio de
    //  partida es plano: la curvatura tiene que aparecer AL alejarse, no estar
    //  ya puesta sobre las ventanas cuando aún ocupan su sitio. Y se deshace
    //  al caer sobre una, que es lo que hace que la miniatura encaje con la
    //  ventana de verdad al llegar.
    readonly property real curva: 0.48 * apertura * (cayendo ? 0 : 1)

    property bool suave: false

    //  Dónde está el puntero. Lo lee el suelo para alumbrar por donde vas.
    //
    //  Por enlace y no asignándolo desde `onPositionChanged`: así al abrir ya
    //  vale lo que vale, sin esperar a que el usuario mueva la mano. Antes el
    //  resplandor nacía en el centro de la pantalla y saltaba al puntero en
    //  cuanto se movía un píxel, que es peor que no tenerlo.
    readonly property real ratonX: raton.containsMouse
        ? raton.mouseX / Math.max(1, capa.width) : 0.5
    readonly property real ratonY: raton.containsMouse
        ? raton.mouseY / Math.max(1, capa.height) : 0.5

    //  El reloj de la onda de apertura. Arranca al nacer la ventana, que es
    //  exactamente cuando esto se abre.
    property real onda: 0
    NumberAnimation on onda {
        from: 0
        to: 1
        duration: 820
        easing.type: Easing.OutQuad
        running: true
    }

    Behavior on camX { enabled: capa.suave; NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
    Behavior on camY { enabled: capa.suave; NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
    Behavior on escala { enabled: capa.suave; NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
    Behavior on apertura { NumberAnimation { duration: 560; easing.type: Easing.OutCubic } }

    // ── el reparto ────────────────────────────────────────────────
    readonly property real celdaW: Math.max(320, plugin.monAncho)
    readonly property real celdaH: Math.max(200, plugin.monAlto)
    readonly property real hueco: celdaW * 0.085

    readonly property var mapa: Lente.reparto(plugin.ventanas.length,
                                              celdaW, celdaH, hueco)

    //  Que quepa todo, dibujado MÁS GRANDE de lo que se quiere ver.
    //
    //  Suena a error y es la cuenta correcta: la lente comprime hacia dentro,
    //  así que lo que se dibuja pegado al borde aparece bastante antes de él.
    //  Medido con la curva en 0.48: el borde del plano sale a ocho décimas del
    //  centro, y el resto de la pantalla se queda en negro. Encajar «con aire»
    //  como si no hubiera lente deja las ventanas nadando en un agujero.
    readonly property real escalaEncaje: {
        if (!mapa || mapa.ancho <= 0)
            return 0.4
        const cx = capa.width * 0.95 / mapa.ancho
        const cy = Math.max(120, capa.height - 170) * 0.98 / mapa.alto
        return Math.max(0.03, Math.min(cx, cy, 1.0))
    }

    readonly property real escalaMin: escalaEncaje * 0.45
    readonly property real escalaMax: 1.4

    // ── proyección ────────────────────────────────────────────────
    //
    //  Plana: la lente va después y no entra aquí.
    function proyectar(px, py) {
        return { x: (px - capa.camX) * capa.escala + capa.width / 2,
                 y: (py - capa.camY) * capa.escala + capa.height / 2 }
    }

    //  De un punto de la PANTALLA al punto del plano dibujado que se ve ahí.
    //  Es la cuenta del shader, en el mismo orden: normalizar contra el alto,
    //  estirar por el factor de la curva, y volver a píxeles.
    function aLienzo(sx, sy) {
        const cx = capa.width / 2
        const cy = capa.height / 2
        const h = Math.max(1, capa.height)
        const ux = (sx - cx) / h
        const uy = (sy - cy) / h
        const f = 1.0 + capa.curva * (ux * ux + uy * uy)
        return { x: cx + (sx - cx) * f, y: cy + (sy - cy) * f }
    }

    //  Y de ahí al plano de verdad, deshaciendo la cámara.
    function aPlano(sx, sy) {
        const p = aLienzo(sx, sy)
        return { x: (p.x - capa.width / 2) / capa.escala + capa.camX,
                 y: (p.y - capa.height / 2) / capa.escala + capa.camY }
    }

    // ── la entrada, escalonada ────────────────────────────────────
    //
    //  Todas a la vez es una diapositiva; con un retardo por distancia al
    //  centro es un movimiento. Las de en medio salen primero y las de fuera
    //  las siguen, que además es el orden en que el ojo las va a leer.
    readonly property real radioPlano:
        Math.max(1, Math.sqrt(mapa.ancho * mapa.ancho + mapa.alto * mapa.alto) / 2)

    function tramo(i) {
        const c = mapa.celdas[i]
        if (!c)
            return capa.apertura
        const d = Math.min(1, Math.sqrt(c.x * c.x + c.y * c.y) / capa.radioPlano)
        const r = 0.38 * d
        const t = Math.max(0, Math.min(1, (capa.apertura - r) / Math.max(0.01, 1 - r)))
        //  Suavizado en las dos puntas: sin esto, arrancar y frenar se notan
        //  como dos tirones.
        return t * t * (3 - 2 * t)
    }

    //  Dónde y de qué tamaño se dibuja la tarjeta `i`, ya interpolada entre su
    //  sitio real y su sitio en el plano.
    function geo(i) {
        const c = mapa.celdas[i]
        const v = plugin.ventanas[i]
        if (!c || !v)
            return { x: 0, y: 0, w: 0, h: 0, op: 0, t: 0 }

        const p = proyectar(c.x, c.y)
        const cabe = Lente.encajar(v.ancho, v.alto, celdaW, celdaH)
        const w = cabe.w * capa.escala
        const h = cabe.h * capa.escala

        let rx, ry, rw, rh, op
        if (v.enPantalla) {
            //  Arranca tapando a su propia ventana. Ese encaje es lo que hace
            //  que la entrada no parezca una animación sino un movimiento de
            //  cámara: al principio no hay nada nuevo en pantalla.
            rx = v.rx; ry = v.ry; rw = v.ancho; rh = v.alto; op = 1
        } else {
            //  Y lo que no se veía crece desde el centro. No desde un borde:
            //  entrar por un lado sugiere que estaba ahí al lado, y estaba en
            //  otro escritorio.
            rw = w * 0.35; rh = h * 0.35
            rx = capa.width / 2 - rw / 2; ry = capa.height / 2 - rh / 2; op = 0
        }

        const t = tramo(i)
        let gx = rx + (p.x - w / 2 - rx) * t
        let gy = ry + (p.y - h / 2 - ry) * t

        //  Las que no son la elegida, fuera del camino: cada una en la
        //  dirección en la que ya estaba respecto al centro.
        if (capa.expulsion > 0 && i !== plugin.seleccion) {
            const dx = p.x - capa.width / 2
            const dy = p.y - capa.height / 2
            const d = Math.max(1, Math.sqrt(dx * dx + dy * dy))
            const emp = capa.expulsion * 520
            gx += dx / d * emp
            gy += dy / d * emp
        }

        return {
            x: gx,
            y: gy,
            w: rw + (w - rw) * t,
            h: rh + (h - rh) * t,
            op: op + (1 - op) * t,
            t: t
        }
    }

    // ── filtro y selección ────────────────────────────────────────
    function casa(i) {
        const v = plugin.ventanas[i]
        if (!v)
            return false
        const f = plugin.filtro.trim().toLowerCase()
        if (f.length === 0)
            return true
        return v.titulo.toLowerCase().indexOf(f) >= 0
            || v.clase.toLowerCase().indexOf(f) >= 0
    }

    readonly property int cuantasCasan: {
        let n = 0
        for (let i = 0; i < plugin.ventanas.length; ++i)
            if (casa(i))
                ++n
        return n
    }

    readonly property var elegida: plugin.ventanas[plugin.seleccion] || null

    function primeraQueCasa() {
        for (let i = 0; i < plugin.ventanas.length; ++i)
            if (casa(i))
                return i
        return -1
    }

    function tarjetaEn(mx, my) {
        //  El puntero está sobre la imagen DOBLADA: hay que llevarlo al plano
        //  plano antes de comparar con nada.
        const p = aLienzo(mx, my)
        for (let i = plugin.ventanas.length - 1; i >= 0; --i) {
            if (!casa(i))
                continue
            const g = geo(i)
            if (p.x >= g.x && p.x <= g.x + g.w && p.y >= g.y && p.y <= g.y + g.h)
                return i
        }
        return -1
    }

    //  La vecina en una dirección, medida en el PLANO y no en pantalla: la
    //  lente mueve las tarjetas, y navegar con flechas por una rejilla que se
    //  curva daría saltos distintos según dónde estés mirando.
    function vecina(dx, dy) {
        const orig = mapa.celdas[plugin.seleccion]
        if (!orig)
            return primeraQueCasa()
        let mejor = -1
        let coste = Infinity
        for (let i = 0; i < mapa.celdas.length; ++i) {
            if (i === plugin.seleccion || !casa(i))
                continue
            const c = mapa.celdas[i]
            const av = (c.x - orig.x) * dx + (c.y - orig.y) * dy
            if (av <= 1)
                continue
            const lat = Math.abs((c.x - orig.x) * dy + (c.y - orig.y) * dx)
            //  El desvío pesa el triple que el avance: así «abajo» prefiere la
            //  de justo debajo antes que una más cercana pero torcida.
            const p = av + lat * 3
            if (p < coste) {
                coste = p
                mejor = i
            }
        }
        return mejor
    }

    function seleccionar(i) {
        if (i < 0 || i >= plugin.ventanas.length)
            return
        plugin.seleccion = i
        capa.suave = true
        asegurarVisible(i)
    }

    function siguienteQueCasa(paso) {
        const n = plugin.ventanas.length
        if (n === 0)
            return -1
        let i = plugin.seleccion
        for (let k = 0; k < n; ++k) {
            i = (i + paso + n) % n
            if (casa(i))
                return i
        }
        return plugin.seleccion
    }

    //  Mover la cámara lo justo para que la elegida quede holgada dentro. Lo
    //  justo y no centrarla siempre: recentrar en cada flecha marea, y el
    //  usuario pierde la referencia de dónde estaba.
    function asegurarVisible(i) {
        const g = geo(i)
        const m = 130
        let dx = 0
        let dy = 0
        if (g.x < m) dx = g.x - m
        else if (g.x + g.w > capa.width - m) dx = g.x + g.w - (capa.width - m)
        if (g.y < m) dy = g.y - m
        else if (g.y + g.h > capa.height - m) dy = g.y + g.h - (capa.height - m)
        if (dx !== 0 || dy !== 0) {
            camX += dx / capa.escala
            camY += dy / capa.escala
        }
    }

    // ── zoom ──────────────────────────────────────────────────────
    function zoomEn(mx, my, mult) {
        const antes = aPlano(mx, my)
        capa.suave = false
        capa.escala = Math.max(escalaMin, Math.min(escalaMax, capa.escala * mult))
        const luego = aPlano(mx, my)
        capa.camX += antes.x - luego.x
        capa.camY += antes.y - luego.y
    }

    // ── caer sobre una ventana ────────────────────────────────────
    function caer(i) {
        const v = plugin.ventanas[i]
        const c = mapa.celdas[i]
        if (!v || !c || capa.cayendo)
            return

        capa.cayendo = true
        capa.suave = true
        //  El salto se pide YA: el compositor tarda en cambiar de escritorio y
        //  pedirlo al final del vuelo deja ver el escritorio viejo por debajo
        //  justo cuando la miniatura ya ocupa toda la pantalla.
        plugin.ir(v.dir)

        const cabe = Lente.encajar(v.ancho, v.alto, celdaW, celdaH)
        capa.camX = c.x
        capa.camY = c.y
        capa.escala = Math.min(capa.width / Math.max(1, cabe.w),
                               capa.height / Math.max(1, cabe.h))
        fin.restart()
    }

    Timer {
        id: fin
        interval: 300
        //  Sin animación de vuelta: la opacidad ya está a cero y lo que hay
        //  debajo es la ventana de verdad, ya enfocada.
        onTriggered: plugin.cerrarYa()
    }

    //  La vuelta ha terminado: ya se puede destruir la ventana.
    Timer {
        id: adios
        interval: 620
        onTriggered: plugin.saliendo = false
    }

    Connections {
        target: plugin
        function onAbiertoChanged() {
            if (!plugin.abierto && plugin.saliendo)
                adios.restart()
        }
        function onVentanasChanged() {
            capa.suave = false
            capa.escala = capa.escalaEncaje
            capa.camX = 0
            capa.camY = 0
        }
        function onFiltroChanged() {
            if (!capa.casa(plugin.seleccion)) {
                const i = capa.primeraQueCasa()
                if (i >= 0)
                    capa.seleccionar(i)
            }
        }
    }

    //  El guardián. Un selector no se deja abierto un minuto y medio, y si se
    //  deja es que algo ha salido mal — y esta ventana tiene el teclado en
    //  exclusiva. Cerrarse sola no pierde nada: aquí no hay estado que perder.
    Timer {
        id: guardian
        interval: 90000
        running: plugin.abierto
        onTriggered: plugin.cerrar()
    }

    function despertar() { guardian.restart() }

    Component.onCompleted: {
        //  El plugin no puede alcanzar la vista por su cuenta —vive dentro de
        //  un `K4.Cargador`— así que la vista se presenta. Es lo que permite
        //  que `elegir` por IPC haga exactamente lo mismo que un clic, y no
        //  una segunda versión de lo mismo que se desincroniza.
        plugin.lienzo = capa
        capa.suave = false
        capa.escala = escalaEncaje
        capa.camX = 0
        capa.camY = 0
    }

    Component.onDestruction: {
        if (plugin.lienzo === capa)
            plugin.lienzo = null
    }

    // ── 1. el suelo ───────────────────────────────────────────────
    ShaderEffect {
        anchors.fill: parent
        opacity: capa.apertura * (capa.cayendo ? 0 : 1)
        Behavior on opacity { NumberAnimation { duration: 260 } }

        //  Por ruta de fichero y no por `Qt.resolvedUrl`: lo segundo devuelve
        //  una URL del esquema interno de Quickshell (`qs:@/qs/…`) y esto se
        //  carga fuera de su alcance.
        fragmentShader: "file://" + plugin.fichero("trama.frag.qsb")

        property real curva: capa.curva
        property real aspecto: capa.height > 0 ? capa.width / capa.height : 1.7
        property real alto: capa.height
        property real escala: capa.escala
        property real camX: capa.camX
        property real camY: capa.camY
        //  Una celda de trama por cada sexto de monitor. Con un tercio los
        //  puntos quedaban a más de doscientos píxeles y el suelo no contaba
        //  nada al arrastrar: para leer movimiento hace falta que haya varios
        //  puntos cruzando la pantalla a la vez.
        property real paso: capa.celdaW / 6
        property real fuerza: capa.apertura
        property real luzX: capa.ratonX
        property real luzY: capa.ratonY
        property real onda: capa.onda
        //  Del tema del usuario, no de aquí.
        property color luzColor: K4.Tema.azul
    }

    // ── 2. el plano, y 3. la lente encima ─────────────────────────
    Item {
        id: contenido
        anchors.fill: parent

        opacity: capa.cayendo ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InQuad } }

        //  Aquí es donde el plano deja de ser una lista de rectángulos y pasa
        //  a ser una imagen: se dibuja entero a una textura y el efecto la
        //  dobla. Cuesta un paso de dibujado a pantalla completa, que es lo
        //  que cuesta cualquier post-proceso, y es lo que compra la curvatura
        //  continua.
        layer.enabled: true
        layer.smooth: true
        layer.effect: ShaderEffect {
            fragmentShader: "file://" + capa.plugin.fichero("lente.frag.qsb")
            property real curva: capa.curva
            //  La separación de colores y la caída de luz entran con la
            //  apertura, como la curvatura: al principio esto es un escritorio
            //  y un escritorio no tiene bordes de cristal.
            //  0.007 y no más: con 0.05 la separación llegaba a CATORCE píxeles
            //  en el borde de una tarjeta y el texto de un terminal se volvía
            //  ilegible. Una lente de verdad separa uno o dos píxeles, y sólo
            //  en las esquinas; lo que se busca es que se note sin poder
            //  decir qué es.
            property real aberracion: 0.007 * capa.apertura
            property real vineta: 1.30 * capa.apertura
            property real aspecto: capa.height > 0 ? capa.width / capa.height : 1.7
        }

        Repeater {
            model: plugin.ventanas
            delegate: Tarjeta { lienzo: capa }
        }
    }

    // ── el ratón ──────────────────────────────────────────────────
    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        property int arrastreX: 0
        property int arrastreY: 0
        //  Dónde se pulsó, aparte de dónde va el arrastre. Son dos cosas: el
        //  segundo se actualiza en cada evento para calcular el tramo, y sólo
        //  el primero sirve para decidir si esto ha sido un clic o un
        //  arrastre.
        property int origenX: 0
        property int origenY: 0
        property bool arrastrando: false
        property bool movido: false

        onPositionChanged: function (m) {
            capa.despertar()
            if (arrastrando) {
                //  Contra el punto donde se PULSÓ, no contra el evento
                //  anterior: comparando con el anterior, un arrastre lento se
                //  cuela como clic, y con seis píxeles de margen una mano que
                //  tiembla al pulsar sigue haciendo clic.
                if (Math.abs(m.x - origenX) + Math.abs(m.y - origenY) > 6)
                    movido = true
                const a = capa.aPlano(arrastreX, arrastreY)
                const b = capa.aPlano(m.x, m.y)
                capa.suave = false
                capa.camX -= b.x - a.x
                capa.camY -= b.y - a.y
                arrastreX = m.x
                arrastreY = m.y
                return
            }
            const i = capa.tarjetaEn(m.x, m.y)
            if (i >= 0 && i !== plugin.seleccion)
                plugin.seleccion = i
        }

        onPressed: function (m) {
            capa.despertar()
            arrastrando = true
            movido = false
            arrastreX = m.x
            arrastreY = m.y
            origenX = m.x
            origenY = m.y
        }

        onReleased: function (m) {
            arrastrando = false
            if (movido)
                return
            const i = capa.tarjetaEn(m.x, m.y)
            if (i >= 0) {
                if (m.button === Qt.RightButton)
                    plugin.seleccion = i
                else
                    capa.caer(i)
                return
            }
            //  Clic en el vacío: fuera. Es la salida que se descubre sola.
            if (m.button === Qt.LeftButton)
                plugin.cerrar()
        }

        onWheel: function (w) {
            capa.despertar()
            //  Arriba acerca, como en todo lo que hace zoom. Y al revés si el
            //  usuario lo ha pedido en Ajustes: con el desplazamiento natural
            //  del sistema puesto, el signo llega cambiado antes de que esto
            //  lo vea, así que no hay una dirección que valga para todos.
            const arriba = w.angleDelta.y > 0
            const acercar = plugin.ruedaAlReves ? !arriba : arriba
            const paso = acercar ? 1.14 : 1 / 1.14
            capa.zoomEn(w.x, w.y, paso)
        }
    }

    // ── teclado ───────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function (e) {
            capa.despertar()
            switch (e.key) {
            case Qt.Key_Escape:
                plugin.cerrar()
                e.accepted = true
                return
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (capa.casa(plugin.seleccion))
                    capa.caer(plugin.seleccion)
                else {
                    const i = capa.primeraQueCasa()
                    if (i >= 0)
                        capa.caer(i)
                }
                e.accepted = true
                return
            case Qt.Key_Left:
                capa.seleccionar(capa.vecina(-1, 0))
                e.accepted = true
                return
            case Qt.Key_Right:
                capa.seleccionar(capa.vecina(1, 0))
                e.accepted = true
                return
            case Qt.Key_Up:
                capa.seleccionar(capa.vecina(0, -1))
                e.accepted = true
                return
            case Qt.Key_Down:
                capa.seleccionar(capa.vecina(0, 1))
                e.accepted = true
                return
            case Qt.Key_Tab:
                capa.seleccionar(capa.siguienteQueCasa(1))
                e.accepted = true
                return
            case Qt.Key_Backtab:
                capa.seleccionar(capa.siguienteQueCasa(-1))
                e.accepted = true
                return
            case Qt.Key_Backspace:
                plugin.filtro = plugin.filtro.slice(0, -1)
                e.accepted = true
                return
            case Qt.Key_Plus:
            case Qt.Key_Equal:
                capa.suave = true
                capa.zoomEn(capa.width / 2, capa.height / 2, 1.2)
                e.accepted = true
                return
            case Qt.Key_Minus:
                capa.suave = true
                capa.zoomEn(capa.width / 2, capa.height / 2, 1 / 1.2)
                e.accepted = true
                return
            case Qt.Key_Home:
                capa.suave = true
                capa.escala = capa.escalaEncaje
                capa.camX = 0
                capa.camY = 0
                e.accepted = true
                return
            }
            //  Y cualquier otra cosa imprimible, a filtrar. Sin caja de texto
            //  ni foco que perseguir: se escribe y ya.
            if (e.text && e.text.length === 1 && e.text.charCodeAt(0) >= 32) {
                plugin.filtro += e.text
                e.accepted = true
            }
        }
    }

    // ── el rótulo, sólo cuando hace falta ─────────────────────────
    //
    //  Antes había aquí una pastilla permanente con el título de la ventana
    //  señalada y las teclas. Fuera: el título ya está en la tarjeta, señalar
    //  algo no es una pregunta que necesite respuesta escrita, y un cartel fijo
    //  en medio de un canvas es lo que hace que parezca un formulario.
    //
    //  Pero no se puede quitar del todo. Al escribir para filtrar hay que VER
    //  lo que se lleva escrito —un buscador ciego no es un buscador— y un
    //  error que nadie enseña es un plugin que no hace nada sin decir por qué.
    //  Así que aparece por esas dos razones y por ninguna más.
    //
    //  Declarado DESPUÉS del MouseArea grande para que lo de abajo reciba el
    //  clic: en QML manda el último que se declara, no el que parezca estar
    //  encima. Y fuera de la lente: doblar el texto lo haría ilegible, y esto
    //  no está EN el plano — está en el cristal, mirándolo.
    Item {
        id: rotulo

        readonly property bool hayError: plugin.error.length > 0
        readonly property bool escribiendo: plugin.filtro.length > 0
        readonly property bool asoma: hayError || escribiendo || plugin.cargando

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        width: fila.width + 34
        height: 40
        visible: opacity > 0.01
        opacity: asoma ? capa.apertura * contenido.opacity : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: Qt.rgba(0.02, 0.03, 0.05, 0.86)
            border.width: 1
            border.color: rotulo.hayError
                ? Qt.rgba(1, 0.3, 0.25, 0.35)
                : Qt.rgba(1, 1, 1, 0.10)
        }

        Row {
            id: fila
            anchors.centerIn: parent
            spacing: 10

            K4.Etiqueta {
                anchors.verticalCenter: parent.verticalCenter
                visible: plugin.cargando || rotulo.hayError
                text: plugin.cargando ? K4.Idioma.t("Mirando…") : plugin.error
                color: rotulo.hayError ? K4.Tema.rojo : K4.Tema.apagado
                font.pixelSize: 13
            }

            K4.Etiqueta {
                anchors.verticalCenter: parent.verticalCenter
                visible: rotulo.escribiendo
                text: plugin.filtro
                color: K4.Tema.tinta
                font.pixelSize: 14
                font.bold: true
            }

            //  Cuántas quedan. Es la mitad útil de escribir: dice cuándo has
            //  tecleado suficiente para que quede una sola.
            K4.Etiqueta {
                anchors.verticalCenter: parent.verticalCenter
                visible: rotulo.escribiendo
                text: capa.cuantasCasan + " / " + plugin.ventanas.length
                color: capa.cuantasCasan === 0 ? K4.Tema.rojo : K4.Tema.azul
                font.pixelSize: 12
            }
        }
    }

    //  El aspa. Entre ESC, el fondo y un aspa visible, las tres: las dos
    //  primeras hay que saberlas y un aspa no.
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 22
        width: 34
        height: 34
        radius: 17
        color: aspa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.5)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        opacity: capa.apertura * contenido.opacity

        K4.Etiqueta {
            anchors.centerIn: parent
            text: "✕"
            font.pixelSize: 15
            color: K4.Tema.tinta
        }

        MouseArea {
            id: aspa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: plugin.cerrar()
        }
    }

}
