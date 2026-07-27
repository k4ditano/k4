//  Monitor del sistema.
//
//  El muestreador solo corre mientras la vista está abierta: un monitor que
//  sondea /proc y llama a nvidia-smi las veinticuatro horas para nadie es lo
//  que hace que una barra se gane fama de pesada.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "system"
    title: "Sistema"
    priority: 62
    active: open || closing
    viewLoaded: open
    tecladoOpcional: open

    property var panel: null

    property bool open: false
    property bool closing: false

    islandWidth: 700
    islandHeight: 430

    view: Component {
        SystemView { plugin: self }
    }

    // Enciende y apaga el muestreo con la vista.
    onOpenChanged: Sistema.mirando = open

    function abrir() {
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

    IpcHandler {
        target: "k4.system"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }
    }
}
