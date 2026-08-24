pragma Singleton

// Espacios de trabajo de Hyprland, ordenados por id.

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    readonly property var list: {
        const values = Hyprland.workspaces.values.slice()
        values.sort(function (a, b) { return a.id - b.id })
        return values
    }

    // Cuál tiene el foco. Hace falta como propiedad suelta porque `list` cambia
    // por muchos motivos —una ventana que abre, un nombre que cambia— y lo que
    // interesa señalar es solo el salto de escritorio.
    readonly property int activo: {
        for (let i = 0; i < list.length; ++i)
            if (list[i].focused)
                return list[i].id
        return -1
    }

    // ancho que ocupan los puntos en la píldora: activo + resto + hueco al reloj
    readonly property int dotsWidth: list.length === 0
        ? 0 : (list.length - 1) * 10 + 18 + 8

    //  ── ¿hay algo llenando la pantalla? ───────────────────────────
    //
    //  Por escritorio y no por ventana, que es donde Hyprland lo apunta:
    //  `hasfullscreen` responde justo a la pregunta —«lo que este monitor tiene
    //  delante, ¿ocupa todo?»— y sale gratis. Mirar cliente a cliente obligaría
    //  a comparar geometrías y a decidir qué es «casi toda», que es una
    //  discusión sin final.
    //
    //  Y cubre las DOS pantallas completas de Hyprland: la de verdad y la
    //  «maximizada» del dispatcher, porque el escritorio marca las dos.
    //
    //  Por NOMBRE de monitor, que es como se conocen las pantallas en el resto
    //  de la barra: una `PanelWindow` sabe la suya y un plugin también.
    readonly property var llenos: {
        const d = ({})
        const monitores = Hyprland.monitors.values
        for (let i = 0; i < monitores.length; ++i) {
            const m = monitores[i]
            const e = m.activeWorkspace
            const dato = e ? e.lastIpcObject : null
            d[String(m.name)] = !!(dato && dato.hasfullscreen)
        }
        return d
    }

    function lleno(pantalla) { return llenos[String(pantalla)] === true }

    //  Y hay que ir a por el dato: la lista de escritorios NO se rehace sola
    //  cuando algo se pone a pantalla completa. Hyprland lo cuenta por el
    //  socket de eventos y ahí se queda; sin pedir la lista otra vez, quien
    //  pregunte se entera la próxima vez que abras o cierres una ventana, que
    //  puede ser dentro de una hora.
    //
    //  `closewindow` también: cerrar la ventana que estaba a pantalla completa
    //  deshace el estado sin que llegue ningún `fullscreen`.
    Connections {
        target: Hyprland
        ignoreUnknownSignals: true
        function onRawEvent(evento) {
            const n = String(evento.name || "")
            if (n !== "fullscreen" && n !== "closewindow")
                return
            if (typeof Hyprland.refreshWorkspaces === "function")
                Hyprland.refreshWorkspaces()
        }
    }
}
