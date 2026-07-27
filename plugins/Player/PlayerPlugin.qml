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

    // el centro de control y la bandeja; los inyecta el host
    property var panel: null
    property var tray: null

    islandWidth: 340 + (Tray.count > 0 ? Math.min(Tray.count, 4) * 24 + 8 : 0)
    // crece para dejar sitio a las notificaciones recientes
    islandHeight: (Media.hasTimeline ? 140 : 115)
        + (Settings.notificacionesAlPasar ? Notifs.stripHeight(3) : 0)

    view: Component {
        PlayerView { panel: self.panel; tray: self.tray }
    }
}
