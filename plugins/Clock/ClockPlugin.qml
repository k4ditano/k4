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
    title: Idioma.t("Reloj")
    priority: 50
    active: habilitado && Island.hovered

    // el módulo de bandeja; lo inyecta el host
    property var tray: null
    property var juego: null

    // Mismo criterio que la píldora: los dos flancos ocupan lo del más ancho,
    // así la hora cae en el centro exacto. La fecha ronda los 96 y la derecha
    // depende de la bandeja y del aviso del juego.
    readonly property int ladoDer: (Tray.count > 0
        ? Math.min(Tray.count, 5) * 24 + 8 : 0) + 48
        + (Captura.grabando || Captura.estado === "cerrando" ? 60 : 0)
        + Modulos.count * 180
    readonly property int ladoAncho: Math.max(96, ladoDer)

    islandWidth: 92 + 2 * ladoAncho + 44
        + (Game.cargado ? 52 : 0)
    // crece para dejar sitio a las notificaciones recientes
    //  68 de la zona del reloj, y si hay notificaciones lo que mida la tira más
    //  el hueco de 6 y los 12 de aire de abajo que pone la vista. Esos 18 son los
    //  que faltaban: sin ellos el reparto aplastaba las filas contra el borde.
    readonly property int alturaTira: Settings.notificacionesAlPasar
        ? Notifs.stripHeight(3) : 0
    islandHeight: 68 + (alturaTira > 0 ? alturaTira + 18 : 0)

    view: Component {
        ClockView { tray: self.tray; juego: self.juego }
    }
}
