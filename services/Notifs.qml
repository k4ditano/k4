pragma Singleton

//  Servidor de notificaciones propio.
//
//  Al llegar una notificación se emite `notified()` en vez de tocar el estado
//  de otros módulos: quien tenga que apartarse (lanzador, panel) se suscribe.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications

Singleton {
    id: notifs

    signal notified()

    property var latest: null
    property int count: 0
    property bool toastOpen: false

    readonly property var tracked: server.trackedNotifications

    function clear() {
        // se copia antes: descartar muta la lista mientras se recorre
        const list = server.trackedNotifications.values.slice()
        for (let i = 0; i < list.length; ++i)
            list[i].dismiss()

        count = 0
        toastOpen = false
        toastTimer.stop()
    }

    function dismissToast() {
        toastTimer.stop()
        toastOpen = false
    }

    // el toast no debe caducar mientras el ratón está encima
    function holdToast() { toastTimer.stop() }
    function resumeToast() { if (toastOpen) toastTimer.restart() }

    function markRead() { count = 0 }

    // ── pulsar una notificación ───────────────────────────────────
    // Por convención del protocolo, la acción de identificador "default" es la
    // que corresponde al clic en el cuerpo; el resto son botones.
    function defaultAction(n) {
        if (!n || !n.actions)
            return null

        for (let i = 0; i < n.actions.length; ++i) {
            if (n.actions[i].identifier === "default")
                return n.actions[i]
        }
        return null
    }

    function buttons(n) {
        if (!n || !n.actions)
            return []

        return n.actions.filter(function (a) { return a.identifier !== "default" })
    }

    // El icono que manda la aplicación: primero la imagen de la notificación,
    // luego el icono de la aplicación. Si no hay ninguno, quien llame pone la
    // campana genérica.
    function iconFor(n) {
        if (!n)
            return ""
        if (n.image && n.image.length > 0)
            return n.image
        if (n.appIcon && n.appIcon.length > 0)
            return Quickshell.iconPath(n.appIcon, true)
        return ""
    }

    // Clic en el cuerpo: la acción por defecto si la hay y, si no, enfocar la
    // ventana de la aplicación, que es lo que espera cualquiera al pulsar.
    function activate(n) {
        if (!n)
            return

        const action = defaultAction(n)
        if (action) {
            action.invoke()
            // el protocolo dice que la notificación se cierra al invocar una
            // acción, salvo que se declare residente
            if (!n.resident)
                n.dismiss()
            return
        }

        focusApp(n)
        if (!n.resident)
            n.dismiss()
    }

    function invokeAction(n, action) {
        if (!action)
            return

        action.invoke()
        if (n && !n.resident)
            n.dismiss()
    }

    // ── enfocar la ventana de la aplicación ───────────────────────
    // Hyprland.toplevels llega vacío aquí, así que se pregunta por hyprctl y
    // se busca a mano: clase exacta, luego clase que contenga, luego título.
    property string pendingMatch: ""

    function focusApp(n) {
        const key = (n.desktopEntry && n.desktopEntry.length > 0 ? n.desktopEntry : n.appName) || ""
        if (key.length === 0)
            return

        // "org.gnome.Nautilus" → también vale probar con "nautilus"
        pendingMatch = key.toLowerCase()
        clientQuery.running = true
    }

    function matchAndFocus(json) {
        const key = pendingMatch
        pendingMatch = ""
        if (key.length === 0)
            return

        let list
        try {
            list = JSON.parse(json)
        } catch (e) {
            return
        }

        const tail = key.indexOf(".") !== -1 ? key.substring(key.lastIndexOf(".") + 1) : key

        let exact = null
        let partial = null
        for (let i = 0; i < list.length; ++i) {
            const c = list[i]
            const cls = String(c.class || "").toLowerCase()
            const initial = String(c.initialClass || "").toLowerCase()
            const title = String(c.title || "").toLowerCase()

            if (cls === key || initial === key || cls === tail || initial === tail) {
                exact = c
                break
            }
            if (partial === null
                && (cls.indexOf(tail) !== -1 || initial.indexOf(tail) !== -1
                    || title.indexOf(tail) !== -1))
                partial = c
        }

        const found = exact || partial
        if (!found)
            return

        // Sintaxis Lua, como el resto de la configuración de Hyprland: con el
        // parser nuevo, `dispatch focuswindow address:…` no compila —se
        // envuelve en hl.dispatch(...) y revienta— y hay que pasar un
        // dispatcher de verdad. Las claves que admite `focus` son direction,
        // monitor, window, urgent_or_last y last.
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + found.address + '" })')
    }

    Process {
        id: clientQuery
        command: ["hyprctl", "-j", "clients"]

        stdout: StdioCollector {
            onStreamFinished: notifs.matchAndFocus(this.text)
        }
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true

        onNotification: function (notification) {
            notification.tracked = true
            notifs.latest = notification
            notifs.count += 1
            notifs.toastOpen = true
            toastTimer.restart()
            notifs.notified()
        }
    }

    Timer {
        id: toastTimer
        interval: 5000
        onTriggered: notifs.dismissToast()
    }
}
