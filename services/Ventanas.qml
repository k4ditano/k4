pragma Singleton

//  Las ventanas abiertas, para el cambiador.
//
//  El compositor las da en el orden en que se abrieron, que es el menos útil
//  posible: lo que uno quiere al pulsar Alt+Tab es la de antes, no la primera
//  que abrió esta mañana. Aquí se lleva el orden de uso —la última en la que
//  estuviste, primera— igual que hace cualquier cambiador decente.

import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: ventanas

    // Identificadores en orden de uso, del más reciente al más antiguo.
    property var recientes: []

    readonly property var lista: {
        const abiertas = ToplevelManager.toplevels.values.slice()
        const salida = []

        // primero las que ya conocemos, en su orden de uso
        for (let i = 0; i < recientes.length; ++i) {
            for (let j = 0; j < abiertas.length; ++j) {
                if (clave(abiertas[j]) === recientes[i]) {
                    salida.push(abiertas[j])
                    abiertas.splice(j, 1)
                    break
                }
            }
        }
        // y detrás las que aún no han tenido el foco
        return salida.concat(abiertas)
    }

    readonly property int count: lista.length

    function clave(t) {
        return t ? (t.appId || "") + "|" + (t.title || "") : ""
    }

    function icono(t) {
        if (!t)
            return ""
        const id = t.appId || ""
        if (id.length === 0)
            return ""

        // El appId casi nunca coincide con el nombre del icono: hay que
        // buscarlo. Tres intentos, de más barato a más caro.
        let r = Quickshell.iconPath(id, true)
        if (r) return r
        r = Quickshell.iconPath(id.toLowerCase(), true)
        if (r) return r

        // por la entrada de escritorio, que es donde vive el icono de verdad
        const apps = DesktopEntries.applications.values
        const bajo = id.toLowerCase()
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            const suyo = (a.id || "").toLowerCase()
            if (suyo === bajo || suyo.indexOf(bajo) !== -1
                || (a.name || "").toLowerCase() === bajo) {
                const p = Quickshell.iconPath(a.icon, true)
                if (p) return p
            }
        }
        return ""
    }

    // El nombre bonito, si la entrada de escritorio lo tiene.
    function titulo(t) {
        if (!t)
            return ""
        const id = (t.appId || "").toLowerCase()
        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; ++i) {
            const a = apps[i]
            if ((a.id || "").toLowerCase() === id)
                return a.name || t.appId
        }
        return t.appId || Idioma.t("Ventana")
    }

    function nombre(t) {
        if (!t)
            return ""
        const id = t.appId || ""
        return id.length > 0 ? id : Idioma.t("Ventana")
    }

    function activar(t) {
        if (t)
            t.activate()
    }

    function cerrar(t) {
        if (t)
            t.close()
    }

    // ── orden de uso ──────────────────────────────────────────────
    Connections {
        target: ToplevelManager

        function onActiveToplevelChanged() {
            const t = ToplevelManager.activeToplevel
            if (!t)
                return
            const k = ventanas.clave(t)
            const sin = ventanas.recientes.filter(function (x) { return x !== k })
            // se recorta: no hace falta recordar cien ventanas cerradas
            ventanas.recientes = [k].concat(sin).slice(0, 40)
        }
    }
}
