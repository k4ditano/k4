//  Centro de control: Wi‑Fi, Bluetooth, volumen, reproducción, accesos y
//  notificaciones. Cuatro pestañas dentro de la misma vista.

import QtQuick
import Quickshell.Io
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "panel"
    title: "Centro de control"
    priority: 60
    active: open

    // "controls" | "notifications" | "wifi" | "bluetooth"
    property string tab: "controls"
    property bool open: false

    // el lanzador; lo inyecta el host
    property var launcher: null

    islandWidth: 860
    islandHeight: tab === "controls" ? 274 : 400

    // solo mientras se escribe la contraseña de una red
    grabKeyboard: Wifi.pskTarget !== null

    handlesBackgroundTap: true
    onBackgroundTapped: toggle()

    function toggle(wanted) {
        // pedir una pestaña que no es la que se ve cambia a ella en vez de cerrar
        const wantsTab = wanted !== undefined && wanted.length > 0
        open = !open || (wantsTab && wanted !== tab)

        if (open) {
            if (wantsTab)
                tab = wanted
            Notifs.dismissToast()
            if (tab === "notifications")
                Notifs.markRead()
        }
    }

    function openTab(wanted) {
        tab = wanted
        open = true
        Wifi.cancelPsk()
        Wifi.notice = ""
    }

    function close() { open = false }

    // El escáner solo mientras se mira la lista correspondiente.
    Binding {
        target: Wifi
        property: "scanning"
        value: self.open && self.tab === "wifi"
    }

    Binding {
        target: Bt
        property: "discovering"
        value: self.open && self.tab === "bluetooth"
    }

    // Una notificación aparta el panel.
    Connections {
        target: Notifs
        function onNotified() { self.open = false }
    }

    // Se cierra solo al salir el ratón, pero no si el lanzador está encima.
    Timer {
        id: closeTimer
        interval: 700
        onTriggered: {
            if (!self.launcher || !self.launcher.open)
                self.open = false
        }
    }

    // El host avisa de la salida del ratón; abrirlo por atajo no lo arma, así
    // que un panel abierto con el teclado sigue abierto hasta que lo toques.
    function hoverExited() { if (open) closeTimer.restart() }
    function hoverEntered() { closeTimer.stop() }

    IpcHandler {
        target: "k4.panel"
        function toggle(): void { self.toggle("controls") }
        function notifications(): void { self.toggle("notifications") }
        function wifi(): void { self.openTab("wifi") }
        function bluetooth(): void { self.openTab("bluetooth") }
        function close(): void { self.close() }
    }

    view: Component {
        PanelView { plugin: self }
    }
}
