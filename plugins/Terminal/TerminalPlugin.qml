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

        function trabajo(mandato: string, salida: string, segundos: string): void {
            const fallo = String(salida) !== "0"
            const cuerpo = self.resumir(mandato) + " · " + self.duracion(segundos)
            const orden = ["notify-send", "-a", "k4term",
                           fallo ? "-u" : "-t", fallo ? "critical" : "6000",
                           fallo ? Idioma.t("Falló el mandato") + " (" + salida + ")"
                                 : Idioma.t("Mandato terminado"),
                           cuerpo]
            K4.Sistema.lanzar(orden)
        }
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
