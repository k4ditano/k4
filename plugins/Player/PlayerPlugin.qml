//  Reproductor: carátula, pista, línea de tiempo arrastrable y transporte.
//  Se activa al pasar el ratón si hay algo sonando, ganándole al reloj.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "player"
    title: Idioma.t("Reproductor")
    priority: 55
    active: habilitado && Island.hovered && Media.isPlaying

    // el centro de control y la bandeja; los inyecta el host
    property var panel: null
    property var tray: null
    property var juego: null

    //  Las píldoras de los plugins también cuentan: sin ellas en la suma, una
    //  campana de agente empujaba el grupo de la derecha sobre el título de la
    //  canción. Mismo problema que tenía el reloj, y misma explicación larga
    //  está allí.
    islandWidth: 340 + (Tray.count > 0 ? Math.min(Tray.count, 4) * 24 + 8 : 0)
        + (Game.cargado ? 46 : 0)
        + Indicadores.anchoAproximado
    // crece para dejar sitio a las notificaciones recientes
    //  El base ya lleva sus márgenes de 14 arriba y abajo. La tira añade lo que
    //  mide más el espaciado de 13 del reparto y los 2 de su propio topMargin.
    readonly property int alturaTira: Settings.notificacionesAlPasar
        ? Notifs.stripHeight(3) : 0
    islandHeight: (Media.hasTimeline ? 140 : 115)
        + (alturaTira > 0 ? alturaTira + 15 : 0)

    view: Component {
        PlayerView { panel: self.panel; tray: self.tray; juego: self.juego }
    }
}
