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
}
