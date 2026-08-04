//  Centro de control: Wi‑Fi, Bluetooth, volumen, reproducción, accesos y
//  notificaciones. Cuatro pestañas dentro de la misma vista.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "panel"
    title: Idioma.t("Centro de control")
    priority: 60
    active: habilitado && open

    // "controls" | "notifications" | "wifi" | "bluetooth" | "sonido"
    property string tab: "controls"
    property bool open: false

    // el lanzador y los módulos que se abren desde los accesos directos;
    // los inyecta el host
    property var launcher: null
    property var theme: null
    property var weather: null
    property var ajustes: null
    property var juego: null
    property var sistema: null

    islandWidth: 860
    // la reproducción compacta y los accesos en rejilla piden menos alto
    islandHeight: tab === "controls" ? 268 : 400

    // solo mientras se escribe la contraseña de una red
    //  El teclado entero mientras está abierto: «opcional» es OnDemand y
    //  el compositor solo lo da si PINCHAS la superficie, así que abierto
    //  desde el centro de aplicaciones o por atajo no llegaba ni el ESC.
    //  Ver `tecladoOpcional` en api/K4/Plugin.qml.
    grabKeyboard: open

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
        //  Las bases —el nivel natural de cada aparato— son un proceso, y solo
        //  hacen falta cuando se está mirando la lista.
        if (wanted === "sonido")
            Audio.mirarBases()
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
    closeOnHoverExit: true
    onHoverTimedOut: {
        if (!launcher || !launcher.open)
            open = false
    }

    K4.Ipc {
        target: "k4.panel"
        function toggle(): void { self.toggle("controls") }
        function notifications(): void { self.toggle("notifications") }
        function wifi(): void { self.openTab("wifi") }
        function bluetooth(): void { self.openTab("bluetooth") }
        function sonido(): void { self.openTab("sonido") }
        function close(): void { self.close() }
    }

    view: Component {
        PanelView { plugin: self }
    }
}
