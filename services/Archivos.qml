pragma Singleton

//  Búsqueda de ficheros.
//
//  El motor es `fd` y no `plocate`, y la decisión salió de medir: el índice de
//  plocate de este equipo no contiene una sola ruta del home, y además es una
//  foto que se rehace cada tantas horas, así que lo que acabas de guardar no
//  aparecería. `fd` recorre los 187.000 ficheros del home en unos 50 ms y
//  siempre está al día.
//
//  Quien busca y ordena es tools/buscar.py; aquí solo se lanza, se espera a
//  que dejes de teclear y se guarda lo que vuelve.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: archivos

    readonly property string guion: Quickshell.shellPath("tools/buscar.py")

    property string consulta: ""
    property string ambito: "home"          // "home" | "sistema"
    property string solo: ""                // "" | "archivo" | "dir"

    property var resultados: []
    property bool buscando: false
    property int ms: 0
    property int total: 0

    // ── lanzar ────────────────────────────────────────────────────
    //  Con espera: mientras tecleas no tiene sentido salir corriendo en cada
    //  letra, y «i», «in», «inf» son tres búsquedas tiradas a la basura.
    onConsultaChanged: reposo.restart()
    onAmbitoChanged: reposo.restart()
    onSoloChanged: reposo.restart()

    Timer {
        id: reposo
        interval: 160
        onTriggered: archivos.buscar()
    }

    function buscar() {
        if (consulta.trim().length < 2) {
            resultados = []
            total = 0
            buscando = false
            return
        }

        buscando = true
        const orden = ["python3", archivos.guion, consulta,
                       "--ambito", ambito, "--tope", "60"]
        if (solo.length > 0)
            orden.push("--solo", solo)

        // Si ya había una en marcha se corta: la respuesta de una consulta
        // vieja llegando tarde pisaría la lista de la nueva.
        proceso.running = false
        proceso.command = orden
        proceso.running = true
    }

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("archivos:", l)
            }
        }
        id: proceso

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    // puede volver la respuesta de algo que ya no se busca
                    if (d.consulta !== archivos.consulta)
                        return
                    archivos.resultados = d.resultados || []
                    archivos.ms = d.ms || 0
                    archivos.total = d.total || 0
                } catch (e) {
                    archivos.resultados = []
                }
                archivos.buscando = false
            }
        }
    }

    // ── abrir ─────────────────────────────────────────────────────
    function abrir(ruta) { lanzar(["xdg-open", ruta]) }
    function abrirCarpeta(ruta) { lanzar(["xdg-open", ruta]) }

    function copiarRuta(ruta) {
        copia.command = ["sh", "-c", "printf %s " + escapar(ruta) + " | wl-copy"]
        copia.running = true
    }

    function escapar(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function lanzar(orden) {
        abridor.command = orden
        abridor.running = true
    }

    Process { id: abridor }
    Process { id: copia }

    // ── texto ─────────────────────────────────────────────────────
    function tamaño(n) {
        if (n >= 1073741824) return (n / 1073741824).toFixed(1) + " GB"
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
        if (n >= 1024) return Math.round(n / 1024) + " KB"
        return n + " B"
    }

    function hace(cuando) {
        const s = Math.max(0, Date.now() / 1000 - cuando)
        if (s < 3600) return Math.max(1, Math.floor(s / 60)) + " min"
        const h = Math.floor(s / 3600)
        if (h < 24) return h + " h"
        const d = Math.floor(h / 24)
        if (d < 30) return d + " d"
        return Math.floor(d / 30) + " meses"
    }

    // Ruta acortada: lo que importa es dónde está, no la ristra entera.
    function dondeEsta(ruta) {
        const casa = Quickshell.env("HOME")
        let d = ruta
        if (casa && d.indexOf(casa) === 0)
            d = "~" + d.substring(casa.length)
        return d.length > 58 ? "…" + d.substring(d.length - 57) : d
    }

    // ── icono por lo que es ───────────────────────────────────────
    readonly property var porExtension: ({
        png: 0xF021F, jpg: 0xF021F, jpeg: 0xF021F, gif: 0xF021F,
        webp: 0xF021F, svg: 0xF021F, bmp: 0xF021F, ico: 0xF021F,
        mp4: 0xF022B, mkv: 0xF022B, avi: 0xF022B, mov: 0xF022B, webm: 0xF022B,
        mp3: 0xF0387, flac: 0xF0387, ogg: 0xF0387, wav: 0xF0387, m4a: 0xF0387,
        pdf: 0xF0226,
        zip: 0xF05C4, gz: 0xF05C4, xz: 0xF05C4, zst: 0xF05C4,
        tar: 0xF05C4, rar: 0xF05C4, "7z": 0xF05C4,
        qml: 0xF0169, js: 0xF0169, ts: 0xF0169, py: 0xF0169, sh: 0xF0169,
        c: 0xF0169, h: 0xF0169, cpp: 0xF0169, rs: 0xF0169, go: 0xF0169,
        lua: 0xF0169, json: 0xF0169, css: 0xF0169, html: 0xF0169,
        txt: 0xF0219, md: 0xF0219, doc: 0xF0219, docx: 0xF0219,
        odt: 0xF0219, csv: 0xF0219, conf: 0xF0219, toml: 0xF0219,
        yaml: 0xF0219, yml: 0xF0219, ini: 0xF0219, log: 0xF0219
    })

    function glifo(r) {
        if (!r) return 0xF0214
        if (r.esCarpeta) return 0xF024B
        return porExtension[r.extension] || 0xF0214
    }

    function tono(r) {
        if (!r) return "#8e8e93"
        if (r.esCarpeta) return "#5ac8fa"
        const g = glifo(r)
        if (g === 0xF021F) return "#bf5af2"      // imagen
        if (g === 0xF022B) return "#ff9f0a"      // vídeo
        if (g === 0xF0387) return "#ff2d92"      // audio
        if (g === 0xF0226) return "#ff453a"      // pdf
        if (g === 0xF05C4) return "#ffd60a"      // comprimido
        if (g === 0xF0169) return "#30d158"      // código
        return "#8e8e93"
    }
}
