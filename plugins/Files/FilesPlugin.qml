//  Buscador de ficheros.
//
//  Se escribe y salen resultados de todo el home en unos 50 ms. Intro abre,
//  ctrl+intro abre la carpeta que lo contiene y ctrl+c copia la ruta, que
//  acaba en el historial del portapapeles.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "files"
    title: Idioma.t("Archivos")
    // Junto al lanzador y el portapapeles: son los tres que se piden a
    // propósito y ninguno debe quedar tapado por lo que se abre solo.
    priority: 81
    active: habilitado && (open || closing)
    viewLoaded: open
    grabKeyboard: open

    property var panel: null

    property bool open: false
    property bool closing: false
    property int index: 0

    islandWidth: 760
    islandHeight: 470

    readonly property var lista: Archivos.resultados
    readonly property int count: lista.length

    view: Component {
        FilesView { plugin: self }
    }

    function abrir() {
        Archivos.consulta = ""
        Archivos.resultados = []
        index = 0
        closing = false
        open = true
        if (panel)
            panel.close()
    }

    function close() {
        if (!open)
            return
        open = false
        closing = true
        cierre.restart()
    }

    function toggle() { open ? close() : abrir() }

    Timer {
        id: cierre
        interval: 260
        onTriggered: self.closing = false
    }

    // ── teclado ───────────────────────────────────────────────────
    function mover(paso) {
        if (count === 0)
            return
        index = Math.max(0, Math.min(count - 1, index + paso))
    }

    function elegir() {
        const r = lista[index]
        if (!r)
            return
        Archivos.abrir(r.ruta)
        close()
    }

    function abrirDonde() {
        const r = lista[index]
        if (!r)
            return
        Archivos.abrirCarpeta(r.esCarpeta ? r.ruta : r.carpeta)
        close()
    }

    function copiar() {
        const r = lista[index]
        if (r)
            Archivos.copiarRuta(r.ruta)
    }

    function alternarAmbito() {
        Archivos.ambito = Archivos.ambito === "home" ? "sistema" : "home"
        index = 0
    }

    function alternarSolo(cual) {
        Archivos.solo = Archivos.solo === cual ? "" : cual
        index = 0
    }

    // la lista cambia con cada búsqueda: el índice no puede quedarse fuera
    onCountChanged: if (index >= count) index = Math.max(0, count - 1)

    K4.Ipc {
        target: "k4.files"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }
        function find(q: string): void {
            self.abrir()
            Archivos.consulta = q
        }
    }
}
