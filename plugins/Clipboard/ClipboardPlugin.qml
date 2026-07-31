//  Portapapeles: el historial de lo copiado, con búsqueda.
//
//  Se abre con el teclado, se escribe para filtrar y se pulsa Intro para
//  devolver algo al portapapeles. Lo que se fija no caduca nunca, que es lo
//  que lo convierte en un cajón de cosas que se pegan cien veces al día.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "clipboard"
    title: Idioma.t("Portapapeles")
    // Por encima del lanzador: si los dos están abiertos, mandas tú con el
    // que acabas de pedir, y este se pide siempre a propósito.
    priority: 82
    active: habilitado && (open || closing)
    viewLoaded: open
    grabKeyboard: open

    property var panel: null

    property bool open: false
    property bool closing: false
    property string query: ""
    property int index: 0

    islandWidth: 720
    islandHeight: 470

    readonly property var lista: Clipboard.filtrar(query)
    readonly property int count: lista.length

    view: Component {
        ClipboardView { plugin: self }
    }

    function abrir() {
        Clipboard.recargar()
        query = ""
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
        const e = lista[index]
        if (!e)
            return
        Clipboard.copiar(e.id)
        close()
    }

    function borrarActual() {
        const e = lista[index]
        if (!e)
            return
        Clipboard.borrar(e.id)
        // el que ocupe su sitio pasa a estar seleccionado
        index = Math.max(0, Math.min(index, count - 2))
    }

    function fijarActual() {
        const e = lista[index]
        if (e)
            Clipboard.fijar(e.id)
    }

    // La lista se rehace sola cuando entra una copia nueva: si el índice se
    // queda fuera, se recorta en vez de apuntar a nada.
    onCountChanged: if (index >= count) index = Math.max(0, count - 1)

    K4.Ipc {
        target: "k4.clipboard"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }
        function clear(): void { Clipboard.limpiar() }
    }
}
