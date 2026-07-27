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
    title: Idioma.t("Píldora")
    priority: 0
    active: true

    // el módulo de bandeja, que se abre al pulsar los iconos; lo inyecta el host
    property var tray: null

    // cuántos iconos caben sin que la píldora se desmadre; el resto se resume
    readonly property int trayShown: Math.min(Tray.count, 4)
    readonly property int trayWidth: Tray.count === 0 || !Settings.bandejaEnPildora
        ? 0 : trayShown * 18 + (Tray.count > trayShown ? 18 : 0) + 6

    // el indicador del juego suma su hueco cuando hay partida cargada
    readonly property int juegoWidth: Settings.juegoActivo
        && Game.cargado && Settings.juegoEnPildora
        ? (Game.cofres > 0 ? 44 : 36) : 0

    // Los dos flancos reservan lo mismo —el del más ancho— para que la hora
    // quede en el centro de verdad y no se mueva al aparecer o irse un icono.
    // Sale una píldora algo más ancha cuando un lado va cargado, que es el
    // precio de la simetría y merece la pena en algo que se mira todo el día.
    readonly property int ladoIzq: Workspaces.dotsWidth + (Media.isPlaying ? 28 : 0)
    readonly property int ladoDer: trayWidth + juegoWidth + (Media.isPlaying ? 30 : 0)
    readonly property int ladoAncho: Math.max(ladoIzq, ladoDer)

    islandWidth: 46 + 2 * ladoAncho + 44
    islandHeight: Theme.baseHeight

    view: Component {
        IdleView { tray: self.tray; shown: self.trayShown }
    }
}
