//  Oír el audio añadido mientras editas.
//
//  Un reproductor de solo sonido por cada capa de audio, colocado a mano al
//  instante que le toca. Suena cuando el cabezal está dentro de su tramo y el
//  vídeo va en marcha, y calla en cuanto sale o se pausa.
//
//  No es la verdad, y conviene decirlo: son dos reproductores independientes
//  siguiendo el mismo reloj, así que al cabo de unos minutos habrá unas décimas
//  de desfase. El fichero que sale del render sí está mezclado por ffmpeg con
//  precisión de muestra —medido: la música entra 19 dB justo en su segundo—, y
//  esto es solo para poder decidir el volumen y el punto de entrada oyéndolos.

import QtQuick
import QtMultimedia
import "../../services"

Item {
    id: extra

    // El instante de la línea y si la reproducción va en marcha.
    property real segundos: 0
    property bool sonando: false
    property bool silenciado: false

    readonly property var pistas: {
        const r = []
        for (let i = 0; i < Editor.capas.length; ++i)
            if (Editor.capas[i].tipo === "audio")
                r.push(Editor.capas[i])
        return r
    }

    Repeater {
        model: extra.pistas

        delegate: Item {
            required property var modelData

            readonly property bool dentro: extra.segundos >= modelData.t0
                && extra.segundos <= modelData.t1
            readonly property bool debeSonar: dentro && extra.sonando
                && !extra.silenciado

            //  Colocarse solo al empezar a sonar, no en cada fotograma.
            //
            //  Perseguir el cabezal a cada cambio sería mandarle un `seek` treinta
            //  veces por segundo, y un reproductor al que se le pide buscar todo
            //  el rato no llega a reproducir nada. Se coloca al entrar y se deja
            //  correr; el desfase que salga es el precio.
            onDebeSonarChanged: {
                if (debeSonar) {
                    mp.position = Math.max(0, extra.segundos - modelData.t0) * 1000
                    mp.play()
                } else {
                    mp.pause()
                }
            }

            MediaPlayer {
                id: mp
                source: modelData.ruta ? "file://" + modelData.ruta : ""
                audioOutput: AudioOutput {
                    // El mismo volumen que va a acabar en el render.
                    volume: modelData.volumen !== undefined
                        ? modelData.volumen : 0.8
                }
            }
        }
    }
}
