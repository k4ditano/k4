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
    active: habilitado

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
    // Grabando: el punto rojo y el mm:ss. Reservarlo es obligatorio, no
    // cosmético: los flancos tienen hueco fijo y lo que no se reserva se sale
    // por encima de la hora, que es lo que pasaba.
    readonly property int grabacionWidth: Captura.grabando
        || Captura.estado === "cerrando" ? 60 : 0

    // La carátula y las barras van juntas a la izquierda, así que el hueco de
    // las barras se reserva ahí y no enfrente.
    readonly property int ladoIzq: Media.isPlaying ? 53 : 0
    // Lo mismo para las cápsulas de lo que has dejado a medias: cada una puede
    // llegar a 116 px con su icono y su detalle recortado.
    readonly property int minimizadosWidth: Modulos.count * 116

    readonly property int ladoDer: trayWidth + juegoWidth + grabacionWidth
        + minimizadosWidth
    readonly property int ladoAncho: Math.max(ladoIzq, ladoDer)

    // El centro ya no es solo la hora: al cambiar de escritorio enseña los
    // puntos en su lugar, y hay que reservar lo que ocupe el más ancho de los
    // dos o la píldora daría un salto cada vez.
    readonly property int centroAncho: Math.max(46, Workspaces.dotsWidth - 8)

    islandWidth: centroAncho + 2 * ladoAncho + 44
    islandHeight: Theme.baseHeight

    view: Component {
        IdleView { tray: self.tray; shown: self.trayShown }
    }
}
