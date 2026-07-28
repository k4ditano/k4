//  Captura de pantalla.
//
//  Dos caras: un menú para elegir qué capturar, y un asomo corto tras hacer la
//  foto con la miniatura y qué hacer con ella. La segunda es la que se usa el
//  99 % de las veces, porque lo normal es disparar con un atajo y no abrir
//  ningún menú.
//
//  El estado no vive aquí sino en services/Captura.qml. Un plugin solo existe
//  mientras es el módulo activo, y grabar dura minutos con la island cerrada.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "captura"
    title: Idioma.t("Captura")
    priority: 84
    active: open
    viewLoaded: open
    grabKeyboard: open && modo === "menu"

    property var panel: null

    property bool open: false
    property string modo: "menu"            // menu · hecha
    property int index: 0

    readonly property var ambitos: [
        { clave: "pantalla", texto: Idioma.t("Pantalla"), icono: 0xF0379 },
        { clave: "region",   texto: Idioma.t("Región"),   icono: 0xF019E },
        { clave: "ventana",  texto: Idioma.t("Ventana"),  icono: 0xF05AF }
    ]

    readonly property var destinos: [
        { clave: "portapapeles", texto: Idioma.t("Copiar"),  icono: 0xF018F },
        { clave: "fichero",      texto: Idioma.t("Guardar"), icono: 0xF0193 },
        { clave: "ambos",        texto: Idioma.t("Las dos"), icono: 0xF05E0 },
        { clave: "anotar",       texto: Idioma.t("Anotar"),  icono: 0xF03EB }
    ]

    // 500 y no 440: con cuatro botones debajo del nombre del fichero, a 440 se
    // salía «Copiar» por el borde derecho.
    islandWidth: modo === "hecha" ? 500 : 520
    islandHeight: modo === "hecha" ? 132 : 208

    view: Component {
        CapturaView { plugin: self }
    }

    // ── el menú ───────────────────────────────────────────────────
    function abrir() {
        modo = "menu"
        index = 0
        open = true
        if (panel)
            panel.close()
    }

    function close() { open = false }
    function toggle() { open && modo === "menu" ? close() : abrir() }

    function avanzar()    { index = (index + 1) % ambitos.length }
    function retroceder() { index = (index - 1 + ambitos.length) % ambitos.length }

    function elegir() { disparar(ambitos[index].clave) }

    // ── disparar ──────────────────────────────────────────────────
    //
    //  Cerrar el menú es solo la mitad: la píldora plegada seguiría saliendo en
    //  la foto. De apartar la island entera se encarga el servicio, que espera
    //  un frame antes de llamar a grim.
    function disparar(ambito, aDonde) {
        close()
        if (ambito === "region") {
            // La región pasa por el selector propio, que congela la pantalla
            // antes de dejarte encuadrar.
            Captura.destinoPuntual = aDonde || ""
            Captura.pedirRegion("foto")
        } else {
            Captura.foto(ambito, "", aDonde || "")
        }
    }

    //  El selector vive colgado del plugin y no de la vista: la vista solo
    //  existe mientras el módulo tiene la island, y encuadrar una región es
    //  justamente cuando la island no está.
    //
    //  Ojo: la propiedad por defecto de LazyLoader es `component`, así que el
    //  hijo suelto ES lo que se carga. Es lo que se quiere aquí.
    LazyLoader {
        active: Captura.seleccionando
        SelectorRegion {}
    }

    // ── el asomo de después ───────────────────────────────────────
    Connections {
        target: Captura

        function onFotoLista(ruta) {
            self.modo = "hecha"
            self.open = true
            marcharse.restart()
        }

        function onFotoFallida(motivo) {
            // Un fallo de verdad sí merece aviso del sistema: puede pasar con
            // la island cerrada y sin nadie mirando la barra.
            Quickshell.execDetached(["notify-send", "-a", "k4", "-u", "critical",
                                     Idioma.t("No se pudo capturar"), motivo])
        }
    }

    // Se va sola, pero no mientras tengas el ratón encima: si estás leyendo
    // los botones, es que los ibas a usar.
    //  Nada de atar `running` a una condición: `restart()` rompería el binding
    //  en cuanto llegara la segunda foto. Se rearma a mano, y si al vencer
    //  sigues con el ratón encima se da otra vuelta.
    //  5 s, no 1,8: con menos no da tiempo a llevar el ratón hasta «Anotar»
    //  desde donde estuvieras. Es lo que dura la miniatura de macOS, y por
    //  algo será.
    Timer {
        id: marcharse
        interval: 5000
        onTriggered: {
            if (Island.hovered)
                restart()
            else
                self.close()
        }
    }

    IpcHandler {
        target: "k4.captura"

        function menu(): void { self.toggle() }
        function close(): void { self.close() }

        function pantalla(): void { self.disparar("pantalla") }
        function region(): void { self.disparar("region") }
        function ventana(): void { self.disparar("ventana") }

        // Capturar y abrir el anotador. El destino va como excepción de esta
        // foto: pedir anotar una vez no debe cambiarte el ajuste.
        function anotar(): void { self.disparar("region", "anotar") }
    }
}
