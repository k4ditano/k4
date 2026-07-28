pragma Singleton

//  Las ventanas abiertas, para el cambiador.
//
//  La fuente es Hyprland y no el protocolo de Wayland, y no por gusto: el
//  `activate()` del protocolo pide el foco pero NO cambia de escritorio, así
//  que elegir una ventana de otro espacio no llevaba a ninguna parte. Hyprland
//  da además la dirección de cada ventana y en qué espacio está, que es
//  justo lo que hace falta para ir a ella de verdad.
//
//  El compositor las lista en el orden en que se abrieron, que es el menos
//  útil posible: al pulsar Alt+Tab uno quiere la de antes, no la primera de la
//  mañana. Aquí se lleva el orden de uso.

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: ventanas

    // Direcciones en orden de uso, de la más reciente a la más antigua.
    property var recientes: []

    readonly property var lista: {
        const abiertas = Hyprland.toplevels.values.slice()
        const salida = []

        for (let i = 0; i < recientes.length; ++i) {
            for (let j = 0; j < abiertas.length; ++j) {
                if (direccion(abiertas[j]) === recientes[i]) {
                    salida.push(abiertas[j])
                    abiertas.splice(j, 1)
                    break
                }
            }
        }
        return salida.concat(abiertas)
    }

    readonly property int count: lista.length

    function refrescar() {
        if (typeof Hyprland.refreshToplevels === "function")
            Hyprland.refreshToplevels()
    }

    // ── datos de una ventana ──────────────────────────────────────
    function datos(t) { return t && t.lastIpcObject ? t.lastIpcObject : ({}) }

    function direccion(t) {
        if (!t)
            return ""
        const d = datos(t).address
        return d ? String(d) : (t.address ? "0x" + t.address : "")
    }

    function clase(t) { return String(datos(t).class || "") }

    function tituloVentana(t) { return String(datos(t).title || "") }

    function espacio(t) {
        const w = datos(t).workspace
        return w && w.name !== undefined ? String(w.name) : ""
    }

    function icono(t) {
        const id = clase(t)
        if (id.length === 0)
            return ""

        // El nombre de la clase casi nunca coincide con el del icono: hay que
        // buscarlo. Tres intentos, de más barato a más caro.
        let r = Quickshell.iconPath(id, true)
        if (r) return r
        r = Quickshell.iconPath(id.toLowerCase(), true)
        if (r) return r

        const apps = DesktopEntries.applications.values
        const bajo = id.toLowerCase()
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            const suyo = String(a.id || "").toLowerCase()
            if (suyo === bajo || suyo.indexOf(bajo) !== -1
                || String(a.name || "").toLowerCase() === bajo) {
                const p = Quickshell.iconPath(a.icon, true)
                if (p) return p
            }
        }
        return ""
    }

    // El nombre bonito, si la entrada de escritorio lo tiene.
    function titulo(t) {
        const id = clase(t).toLowerCase()
        if (id.length === 0)
            return Idioma.t("Ventana")

        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            if (String(a.id || "").toLowerCase() === id)
                return a.name || clase(t)
        }
        return clase(t)
    }

    // ── ir a ella ─────────────────────────────────────────────────
    //
    //  En sintaxis Lua, como el resto de la configuración de Hyprland: con el
    //  parser nuevo `dispatch focuswindow address:…` no compila. `focus` con
    //  la dirección sí cambia de escritorio, que es lo que fallaba usando el
    //  activate del protocolo de Wayland.
    function activar(t) {
        const d = direccion(t)
        if (d.length === 0)
            return
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + d + '" })')
    }

    function cerrar(t) {
        const d = direccion(t)
        if (d.length === 0)
            return
        Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + d + '" })')
        refrescar()
    }

    // ── orden de uso ──────────────────────────────────────────────
    Connections {
        target: Hyprland

        function onActiveToplevelChanged() {
            const t = Hyprland.activeToplevel
            if (!t)
                return
            const d = ventanas.direccion(t)
            if (d.length === 0)
                return
            const sin = ventanas.recientes.filter(function (x) { return x !== d })
            ventanas.recientes = [d].concat(sin).slice(0, 40)
        }
    }

    Component.onCompleted: refrescar()
}
