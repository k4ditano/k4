//  Chuleta de atajos: qué tienes atado a cada tecla, sin abrir el fichero.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "keys"
    title: Idioma.t("Atajos")
    priority: 65
    active: habilitado && (open || closing)
    viewLoaded: open
    grabKeyboard: open

    property var panel: null

    property bool open: false
    property bool closing: false
    property string query: ""

    islandWidth: 760
    islandHeight: 440

    readonly property var lista: Atajos.filtrar(query)
    readonly property int count: lista.length

    view: Component {
        KeysView { plugin: self }
    }

    function abrir() {
        // se relee al abrir: si acabas de tocar la configuración, quieres ver
        // lo que hay ahora, no lo que había al arrancar la barra
        Atajos.recargar()
        query = ""
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

    K4.Ipc {
        target: "k4.keys"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }
    }
}
