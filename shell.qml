//  k4 — host de la island.
//
//  Aquí no hay lógica de ningún módulo: esto monta la superficie, dibuja la
//  silueta y decide qué plugin se queda la island. Añadir un módulo es crear
//  una carpeta en plugins/ y darla de alta en plugins/catalog.json.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import K4 as K4
import "core"
import "services"

Scope {
    id: root

    // ── los módulos ───────────────────────────────────────────────
    //
    //  Ya no se instancian aquí: los crea PluginManager desde el catálogo,
    //  cada uno en su try. La diferencia no es de estilo — con la
    //  instanciación estática, un plugin con un error de sintaxis dejaba
    //  «Type X unavailable» y CERO barras, y pasó esta semana. Con la carga
    //  dinámica, el roto se apunta en Ajustes y los demás arrancan.
    //
    //  Las referencias cruzadas (`panel`, `tray`, `juego`…) también las
    //  reparte el gestor: cualquier plugin que declare la propiedad la
    //  recibe, venga del repo o de ~/.config/k4/plugins.

    // ── quién se queda la island ──────────────────────────────────
    // Gana el activo de mayor prioridad. El binding se recalcula solo cuando
    // cualquier plugin cambia su `active`.
    readonly property var activePlugin: {
        if (Island.debugMode.length > 0) {
            const l = PluginManager.instancias
            for (let i = 0; i < l.length; ++i) {
                if (l[i].name === Island.debugMode)
                    return l[i]
            }
        }

        let best = null
        const lista = PluginManager.instancias
        for (let i = 0; i < lista.length; ++i) {
            const p = lista[i]
            if (p.habilitado && p.active
                    && (best === null || p.priority > best.priority))
                best = p
        }
        return best
    }

    //  ── lo que se va solo se aparta ───────────────────────────────
    //
    //  Una vista transitoria —un aviso, la confirmación de una captura— aparece
    //  sin que nadie la pida y se cierra sola a los pocos segundos. Si en esos
    //  segundos el usuario abre algo, lo que quiere es lo que ha abierto: la
    //  confirmación ya ha dicho lo suyo.
    //
    //  Antes se quedaba, y no por prioridad sino por su reloj: la captura tiene
    //  cinco segundos y no cede hasta que vencen, así que pulsar el atajo del
    //  lanzador enseñaba la miniatura de la captura hasta el final y el
    //  lanzador después. Y cerrarla no basta con que otro le gane la prioridad:
    //  su temporizador se rearma mientras el ratón esté sobre la island —que es
    //  donde está, si acabas de abrir algo— así que volvería a salir al cerrar
    //  lo de encima.
    //
    //  Aquí y no en cada plugin: `Notifs.dismissToast()` a mano en cada sitio
    //  que abre algo era lo que había, y es exactamente lo que se olvida — solo
    //  lo llamaban dos.
    function apartarTransitorios() {
        const gana = activePlugin
        if (!gana || gana.transitorio)
            return

        const lista = PluginManager.instancias
        for (let i = 0; i < lista.length; ++i) {
            const p = lista[i]
            if (p !== gana && p.transitorio && p.active
                    && typeof p.close === "function")
                p.close()
        }
    }

    //  Lo que decide el reparto, publicado para que lo lean los plugins por
    //  K4.Isla: quién la tiene y si está desplegada.
    onActivePluginChanged: {
        apartarTransitorios()
        const anterior = Island.ocupante
        if (activePlugin && activePlugin.name !== "idle") {
            // Desde reposo, el origen explícito del clic; sin él, el monitor
            // con foco. Entre dos vistas abiertas se conserva la pantalla para
            // que navegar por el panel no haga saltar la island.
            if (Island.pantallaPedida.length > 0
                    || anterior.length === 0 || anterior === "idle")
                Island.pantallaActiva = Island.tomarPantallaPedida()
        } else {
            Island.pantallaPedida = ""
        }
        Island.ocupante = activePlugin ? activePlugin.name : ""
        //  «Abierta» es DESPLEGADA, no «hay alguien»: la píldora también
        //  ocupa la island y siempre está, así que con `activePlugin !== null`
        //  esto valía true a todas horas y no le servía a nadie. Desplegada es
        //  pedir más alto que la píldora.
        Island.abierta = activePlugin !== null
            && activePlugin.islandHeight > Theme.baseHeight
    }

    // Clic en el fondo: lo atiende el plugin activo si lo pide; si no, abre el
    // centro de control.
    function abrirPanelEn(pantalla) {
        Island.pedirPantalla(pantalla)
        Island.pantallaActiva = pantalla
        const panel = PluginManager.instancia("panel")
        if (panel)
            panel.openTab("controls")
    }

    function backgroundTap(pantalla, mostrado) {
        if (mostrado && mostrado.name !== "idle" && mostrado.handlesBackgroundTap)
            mostrado.backgroundTapped()
        else
            abrirPanelEn(pantalla)
    }

    // Los singletons de QML son perezosos: sin tocarlos no arrancan sus
    // procesos ni registran nada (el servidor de notificaciones, por ejemplo).
    Component.onCompleted: {
        //  El puente de la API, lo PRIMERO: los ficheros del módulo K4 no
        //  pueden importar la barra por ruta relativa —cargarían una segunda
        //  copia entera de services/, ver api/K4/Puente.qml— así que el host
        //  les inyecta aquí lo que necesitan.
        K4.Puente.tema = Theme
        K4.Puente.idioma = Idioma
        K4.Puente.indicadores = Indicadores
        K4.Puente.audio = Audio
        K4.Puente.medios = Media
        K4.Puente.notificaciones = Notifs
        K4.Puente.wifi = Wifi
        K4.Puente.bluetooth = Bt
        K4.Puente.escritorios = Workspaces
        K4.Puente.portapapeles = Clipboard
        K4.Puente.reloj = Clock
        K4.Puente.enganches = Enganches
        K4.Puente.isla = Island
        K4.Puente.huella = Huella
        K4.Puente.consola = Consola

        void Audio.volume
        void Wifi.name
        void Bt.adapter
        void Notifs.count
        void Media.hasPlayer
        void Clock.date
        void Workspaces.list
        void Weather.located
        void Tray.count
        void Game.cargado
        void Idioma.cargado
        void Settings.cargado
        void PluginManager.cargado
        void Tokens.cargado
        void Clipboard.cargado
        void Ventanas.count
        void Captura.carpetaFotos
        void Modulos.count
    }

    // ── IPC ───────────────────────────────────────────────────────
    // Cada módulo publica su propio target (k4.panel, k4.ask, k4.launcher).
    // Esto es la capa de compatibilidad: mantiene el target `k4` con los
    // nombres de siempre para no romper los atajos ya configurados.
    //  Atajo del registro: el plugin vivo con ese id, o null si está
    //  deshabilitado o roto. Con `?.` detrás, llamar a uno apagado no hace
    //  nada, que es exactamente lo que debe hacer.
    function _p(id) { return PluginManager.instancia(id) }

    IpcHandler {
        target: "k4"
        function toggleLauncher(): void { _p("launcher")?.toggle() }
        function clipboard(): void { _p("clipboard")?.toggle() }
        function system(): void { _p("system")?.toggle() }
        function files(): void { _p("files")?.toggle() }
        function keys(): void { _p("keys")?.toggle() }
        function windows(): void { _p("windows")?.toggle() }
        function install(query: string): void { _p("launcher")?.openPackageSearch(query) }
        function search(query: string): void {
            const l = _p("launcher")
            if (!l)
                return
            if (!l.open)
                l.toggle()
            l.query = query
            l.rebuild()
        }
        function togglePanel(): void { _p("panel")?.toggle("controls") }
        function toggleNotifications(): void { _p("panel")?.toggle("notifications") }
        function pluginEnable(id: string): void { PluginManager.habilitar(id) }
        function pluginDisable(id: string): void { PluginManager.deshabilitar(id) }
        function pluginToggle(id: string): void { PluginManager.alternar(id) }
        function pluginRetry(id: string): void { PluginManager.reintentar(id) }
        function pluginReload(id: string): void { PluginManager.recargar(id) }
        function pluginRefresh(): void { PluginManager.releerCatalogo() }
        //  Devuelve, no imprime. Lo de antes hacía `console.log`, así que el
        //  JSON acababa en el log de Quickshell y quien lo había pedido por
        //  IPC no recibía nada: se podía leer, pero solo si además ibas a
        //  buscar el log. Con tipo de retorno, `quickshell ipc call` lo
        //  escribe en tu terminal, que es lo que uno espera al preguntar.
        function pluginStatus(): string {
            return JSON.stringify(PluginManager.catalogo.map(function (m) {
                return { id: m.id, enabled: PluginManager.estaHabilitado(m.id),
                         error: PluginManager.errores[m.id] || "" }
            }))
        }

        //  Pregunta al registro qué hay más nuevo. Contesta al momento y el
        //  resultado llega después a `PluginManager.novedades`: la respuesta
        //  útil la enseña la barra, aquí solo se dispara.
        function pluginCheck(): void { PluginManager.comprobarNovedades() }
        function wifi(): void { _p("panel")?.openTab("wifi") }
        function bluetooth(): void { _p("panel")?.openTab("bluetooth") }
        function sonido(): void { _p("panel")?.openTab("sonido") }
        function clearNotifications(): void { Notifs.clear() }
        function ask(): void {
            const a = _p("ask")
            if (!a)
                return
            if (a.open) a.close()
            else a.openAsk(false)
        }
        function askSelection(): void { _p("ask")?.openAsk(true) }
        function askNow(question: string): void {
            const a = _p("ask")
            if (!a)
                return
            a.openAsk(false)
            a.query = question
            a.send()
        }
        function askFollowUp(question: string): void {
            const a = _p("ask")
            if (!a)
                return
            if (!a.open)
                a.openAsk(false)
            a.query = question
            a.send()
        }
        function askScreen(): void { _p("ask")?.withScreenshot() }
        function askRegion(): void { _p("ask")?.withRegion() }
        function togglePlay(): void { Media.togglePlaying() }
        function nextTrack(): void { Media.siguiente() }
        function prevTrack(): void { Media.anterior() }
        function theme(): void { _p("hyprtheme")?.toggle() }
        function weather(): void { _p("weather")?.toggle() }
        function tray(): void { _p("tray")?.toggle() }
        function game(): void { _p("game")?.toggle() }
        function settings(): void { _p("settings")?.toggle() }
        function session(): void { _p("session")?.toggle() }
        function lock(): void { Sesion.bloquear() }
        function setMode(mode: string): void { Island.debugMode = mode }
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData

            //  La barra vive en el borde que diga Ajustes. El resto del
            //  fichero pregunta `abajo` en vez de repetir la comparación.
            readonly property bool abajo: Settings.posicionBarra === "abajo"

            // Solo la pantalla propietaria enseña la acción global. Las demás
            // siguen con su píldora, que sí pertenece a todos los monitores.
            readonly property var idlePlugin: PluginManager.instancia("idle")
            readonly property bool esPantallaActiva: root.activePlugin
                && root.activePlugin.name !== "idle"
                && panelWindow.screen.name === Island.pantallaActiva
            readonly property var pluginVisible: root.activePlugin
                && (root.activePlugin.name === "idle" || esPantallaActiva)
                ? root.activePlugin : idlePlugin
            //  ── la barra apartada de UNA pantalla ─────────────────────
            //
            //  `activePlugin` es uno solo y global: gana el de más prioridad y
            //  mientras esté activo NADIE más puede activarse, en ninguna
            //  pantalla. Eso vale para un módulo que se abre y se cierra, pero
            //  no para uno que se queda —el modo dual se lleva la barra al
            //  borde de abajo y ahí sigue— porque deja la island de los otros
            //  monitores muerta: ni se despliega ni responde.
            //
            //  Así que apartar la barra deja de ser cosa de ocupar la island.
            //  Un módulo declara `barraApartada` con la pantalla que se lleva y
            //  el sitio que hay que seguir guardándole, y esa pantalla se queda
            //  sin barra sin que el resto se entere. Quien no la declare da
            //  `undefined` y todo sigue como siempre.
            readonly property var apartada: {
                const lista = PluginManager.instancias
                for (let i = 0; i < lista.length; ++i) {
                    const p = lista[i]
                    if (!p.habilitado)
                        continue
                    const a = p.barraApartada
                    if (a && a.pantalla === panelWindow.screen.name)
                        return a
                }
                return null
            }

            //  Apartada es apartada, ocupe la island quien la ocupe.
            //
            //  Antes se hacía la excepción de dejarla salir en cuanto un módulo
            //  se activaba —el lanzador, el portapapeles—, para que su atajo no
            //  pareciese roto. El precio era que la barra REAPARECÍA DE GOLPE
            //  en el sitio donde ya no estaba, sin recorrido y con el dock aún
            //  abajo: dos barras a la vez.
            //
            //  Quien aparta la barra es quien tiene que devolverla, y con su
            //  animación. El contrato de `barraApartada` es ese: si te la
            //  llevas, mira `K4.Isla.ocupadaPor` y tráela cuando alguien la
            //  pida. Un módulo que se abre mientras tanto espera lo que dure el
            //  regreso, y entonces sale con ella.
            readonly property bool sinBarra: apartada !== null

            readonly property int anchoIsla: sinBarra ? 0
                : (pluginVisible ? pluginVisible.islandWidth : 176)
            readonly property int altoIsla: sinBarra ? 0
                : (pluginVisible ? pluginVisible.islandHeight : Theme.baseHeight)

            //  ── qué hace la barra con el sitio del escritorio ─────────
            //
            //  Tres maneras, y las elige el usuario en Ajustes. «reserva» es
            //  lo de siempre: la franja plegada se le quita al escritorio y
            //  ninguna ventana se mete debajo. «encima» no le quita nada —la
            //  píldora flota sobre las ventanas— y «escondida» además la
            //  retira por el borde hasta que hay algo que enseñar.
            //
            //  Y una cuarta que no es un modo sino una REGLA, y por eso se
            //  resuelve a uno de los tres: «completa» reserva como siempre y se
            //  esconde solo mientras una ventana llena esta pantalla. Que es la
            //  queja de verdad —que la barra estorbe cuando estás usando la
            //  pantalla entera— sin perderla el resto del día.
            //
            //  Por pantalla y no global: con dos monitores, el vídeo a pantalla
            //  completa está en uno, y en el otro la barra no molesta a nadie.
            readonly property string modoSitio: Settings.reservaIsla === "completa"
                ? (Workspaces.lleno(panelWindow.screen.name) ? "escondida" : "reserva")
                : Settings.reservaIsla
            readonly property bool flotante: modoSitio !== "reserva"
            readonly property bool seEsconde: modoSitio === "escondida"

            //  Qué cuenta como «está pasando algo»: que la island la tenga
            //  alguien que no sea el reposo. No hay que inventarse un aviso
            //  nuevo — un módulo se activa EXACTAMENTE cuando tiene algo que
            //  enseñar.
            //
            //  Cuáles salen solos, mirado uno a uno y no de memoria: el aviso
            //  de notificación (`Notifs.toastOpen`), el volumen
            //  (`Audio.overlayOpen`), la confirmación de una captura, y
            //  cualquier módulo que abras con su atajo. El reproductor y el
            //  reloj NO: los dos piden `Island.hovered`, así que una canción
            //  que cambia sola no saca la barra — se ve al asomarse, como
            //  siempre.
            //
            //  Y el ratón en el borde cuenta igual: ir a buscarla es pedirla.
            readonly property bool ratonEncima: sobreIsla.hovered || sobreFilo.hovered
            readonly property bool hayQueEnsenar: ratonEncima
                || (!!pluginVisible && pluginVisible.name !== "idle")

            //  Vuelve al instante y se va con retraso. Al revés —irse en cuanto
            //  se cierra lo que había— la barra parpadea cada vez que cruzas el
            //  borde, y quedarse un segundo de más no le estorba a nadie.
            property bool retirada: false

            function repensarRetirada() {
                //  Sin modo escondite no hay nada que retirar, y con la barra
                //  apartada tampoco: ahí manda quien se la llevó.
                if (!seEsconde || sinBarra) {
                    retiroTimer.stop()
                    retirada = false
                } else if (hayQueEnsenar) {
                    retiroTimer.stop()
                    retirada = false
                } else {
                    retiroTimer.restart()
                }
            }

            //  ── asomarse no es abrir, y quién cuenta el tiempo ────────
            //
            //  Rozar el filo trae la barra de vuelta y el ratón queda encima de
            //  la píldora, así que con la regla de siempre —el reloj se activa
            //  al pasar— el roce la abría del todo. Rozar un borde sin querer
            //  no es pedir nada: la píldora asoma, y para que se ABRA hay que
            //  quedarse.
            //
            //  Y quien cuenta ese medio segundo es `ratonEncima`, que incluye
            //  el filo, y NO el hover de la island. Atado solo a la island no
            //  se abría NUNCA dejando el ratón quieto: la barra vuelve y se
            //  mete bajo un puntero que no se ha movido, y sin movimiento Qt no
            //  tiene por qué entregarle un `hovered` nuevo a nadie. El filo, en
            //  cambio, ya estaba debajo del ratón antes de que la barra
            //  volviera, así que su `hovered` es de fiar.
            onRatonEncimaChanged: {
                if (!seEsconde)
                    return
                if (ratonEncima)
                    quedarseTimer.restart()
                else
                    quedarseTimer.stop()
            }

            onHayQueEnsenarChanged: repensarRetirada()
            onSeEscondeChanged: repensarRetirada()
            onSinBarraChanged: repensarRetirada()

            //  Y se cuenta, que hay animaciones que no se paran solas: ver
            //  `aLaVista` en services/Island.qml.
            onRetiradaChanged: Island.publicarVista(screen.name, !retirada)

            Component.onCompleted: {
                repensarRetirada()
                Island.publicarVista(screen.name, !retirada)
            }

            //  Un monitor que se va deja de contar. Si no, su «sí la veo» se
            //  quedaría puesto para siempre y las animaciones seguirían
            //  corriendo por una pantalla que ya no está.
            Component.onDestruction: Island.publicarVista(screen.name, false)

            Timer {
                id: retiroTimer
                interval: 1600
                //  Se vuelve a preguntar al vencer, y no se da por hecho lo que
                //  era verdad al armarlo: entre medias ha podido volver el
                //  ratón, o el dual llevarse la barra abajo.
                onTriggered: panelWindow.retirada = panelWindow.seEsconde
                    && !panelWindow.sinBarra && !panelWindow.hayQueEnsenar
            }

            anchors.top: !abajo
            anchors.bottom: abajo
            anchors.left: true
            anchors.right: true
            color: "transparent"
            aboveWindows: true
            focusable: true

            //  Exclusivo solo para lo que se escribe; el resto, bajo demanda.
            //  Poner Exclusive en todos los módulos abribles dejaba el teclado
            //  secuestrado mientras tuvieras cualquiera abierto: no se podía
            //  escribir en ninguna ventana.
            WlrLayershell.keyboardFocus: {
                //  Con un diálogo del sistema delante, el teclado es suyo.
                //
                //  Apartar la island de la vista no bastaba: seguía teniendo el
                //  foco en exclusiva, así que el selector de ficheros se veía
                //  pero no se podía ni escribir en él ni cerrarlo con Escape.
                if (Island.apartada)
                    return WlrKeyboardFocus.None
                const p = panelWindow.pluginVisible
                if (!p || p !== root.activePlugin || p.name === "idle")
                    return WlrKeyboardFocus.None
                if (p.grabKeyboard)
                    return WlrKeyboardFocus.Exclusive
                //  El punto medio para los juegos: exclusivo mientras el ratón
                //  esté encima —que es donde se juega— y devuelto al salir.
                //  Wayland no tiene un modo «al pasar», así que se conmuta con
                //  `Island.hovered`, que ya trae su margen de 240 ms y por eso
                //  no parpadea al rozar un borde.
                if (p.tecladoAlPasar && Island.hovered)
                    return WlrKeyboardFocus.Exclusive
                if (p.tecladoOpcional)
                    return WlrKeyboardFocus.OnDemand
                return WlrKeyboardFocus.None
            }

            //  Se reserva solo la franja plegada: las ventanas nunca se meten
            //  bajo la píldora, y todo lo que crece por encima flota.
            //
            //  Salvo que no haya píldora. Un módulo puede pedir la island de
            //  alto CERO, que es como se dice «ahora mismo aquí no hay barra»
            //  —lo usa el modo dual, que se lleva la barra al borde de abajo—,
            //  y entonces seguir quitándole 34 px al escritorio sería cobrar
            //  por una franja que no se ve.
            //  Y quien lo decide es el módulo, no su altura.
            //
            //  Atado a `altoIsla > 0`, la franja se soltaba en el instante en
            //  que un módulo pedía la island a cero, y el escritorio entero
            //  pegaba un salto ANTES de que hubiera pasado nada. Quien manda la
            //  barra de viaje sabe cuándo ya no hace falta guardarle el sitio;
            //  la barra, no.
            //
            //  Se lee sin que el contrato la declare: un plugin que no la
            //  define da `undefined`, que no es `false`, así que reserva —el
            //  comportamiento de siempre para los otros veintisiete—.
            //  En PÍXELES, para que quien la mande pueda soltarla poco a poco
            //  y el escritorio acompañe en vez de pegar un salto.
            //  Y por encima de todo eso manda Ajustes: quien ha dicho que la
            //  barra no le quite sitio no lo ha dicho a medias, así que
            //  «encima» y «escondida» le ganan también a lo que pida un módulo.
            //  Incluida la franja que el dual guarda para el viaje al dock: si
            //  nunca se reservó nada, empezar a reservarlo justo al bajar la
            //  barra sería un salto del escritorio salido de la nada.
            exclusiveZone: panelWindow.flotante ? 0
                : (panelWindow.sinBarra
                   ? (panelWindow.apartada.reserva || 0)
                   : (panelWindow.pluginVisible
                      && typeof panelWindow.pluginVisible.reservaBarra === "number"
                      ? panelWindow.pluginVisible.reservaBarra : Theme.baseHeight))

            // Redimensionar una layer surface cuesta un ciclo configure/ack, así
            // que hacerlo por frame es lo que hacía parpadear el panel. La
            // superficie crece una vez al empezar y encoge una vez al acabar;
            // entre medias solo se anima la island dentro de ella.
            //  El +44 durante un gesto: el empujón baja la island entera y sin
            //  ese margen los píxeles desplazados se recortan contra el borde
            //  de la superficie. Crece al empezar el gesto y el encogido lo
            //  recoge el mismo temporizador de siempre.
            readonly property int targetHeight: Math.min(Theme.maxIslandHeight,
                panelWindow.altoIsla + 2 + (island.gestoEnCurso ? 44 : 0))
            property int surfaceHeight: targetHeight

            onTargetHeightChanged: {
                if (targetHeight > surfaceHeight)
                    surfaceHeight = targetHeight
                else
                    surfaceShrinkTimer.restart()
            }

            Timer {
                id: surfaceShrinkTimer
                interval: 520
                onTriggered: panelWindow.surfaceHeight = panelWindow.targetHeight
            }

            implicitHeight: surfaceHeight
            //  Sin la island, la ventana no acepta ni un clic.
            //
            //  No basta con dejar de dibujarla: la región de entrada seguía
            //  siendo la suya, así que un selector de ficheros que le quedara
            //  debajo perdía todos los clics de esa franja sin que se viera por
            //  qué. Con la región vacía, el ratón pasa de largo.
            //  Y escondida, lo que recibe el ratón es el filo y no la island.
            //  La island NO se ha movido —lo que se desplaza es su dibujo—, así
            //  que dejarla de región de entrada sería seguir tragándose los
            //  clics de una barra que no se ve.
            //
            //  Pero el filo entra SIEMPRE que la barra se esconda, no solo
            //  mientras está fuera, y eso es lo que arregla el agujero de los
            //  360 ms del regreso: la región de una `Region { item }` sigue a
            //  la TRANSFORMADA del item, así que mientras la island vuelve su
            //  región todavía está fuera de la pantalla. En ese rato la
            //  superficie no recibía nada: el puntero se lo quedaba la ventana
            //  de debajo —salía su cursor de redimensionar, pegado al borde— y
            //  la barra que acababa de volver no se enteraba de tener el ratón
            //  encima. Con el filo dentro, el puntero no se va nunca.
            mask: Region {
                item: Island.apartada ? null : island

                Region {
                    item: (Island.apartada || panelWindow.sinBarra
                           || !panelWindow.seEsconde) ? null : filo
                    intersection: Intersection.Combine
                }
            }

            //  ── el filo: por dónde se la llama cuando no está ─────────
            //
            //  Retirada, no hay pastilla que rozar para traerla de vuelta. Esta
            //  tira invisible del borde es lo que se roza.
            //
            //  Del ANCHO DE LA PÍLDORA y no de la pantalla entera, que es la
            //  diferencia entre un escondite y una barra que estorba sin verse:
            //  una tira de punta a punta se traga los clics de todo el borde
            //  —las pestañas del navegador, la cruz de una ventana maximizada—
            //  y eso no lo ha pedido nadie.
            Item {
                id: filo
                x: island.x
                width: island.width
                height: 4
                anchors.top: panelWindow.abajo ? undefined : parent.top
                anchors.bottom: panelWindow.abajo ? parent.bottom : undefined
                //  Invisible, pero NO `visible: false`: un item oculto no
                //  recibe ratón, y recibirlo es para lo único que existe.
                opacity: 0

                //  Sigue contando con la barra ya fuera, a propósito. Al
                //  volver, la island tapa el filo sin que el ratón se haya
                //  movido —y sin movimiento nadie garantiza que le llegue un
                //  `hovered` nuevo—, así que si el filo dejase de contar en ese
                //  instante la barra se iría otra vez con el ratón encima.
                HoverHandler { id: sobreFilo }
            }

            Item {
                id: island
                anchors.top: panelWindow.abajo ? undefined : parent.top
                anchors.bottom: panelWindow.abajo ? parent.bottom : undefined

                // Ver services/Island.qml: apartarse para las capturas y
                // mientras haya un diálogo del sistema abierto.
                opacity: Island.apartada ? 0 : 1

                //  Ya no siempre al centro: la island vive en el punto del
                //  borde que digan Ajustes, o donde la coloque temporalmente
                //  un plugin (services/Island.qml).
                //
                //  Se anima la FRACCIÓN y no la x: la x es cálculo directo,
                //  así que al cambiar el ancho se recoloca en el mismo frame
                //  —como hacía el ancla al centro— y no va a remolque con su
                //  propia animación, que era lo que descentraba la island al
                //  abrir y cerrar módulos.
                property real fraccionSuave: Island.colocacion
                x: (parent.width - width) * fraccionSuave
                width: Math.min(parent.width, panelWindow.anchoIsla + Theme.wing * 2)
                height: panelWindow.altoIsla

                Behavior on fraccionSuave {
                    NumberAnimation {
                        duration: 440
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.42
                    }
                }

                readonly property real bodyRadius: Math.min(32, height / 2)

                // ESC cierra el módulo que esté abierto, sea cual sea.
                //
                // Va aquí y no en cada vista por dos razones: los módulos que
                // vengan después lo heredan sin hacer nada, y las vistas que ya
                // tratan la tecla —el lanzador, el portapapeles, la clave de
                // wifi— la consumen antes de llegar hasta aquí, que es
                // justamente lo que se quiere: primero cancela lo de dentro y
                // solo después cierra el módulo.
                focus: true

                //  Y pedirlo de verdad una vez, que `focus: true` a secas no
                //  basta: hasta que ALGUIEN dentro de esta ventana toma el
                //  foco activo, no hay foco activo, y las teclas que llegan a
                //  la capa no las recibe nadie. Se veía así: el ESC no cerraba
                //  ningún módulo hasta que abrías el lanzador —que sí lo pide,
                //  para su campo de texto— y a partir de ahí funcionaba para
                //  siempre. Un atajo que empieza a ir cuando has usado otra
                //  cosa es peor que uno que no va: parece cosa tuya.
                //
                //  Va una vez al crearse —en el `Component.onCompleted` de
                //  abajo, que uno por objeto o el QML no carga— y antes de que
                //  exista ninguna vista, así que no le quita el foco a nadie:
                //  quien lo quiera lo pide después y gana.
                //
                //  Y hay que RECUPERARLO, que es la otra mitad. Cuando el que
                //  lo tenía se va sin devolverlo —un campo que se oculta al
                //  cerrar su buscador, una vista que se destruye— la ventana
                //  se queda sin foco activo y a partir de ahí el ESC no lo
                //  recibe nadie otra vez. Se vigila quién lo tiene y, cuando
                //  no lo tiene nadie, vuelve aquí. Solo cuando no hay nadie:
                //  si alguien lo pidió, es suyo.
                readonly property var focoVentana: island.Window.activeFocusItem

                onFocoVentanaChanged: if (!focoVentana) Qt.callLater(reclamarFoco)

                function reclamarFoco() {
                    if (!island.Window.activeFocusItem)
                        island.forceActiveFocus()
                }

                Keys.onPressed: function (ev) {
                    if (ev.key !== Qt.Key_Escape)
                        return
                    const p = panelWindow.pluginVisible
                    if (p && typeof p.close === "function") {
                        p.close()
                        ev.accepted = true
                    }
                }

                Behavior on width {
                    NumberAnimation {
                        duration: 440
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.42
                    }
                }

                Behavior on height {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.32
                    }
                }

                // ── geometría publicada, para pintar fuera de la island ──
                //
                //  K4.Isla.rect: coordenadas de pantalla, solo la principal.
                //  Un plugin con K4.Ventana ancla aquí lo que asoma.
                onXChanged: publicarRect()
                onWidthChanged: publicarRect()
                onHeightChanged: publicarRect()
                Component.onCompleted: {
                    publicarRect()
                    forceActiveFocus()      // el ESC de arriba; ver por qué
                }

                function publicarRect() {
                    Island.publicarRect(panelWindow.screen.name, {
                        x: island.x,
                        y: panelWindow.abajo
                            ? panelWindow.screen.height - island.height : 0,
                        ancho: island.width, alto: island.height
                    }, panelWindow.modelData === Quickshell.screens[0])
                }

                Connections {
                    target: Settings
                    function onPosicionBarraChanged() { island.publicarRect() }
                }

                // ── gestos: el plugin pide (services/Island.qml), esto anima ──
                //
                //  Un desplazamiento del contenido, nunca de la ventana: mover
                //  una layer surface reajustaría el escritorio entero.
                transform: [
                    Translate { id: gestoTr },
                    //  ── y el escondite, por el mismo camino ──────────
                    //
                    //  La que se retira se va POR EL BORDE, y también
                    //  desplazando su dibujo: encoger la superficie o soltar el
                    //  ancla movería el escritorio entero cada vez, que es
                    //  justo lo que este modo viene a no hacer.
                    Translate {
                        id: retiroTr
                        y: panelWindow.retirada
                            ? (panelWindow.abajo ? island.height + 6
                                                 : -(island.height + 6))
                            : 0

                        //  La misma curva en los dos sentidos, y no una por
                        //  sentido atada a `retirada`: la `y` se recalcula
                        //  ANTES que la duración y la curva —el binding es más
                        //  viejo, se conecta primero— así que cada tránsito
                        //  habría salido con los valores del anterior.
                        //
                        //  Y SIN rebote, que aquí el rebote de la casa está
                        //  mal. `OutBack` se pasa del destino y vuelve, y el
                        //  destino es cero: pasarse de cero es separarse del
                        //  borde. La silueta lleva esquinas invertidas para
                        //  FUNDIRSE con el canto de la pantalla, así que ese
                        //  píxel de aire al llegar no se lee como un rebote
                        //  sino como un salto y una raya. Comprobado a ojo: se
                        //  veía. Lo que se quiere es que frene, no que bote.
                        Behavior on y {
                            NumberAnimation {
                                duration: 360
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                ]

                readonly property bool gestoEnCurso: aniSacudida.running
                    || aniEmpujon.running || aniTiron.running

                SequentialAnimation {
                    id: aniSacudida
                    property real f: 1
                    NumberAnimation { target: gestoTr; property: "x"; to: -8 * aniSacudida.f; duration: 40 }
                    NumberAnimation { target: gestoTr; property: "x"; to: 7 * aniSacudida.f; duration: 70 }
                    NumberAnimation { target: gestoTr; property: "x"; to: -5 * aniSacudida.f; duration: 70 }
                    NumberAnimation { target: gestoTr; property: "x"; to: 3 * aniSacudida.f; duration: 60 }
                    NumberAnimation { target: gestoTr; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
                }

                //  Los gestos verticales empujan hacia DENTRO de la pantalla:
                //  con la barra abajo, el empujón y el tirón van hacia arriba.
                readonly property real gestoDir: panelWindow.abajo ? -1 : 1

                SequentialAnimation {
                    id: aniEmpujon
                    property real f: 1
                    NumberAnimation { target: gestoTr; property: "y"; to: 26 * aniEmpujon.f * island.gestoDir; duration: 150; easing.type: Easing.OutQuad }
                    NumberAnimation { target: gestoTr; property: "y"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                }

                SequentialAnimation {
                    id: aniTiron
                    property real f: 1
                    NumberAnimation { target: gestoTr; property: "y"; to: 10 * aniTiron.f * island.gestoDir; duration: 90; easing.type: Easing.OutQuad }
                    NumberAnimation { target: gestoTr; property: "y"; to: 2 * island.gestoDir; duration: 90 }
                    NumberAnimation { target: gestoTr; property: "y"; to: 12 * aniTiron.f * island.gestoDir; duration: 90 }
                    NumberAnimation { target: gestoTr; property: "y"; to: 0; duration: 140; easing.type: Easing.OutQuad }
                }

                Connections {
                    target: Island
                    function onGesto(nombre, fuerza) {
                        //  Corta el que hubiera: dos gestos a la vez son un
                        //  temblor sin forma.
                        aniSacudida.stop(); aniEmpujon.stop(); aniTiron.stop()
                        gestoTr.x = 0; gestoTr.y = 0
                        if (nombre === "sacudida") { aniSacudida.f = fuerza; aniSacudida.start() }
                        else if (nombre === "empujon") { aniEmpujon.f = fuerza; aniEmpujon.start() }
                        else if (nombre === "tiron") { aniTiron.f = fuerza; aniTiron.start() }
                    }
                }

                //  ── asomarse no es abrir ──────────────────────────
                //
                //  Lo que hace que pasar el ratón despliegue la island: el
                //  reloj se activa con `Island.hovered`. Se separa del gesto
                //  para poder retrasarlo, que es lo único que cambia aquí.
                function abrirPorRaton() {
                    if (!root.activePlugin || root.activePlugin.name === "idle")
                        Island.pedirPantalla(panelWindow.screen.name)
                    else if (root.activePlugin.name === "clock"
                             || root.activePlugin.name === "player")
                        Island.usarPantalla(panelWindow.screen.name)
                    Island.hovered = true
                }

                HoverHandler {
                    id: sobreIsla
                    onHoveredChanged: {
                        if (hovered) {
                            //  Esto va SIEMPRE al instante: no abre nada, solo
                            //  impide que se cierre lo que ya estaba. Retrasarlo
                            //  dejaría irse un aviso mientras vas hacia él.
                            hoverExitTimer.stop()
                            root.holdHoverExit()
                            Notifs.holdToast()

                            //  Escondida, el reloj de la espera no lo lleva
                            //  esto: lo lleva `ratonEncima` en panelWindow, que
                            //  cuenta también el filo. Ver por qué allí.
                            //
                            //  Salvo que ya haya algo puesto. La espera existe
                            //  para que rozar un borde VACÍO no despliegue el
                            //  reloj; si la island ya está fuera enseñando algo
                            //  —un aviso, el asomo del reproductor—, ir hacia
                            //  ella es ir a por eso, y hacerte esperar medio
                            //  segundo es perder el tiempo justo cuando lo que
                            //  quieres se está yendo. Con asomos de tres
                            //  segundos, ese medio segundo era la diferencia
                            //  entre alcanzarlo y verlo desaparecer.
                            const enReposo = !panelWindow.pluginVisible
                                || panelWindow.pluginVisible.name === "idle"
                            if (!panelWindow.seEsconde || !enReposo)
                                island.abrirPorRaton()
                        } else {
                            hoverExitTimer.restart()
                            root.armHoverExit()
                            Notifs.resumeToast()
                        }
                    }
                }

                //  Medio segundo: más que un roce, menos que una espera.
                Timer {
                    id: quedarseTimer
                    interval: 500
                    onTriggered: island.abrirPorRaton()
                }

                // clic derecho en cualquier parte → centro de control
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.abrirPanelEn(panelWindow.screen.name)
                }

                // ── la silueta: cuerpo + esquinas invertidas que funden con el borde
                Shape {
                    id: silueta
                    anchors.fill: parent
                    // CurveRenderer suaviza mejor, pero descarta las esquinas
                    // invertidas (las alas), así que se antialiasa con MSAA.
                    antialiasing: true
                    layer.enabled: true
                    layer.samples: 8
                    layer.smooth: true

                    //  Con la barra abajo, la silueta entera se refleja: las
                    //  alas pasan a fundirse con el borde inferior sin tocar
                    //  ni un punto del trazado.
                    transform: Scale {
                        origin.y: silueta.height / 2
                        yScale: panelWindow.abajo ? -1 : 1
                    }

                    ShapePath {
                        id: islandPath
                        fillColor: Theme.islandBg
                        strokeWidth: 0
                        strokeColor: "transparent"

                        readonly property real w: island.width
                        readonly property real h: island.height
                        readonly property real r: island.bodyRadius
                        readonly property real g: Math.min(Theme.wing, island.height / 2)

                        startX: 0
                        startY: 0

                        // esquina invertida izquierda
                        PathArc {
                            x: islandPath.g
                            y: islandPath.g
                            radiusX: islandPath.g
                            radiusY: islandPath.g
                            direction: PathArc.Clockwise
                        }

                        PathLine { x: islandPath.g; y: islandPath.h - islandPath.r }

                        // inferior izquierda
                        PathArc {
                            x: islandPath.g + islandPath.r
                            y: islandPath.h
                            radiusX: islandPath.r
                            radiusY: islandPath.r
                            direction: PathArc.Counterclockwise
                        }

                        PathLine { x: islandPath.w - islandPath.g - islandPath.r; y: islandPath.h }

                        // inferior derecha
                        PathArc {
                            x: islandPath.w - islandPath.g
                            y: islandPath.h - islandPath.r
                            radiusX: islandPath.r
                            radiusY: islandPath.r
                            direction: PathArc.Counterclockwise
                        }

                        PathLine { x: islandPath.w - islandPath.g; y: islandPath.g }

                        // esquina invertida derecha
                        PathArc {
                            x: islandPath.w
                            y: 0
                            radiusX: islandPath.g
                            radiusY: islandPath.g
                            direction: PathArc.Clockwise
                        }

                        PathLine { x: 0; y: 0 }
                    }
                }

                // ── zona de contenido (dentro del cuerpo, sin las alas)
                Item {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.wing
                    anchors.rightMargin: Theme.wing
                    clip: true

                    // Debajo de toda vista: los botones y sliders se quedan sus
                    // clics, lo que no coja nadie cae aquí.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.backgroundTap(panelWindow.screen.name,
                                                      panelWindow.pluginVisible)
                    }

                    // Se dispone al tamaño final y se destapa con el clip, así
                    // que no hay recálculo de layout durante la animación.
                    Item {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: panelWindow.anchoIsla
                        height: panelWindow.altoIsla

                        Repeater {
                            //  Las instancias vivas del gestor. Cuando esto
                            //  era `root.plugins` y la lista se fue, el modelo
                            //  quedó indefinido y la island se abría NEGRA:
                            //  cero delegates, cero vistas, sin un solo error.
                            model: PluginManager.instancias

                            delegate: Loader {
                                required property var modelData
                                anchors.fill: parent
                                active: modelData === panelWindow.pluginVisible
                                    && modelData.viewLoaded
                                sourceComponent: modelData.view
                                onStatusChanged: {
                                    if (status === Loader.Error)
                                        PluginManager.registrarError(
                                            modelData.name, "No se pudo cargar la vista")
                                    else if (status === Loader.Ready)
                                        PluginManager.limpiarError(modelData.name)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: hoverExitTimer
        interval: 240
        onTriggered: Island.hovered = false
    }

    // ── salida del ratón ──────────────────────────────────────────
    // Los módulos que se abren con el ratón se van al sacarlo, pero cada uno
    // decide qué hacer: aquí solo se cuenta el tiempo y se avisa al activo.
    function armHoverExit() {
        const p = activePlugin
        if (!p || !p.closeOnHoverExit)
            return

        pluginHoverExitTimer.interval = p.hoverExitDelay
        pluginHoverExitTimer.restart()
    }

    function holdHoverExit() { pluginHoverExitTimer.stop() }

    Timer {
        id: pluginHoverExitTimer
        interval: 700
        onTriggered: {
            const p = root.activePlugin
            if (p && p.closeOnHoverExit)
                p.hoverTimedOut()
        }
    }

}
