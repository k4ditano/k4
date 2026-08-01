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
}
