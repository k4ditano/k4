pragma Singleton

//  Historial del portapapeles.
//
//  Quickshell expone `clipboardText`, pero en Wayland su señal de cambio no
//  salta cuando copia otra aplicación: probado con una sonda, no llegó ni el
//  contenido inicial. El compositor solo avisa a quien tiene el foco, y la
//  barra nunca lo tiene. Así que quien vigila es `wl-paste --watch`, uno para
//  texto y otro para imágenes, que sí se enteran de todo.
//
//  El archivo lo lleva tools/portapapeles.py: guarda cada copia en su propio
//  fichero y mantiene un índice ligero. Aquí solo se arrancan los vigilantes,
//  se pide la lista y se mandan las órdenes.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: portapapeles

    readonly property string guion: Quickshell.shellPath("tools/portapapeles.py")

    property var entradas: []
    readonly property int count: entradas.length
    property bool cargado: false

    signal cambio()

    // ── consulta ──────────────────────────────────────────────────
    function filtrar(texto) {
        const q = (texto || "").trim().toLowerCase()
        if (q.length === 0)
            return entradas

        const salida = []
        for (let i = 0; i < entradas.length; ++i) {
            const e = entradas[i]
            if (e.resumen.toLowerCase().indexOf(q) !== -1
                || (e.etiqueta || "").indexOf(q) !== -1)
                salida.push(e)
        }
        return salida
    }

    // Primera línea con algo escrito: una copia que empieza con saltos de
    // línea no puede salir como una fila en blanco.
    function titulo(e) {
        if (!e)
            return ""
        if (e.tipo === "imagen")
            return "Imagen · " + tamaño(e.bytes)

        const lineas = e.resumen.split("\n")
        for (let i = 0; i < lineas.length; ++i) {
            if (lineas[i].trim().length > 0)
                return lineas[i].trim()
        }
        return e.resumen.trim()
    }

    function tamaño(n) {
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
        if (n >= 1024) return Math.round(n / 1024) + " KB"
        return n + " B"
    }

    function hace(cuando) {
        const s = Math.max(0, Date.now() / 1000 - cuando)
        if (s < 60) return "ahora"
        const m = Math.floor(s / 60)
        if (m < 60) return m + " min"
        const h = Math.floor(m / 60)
        if (h < 24) return h + " h"
        return Math.floor(h / 24) + " d"
    }

    // ── órdenes ───────────────────────────────────────────────────
    function copiar(id) { mandar(["copiar", id]) }
    function borrar(id) { mandar(["borrar", id]) }
    function fijar(id) { mandar(["fijar", id]) }
    function limpiar() { mandar(["limpiar"]) }

    function mandar(args) {
        orden.command = ["python3", portapapeles.guion].concat(args)
        orden.running = true
    }

    Process {
        id: orden
        onExited: portapapeles.recargar()
    }

    // ── la lista ──────────────────────────────────────────────────
    function recargar() { lector.running = true }

    Process {
        id: lector
        command: ["python3", portapapeles.guion, "listar"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    portapapeles.entradas = d.entradas || []
                } catch (e) {
                    portapapeles.entradas = []
                }
                portapapeles.cargado = true
                portapapeles.cambio()
            }
        }
    }

    // ── los vigilantes ────────────────────────────────────────────
    //
    //  `wl-paste --watch` ejecuta el guión con la copia en la entrada estándar
    //  cada vez que cambia el portapapeles, y lo que el guión imprime sale por
    //  aquí: es el aviso de que hay algo nuevo que releer.
    //
    //  Van dos porque el vigilante de texto ignora las imágenes y al revés;
    //  con uno solo se perdería la mitad.

    Process {
        id: vigilaTexto
        command: ["wl-paste", "--type", "text", "--watch",
                  "python3", portapapeles.guion, "guardar", "texto"]
        running: true

        stdout: SplitParser {
            onRead: portapapeles.recargar()
        }

        onExited: revivir.restart()
    }

    Process {
        id: vigilaImagen
        command: ["wl-paste", "--type", "image", "--watch",
                  "python3", portapapeles.guion, "guardar", "imagen"]
        running: true

        stdout: SplitParser {
            onRead: portapapeles.recargar()
        }

        onExited: revivir.restart()
    }

    // Si el compositor se reinicia, wl-paste se cae y el historial dejaría de
    // llenarse en silencio. Se reintenta con calma.
    Timer {
        id: revivir
        interval: 12000
        onTriggered: {
            vigilaTexto.running = true
            vigilaImagen.running = true
        }
    }
}
