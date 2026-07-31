//  Cambiador de ventanas.
//
//  Se abre con Tab y se recorre con Tab mientras lo tengas pulsado, como
//  cualquier Alt+Tab: la lista va en orden de uso, así que pulsar y soltar te
//  lleva a la anterior, que es el 90% de las veces lo que quieres.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "windows"
    title: Idioma.t("Ventanas")
    priority: 83
    active: habilitado && open
    viewLoaded: open
    grabKeyboard: open

    property var panel: null

    property bool open: false
    property int index: 0

    readonly property var lista: Ventanas.lista
    readonly property int count: lista.length

    islandWidth: Math.min(880, Math.max(360, 60 + count * 128))
    islandHeight: 190

    view: Component {
        WindowsView { plugin: self }
    }

    function abrir() {
        // la lista puede venir de hace rato: se pide fresca antes de enseñarla
        Ventanas.refrescar()
        if (Ventanas.count === 0)
            return
        // arranca en la anterior, no en la actual: es lo que se espera
        index = Ventanas.count > 1 ? 1 : 0
        open = true
        if (panel)
            panel.close()
    }

    function close() { open = false }

    function toggle() { open ? avanzar() : abrir() }

    function avanzar() {
        if (count === 0)
            return
        index = (index + 1) % count
    }

    function retroceder() {
        if (count === 0)
            return
        index = (index - 1 + count) % count
    }

    function elegir() {
        const t = lista[index]
        close()
        Ventanas.activar(t)
    }

    function cerrarActual() {
        const t = lista[index]
        Ventanas.cerrar(t)
        if (index >= count - 1)
            index = Math.max(0, count - 2)
    }

    onCountChanged: if (index >= count) index = Math.max(0, count - 1)

    K4.Ipc {
        target: "k4.windows"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }
        function next(): void { self.avanzar() }
        function focus(i: int): void {
            Ventanas.refrescar()
            self.index = i
            self.elegir()
        }
    }
}
