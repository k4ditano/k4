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

    //  Sin cazador de clics: esto se abre AL PASAR EL RATÓN, no lo pide nadie,
    //  y se va solo cuando el puntero se va. El mismo caso que el HUD del
    //  volumen. Ver `closeOnClickOutside` en el contrato.
    closeOnClickOutside: false

    // el módulo de bandeja; lo inyecta el host
    property var tray: null
    property var juego: null

    // Mismo criterio que la píldora, y ahora también la misma forma: cada zona
    // ocupa LO SUYO y se encadena con la siguiente, en vez de reservar los dos
    // flancos el ancho del más gordo.
    //
    //  ── por qué ya no se reserva a los dos lados ──────────────────
    //
    //  Con la hora en el centro exacto de la caja, `islandWidth` reservaba
    //  `ladoAncho` a CADA lado, así que cada píxel de indicador costaba dos y
    //  hacía falta un tope para que la island no se comiera la pantalla. Y al
    //  tocar ese tope no pasaba nada bueno: la fila de la derecha iba anclada al
    //  borde derecho, crecía hacia dentro y acababa pintada ENCIMA de la hora.
    //  Con dos agentes trabajando se veía casi siempre.
    //
    //  Encadenadas —fecha, hora, indicadores, cada una colgada de la anterior—
    //  el solape deja de ser posible: lo que no quepa se sale por la derecha y
    //  lo recorta la island. Y como ahora cada píxel vale uno, en el mismo ancho
    //  de island cabe casi el doble de flanco derecho que antes.
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
    property int anchoIzqMedido: 0
    property int anchoCentroMedido: 0
    property int anchoDerechoMedido: 0

    readonly property int ladoEstimado: (Tray.count > 0
        ? Math.min(Tray.count, 5) * 24 + 8 : 0) + 48
        + (Captura.grabando || Captura.estado === "cerrando" ? 60 : 0)
        + Modulos.count * 180
        + (Game.cargado ? 52 : 0)
        + Indicadores.anchoAproximado

    //  Las sumas y los suelos se quedan como ARRANQUE y red de seguridad, y en
    //  cuanto la vista existe manda lo medido — que es como ya lo hace la
    //  píldora plegada. La fecha rondaba los 96 y el reloj los 92, y esos
    //  números valen para el primer fotograma: cuando la island se abre, su
    //  tamaño se decide antes de que la vista se disponga.
    //
    //  Antes esto era `Math.max(suma, medido)` y el mayor de los dos mandaba
    //  siempre. Con las zonas ancladas daba igual —lo de más se repartía entre
    //  los dos flancos y no se veía— pero encadenadas se nota: la suma estima
    //  510 donde la fila mide 406, así que sobraban casi cien píxeles de island
    //  vacía a la derecha de los iconos.
    readonly property int izqAncho: anchoIzqMedido > 0 ? anchoIzqMedido : 96
    readonly property int centroAncho: anchoCentroMedido > 0
        ? anchoCentroMedido : 92
    readonly property int derMedido: anchoDerechoMedido > 0
        ? anchoDerechoMedido : ladoEstimado

    //  Y un techo para el flanco derecho, que sigue haciendo falta: el de verdad
    //  lo pone cada píldora recortando su texto, y esto es el cinturón —aunque
    //  un día alguien registre veinte indicadores, la island no se come la
    //  pantalla—. 480 y no los 380 de antes porque antes se pagaba doble: con
    //  380 a cada lado el techo de la island era 896 px, y con 480 a uno solo se
    //  queda en 760 y cabe cien píxeles más de indicadores.
    readonly property int derAncho: Math.min(derMedido, 480)

    //  El aire entre zonas es el mismo número que reparte la vista.
    readonly property int hueco: 24

    islandWidth: 44 + izqAncho + hueco + centroAncho + hueco + derAncho
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
                property: "anchoIzqMedido"
                value: anchoIzquierdo
            }
            Binding {
                target: self
                property: "anchoCentroMedido"
                value: anchoCentro
            }
            Binding {
                target: self
                property: "anchoDerechoMedido"
                value: anchoDerecho
            }
        }
    }
}
