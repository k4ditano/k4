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

    //  El pid de la ventana que tiene el foco ahora mismo.
    //
    //  Está aquí y no en quien lo usa porque un plugin no puede preguntarle a
    //  Hyprland por su cuenta —y con razón: la plataforma se toca desde un
    //  servicio—. Lo quiere quien tenga algo apuntado por pid y necesite saber
    //  que ya te has puesto delante: la campana de la terminal, sin ir más
    //  lejos, pedía que fueras y no tenía forma de enterarse de que fuiste.
    //
    //  Cadena y no entero para que el que compara no tenga que convertir: lo
    //  que llega por IPC son cadenas.
    property string pidActivo: ""

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

    //  ── cuáles se están viendo ────────────────────────────────────
    //
    //  El campo `visible` de un cliente de Hyprland NO sirve para esto: una
    //  ventana de otro escritorio lo trae en `true` igualmente. Lo que sí vale
    //  es mirar qué escritorio tiene delante cada monitor —más el especial, si
    //  hay uno desplegado— y comparar.
    //
    //  Quien pinta encima del escritorio necesita esta distinción: ofrecer como
    //  objetivo una ventana que no está en pantalla es recortar el vacío.
    readonly property var espaciosVistos: {
        const ids = ({})
        const monitores = Hyprland.monitors.values
        for (let i = 0; i < monitores.length; ++i) {
            const m = monitores[i]
            if (m.activeWorkspace)
                ids[m.activeWorkspace.id] = true
            const d = m.lastIpcObject
            if (d && d.specialWorkspace && d.specialWorkspace.id !== 0)
                ids[d.specialWorkspace.id] = true
        }
        return ids
    }

    function seVe(d) {
        const w = d ? d.workspace : null
        return !!(w && espaciosVistos[w.id] === true)
    }

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

            const pid = ventanas.datos(t).pid
            ventanas.pidActivo = pid === undefined ? "" : String(pid)

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
