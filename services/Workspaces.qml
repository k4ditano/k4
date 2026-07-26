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

    // ancho que ocupan los puntos en la píldora: activo + resto + hueco al reloj
    readonly property int dotsWidth: list.length === 0
        ? 0 : (list.length - 1) * 10 + 18 + 8
}
