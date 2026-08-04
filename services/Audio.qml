pragma Singleton

//  Volumen del sink por defecto, por señales de Pipewire.
//
//  Antes esto sondeaba `wpctl get-volume` cada 350 ms — unas diez mil
//  ejecuciones por hora, para siempre, se usara o no el volumen. Quickshell
//  habla Pipewire directamente y AVISA: cuando el volumen cambia por fuera
//  (teclas multimedia, un mixer) llega una señal, se actualiza el estado y
//  se levanta `overlayOpen` igual que antes, sin un solo proceso.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: audio

    //  Un nodo de Pipewire solo publica sus propiedades mientras alguien lo
    //  rastrea: esto es ese alguien.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    readonly property var _sink: Pipewire.defaultAudioSink

    property int volume: 0
    property bool muted: false
    property bool initialized: false
    property bool overlayOpen: false

    //  Por señal y no por binding directo: hay que distinguir el primer
    //  valor (que no es un cambio) para no abrir el overlay al arrancar.
    property var _vigila: Connections {
        target: audio._sink ? audio._sink.audio : null
        function onVolumesChanged() { audio._sincronizar() }
        function onMutedChanged() { audio._sincronizar() }
    }

    on_SinkChanged: _sincronizar()

    function _sincronizar() {
        if (!_sink || !_sink.audio)
            return
        const nuevoVolumen = Math.round(_sink.audio.volume * 100)
        const nuevoSilencio = _sink.audio.muted
        const cambio = initialized
            && (nuevoVolumen !== volume || nuevoSilencio !== muted)

        volume = nuevoVolumen
        muted = nuevoSilencio
        initialized = true

        if (cambio)
            showOverlay()
    }

    function showOverlay() {
        overlayOpen = true
        overlayTimer.restart()
    }

    function setVolume(percent) {
        const bounded = Math.max(0, Math.min(100, Math.round(percent)))
        if (_sink && _sink.audio) {
            _sink.audio.volume = bounded / 100
            _sink.audio.muted = false
        }
        //  El eco local mantiene el deslizador suave; la señal confirma.
        volume = bounded
        muted = false
        showOverlay()
    }

    function toggleMute() {
        if (_sink && _sink.audio)
            _sink.audio.muted = !_sink.audio.muted
        showOverlay()
    }

    Timer {
        id: overlayTimer
        interval: 1600
        onTriggered: audio.overlayOpen = false
    }

    //  ── los aparatos: qué hay enchufado y por dónde suena ─────────
    //
    //  Hasta aquí este servicio solo sabía subir y bajar el volumen general.
    //  Elegir por dónde sale el sonido o por dónde entra —y con cuánta
    //  ganancia— había que hacerlo en pavucontrol, que es salir de la casa
    //  para algo que la casa debería saber.
    //
    //  Todo por Pipewire y sin un solo proceso: los nodos llegan por señal, y
    //  cambiar el predeterminado es asignar una propiedad.
    readonly property var todos: Pipewire.nodes ? Pipewire.nodes.values : []

    //  Los aparatos de verdad, sin los flujos de las aplicaciones —un
    //  «Firefox» no es una salida, es alguien que usa una— y sin los nodos
    //  internos de Pipewire: «Dummy-Driver», «Freewheel-Driver»,
    //  «Midi-Bridge» y «BLE MIDI» salían en la lista como si fueran
    //  micrófonos. Lo que los distingue es tener `device.api`: los de verdad
    //  vienen de alsa o de bluez, los inventados no vienen de ninguna parte.
    //  Por el NOMBRE y no por las propiedades.
    //
    //  Las propiedades de un nodo llegan vacías al principio y se rellenan
    //  después —lo publica el rastreador cuando puede—, así que filtrar por
    //  ellas dejaba la lista en blanco justo al abrir el panel y la llenaba
    //  medio segundo más tarde. El nombre está desde el primer momento.
    //
    //  Lo que se queda: lo que viene de una tarjeta (`alsa_`) o de un aparato
    //  bluetooth. Lo que se va: los nodos internos de Pipewire
    //  —«Dummy-Driver», «Freewheel-Driver», «Midi-Bridge», «BLE MIDI»—, que
    //  salían en la lista como si fueran micrófonos.
    function esAparato(n) {
        if (!n || n.isStream)
            return false
        const nombre = String(n.name || "")
        if (nombre.indexOf("alsa_") === 0)
            return true
        return nombre.indexOf("bluez_") === 0 && nombre.indexOf("midi") < 0
    }

    readonly property var salidas: todos.filter(function (n) {
        return audio.esAparato(n) && n.isSink
    })

    readonly property var entradas: todos.filter(function (n) {
        return audio.esAparato(n) && !n.isSink
    })

    //  Se rastrean todos: un nodo de Pipewire no publica sus propiedades
    //  —ni el volumen, ni el nombre— mientras nadie lo mire.
    property PwObjectTracker _rastro: PwObjectTracker {
        objects: audio.salidas.concat(audio.entradas)
    }

    readonly property var salidaActiva: Pipewire.defaultAudioSink
    readonly property var entradaActiva: Pipewire.defaultAudioSource

    function nombreDe(nodo) {
        if (!nodo)
            return ""
        return String(nodo.description || nodo.nickname || nodo.name || "")
    }

    function elegirSalida(nodo) {
        if (nodo)
            Pipewire.preferredDefaultAudioSink = nodo
    }

    function elegirEntrada(nodo) {
        if (nodo)
            Pipewire.preferredDefaultAudioSource = nodo
    }

    //  El volumen de UN aparato, no el del sistema. Hasta 150 %: por encima
    //  del 100 % es ganancia por software, que es útil con un micro flojo y
    //  es justo lo que satura uno que ya venía bien.
    function volumenDe(nodo) {
        return nodo && nodo.audio ? Math.round(nodo.audio.volume * 100) : 0
    }

    function ponerVolumenDe(nodo, pct) {
        if (!nodo || !nodo.audio)
            return
        nodo.audio.volume = Math.max(0, Math.min(150, Math.round(pct))) / 100
    }

    function mudoDe(nodo) {
        return !!(nodo && nodo.audio && nodo.audio.muted)
    }

    function alternarMudoDe(nodo) {
        if (nodo && nodo.audio)
            nodo.audio.muted = !nodo.audio.muted
    }

    //  ── dónde está la unidad de cada aparato ──────────────────────
    //
    //  El «volumen base»: el nivel natural del cacharro, sin amplificar ni
    //  atenuar. Un micro USB con base al 56 % está metiendo +15 dB cuando lo
    //  pones al 100 % —y entra saturado sin que nada avise—. Esto pasó de
    //  verdad y por eso se enseña.
    //
    //  No lo publica Pipewire: hay que preguntárselo a pactl, una vez y solo
    //  cuando se abre el panel.
    property var bases: ({})

    //  Los decibelios que el aparato está poniendo POR ENCIMA de su nivel
    //  natural. Es la cifra que significa algo: el porcentaje es un invento
    //  del mezclador, y «+44 %» no le dice nada a nadie —«+15 dB» sí—.
    //
    //  La curva es la de PulseAudio, cúbica: 60·log10(v). Comprobada contra
    //  los números del propio pactl —56 % da −15 dB clavados— y no sacada de
    //  ninguna fórmula de cabeza.
    function dbSobreNatural(nodo) {
        const base = baseDe(nodo)
        const v = volumenDe(nodo)
        if (base <= 0 || v <= 0)
            return 0
        return 60 * Math.log(v / base) / Math.LN10
    }

    function baseDe(nodo) {
        const b = bases[nombreDe(nodo)]
        return b === undefined ? 0 : b
    }

    function mirarBases() { lector.running = true }

    Process {
        id: lector
        //  Dos llamadas y no una: `pactl list` acepta UN tipo, y pedirle
        //  «sources sinks» se queda con el primero sin decir nada — la mitad
        //  de las bases no llegaban y la marca no salía en media lista.
        command: ["sh", "-c",
            "{ pactl list sources; pactl list sinks; } | "
            + "grep -E '^[[:space:]]*(Description|Base Volume):'"]
        stdout: StdioCollector {
            onStreamFinished: {
                //  Se leen por pares: la descripción y, debajo, su base. Es
                //  como los saca pactl y no hay que analizar el bloque entero.
                const nuevo = ({})
                let quien = ""
                const lineas = this.text.split("\n")
                for (let i = 0; i < lineas.length; ++i) {
                    const l = lineas[i].trim()
                    if (l.indexOf("Description:") === 0) {
                        quien = l.slice(12).trim()
                    } else if (l.indexOf("Base Volume:") === 0 && quien) {
                        const m = l.match(/(\d+)%/)
                        if (m)
                            nuevo[quien] = parseInt(m[1], 10)
                        quien = ""
                    }
                }
                audio.bases = nuevo
            }
        }
    }
}
