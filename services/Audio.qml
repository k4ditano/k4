pragma Singleton

//  Volumen del sink por defecto, vía wireplumber.
//
//  wpctl no notifica cambios, así que se sondea. Cuando el volumen cambia por
//  fuera (teclas de multimedia, mixer…) se levanta overlayOpen, que es lo que
//  el plugin Volume usa para pedir la island.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: audio

    property int volume: 0
    property bool muted: false
    property bool initialized: false
    property bool overlayOpen: false

    function showOverlay() {
        overlayOpen = true
        overlayTimer.restart()
    }

    function setVolume(percent) {
        const bounded = Math.max(0, Math.min(100, Math.round(percent)))
        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", String(bounded / 100)])
        volume = bounded
        muted = false
        showOverlay()
        poll.restart()
    }

    function toggleMute() {
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        showOverlay()
        poll.restart()
    }

    function parse(output) {
        const match = output.match(/Volume:\s+([0-9.]+)/)
        const nextVolume = match ? Math.round(parseFloat(match[1]) * 100) : volume
        const nextMuted = output.indexOf("[MUTED]") !== -1
        // en el primer sondeo no hay nada con qué comparar: no es un cambio
        const changed = initialized && (nextVolume !== volume || nextMuted !== muted)

        volume = nextVolume
        muted = nextMuted
        initialized = true

        if (changed)
            showOverlay()
    }

    Process {
        id: volumeProcess
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: audio.parse(this.text)
        }

        onExited: poll.restart()
    }

    Timer {
        id: poll
        interval: 350
        onTriggered: volumeProcess.running = true
    }

    Timer {
        id: overlayTimer
        interval: 1600
        onTriggered: audio.overlayOpen = false
    }
}
