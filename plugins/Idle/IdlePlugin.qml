//  Píldora plegada: carátula · espacios de trabajo · hora · visualizador.
//  Siempre activo con prioridad 0, así que es el fondo de armario: se ve
//  cuando ningún otro módulo quiere la island.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    name: "idle"
    title: "Píldora"
    priority: 0
    active: true

    islandWidth: (Media.isPlaying ? 210 : 176) + Workspaces.dotsWidth
    islandHeight: Theme.baseHeight

    view: Component { IdleView {} }
}
