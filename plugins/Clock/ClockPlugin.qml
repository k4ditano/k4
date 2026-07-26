//  Hover sin música: fecha y hora. Comparte disparador con el reproductor
//  (el ratón encima) pero tiene menos prioridad, así que si suena algo gana él.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    name: "clock"
    title: "Reloj"
    priority: 50
    active: Island.hovered

    islandWidth: 300
    islandHeight: 68

    view: Component { ClockView {} }
}
