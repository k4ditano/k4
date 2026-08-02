//  La terminal de la casa, vista desde la barra.
//
//  k4term vive fuera (Rust, libghostty + GPUI) y esta es su embajada: abre
//  ventanas por IPC y convierte en aviso lo que la terminal cuenta.
//
//  El plugin no ocupa la island nunca. Es una pieza de servicio con forma de
//  plugin, y está bien así: se enciende y se apaga desde Ajustes como todo lo
//  demás, y su target de IPC se desregistra solo al apagarlo.
//
//      quickshell ipc -p shell.qml call k4.term abrir
//      quickshell ipc -p shell.qml call k4.term aqui
//      quickshell ipc -p shell.qml call k4.term ejecutar "yay -Syu"

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "terminal"
    title: Idioma.t("Terminal")
    //  Por encima del reproductor y del reloj, por debajo del lanzador: si
    //  estás escribiendo en ella, ninguna canción te la quita.
    priority: 75
    active: abierto

    //  ── la terminal de la island ──────────────────────────────────
    //
    //  Para lo rápido: un `systemctl restart`, un `git status`, mirar cómo va
    //  algo. La sesión vive en k4term-isla, fuera de la barra, así que cerrar
    //  la vista no para nada y volver a abrirla te devuelve donde estabas.
    property bool abierto: false
    property bool arrancado: false
    property var marco: null

    //  Cuántos fantasmas deja el cursor al moverse. No es una decisión de la
    //  barra: lo dice la sesión, que lee los ajustes de k4term y los vigila.
    //  Así la estela de la island y la de la ventana son la misma cosa
    //  tocando un solo sitio, en vez de dos parecidas que se separan.
    property int estela: 8

    //  Con qué letra se pinta la rejilla. Lo dice la sesión, que lee los
    //  ajustes de k4term, para que la isla y la ventana usen LA MISMA. Con la
    //  de iconos de la barra no vale: es la variante ancha de la Nerd Font, y
    //  medir la celda con ella deja el cursor separándose del texto.
    property string fuente: "MesloLGS Nerd Font Mono"
    property int cuerpo: 13

    grabKeyboard: abierto
    islandWidth: 900

    //  La island crece con lo que hay dentro, que es lo que se espera de
    //  ella: un `ls` de tres líneas no tiene por qué abrir un cajón de medio
    //  monitor.
    //
    //  Ojo al lazo, que es la trampa de esto: la island decide cuántas filas
    //  tiene el PTY, así que «lo escrito» nunca puede pasar de lo que cabe y
    //  medir el contenido para decidir el tamaño no lleva a ninguna parte.
    //  Lo que funciona es al revés: se abre pequeña y se ensancha cuando se
    //  LLENA, y se recoge cuando se queda medio vacía —después de un `clear`,
    //  por ejemplo—. Con margen entre las dos condiciones para que no baile.
    //
    //  La medida de la letra se toma AQUÍ y la vista la usa de aquí, aunque
    //  quien pinta es ella. Tenerla en los dos sitios costó caro: el alto de
    //  la island se calculaba con 18 y la vista dividía por la métrica de
    //  verdad, 17. Salía una fila más de las que cabían, o sea que `usadas`
    //  nunca llegaba a `filas_n`, o sea que la condición de crecer no se
    //  cumplía NUNCA: la island se quedaba en su tamaño mínimo para siempre y
    //  un programa de pantalla completa —claude, vim— se pintaba aplastado en
    //  siete filas con el cursor al fondo de la caja.
    //
    //  El margen y el pie ocupan lo que ocupan; el resto son filas enteras.
    readonly property int chrome: 40
    readonly property real altoLinea: Math.ceil(metricas.height)

    //  El ancho de celda, en píxeles ENTEROS y recalculado cuando cambia la
    //  letra. Las dos primeras líneas del bloque no sobran, y costaron caro:
    //  `advanceWidth` es una FUNCIÓN, y un enlace de QML solo se reevalúa
    //  cuando cambia una PROPIEDAD que haya leído. Sin nombrar la familia y el
    //  cuerpo, esto se calculaba UNA vez —con la fuente todavía sin resolver—
    //  y se quedaba con el ancho de la tipografía de reserva para siempre:
    //  13,8 px de celda para una letra que mide 7,8. El texto se pintaba a su
    //  ancho y el cursor a casi el doble, así que se separaba hacia la derecha
    //  cuanto más larga era la línea.
    //
    //  Y entero porque así se pinta: con `NativeRendering` los avances se
    //  redondean a píxel, o sea que una celda fraccionaria no la respeta nadie.
    readonly property real anchoCelda: {
        const _familia = metricas.font.family
        const _cuerpo = metricas.font.pixelSize
        return Math.max(1, Math.round(metricas.advanceWidth("M")))
    }

    property FontMetrics metricas: FontMetrics {
        font.family: self.fuente
        font.pixelSize: self.cuerpo
    }

    readonly property int filasMinimas: 6
    readonly property int filasMaximas: 26

    //  Crecer y recoger, a ritmo constante y con UN solo número.
    //
    //  Antes esto iba a empujones: cada marco que llegaba lleno subía el
    //  destino unas filas y una animación corría detrás. Y se veía, porque el
    //  destino solo se mueve cuando llega un marco —cada 30 a 120 ms—: la
    //  animación llegaba, se paraba y esperaba al siguiente empujón. Medido en
    //  una sola crecida: 555, 111, 938 y 733 px/s. Eso es la escalera.
    //
    //  Peor era lo otro: el alto animado y las filas del PTY se calculaban por
    //  separado, así que la caja y el texto de dentro no se movían a la vez —
    //  encogía uno y luego el otro.
    //
    //  Ahora hay un solo número, `filasReales`, que avanza hacia `objetivo` a
    //  ritmo fijo. De él salen LAS DOS COSAS: el alto de la island y las filas
    //  que se le piden a la sesión. Al salir del mismo sitio no pueden ir
    //  desacompasados, y al avanzar de continuo no hay escalones.
    //  Crecer es una cosa y recoger es otra. Crecer acompaña a algo que está
    //  pasando —la salida del mandato llegando— y quiere ir a su ritmo. Al
    //  recoger ya no hay nada que mirar: lo que sobra es hueco vacío, y
    //  arrastrarlo a la misma velocidad se hace largo.
    readonly property real filasPorSegundo: 22
    readonly property real filasPorSegundoAlRecoger: 65
    property real velocidad: filasPorSegundo

    property real objetivo: filasMinimas
    property real filasReales: objetivo
    readonly property int filasDeseadas: Math.max(filasMinimas, Math.round(filasReales))

    //  Lo mueve el motor de animación y no un Timer, y no es un detalle: un
    //  Timer de 16 ms no dispara a sesenta por segundo —medido, salía a menos
    //  de la mitad del ritmo pedido—, mientras que esto va con el refresco de
    //  la pantalla.
    //
    //  Y en `Behavior`, no en `SmoothedAnimation on`: esa segunda forma corre
    //  UNA vez y al terminar se apaga, así que cambiar el destino después no
    //  hacía nada. Se vio claro — la island crecía hasta la mitad y se
    //  plantaba ahí.
    Behavior on filasReales { SmoothedAnimation { velocity: self.velocidad } }

    onMarcoChanged: {
        if (!marco)
            return
        //  «Se ha llenado» es llegar a la última fila o a la penúltima. Lo de
        //  la penúltima no es una concesión: un programa de pantalla completa
        //  se ajusta SIEMPRE al hueco que le das, así que nunca se desborda y
        //  nunca pide más — y si su última fila queda en blanco, como el
        //  diálogo de claude, con la condición estricta la island no crecería
        //  jamás y el programa se quedaría apretado para siempre.
        if (marco.usadas >= marco.filas_n - 1) {
            //  Mientras siga llena, hacia arriba sin parar. En cuanto deje de
            //  estarlo se queda donde esté: no hay destino que perseguir a
            //  saltos, solo una dirección.
            recoger.stop()
            velocidad = filasPorSegundo
            objetivo = filasMaximas
        } else if (marco.usadas * 2 <= marco.filas_n && filasReales > filasMinimas) {
            //  Vaciada del todo —un `clear`, salir de un programa— se recoge
            //  YA: no hay nada que confirmar, y esperar ahí es lo que se
            //  sentía como un retraso raro antes de que la caja reaccionara.
            //
            //  Medio vacía es otra cosa y esa sí espera un poco: al pulsar
            //  Intro la pantalla se queda un instante con menos de lo que
            //  tenía antes de que llegue la salida del mandato, y reaccionar a
            //  ese hueco daba un tirón hacia abajo justo antes de crecer
            //  —medido: 26 px de bajada y 73 de subida a continuación—. Con
            //  esperar dos marcos basta para distinguirlo.
            if (marco.usadas <= 2) {
                recoger.stop()
                encoger()
            } else {
                objetivo = filasReales
                recoger.restart()
            }
        } else {
            recoger.stop()
            objetivo = filasReales
        }
    }

    function encoger() {
        velocidad = filasPorSegundoAlRecoger
        objetivo = Math.max(filasMinimas, marco.usadas + 2)
    }

    Timer {
        id: recoger
        interval: 180
        onTriggered: {
            if (!self.marco)
                return
            if (self.marco.usadas * 2 <= self.marco.filas_n
                    && self.filasReales > self.filasMinimas)
                self.encoger()
        }
    }

    //  Cada sesión nueva empieza recogida.
    onArrancadoChanged: if (!arrancado) { filasReales = filasMinimas; objetivo = filasMinimas }

    //  Sin animación por encima: `filasReales` YA se mueve de continuo, y
    //  ponerle una animación detrás solo añadiría un retardo entre el alto y
    //  las filas que se le piden a la sesión, que es justo lo que hacía que la
    //  caja y el texto no fueran al unísono.
    islandHeight: Math.min(560, chrome + filasReales * altoLinea)
    closeOnHoverExit: false
    handlesBackgroundTap: true
    onBackgroundTapped: {}

    view: Component { TerminalIslaView { plugin: self } }

    function mandar(orden) {
        if (arrancado)
            sesion.escribir(JSON.stringify(orden) + "\n")
    }

    function cerrar() { abierto = false }

    //  ── correr un mandato de la casa aquí dentro ──────────────────
    //
    //  Actualizar el sistema abría una ventana aparte. Teniendo esto, lo suyo
    //  es verlo en la island: se asoma sola, lo enseña, y si la cierras el
    //  mandato sigue corriendo — que es justo para lo que sirve una sesión que
    //  no depende de la vista.
    //
    //  Se ofrece a Consola en vez de que Consola nos busque: un servicio no
    //  puede depender de que un plugin exista, y este se apaga desde Ajustes
    //  como cualquier otro. Al apagarlo se retira la oferta y todo vuelve a
    //  abrirse en ventana.
    Component.onCompleted: Consola.registrarIsla(function (guion) {
        self.correrAqui(guion)
    })
    Component.onDestruction: Consola.registrarIsla(null)

    function correrAqui(guion) {
        if (!Consola.hayIsla) {
            K4.Sistema.lanzar(Consola.orden(guion))
            return
        }
        const yaEstaba = arrancado
        arrancado = true
        abierto = true
        mandar({ que: "pinta" })
        //  Si la sesión acaba de nacer hay que dejar que la shell saque su
        //  prompt: el texto que llegue antes lo repite el tty en crudo y se ve
        //  el mandato dos veces, una suelta arriba y otra en su sitio.
        if (yaEstaba)
            escribirMandato(guion)
        else {
            pendiente = guion
            esperarPrompt.restart()
        }
    }

    property string pendiente: ""

    function escribirMandato(guion) {
        //  Ctrl-U delante: si habías dejado algo a medio escribir, el mandato
        //  se pegaría detrás y saldría un engendro.
        mandar({ que: "texto", valor: String.fromCharCode(0x15) + guion + "\n" })
    }

    Timer {
        id: esperarPrompt
        interval: 450
        onTriggered: {
            if (!self.pendiente)
                return
            self.escribirMandato(self.pendiente)
            self.pendiente = ""
        }
    }

    function toggle() {
        //  Sin k4term-isla no hay mini-terminal —habla un protocolo que es
        //  nuestro— pero tampoco hay por qué no hacer nada: se abre una
        //  ventana con la terminal que haya.
        if (!Consola.hayIsla) {
            K4.Sistema.lanzar(Consola.abrir(""))
            return
        }
        //  La sesión no se arranca hasta que la pides por primera vez: quien
        //  no use la terminal de la island no paga ni un proceso.
        arrancado = true
        abierto = !abierto
        if (abierto)
            mandar({ que: "pinta" })
    }

    //  Sacarla a lo grande: se le pregunta a la sesión dónde está y se abre
    //  una ventana ahí mismo. La sesión de la island NO se mueve —sigue
    //  viva, con lo que estuviera corriendo— porque es suya y de nadie más;
    //  lo que se hereda es el sitio.
    function sacar() {
        if (!arrancado) {
            K4.Sistema.lanzar(Consola.abrir(""))
            return
        }
        sacando = true
        mandar({ que: "donde" })
    }

    property bool sacando: false

    K4.Process {
        id: sesion
        command: ["k4term-isla"]
        running: self.arrancado
        porLineas: true
        entradaAbierta: true
        onLinea: function (linea) {
            let m = null
            try {
                m = JSON.parse(linea)
            } catch (e) {
                return
            }
            if (!m)
                return
            if (m.que === "marco") {
                self.marco = m
                return
            }
            if (m.que === "config") {
                self.estela = m.estela
                if (m.fuente)
                    self.fuente = m.fuente
                if (m.tamano)
                    self.cuerpo = Math.round(m.tamano)
                return
            }
            //  La sesión contesta dónde está: solo interesa si se lo hemos
            //  preguntado para sacarla, no vaya a abrirse una ventana por un
            //  mensaje rezagado.
            if (m.que === "donde" && self.sacando) {
                self.sacando = false
                self.abierto = false
                K4.Sistema.lanzar(Consola.abrir(m.ruta || ""))
            }
        }
        //  Si la sesión se cae —la shell salió con exit— se olvida lo pintado
        //  y la siguiente apertura arranca una nueva.
        onTerminado: {
            self.marco = null
            self.arrancado = false
            self.abierto = false
        }
    }

    //  Despierta a los dos servicios que le hacen falta: un singleton de QML
    //  no se instancia hasta que alguien lo mira. El del ambiente publica el
    //  tema para la terminal —apagar este plugin deja de publicarlo, que es
    //  justo lo que tiene que pasar— y el de la consola averigua qué
    //  terminal hay instalada, que lo necesita hasta el actualizador.
    readonly property string ambiente: Ambiente.ruta
    readonly property string cual: Consola.binario

    //  ── trabajos en curso ─────────────────────────────────────────
    //
    //  Lo que se está cociendo ahora mismo, por pid de la ventana que lo
    //  corre. La terminal solo cuenta los que llevan unos segundos vivos, así
    //  que aquí no llega el ruido de un `ls`: si algo está apuntado, es
    //  porque de verdad merece un hueco en la píldora.
    property var trabajos: ({})

    //  La cuenta va aparte y no calculada del mapa: reasignar a una propiedad
    //  `var` el MISMO objeto que ya tenía no notifica a nadie, y el latido se
    //  quedaba parado con el indicador clavado en cero. De ahí también que
    //  aquí se copie el mapa en vez de tocarlo por dentro.
    property int enCurso: 0

    //  De aquí para arriba, además del indicador, un aviso al terminar.
    readonly property int avisoSegundos: 20

    function idDe(pid) { return "terminal." + pid }

    //  Un reloj de píldora: cabe en dos dedos de ancho y no baila al pasar de
    //  los sesenta, que es lo que importa cuando está al lado de la hora.
    function reloj(ms) {
        const s = Math.max(0, Math.round(ms / 1000))
        if (s < 60)
            return s + " s"
        const m = Math.floor(s / 60)
        return m + ":" + String(s % 60).padStart(2, "0")
    }

    //  `llevaba` son los segundos que el mandato acumulaba cuando la terminal
    //  se decidió a contarlo: el reloj de la píldora arranca ahí y no en cero,
    //  o enseñaría menos tiempo del que de verdad lleva trabajando.
    //  Los agentes de consola son otra cosa que un mandato largo: no están
    //  «tardando», están pensando, y uno los deja correr a propósito. Se les
    //  da su propio glifo para distinguirlos de un vistazo.
    readonly property var agentes: ["claude", "codex", "aider", "gemini", "opencode", "goose"]

    function esAgente(mandato) {
        const primero = String(mandato).trim().split(/\s+/)[0] || ""
        const limpio = primero.split("/").pop()
        return agentes.indexOf(limpio) >= 0
    }

    function apuntar(pid, mandato, llevaba) {
        const t = Object.assign({}, trabajos)
        t[pid] = { mandato: String(mandato),
                   desde: Date.now() - (Number(llevaba) || 0) * 1000 }
        trabajos = t
        enCurso = Object.keys(t).length

        const agente = esAgente(mandato)
        K4.Pildora.registrar(idDe(pid), reloj(0),
                             agente ? Theme.ico.ask.codePointAt(0) : 0xF018D,
                             agente ? Theme.green : Theme.blue, 30, true)
    }

    //  Los que te esperan van con el id aparte: un mandato largo y un agente
    //  que ha acabado su turno son dos cosas distintas y pueden coincidir.
    function idEspera(pid) { return "terminal.espera." + pid }

    function esperando(pid, titulo) {
        const nombre = String(titulo || "").trim() || Idioma.t("Terminal")
        //  La campana del tema: dice «te llaman» sin necesidad de leerlo, y
        //  en amarillo, que reclama sin alarmar.
        K4.Pildora.registrar(idEspera(pid), nombre.slice(0, 18), Theme.ico.bell.codePointAt(0),
                             Theme.yellow, 29, true)
        K4.Sistema.lanzar(["notify-send", "-a", "k4term", "-t", "8000",
                           Idioma.t("Te está esperando"), nombre])
    }

    function olvidar(pid) {
        if (trabajos[pid] === undefined)
            return
        const t = Object.assign({}, trabajos)
        delete t[pid]
        trabajos = t
        enCurso = Object.keys(t).length
        K4.Pildora.quitar(idDe(pid))
    }

    function tictac() {
        const ahora = Date.now()
        for (const pid in trabajos)
            K4.Pildora.actualizar(idDe(pid), { texto: reloj(ahora - trabajos[pid].desde) })
    }

    //  Solo late mientras hay algo que contar: sin trabajos, ni un despertar.
    property Timer latido: Timer {
        interval: 1000
        repeat: true
        running: self.enCurso > 0
        onTriggered: self.tictac()
    }

    //  Pulsar el indicador lleva a la ventana que está trabajando. Se
    //  pregunta primero por ella: si ya no existe —la mataron sin avisar— el
    //  indicador se cura solo, y pulsarlo es el único momento en el que
    //  compensa comprobarlo.
    property Connections clics: Connections {
        target: K4.Pildora
        function onInvocado(id) {
            if (String(id).indexOf("terminal.") !== 0)
                return
            //  Ir a la ventana quita el aviso de que te espera: ya la has
            //  atendido, que es lo que el indicador estaba pidiendo.
            const espera = String(id).indexOf("terminal.espera.") === 0
            const pid = String(id).substring(espera ? "terminal.espera.".length
                                                    : "terminal.".length)
            if (espera)
                K4.Pildora.quitar(id)
            buscar.pid = pid
            buscar.running = true
        }
    }

    //  Trabajos largos: la terminal avisa al terminar y aquí se convierte en
    //  notificación, que es la vía por la que la casa entera enseña avisos.
    //  El mandato se recorta porque un `find` con veinte argumentos no cabe
    //  en un toast y lo que importa es reconocerlo, no leerlo entero.
    function resumir(mandato) {
        const limpio = String(mandato).trim()
        return limpio.length > 48 ? limpio.slice(0, 47) + "…" : limpio
    }

    function duracion(segundos) {
        const s = Math.round(Number(segundos) || 0)
        if (s < 60)
            return s + " s"
        const m = Math.floor(s / 60)
        return m < 60 ? m + " min " + (s % 60) + " s"
                      : Math.floor(m / 60) + " h " + (m % 60) + " min"
    }

    K4.Ipc {
        target: "k4.term"

        //  Sin decir dónde, en tu casa. Hay que ser explícito: lo que se
        //  hereda al lanzar desde aquí es el directorio de la barra, que no
        //  le importa a nadie.
        function abrir(): void {
            K4.Sistema.lanzar(Consola.abrir(K4.Sistema.entorno("HOME")))
        }

        function abrirEn(ruta: string): void {
            K4.Sistema.lanzar(Consola.abrir(ruta))
        }

        //  Donde la casa corra las cosas: la island si la hay, y si no una
        //  ventana. Antes esto abría ventana siempre, y era incoherente con
        //  que Actualizar sí se vea en la island.
        function ejecutar(mandato: string): void {
            if (mandato)
                Consola.ejecutar(mandato)
        }

        //  Lo de la island, a lo grande y en el mismo sitio.
        function sacar(): void { self.sacar() }

        //  Abrir donde estás mirando: se pregunta a Hyprland por la ventana
        //  con foco y se baja por el árbol de procesos hasta el último hijo
        //  —el intérprete que de verdad tiene el directorio— para leerle el
        //  cwd. Si algo falla, cae en abrir sin más.
        function aqui(): void { donde.running = true }

        //  Empieza algo largo: a la píldora. Quien decide qué es «largo» es
        //  la terminal, que es la que tiene el reloj puesto.
        function inicio(pid: string, mandato: string, llevaba: string): void {
            self.apuntar(pid, mandato, llevaba)
        }

        //  Y al acabar: fuera de la píldora, y aviso si de verdad ha llevado
        //  su rato. El indicador aparece antes que el aviso a propósito —
        //  primero enterarse de que trabaja, luego de que terminó.
        function fin(pid: string, mandato: string, salida: string,
                     segundos: string): void {
            self.olvidar(pid)
            if (Number(segundos) >= self.avisoSegundos)
                self.avisar(mandato, salida, segundos)
        }

        //  La ventana se cierra con algo dentro: se lleva su indicador.
        function limpiar(pid: string): void {
            self.olvidar(pid)
            K4.Pildora.quitar(self.idEspera(pid))
        }

        //  La terminal de la island, para lo rápido.
        function isla(): void { self.toggle() }

        //  Una terminal que toca la campana sin tener el foco casi siempre es
        //  un agente que ha terminado su turno y te espera. Se apunta en la
        //  píldora —con su propio glifo, que no es lo mismo que un mandato
        //  largo— y se avisa una vez.
        function campana(pid: string, titulo: string): void {
            self.esperando(pid, titulo)
        }

        //  Un recado suelto de la terminal: no tiene dónde decir «guardado»
        //  sin taparse a sí misma, y la isla sí.
        function decir(titulo: string, cuerpo: string): void {
            K4.Sistema.lanzar(["notify-send", "-a", "k4term", "-t", "5000",
                               titulo, cuerpo])
        }
    }

    function avisar(mandato, salida, segundos) {
        const fallo = String(salida) !== "0"
        const cuerpo = resumir(mandato) + " · " + duracion(segundos)
        K4.Sistema.lanzar(["notify-send", "-a", "k4term",
                           fallo ? "-u" : "-t", fallo ? "critical" : "6000",
                           fallo ? Idioma.t("Falló el mandato") + " (" + salida + ")"
                                 : Idioma.t("Mandato terminado"),
                           cuerpo])
    }

    //  ── los ajustes de k4term, en los Ajustes de la casa ──────────
    //
    //  k4term los lee de ~/.config/k4term/k4term.conf y los sigue en
    //  caliente, así que tocar aquí un interruptor se ve en las ventanas
    //  abiertas sin reabrir nada. Se escribe LÍNEA A LÍNEA y no el fichero
    //  entero a propósito: quien lo haya editado a mano tiene derecho a que
    //  no se le borren sus comentarios ni sus claves.

    readonly property string ficheroConf: K4.Sistema.entorno("HOME") + "/.config/k4term/k4term.conf"

    property var conf: ({ tamaño: "13", opacidad: "0.92", estela: "si",
                          tranquilo: "no" })

    function leerConf() {
        const texto = fConf.text() || ""
        const nuevo = Object.assign({}, conf)
        texto.split("\n").forEach(function (linea) {
            const limpia = linea.split("#")[0].trim()
            const corte = limpia.indexOf("=")
            if (corte < 0)
                return
            nuevo[limpia.slice(0, corte).trim()] = limpia.slice(corte + 1).trim()
        })
        conf = nuevo
    }

    function poner(clave, valor) {
        const nuevo = Object.assign({}, conf)
        nuevo[clave] = String(valor)
        conf = nuevo

        let texto = fConf.text() || ""
        const patron = new RegExp("^[ \\t]*" + clave + "[ \\t]*=.*$", "m")
        if (patron.test(texto))
            texto = texto.replace(patron, clave + " = " + valor)
        else
            texto = (texto.length && texto.slice(-1) !== "\n" ? texto + "\n" : texto)
                  + clave + " = " + valor + "\n"
        fConf.setText(texto)
    }

    property K4.Fichero fConf: K4.Fichero {
        path: self.ficheroConf
        onLoaded: self.leerConf()
    }

    K4.Ajustes {
        plugin: "terminal"
        grupo: Idioma.t("Terminal")

        //  Solo si hay k4term. Son SUS ajustes: sin él, esta sección ofrecía
        //  cambiar el tamaño de letra y el cristal de una terminal que no está
        //  instalada, y lo escribía en un fichero que no lee nadie. Con la
        //  lista vacía, la sección entera no sale.
        //
        //  La detección de Consola tarda —es un proceso que corre al
        //  arrancar—, así que esto vale «no» durante los primeros
        //  milisegundos; lo que hace que aparezca después es que K4.Ajustes se
        //  vuelve a registrar cuando `opciones` cambia.
        opciones: !Consola.esNuestra ? [] : [
            { id: "tamaño", nombre: Idioma.t("Tamaño de letra"),
              desc: Idioma.t("De la ventana; en la island manda el hueco"),
              glifo: 0xF0207, tipo: "eleccion",
              alternativas: [{ codigo: "11", nombre: "11" },
                             { codigo: "13", nombre: "13" },
                             { codigo: "15", nombre: "15" },
                             { codigo: "18", nombre: "18" }] },
            { id: "opacidad", nombre: Idioma.t("Cristal"),
              desc: Idioma.t("Cuánto se ve del fondo por detrás"),
              glifo: 0xF00B5, tipo: "eleccion",
              alternativas: [{ codigo: "1", nombre: Idioma.t("Opaca") },
                             { codigo: "0.94", nombre: Idioma.t("Suave") },
                             { codigo: "0.88", nombre: Idioma.t("Media") },
                             { codigo: "0.8", nombre: Idioma.t("Mucha") }] },
            { id: "estela", nombre: Idioma.t("Estela del cursor"),
              desc: Idioma.t("Deja rastro al moverse"), glifo: 0xF05D8 },
            { id: "tranquilo", nombre: Idioma.t("Modo tranquilo"),
              desc: Idioma.t("Atenúa lo anterior al último mandato"),
              glifo: 0xF0335 }
        ]
        valores: ({
            "tamaño": self.conf["tamaño"] || "13",
            opacidad: self.conf.opacidad || "0.94",
            estela: self.conf.estela !== "no" && self.conf.estela !== "0",
            tranquilo: self.conf.tranquilo === "si" || self.conf.tranquilo === "1"
        })
        onCambiado: function (id, valor) {
            if (id === "estela" || id === "tranquilo")
                self.poner(id, valor ? "si" : "no")
            else
                self.poner(id, valor)
        }
    }

    K4.Process {
        id: buscar
        property string pid: ""
        command: ["hyprctl", "clients", "-j"]
        onSalida: function (texto) {
            let ventanas = []
            try {
                ventanas = JSON.parse(texto)
            } catch (e) {
                return
            }
            const viva = ventanas.some(function (v) {
                return String(v.pid) === buscar.pid
            })
            if (!viva) {
                self.olvidar(buscar.pid)
                return
            }
            enfoque.pid = buscar.pid
            enfoque.running = true
        }
        onTerminado: running = false
    }

    //  Hyprland 0.56 ya no traga `dispatch focuswindow pid:N`: su parser Lua
    //  se atraganta con los dos puntos del selector. La vía viva es `eval`,
    //  la misma que usa el tema de Hyprland en esta casa.
    K4.Process {
        id: enfoque
        property string pid: ""
        command: ["hyprctl", "eval",
                  "local v = hl.get_window(\"pid:" + pid + "\")"
                  + " if v then hl.dispatch(hl.dsp.focus({ window = v })) end"]
        onTerminado: running = false
    }

    K4.Process {
        id: donde
        command: ["sh", "-c",
            "p=$(hyprctl activewindow -j | python3 -c 'import json,sys; print(json.load(sys.stdin).get(\"pid\") or 0)' 2>/dev/null);" +
            " [ \"$p\" -gt 0 ] 2>/dev/null || exit 0;" +
            " while c=$(pgrep -P \"$p\" -n 2>/dev/null); [ -n \"$c\" ]; do p=$c; done;" +
            " readlink /proc/$p/cwd 2>/dev/null"]
        onSalida: function (texto) {
            K4.Sistema.lanzar(Consola.abrir(texto.trim()))
        }
        onTerminado: running = false
    }
}
