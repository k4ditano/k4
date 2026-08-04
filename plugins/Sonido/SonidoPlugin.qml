//  El sonido de la casa: por dónde sale, por dónde entra y con cuánta
//  ganancia.
//
//  La barra sabía subir y bajar el volumen general y nada más. Elegir el
//  aparato o mirar la ganancia de un micro obligaba a abrir pavucontrol, que
//  es salir de casa para algo que la casa tiene delante — y para enterarse
//  demasiado tarde, además: un micro con la ganancia disparada no se nota
//  hasta que escuchas lo que grabaste.
//
//  Todo por Pipewire, sin sondear nada: los aparatos llegan por señal y
//  cambiar el predeterminado es asignar una propiedad. Lo único que se
//  pregunta por proceso es el volumen BASE de cada uno —el nivel natural del
//  cacharro, que Pipewire no publica—, una vez al abrir.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "sonido"
    title: Idioma.t("Sonido")
    priority: 61
    active: habilitado && abierto

    property bool abierto: false

    //  Lo aparta al abrirse; lo inyecta el host. Declararlo es lo que hace que
    //  llegue: sin la propiedad, la referencia no se reparte y usarla revienta
    //  el `toggle()` a media función —pasó, y lo que se quedó sin correr fue
    //  justo la lectura de las bases—.
    property var panel: null

    islandWidth: 520

    //  Crece con lo que haya enchufado, con tope: un portátil con dock puede
    //  tener seis salidas y no por eso la island debe llegar al suelo.
    islandHeight: {
        const filas = Audio.salidas.length + Audio.entradas.length
        return Math.min(560, 150 + filas * 62)
    }

    grabKeyboard: abierto
    closeOnHoverExit: false
    handlesBackgroundTap: true
    onBackgroundTapped: {}

    function toggle() {
        abierto = !abierto
        if (abierto) {
            if (panel)
                panel.close()
            //  Las bases se preguntan al abrir y no al arrancar la barra: es
            //  un proceso, y solo hace falta cuando se está mirando esto.
            Audio.mirarBases()
        }
    }

    function close() { abierto = false }

    K4.Ipc {
        target: "k4.sonido"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
    }

    view: Component { SonidoView { plugin: self } }
}
