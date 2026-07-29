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
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "captura"
    title: Idioma.t("Captura")
    active: open
    viewLoaded: open
    //  También durante la cuenta atrás, o el ESC que la cancela no llega a
    //  ninguna parte. Son tres segundos en los que nadie está escribiendo.
    grabKeyboard: open && (modo === "menu" || modo === "cuenta" || modo === "zoom")

    //  La cuenta atrás manda sobre todo lo demás mientras dura: si te tapa el
    //  reloj tres segundos no pasa nada, pero perderte el 3-2-1 sí importa.
    priority: modo === "cuenta" ? 92 : 84

    property var panel: null

    property bool open: false
    property string modo: "menu"            // menu · cuenta · hecha · zoom
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
    // La cuenta atrás se queda la island entera y sin nada más: es un número
    // gigante, y para eso no hace falta anchura.
    islandWidth: modo === "cuenta" ? 200
        : (modo === "zoom" ? 940 : (modo === "hecha" ? 500 : 520))
    islandHeight: modo === "cuenta" ? 150
        : (modo === "zoom" ? 610 : (modo === "hecha" ? 132 : 208))

    view: Component {
        Loader {
            // El editor es otra vista entera, no un modo más de la de captura:
            // comparten plugin pero no se parecen en nada.
            sourceComponent: self.modo === "zoom" ? editor : normal
        }
    }

    property Component normal: Component { CapturaView { plugin: self } }
    property Component editor: Component { EditorZoom { plugin: self } }

    // ── el menú ───────────────────────────────────────────────────
    function abrir() {
        modo = "menu"
        index = 0
        open = true
        if (panel)
            panel.close()
    }

    //  El ESC del host entra por aquí, así que cerrar durante la cuenta atrás
    //  tiene que significar «no grabes», no solo «quita la vista».
    function close() {
        if (modo === "cuenta") {
            Captura.parar()
            return
        }
        if (grande) {
            //  Apartar desde la ventana: se cierra y queda en la píldora, igual
            //  que desde la island.
            grande = false
            Modulos.minimizar("captura-zoom", Idioma.t("Editor de zoom"),
                              Captura.momentos.length + Idioma.t(" momentos"),
                              0xF1276)
            return
        }
        if (modo === "zoom") {
            //  Cerrar el editor lo aparta, no lo tira. Editar un vídeo lleva su
            //  rato y no tiene sentido obligar a tenerlo delante hasta acabar:
            //  se cierra, se sigue con lo que sea, y se retoma desde la
            //  píldora por donde ibas.
            Modulos.minimizar("captura-zoom", Idioma.t("Editor de zoom"),
                              Captura.momentos.length + Idioma.t(" momentos"),
                              0xF1276)
            modo = "menu"
        }
        open = false
    }
    function toggle() { open && modo === "menu" ? close() : abrir() }

    //  Apartar y descartar son cosas distintas y la cabecera del editor tiene
    //  un botón para cada una. `close()` aparta —es lo que hace también ESC—;
    //  esto tira el plan y se olvida.
    function descartar() {
        Captura.descartarZoom()
        grande = false
        modo = "menu"
        open = false
    }

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
    //  Ojo: la propiedad por defecto de K4.Cargador es `component`, así que el
    //  hijo suelto ES lo que se carga. Es lo que se quiere aquí.
    K4.Cargador {
        active: Captura.seleccionando
        SelectorRegion {}
    }

    //  El editor en grande, en su propia ventana.
    //
    //  Cuelga del plugin y no de la vista por lo mismo que el selector: la
    //  vista solo existe mientras el módulo tiene la island, y aquí la island
    //  se libera justamente al abrir la ventana.
    property bool grande: false

    K4.Cargador {
        active: self.grande
        EditorGrande { plugin: self }
    }

    function abrirGrande() {
        grande = true
        modo = "menu"
        open = false
    }

    function cerrarGrande() {
        grande = false
        if (Captura.momentos.length > 0) {
            modo = "zoom"
            open = true
        }
    }

    // ── la cuenta atrás y el vídeo ────────────────────────────────
    Connections {
        target: Captura

        function onEstadoChanged() {
            if (Captura.estado === "cuenta") {
                self.modo = "cuenta"
                self.open = true
            } else if (self.modo === "cuenta") {
                self.modo = "menu"
                self.open = false
            }
        }

        function onPlanListo() {
            self.modo = "zoom"
            self.open = true
        }

        function onMomentosChanged() {
            // Si está apartado, que la cápsula diga la verdad.
            if (Modulos.tiene("captura-zoom"))
                Modulos.actualizar("captura-zoom",
                    Captura.momentos.length + Idioma.t(" momentos"))
        }

        function onRenderListo(ruta) {
            Modulos.quitar("captura-zoom")
            self.modo = "menu"
            self.open = false
            K4.Sistema.lanzar(["notify-send", "-a", "k4",
                                     Idioma.t("Vídeo con zoom listo"),
                                     ruta.split("/").pop()])
        }

        function onVideoListo(ruta) {
            K4.Sistema.lanzar(["notify-send", "-a", "k4",
                                     Idioma.t("Grabación guardada"),
                                     ruta.split("/").pop()])
        }

        function onVideoFallido(motivo) {
            K4.Sistema.lanzar(["notify-send", "-a", "k4", "-u", "critical",
                                     Idioma.t("No se pudo grabar"), motivo])
        }

        function onFotoLista(ruta) {
            self.modo = "hecha"
            self.open = true
            marcharse.restart()
        }

        function onFotoFallida(motivo) {
            // Un fallo de verdad sí merece aviso del sistema: puede pasar con
            // la island cerrada y sin nadie mirando la barra.
            K4.Sistema.lanzar(["notify-send", "-a", "k4", "-u", "critical",
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

    //  Los clics para el zoom.
    //
    //  Hyprland no los publica por su socket de eventos —no hay ningún suceso
    //  de ratón—, así que la única vía razonable es un atajo global. Va con
    //  `non_consuming` en binds.lua para que el clic siga llegando a la
    //  aplicación: si se lo comiera, el ratón dejaría de funcionar mientras
    //  grabas, que sería un remedio bastante peor.
    //
    //  Si esto no llegara a funcionar no se pierde el zoom: tools/zoom.py sabe
    //  deducir los momentos del propio rastro, por los reposos del cursor.
    K4.Atajo {
        name: "clic"
        description: "Marca un clic izquierdo en el rastro de la grabación"
        onPressed: Captura.marcarClic(1)
    }

    K4.Atajo {
        name: "clicDerecho"
        description: "Marca un clic derecho en el rastro de la grabación"
        onPressed: Captura.marcarClic(3)
    }

    Connections {
        target: Modulos

        function onRestaurado(id) {
            if (id !== "captura-zoom")
                return
            self.modo = "zoom"
            self.open = true
        }
    }

    K4.Ipc {
        target: "k4.captura"

        function menu(): void { self.toggle() }
        function close(): void { self.close() }

        function pantalla(): void { self.disparar("pantalla") }
        function region(): void { self.disparar("region") }
        function ventana(): void { self.disparar("ventana") }

        // Capturar y abrir el anotador. El destino va como excepción de esta
        // foto: pedir anotar una vez no debe cambiarte el ajuste.
        function anotar(): void { self.disparar("region", "anotar") }

        // ── vídeo ──
        function grabar(): void { self.close(); Captura.grabar("") }
        function grabarRegion(): void { self.close(); Captura.grabarRegion() }
        function parar(): void { Captura.parar() }
        function grabarAlternar(): void { self.close(); Captura.alternarGrabacion() }

        function grande(): void { self.abrirGrande() }
        function encoger(): void { self.cerrarGrande() }

        // Reabrir el editor del último vídeo, por si se cerró sin querer.
        function zoom(): void { Captura.proponerZoom() }
    }
}
