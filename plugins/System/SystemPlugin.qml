//  Monitor del sistema.
//
//  El muestreador solo corre mientras la vista está abierta: un monitor que
//  sondea /proc y llama a nvidia-smi las veinticuatro horas para nadie es lo
//  que hace que una barra se gane fama de pesada.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "system"
    title: Idioma.t("Sistema")
    priority: 62
    active: habilitado && (open || closing)
    viewLoaded: open
    //  El teclado entero mientras está abierto: «opcional» es OnDemand y
    //  el compositor solo lo da si PINCHAS la superficie, así que abierto
    //  desde el centro de aplicaciones o por atajo no llegaba ni el ESC.
    //  Ver `tecladoOpcional` en api/K4/Plugin.qml.
    grabKeyboard: open

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

    K4.Ipc {
        target: "k4.system"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }
    }
}
