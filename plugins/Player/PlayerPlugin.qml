//  Reproductor: carátula, pista, línea de tiempo arrastrable y transporte.
//  Se activa al pasar el ratón si hay algo sonando, ganándole al reloj.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "player"
    title: "Reproductor"
    priority: 55
    active: Island.hovered && Media.isPlaying

    // el botón de salida abre el centro de control; lo inyecta el host
    property var panel: null

    islandWidth: 340
    islandHeight: Media.hasTimeline ? 140 : 115

    view: Component {
        PlayerView { panel: self.panel }
    }
}
