//  Reproducir una línea de tiempo hecha de trozos.
//
//  Un `MediaPlayer` reproduce UN fichero de principio a fin, y aquí hay que
//  enseñar cachos de varios en un orden que no es el suyo. La conversión es
//  siempre la misma: el cabezal va en tiempo de LÍNEA, y para cada instante el
//  mapa dice qué fichero toca y por qué segundo de ese fichero va.
//
//  `cabezal` es la verdad y no `position`. Parece rebuscado hasta que cortas un
//  clip: la tabla de tramos cambia debajo, `position` sigue apuntando a un sitio
//  del fichero que ya no significa lo mismo, y el cabezal daría un salto. Con el
//  tiempo de línea guardado aparte basta con volver a colocarse donde estabas.
//
//  Al cruzar de un trozo a otro hay un tirón: el decodificador tiene que
//  recolocarse, y eso son unas décimas. Es el precio de previsualizar sin
//  renderizar nada, y se paga solo en los cortes.

import QtQuick
import QtMultimedia
import "../../services"

Item {
    id: repro

    property bool silenciado: false

    readonly property var tramos: Editor.tramos
    readonly property real total: Editor.duracionLinea

    //  Dónde está la reproducción, en tiempo de línea.
    property real cabezal: 0

    property int indice: 0
    readonly property var tramo: indice >= 0 && indice < tramos.length
        ? tramos[indice] : null

    readonly property bool reproduciendo: mp.playbackState === MediaPlayer.PlayingState
    readonly property int pistaAudio: mp.activeAudioTrack

    function indiceEn(t) {
        for (let i = 0; i < tramos.length; ++i)
            if (t >= tramos[i].inicio && t < tramos[i].fin)
                return i
        return tramos.length > 0 ? tramos.length - 1 : -1
    }

    //  El instante que hay que pedirle al fichero para estar en `t` de la línea.
    function enFuente(t, tr) {
        return tr.desde + Math.max(0, Math.min(tr.hasta - tr.desde,
                                               t - tr.inicio))
    }

    //  Lo que se le pidió al medio antes de que estuviera cargado.
    //
    //  Escribir `position` sobre un medio que aún no ha cargado no hace nada y
    //  no avisa: el vídeo arrancaba desde el principio y parecía que el salto se
    //  había perdido.
    property real pendiente: -1

    //  Si venía sonando, que siga sonando después de cambiar de fichero.
    //
    //  Hay que apuntarlo ANTES de tocar `source`: asignar un medio nuevo deja el
    //  reproductor parado al instante, así que preguntárselo luego contesta
    //  siempre que no, y la reproducción se cortaba en cada cambio de fichero.
    property bool seguir: false

    function irA(t) {
        if (tramos.length === 0)
            return
        const limpio = Math.max(0, Math.min(total - 0.001, t))
        const n = indiceEn(limpio)
        if (n < 0)
            return
        const tr = tramos[n]
        cabezal = limpio
        indice = n

        const fuente = "file://" + tr.ruta
        if (mp.source !== fuente) {
            pendiente = enFuente(limpio, tr)
            seguir = mp.playbackState === MediaPlayer.PlayingState
            mp.source = fuente
        } else {
            mp.position = enFuente(limpio, tr) * 1000
        }
    }

    // Al siguiente trozo, o al principio si era el último.
    function avanzar() {
        if (indice + 1 < tramos.length)
            irA(tramos[indice + 1].inicio)
        else
            irA(0)
    }

    function alternar() {
        mp.playbackState === MediaPlayer.PlayingState ? mp.pause() : mp.play()
    }

    function pausar() { mp.pause() }
    function fijarPistaAudio(i) { mp.activeAudioTrack = i }

    //  Al cambiar los clips, volver a donde estabas.
    //
    //  Cortar, mover o recortar un trozo cambia el significado de cada instante
    //  del fichero, así que el reproductor tiene que recolocarse. Y como el
    //  cabezal va en tiempo de línea, «donde estabas» sigue queriendo decir algo
    //  aunque el trozo de debajo sea otro.
    Connections {
        target: Editor
        function onClipsChanged() { repro.irA(repro.cabezal) }
    }

    MediaPlayer {
        id: mp
        videoOutput: salida
        audioOutput: AudioOutput { muted: repro.silenciado }

        //  Con parámetro declarado y no usando el `position` que Qt inyecta:
        //  la inyección está en desahucio y avisa por consola en cada carga.
        onPositionChanged: function (ms) {
            if (!repro.tramo || playbackState === MediaPlayer.StoppedState)
                return
            const s = ms / 1000

            //  ¿Se acabó el trozo? Al siguiente.
            //
            //  Un margen de 40 ms, que es algo más de un fotograma a 25 fps: sin
            //  él, el último fotograma del trozo puede no llegar nunca —el
            //  decodificador no está obligado a darte exactamente el instante
            //  que pediste— y la reproducción se quedaba clavada al final del
            //  primer corte.
            if (s >= repro.tramo.hasta - 0.04) {
                repro.avanzar()
                return
            }

            repro.cabezal = repro.tramo.inicio + (s - repro.tramo.desde)
            Editor.posicionEditor = repro.cabezal
        }

        onMediaStatusChanged: {
            //  Que se acabe el FICHERO no es que se acabe la línea: puede
            //  quedar otro trozo, y puede estar en el mismo fichero más atrás.
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                repro.avanzar()
                return
            }
            if (mediaStatus !== MediaPlayer.LoadedMedia
                    && mediaStatus !== MediaPlayer.BufferedMedia)
                return
            if (repro.pendiente >= 0) {
                position = repro.pendiente * 1000
                repro.pendiente = -1
            }
            if (repro.seguir) {
                repro.seguir = false
                play()
            }
        }
    }

    VideoOutput {
        id: salida
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    //  Arrancar por donde se dejó.
    //
    //  Se apunta el instante según se reproduce y no al destruirse: en la
    //  destrucción el reproductor ya ha soltado el medio y `position` vale cero.
    Component.onCompleted: {
        irA(Editor.posicionEditor > 0.2 ? Editor.posicionEditor : 0)
        mp.play()
    }
}
