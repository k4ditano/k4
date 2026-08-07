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
    // depende de la bandeja, del aviso del juego y de las píldoras.
    //
    //  ── por qué esto se MIDE y no se suma ─────────────────────────
    //
    //  La cuenta de aquí abajo era la única fuente, y no contaba las píldoras
    //  que aportan los plugins —la campana de un agente, el porcentaje de
    //  límites, un mandato largo—: sumaba `Modulos.count`, que es la lista de
    //  los módulos minimizados, otra cosa distinta. Con una campana puesta el
    //  grupo de la derecha crecía sin que nadie le hubiera reservado sitio, se
    //  metía hacia el centro y quedaba dibujado ENCIMA de la hora.
    //
    //  Y alargar la suma con otra constante no arreglaba nada: lo que ocupa
    //  «🔔 claude · k4» depende de su texto y de la fuente, así que el único
    //  que puede decirlo es quien lo pinta. La vista lo mide y lo publica en
    //  `anchoDerecho`; aquí se recoge.
    //
    //  La suma se queda como suelo y no como verdad: mientras la island está
    //  cerrada no hay vista que mida, y al abrirse el tamaño se decide antes de
    //  que la vista se disponga. Sin ese suelo, el primer fotograma saldría
    //  estrecho. Manda el mayor de los dos.
    property int anchoDerechoMedido: 0

    readonly property int ladoEstimado: (Tray.count > 0
        ? Math.min(Tray.count, 5) * 24 + 8 : 0) + 48
        + (Captura.grabando || Captura.estado === "cerrando" ? 60 : 0)
        + Modulos.count * 180
        + Indicadores.anchoAproximado

    readonly property int ladoDer: Math.max(ladoEstimado, anchoDerechoMedido)

    //  Y un techo, porque esto se multiplica por dos.
    //
    //  `islandWidth` reserva `ladoAncho` a CADA lado para que el reloj quede
    //  centrado, así que lo que crezca aquí crece el doble abajo. Con varios
    //  agentes trabajando —cada uno su píldora— la island se iba de ancho hasta
    //  dejar de parecerse a una island.
    //
    //  El tope de verdad lo pone cada píldora recortando su texto; esto es el
    //  cinturón: aunque un día alguien registre veinte indicadores, la island no
    //  se come la pantalla. Al pasarse, las píldoras se salen por la derecha en
    //  vez de estirarlo todo, que es lo menos malo de las dos cosas.
    readonly property int ladoAncho: Math.max(96, Math.min(ladoDer, 380))

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
        ClockView {
            tray: self.tray
            juego: self.juego
            //  Por Binding y no asignando en un `on…Changed`: así el valor
            //  llega también en la primera disposición, que es justo cuando
            //  hace falta.
            Binding {
                target: self
                property: "anchoDerechoMedido"
                value: anchoDerecho
            }
        }
    }
}
