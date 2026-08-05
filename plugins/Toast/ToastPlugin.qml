//  Aviso emergente de notificación. Caduca solo salvo que tengas el ratón
//  encima (de eso se encarga el host), y un clic en el fondo lo descarta en
//  vez de abrir el centro de control.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "toast"
    title: Idioma.t("Notificación")

    //  59 y no 70, que es lo que hace que la lista de abajo y la prioridad
    //  digan lo MISMO. `enReposo` ya declaraba a quién puede relevar el toast
    //  —píldora, reloj, reproductor, volumen— pero la prioridad decía otra
    //  cosa: con 70 también le ganaba al centro de control, al sonido o a la
    //  mazmorra si se abrían DESPUÉS, porque la banda solo se decide al abrirse
    //  el aviso. En 59 queda justo por encima de las de reposo y por debajo de
    //  todo lo que abres tú, que es lo que la lista ya decía.
    priority: 59

    //  Y si te abre algo la island mientras está puesto, se va. Un aviso ya ha
    //  dicho lo suyo con salir; quedarse tapando lo que acabas de abrir es
    //  cobrarte el aviso dos veces. La notificación NO se pierde: sigue en la
    //  lista y en el centro de control, lo que se va es el emergente.
    transitorio: true

    function close() { Notifs.dismissToast() }

    //  ¿La island la tiene alguien DE VERDAD? Las vistas de reposo (píldora,
    //  reloj, reproductor) no cuentan: a esas el toast siempre las relevó y
    //  debe seguir haciéndolo. Al juego abierto o al editor a medias, ya no:
    //  ahí la notificación sale en banda aparte y nadie pierde la pantalla.
    readonly property var enReposo: ["", "toast", "idle", "clock", "player",
                                     "volume"]

    //  El modo se fija AL ABRIRSE cada toast: que cerrar la island a mitad
    //  no haga saltar el aviso de la banda a la island.
    //
    //  Y se decide con quién la tenía ANTES del toast, no con el ocupante
    //  del momento: en cuanto toastOpen se enciende, el propio toast puede
    //  haberse adjudicado ya la island —el orden de señales no promete
    //  nada— y mirarla entonces siempre decía «toast, o sea reposo».
    property bool enBanda: false
    property string _dueñoReal: ""

    property var _memoria: Connections {
        target: Island
        function onOcupanteChanged() {
            if (Island.ocupante !== "toast")
                self._dueñoReal = Island.ocupante
        }
    }

    property var _latch: Connections {
        target: Notifs
        function onToastOpenChanged() {
            if (Notifs.toastOpen)
                self.enBanda = self.enReposo.indexOf(self._dueñoReal) < 0
        }
    }

    active: habilitado && Notifs.toastOpen && !enBanda

    //  La banda vive fuera de la island y solo mientras hace falta.
    property var banda: K4.Cargador {
        active: self.habilitado && Notifs.toastOpen && self.enBanda
        BandaToast {}
    }

    islandWidth: 440

    // El toast crece un poco cuando la aplicación manda botones de acción.
    islandHeight: Notifs.buttons(Notifs.latest).length > 0 ? 112 : 96

    // Pulsar el cuerpo lleva a la aplicación: su acción por defecto si la
    // manda y, si no, enfocar su ventana. Antes solo descartaba el aviso.
    handlesBackgroundTap: true
    onBackgroundTapped: {
        Notifs.activate(Notifs.latest)
        Notifs.dismissToast()
    }

    view: Component { ToastView {} }
}
