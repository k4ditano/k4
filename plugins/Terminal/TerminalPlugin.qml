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
    priority: 50
    active: false

    //  Despierta al servicio que publica el ambiente: un singleton de QML no
    //  se instancia hasta que alguien lo mira, y su único cliente de hoy es
    //  la terminal. Apagar este plugin deja de publicar el tema, que es
    //  justo lo que tiene que pasar.
    readonly property string ambiente: Ambiente.ruta

    //  Se lanza por uwsm como todo lo que abre la barra: así la ventana
    //  hereda el ámbito de la sesión y no muere con quickshell.
    function lanzar(args) {
        K4.Sistema.lanzar(["uwsm", "app", "--", "k4term"].concat(args || []))
    }

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
    function apuntar(pid, mandato, llevaba) {
        const t = Object.assign({}, trabajos)
        t[pid] = { mandato: String(mandato),
                   desde: Date.now() - (Number(llevaba) || 0) * 1000 }
        trabajos = t
        enCurso = Object.keys(t).length
        K4.Pildora.registrar(idDe(pid), reloj(0), 0xF018D, Theme.blue, 30, true)
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
            buscar.pid = String(id).substring("terminal.".length)
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
            const casa = K4.Sistema.entorno("HOME")
            self.lanzar(casa ? ["-d", casa] : [])
        }

        function abrirEn(ruta: string): void {
            self.lanzar(ruta ? ["-d", ruta] : [])
        }

        function ejecutar(mandato: string): void {
            if (mandato)
                self.lanzar(["-e", "sh", "-c", mandato])
        }

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
        function limpiar(pid: string): void { self.olvidar(pid) }
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
            const ruta = texto.trim()
            self.lanzar(ruta ? ["-d", ruta] : [])
        }
        onTerminado: running = false
    }
}
