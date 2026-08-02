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
    readonly property int altoLinea: 18
    readonly property int filasMinimas: 6
    readonly property int filasMaximas: 26
    property int filasDeseadas: filasMinimas

    onMarcoChanged: {
        if (!marco)
            return
        if (marco.usadas >= marco.filas_n && filasDeseadas < filasMaximas)
            filasDeseadas = Math.min(filasMaximas, filasDeseadas + 5)
        else if (marco.usadas * 2 <= marco.filas_n && filasDeseadas > filasMinimas)
            filasDeseadas = Math.max(filasMinimas, marco.usadas + 2)
    }

    //  Cada sesión nueva empieza recogida.
    onArrancadoChanged: if (!arrancado) filasDeseadas = filasMinimas

    islandHeight: Math.min(560, 40 + filasDeseadas * altoLinea)
    Behavior on islandHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    closeOnHoverExit: false
    handlesBackgroundTap: true
    onBackgroundTapped: {}

    view: Component { TerminalIslaView { plugin: self } }

    function mandar(orden) {
        if (arrancado)
            sesion.escribir(JSON.stringify(orden) + "\n")
    }

    function cerrar() { abierto = false }

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

        function ejecutar(mandato: string): void {
            if (mandato)
                K4.Sistema.lanzar(Consola.orden(mandato))
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
