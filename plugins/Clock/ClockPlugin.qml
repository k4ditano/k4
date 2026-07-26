//  Hover sin música: fecha y hora. Comparte disparador con el reproductor
//  (el ratón encima) pero tiene menos prioridad, así que si suena algo gana él.
//
//  Lleva también los iconos de bandeja pulsables: en la píldora no se pueden
//  tocar, porque acercar el ratón ya la ha cambiado por esta vista.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "clock"
    title: "Reloj"
    priority: 50
    active: Island.hovered

    // el módulo de bandeja; lo inyecta el host
    property var tray: null

    islandWidth: 300 + (Tray.count > 0 ? Math.min(Tray.count, 5) * 24 + 8 : 0)
    // crece para dejar sitio a las notificaciones recientes
    islandHeight: 68 + Notifs.stripHeight(3)

    view: Component {
        ClockView { tray: self.tray }
    }
}
