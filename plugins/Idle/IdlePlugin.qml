//  Píldora plegada: carátula · espacios de trabajo · hora · visualizador, más
//  los iconos de la bandeja si hay alguno.
//  Siempre activo con prioridad 0, así que es el fondo de armario: se ve
//  cuando ningún otro módulo quiere la island.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "idle"
    title: "Píldora"
    priority: 0
    active: true

    // el módulo de bandeja, que se abre al pulsar los iconos; lo inyecta el host
    property var tray: null

    // cuántos iconos caben sin que la píldora se desmadre; el resto se resume
    readonly property int trayShown: Math.min(Tray.count, 4)
    readonly property int trayWidth: Tray.count === 0
        ? 0 : trayShown * 18 + (Tray.count > trayShown ? 18 : 0) + 6

    // el indicador del juego suma su hueco cuando hay partida cargada
    readonly property int juegoWidth: Game.cargado ? (Game.cofres > 0 ? 44 : 36) : 0

    islandWidth: (Media.isPlaying ? 210 : 176) + Workspaces.dotsWidth + trayWidth + juegoWidth
    islandHeight: Theme.baseHeight

    view: Component {
        IdleView { tray: self.tray; shown: self.trayShown }
    }
}
