//  El lienzo: el fondo de escritorio, dibujado por la propia barra.
//
//  Hasta ahora el fondo lo ponía swaybg y la barra solo le pasaba una ruta. Eso
//  deja fuera tres cosas a la vez: no hay transiciones —el propio módulo lo
//  admitía en su pie, «instala awww para tenerlas»—, no hay vídeo, y la barra
//  no sabe qué está enseñando, así que no puede sacarle los colores. Pintándolo
//  aquí, en una K4.Ventana en la capa de abajo —que la API aprendió para esto—,
//  el fondo pasa a estar DENTRO del mismo motor que dibuja la island.
//
//  Y sin una sola dependencia nueva: `AnimatedImage` viene en QtQuick y
//  `MediaPlayer` en QtMultimedia, que ya es dependencia declarada desde que el
//  editor de vídeo necesita su descodificador.
//
//  ── swaybg NO se retira: se queda de SUELO ───────────────────────
//
//  Lo que dibuja la barra vive mientras vive la barra, y entre que entras a la
//  sesión y arranca quickshell hay un rato en el que no hay nadie. Si en ese
//  rato el fondo es un rectángulo negro, hemos empeorado algo que funcionaba. Y
//  si un día la barra se cae, lo mismo. Así que a swaybg se le sigue dando el
//  fotograma quieto —para un vídeo, su póster— y el lienzo pinta encima: al
//  entrar ves la foto, y cuando la barra llega se pone en marcha.
//
//  ── lo que cuesta, medido antes de escribirlo ────────────────────
//
//  En un banco aparte, monitor a 60 Hz, sobre el proceso y no a ojo:
//
//      quieto            0,5 % de un núcleo  (y de esos, casi todo es el
//                                             contador de fps del banco)
//      GIF 960 · 20 fps  11,9 %
//      vídeo 1080p60     14–18 %   ·  o sea el 1,5 % de una máquina de 12
//
//  Un GIF cuesta casi lo mismo que un vídeo por la cuarta parte de calidad: se
//  descomprime en CPU y no hay descodificador que valga. Quien traiga un GIF
//  grande hace mejor en convertirlo, y eso es cosa de la pantalla que vendrá.

import QtQuick
import QtMultimedia
import QtQuick.Effects
import QtQuick.Shapes
import K4 as K4
import "../../services"

K4.PorPantalla {
    id: lienzo

    //  Quien sabe qué fondo va en cada pantalla. Se le pregunta en vez de
    //  guardarlo aquí porque el estado es del plugin —lo guarda, lo carga y lo
    //  publica por IPC— y esto solo pinta.
    required property var plugin

    //  Qué transición y cuánto dura. Salen del plugin, que es quien las guarda.
    readonly property string transicion: lienzo.plugin
        ? lienzo.plugin.transicion : "fundido"
    readonly property int duracion: 900

    //  Poner una ruta en una capa es poner DOS cosas —la ruta y su tipo— y
    //  hacerlo por separado deja un fotograma con el tipo de la anterior.
    function poner(c, r) {
        c.ruta = String(r || "")
        c.tipo = lienzo.tipoDe(c.ruta)
    }

    //  Por la extensión y no preguntando al usuario: nadie quiere elegir en un
    //  desplegable si su fichero es un vídeo. `webp` va por el camino animado a
    //  propósito — uno quieto se pinta igual de bien ahí, y adivinar cuál es
    //  cuál pide abrir el fichero.
    //  ── cuánto se ve, y por tanto si merece la pena moverse ──────
    //
    //  Un fondo animado NO se para solo cuando lo tapan. Medido antes de
    //  escribir nada: 16 % de un núcleo descodificando un vídeo con un terminal
    //  de 1900×1026 encima. Eso es todo el día gastando por nadie, y es la
    //  única de las tres cosas de esta fase que ningún demonio de fondo te da
    //  hecha — de ahí que valga la pena dibujarlo aquí.
    //
    //  Se mide MUESTREANDO y no calculando la unión de rectángulos: la unión
    //  exacta de N ventanas superpuestas es un algoritmo con casos raros, y lo
    //  que hace falta aquí no es un área exacta sino una respuesta a «¿queda
    //  algo de fondo a la vista?». Una rejilla de 16×9 son 144 puntos, se
    //  resuelve con cuatro comparaciones cada uno, y se equivoca como mucho en
    //  un dieciseisavo de pantalla.
    readonly property int rejillaX: 24
    readonly property int rejillaY: 14

    //  Por debajo de esto se para. No es 0 %: con las ventanas en mosaico
    //  siempre asoman las rendijas de los huecos, y dejar un vídeo corriendo por
    //  ocho píxeles de rendija es justo lo que se quería evitar.
    //
    //  Y es 3 % y no 8 porque la cuenta se hace sobre el área UTILIZABLE (ver
    //  `libresEn`): sin descontar lo reservado, la franja del dock —62 px— valía
    //  un 6 % ella sola y con el dock puesto no se paraba nunca.
    readonly property real umbralVisible: 0.03

    //  Las ventanas que hay delante, en coordenadas de escritorio.
    //  ── las ventanas que hay delante ────────────────────────────
    //
    //  Se le preguntan a `hyprctl` directamente y no al servicio de ventanas, y
    //  no por gusto: `Ventanas.refrescar()` llama a `Hyprland.refreshToplevels()`
    //  **si existe**, y en esta versión de Quickshell no existe — el `typeof` de
    //  guardia lo convierte en un no-op silencioso. Consecuencia medida: una
    //  ventana recién abierta salía en la lista con su `lastIpcObject` VACÍO
    //  (`ws=None at=None`), se caía del filtro, el lienzo daba `libres 144/144`
    //  y el vídeo seguía corriendo debajo de una ventana que lo tapaba entero.
    //
    //  Qué escritorios están delante sí sale de `Workspaces`, que trae el
    //  `active` de cada uno al día — eso se comprobó y venía bien.
    property var cajas: []

    //  Lo que cada monitor le tiene reservado a las barras, por nombre.
    property var reservas: ({})

    //  En una property con nombre y no como hijo suelto: la propiedad por
    //  defecto de `Variants` es `delegate`, así que un hijo pelado se le asigna
    //  ahí y el id nunca llega a existir. Síntoma: `ReferenceError:
    //  mirarVentanas is not defined` y cero ventanas contadas, con el delegate
    //  funcionando igual porque su asignación explícita gana.
    property var procVentanas: K4.Process {
        //  Los dos de una vez y en un solo proceso: hacen falta las ventanas Y
        //  lo reservado, y dos procesos serían dos respuestas desacompasadas y
        //  una cuenta hecha con mitad de cada foto.
        command: ["sh", "-c",
            "hyprctl monitors -j; echo '@@@'; hyprctl clients -j"]

        onSalida: function (texto) {
            const partes = String(texto).split("@@@")
            if (partes.length < 2)
                return
            let mons = [], l = []
            try {
                mons = JSON.parse(partes[0])
                l = JSON.parse(partes[1])
            } catch (e) {
                return
            }
            const res = ({})
            for (let i = 0; i < mons.length; ++i) {
                const r = mons[i].reserved
                res[mons[i].name] = (r && r.length === 4) ? r : [0, 0, 0, 0]
            }
            lienzo.reservas = res
            const delante = ({})
            const ws = Workspaces.list
            for (let i = 0; i < ws.length; ++i)
                if (ws[i].active)
                    delante[ws[i].id] = true

            const nuevas = []
            for (let i = 0; i < l.length; ++i) {
                const c = l[i]
                if (!c || !c.at || !c.size || c.hidden === true)
                    continue
                if (!c.workspace || delante[c.workspace.id] !== true)
                    continue
                nuevas.push([c.at[0], c.at[1],
                             c.at[0] + c.size[0], c.at[1] + c.size[1]])
            }
            //  Contenedor NUEVO: mutar el que hay no repinta nada en QML, y
            //  entonces `aLaVista` no se entera de que el mundo ha cambiado.
            lienzo.cajas = nuevas
        }
    }

    function pedirVentanas() {
        if (lienzo.procVentanas && !lienzo.procVentanas.running)
            lienzo.procVentanas.running = true
    }

    function cajasVistas() { return lienzo.cajas }

    //  ¿Hay algo que se mueva ahora mismo? De la lista guardada y no de las
    //  telas, porque esto tiene que ser REACTIVO y `instances` no lo es.
    readonly property bool hayMovimiento: {
        if (!lienzo.plugin)
            return false
        const mueve = function (r) {
            const t = lienzo.tipoDe(r)
            return t === "video" || t === "animado"
        }
        const f = lienzo.plugin.fondos || ({})
        for (const k in f)
            if (mueve(f[k]))
                return true
        return mueve(lienzo.plugin.wallpaper)
    }

    //  Dos disparadores. El bueno es abrir o cerrar una ventana, que sí llega
    //  por señal y hace que la pausa responda al instante; el reloj es la red
    //  para lo que no avisa —mover o redimensionar— y solo corre mientras haya
    //  algo que se mueva. Con todo quieto no se lanza un solo proceso.
    property Connections escucha: Connections {
        target: Ventanas
        function onListaChanged() { lienzo.pedirVentanas() }
    }

    property Timer vigia: Timer {
        interval: 2000
        repeat: true
        running: lienzo.hayMovimiento
        triggeredOnStart: true
        onTriggered: lienzo.pedirVentanas()
    }

    //  Los puntos de la rejilla que no tapa ninguna ventana, contados sobre el
    //  área UTILIZABLE del monitor y no sobre el monitor entero.
    //
    //  Lo reservado —la franja de la barra arriba, la del dock abajo— lo tapa la
    //  propia barra o el propio dock, que no son ventanas y por tanto no salen
    //  en `hyprctl clients`. Contándolo, una pantalla con una ventana maximizada
    //  y el dock puesto daba 16 de 144 puntos «libres» —un 11 %— y el vídeo no
    //  se paraba nunca. Que es exactamente lo que se veía.
    function libresEn(nombre, x0, y0, ancho, alto) {
        const r = lienzo.reservas[nombre] || [0, 0, 0, 0]
        x0 += r[0]
        y0 += r[1]
        ancho -= r[0] + r[2]
        alto -= r[1] + r[3]
        if (ancho <= 0 || alto <= 0)
            return 0
        const cajas = lienzo.cajasVistas()
        let libres = 0
        for (let ix = 0; ix < lienzo.rejillaX; ++ix) {
            const px = x0 + ancho * (ix + 0.5) / lienzo.rejillaX
            for (let iy = 0; iy < lienzo.rejillaY; ++iy) {
                const py = y0 + alto * (iy + 0.5) / lienzo.rejillaY
                let tapado = false
                for (let c = 0; c < cajas.length; ++c) {
                    const b = cajas[c]
                    if (px >= b[0] && px < b[2] && py >= b[1] && py < b[3]) { tapado = true; break }
                }
                if (!tapado) libres += 1
            }
        }
        return libres
    }

    //  Y la respuesta: ¿queda bastante fondo a la vista como para que valga la
    //  pena moverse?
    function seVeAlgoEn(nombre, x0, y0, ancho, alto) {
        if (!nombre || ancho <= 0 || alto <= 0)
            return true
        if (lienzo.cajasVistas().length === 0)
            return true
        return lienzo.libresEn(nombre, x0, y0, ancho, alto)
            / (lienzo.rejillaX * lienzo.rejillaY) > lienzo.umbralVisible
    }

    function tipoDe(ruta) {
        const r = String(ruta || "").toLowerCase()
        if (/\.(mp4|webm|mkv|mov|m4v|avi)$/.test(r))
            return "video"
        if (/\.(gif|webp|apng)$/.test(r))
            return "animado"
        if (r.length === 0)
            return "nada"
        return "quieto"
    }

    delegate: K4.Ventana {
        id: tela

        required property var modelData
        screen: modelData

        nombre: "k4-fondo"

        //  Debajo de las ventanas. Y sin recoger un solo clic: sin `zonaActiva`
        //  el mask se queda en `null` y esta superficie se lleva TODOS los clics
        //  del escritorio — que en la capa de abajo significa un escritorio que
        //  deja de responder y nadie sabe por qué (ver api/K4/Ventana.qml).
        capa: "fondo"

        //  Y a pantalla COMPLETA, saltándose las reservas ajenas.
        //
        //  Con `reserva: 0` —lo de fábrica— la ventana no reserva sitio pero sí
        //  respeta el de los demás, así que la franja de 34 px de la barra la
        //  empujaba: medido, salía `1920x1046 en (…,34)`. Un fondo de escritorio
        //  que empieza donde acaba la barra deja una banda muerta arriba y
        //  descuadra el encaje de la imagen. `-1` es no reservar nada Y además
        //  saltarse lo ajeno, que es justo lo que hace falta debajo de todo.
        reserva: -1

        zonaActiva: nada

        Item { id: nada; width: 0; height: 0 }

        readonly property string cual: modelData ? modelData.name : ""
        readonly property string ruta: lienzo.plugin
            ? lienzo.plugin.fondoDe(cual) : ""

        //  Solo existe si hay algo que pintar. Sin fondo asignado no se crea la
        //  superficie: entonces se ve el suelo de swaybg, que es exactamente lo
        //  que había antes de todo esto.
        //
        //  ── y una FOTO la pinta swaybg, no esto ──────────────────
        //
        //  Con un fondo quieto esta capa dibuja exactamente lo que el suelo ya
        //  está dibujando debajo. Medido sobre el proceso: **80 MiB de VRAM** y
        //  unos 18 MB de RSS por no aportar nada —la barra era el mayor
        //  consumidor de vídeo de la máquina, por delante del navegador—. Así
        //  que con una foto la barra se aparta y se ve el suelo; se queda solo
        //  con lo que swaybg no sabe hacer, que es el vídeo, el GIF y las
        //  transiciones.
        //
        //  La GRACIA de después no es un adorno. Al acabar el fundido hay que
        //  esperar a que swaybg tenga la imagen NUEVA, y ponerlo no es
        //  instantáneo: `ponerSuelo` amortigua 300 ms, mata al viejo, espera
        //  200 más y levanta el nuevo. Soltando la capa al terminar la
        //  transición se ve un parpadeo del fondo viejo, o del vacío.
        //
        //  Y se arma también al arrancar, por lo mismo: entre que entras a la
        //  sesión y swaybg está puesto hay un hueco, y taparlo es justo para lo
        //  que el suelo existe.
        readonly property bool loPintaElSuelo: lienzo.tipoDe(ruta) === "quieto"
            && !tela.cambiando && !gracia.running

        visible: lienzo.tipoDe(ruta) !== "nada" && !tela.loPintaElSuelo

        Timer {
            id: gracia
            interval: 2500
        }

        onCambiandoChanged: if (!tela.cambiando) gracia.restart()

        // ── las dos capas y el relevo ───────────────────────────
        //
        //  Una transición necesita las DOS a la vez: la que se va sigue puesta
        //  hasta el final, y la que llega se revela encima. `viva` dice cuál
        //  tiene el fondo puesto; la otra es la que entra, y va siempre arriba.
        property int viva: 0
        property real avance: 1
        readonly property bool cambiando: tela.avance < 1

        readonly property var capaViva: tela.viva === 0 ? capaA : capaB
        readonly property var capaEntra: tela.viva === 0 ? capaB : capaA

        //  ¿Se ve algo de este fondo? Se recalcula solo: depende de
        //  `Ventanas.lista`, que es reactiva, así que abrir o cerrar una ventana
        //  y cambiar de escritorio ya disparan la cuenta. Un fondo quieto no
        //  pregunta: no gasta nada aunque no se vea.
        readonly property bool aLaVista: lienzo.tipoDe(ruta) === "quieto"
            || lienzo.tipoDe(ruta) === "nada"
            || !tela.screen
            || lienzo.seVeAlgoEn(tela.cual, tela.screen.x, tela.screen.y,
                                 tela.screen.width, tela.screen.height)

        Capa {
            id: capaA
            anchors.fill: parent
            z: tela.viva === 0 ? 0 : 1
            animando: tela.aLaVista
            plugin: lienzo.plugin
            anchoPantalla: tela.screen ? tela.screen.width : 1920
            altoPantalla: tela.screen ? tela.screen.height : 1080
        }

        Capa {
            id: capaB
            anchors.fill: parent
            z: tela.viva === 1 ? 0 : 1
            animando: tela.aLaVista
            plugin: lienzo.plugin
            anchoPantalla: tela.screen ? tela.screen.width : 1920
            altoPantalla: tela.screen ? tela.screen.height : 1080
        }

        onRutaChanged: tela.relevar()

        Component.onCompleted: {
            tela.relevar()
            gracia.restart()
        }

        function relevar() {
            const nueva = tela.ruta
            //  Sin nada puesto todavía —al arrancar— o sin efecto, no hay
            //  transición: se pone y ya. Fundir desde un fondo que no existe es
            //  fundir desde negro, que es peor que no fundir.
            if (tela.capaViva.ruta === nueva)
                return
            if (tela.capaViva.ruta.length === 0
                    || nueva.length === 0
                    || lienzo.transicion === "ninguna") {
                lienzo.poner(tela.capaViva, nueva)
                lienzo.poner(tela.capaEntra, "")
                tela.avance = 1
                return
            }
            lienzo.poner(tela.capaEntra, nueva)
            tela.avance = 0
            paso.restart()
        }

        NumberAnimation {
            id: paso
            target: tela
            property: "avance"
            to: 1
            duration: lienzo.duracion
            //  Arranca suave y para suave: lo que se enseña es una superficie
            //  cambiando, no un objeto que se lanza.
            easing.type: Easing.InOutCubic
            onFinished: {
                //  El relevo: la que entraba pasa a ser la puesta, y la otra se
                //  vacía. Vaciarla ANTES de cambiar `viva` borraría la que se
                //  está viendo.
                tela.viva = tela.viva === 0 ? 1 : 0
                lienzo.poner(tela.capaEntra, "")
            }
        }

        // ── cómo se revela la que entra ─────────────────────────
        //
        //  Una sola vía para los tres efectos: la capa que entra se pinta SIEMPRE
        //  a través del efecto, y lo que cambia es si lleva máscara o solo
        //  opacidad. Tenerlos por caminos distintos era tener dos sitios donde
        //  el relevo puede salir mal.
        ShaderEffectSource {
            id: texturaEntra
            anchors.fill: parent
            sourceItem: tela.capaEntra
            //  La esconde: la pinta el efecto, y dibujada dos veces se vería la
            //  de abajo asomando por donde la máscara la recorta.
            hideSource: true
            live: true
            visible: false
        }

        //  El molde de la máscara. No se dibuja —lo esconde su propia textura— y
        //  solo existe para que el efecto tenga de dónde sacar la forma. Blanco
        //  es «aquí se ve la nueva».
        Item {
            id: molde
            anchors.fill: parent

            //  ── iris: un círculo que crece DESDE LA ISLAND ──
            //
            //  Desde la island y no desde el centro de la pantalla porque es la
            //  island quien acaba de cambiar el fondo: el cambio sale de donde
            //  lo has pedido. En la pantalla que no la tenga desplegada, su
            //  píldora sigue estando, así que el punto vale igual.
            Rectangle {
                visible: lienzo.transicion === "iris"
                color: "white"
                width: tela.radioIris * 2
                height: width
                radius: width / 2
                x: tela.focoX - width / 2
                y: tela.focoY - height / 2
            }

            //  ── marea: sube desde el canto de abajo ──
            //
            //  Con el frente ondulado y no recto, que es lo que la separa de una
            //  cortina: dos senos de distinta longitud desfasados, para que no
            //  se lea el patrón. La onda se apaga al final —`Math.sin(pi·avance)`
            //  vale 0 en los dos extremos— porque un frente ondulado justo al
            //  llegar al borde deja el último dedo de fondo viejo asomando.
            Shape {
                anchors.fill: parent
                visible: lienzo.transicion === "marea"
                antialiasing: true

                ShapePath {
                    //  Con id, y NO por `parent`, que es de lo que se quejaba
                    //  el log en cada transición: un `PathQuad` no es un Item
                    //  —es un elemento de trazado— así que no tiene `parent`, y
                    //  `parent.frente` valía `undefined`. Los puntos de control
                    //  salían indefinidos y la onda del frente no se dibujaba:
                    //  la marea subía RECTA, que es justo la cortina de la que
                    //  el comentario de arriba dice que quiere distinguirse.
                    id: marea

                    fillColor: "white"
                    strokeWidth: 0
                    strokeColor: "transparent"

                    readonly property real frente: tela.height * (1 - tela.avance)
                    readonly property real onda: tela.height * 0.06
                        * Math.sin(Math.PI * tela.avance)

                    startX: 0
                    startY: frente

                    PathQuad {
                        x: tela.width * 0.5; y: marea.frente
                        controlX: tela.width * 0.25
                        controlY: marea.frente - marea.onda * 2
                    }
                    PathQuad {
                        x: tela.width; y: marea.frente
                        controlX: tela.width * 0.75
                        controlY: marea.frente + marea.onda * 2
                    }
                    PathLine { x: tela.width; y: tela.height }
                    PathLine { x: 0; y: tela.height }
                }
            }
        }

        ShaderEffectSource {
            id: texturaMolde
            anchors.fill: parent
            sourceItem: molde
            hideSource: true
            live: true
            visible: false
        }

        MultiEffect {
            anchors.fill: parent
            z: 2
            visible: tela.cambiando
            source: texturaEntra
            //  El fundido es opacidad y los otros dos son máscara. Un fundido
            //  hecho con máscara pediría un molde de gris uniforme y el umbral
            //  barriéndose, que es dar un rodeo para llegar al mismo sitio.
            opacity: lienzo.transicion === "fundido" ? tela.avance : 1
            maskEnabled: lienzo.transicion !== "fundido"
            maskSource: texturaMolde
        }

        //  De dónde sale el iris y hasta dónde tiene que crecer para tapar la
        //  pantalla: la esquina más lejana, que es la que manda.
        readonly property var rectIsla: K4.Isla.rectEn(tela.cual)
        readonly property real focoX: rectIsla && rectIsla.ancho > 0
            ? rectIsla.x + rectIsla.ancho / 2 : tela.width / 2
        readonly property real focoY: rectIsla && rectIsla.alto > 0
            ? rectIsla.y + rectIsla.alto : 0
        readonly property real radioIris: {
            const dx = Math.max(tela.focoX, tela.width - tela.focoX)
            const dy = Math.max(tela.focoY, tela.height - tela.focoY)
            return Math.sqrt(dx * dx + dy * dy) * tela.avance
        }

        //  Para poder mirarle las tripas desde fuera.
        function estado() {
            return { pantalla: tela.cual, tipo: lienzo.tipoDe(tela.ruta),
                     ruta: tela.ruta,
                     aLaVista: tela.aLaVista,
                     ventanasDelante: lienzo.cajasVistas().length,
                     libres: tela.screen ? lienzo.libresEn(
                         tela.cual, tela.screen.x, tela.screen.y,
                         tela.screen.width, tela.screen.height) : -1,
                     puntos: lienzo.rejillaX * lienzo.rejillaY,
                     avance: Math.round(tela.avance * 100) / 100,
                     viva: tela.viva,
                     reproduciendo: tela.capaViva.reproduciendo,
                     error: tela.capaViva.fallo }
        }
    }
}
