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

    //  Si se ha PEDIDO que suene, que no es lo mismo que si suena.
    //
    //  Manda esto y no `playbackState`, y es la diferencia entre que funcione y
    //  que no. El estado del medio se va a parado por su cuenta en tres sitios:
    //  al asignar un `source` nuevo, al llegar al final del fichero, y mientras
    //  carga. Preguntándoselo a él, cualquiera de esas tres cosas dejaba el vídeo
    //  clavado: saltabas con la línea de tiempo y se paraba, o llegaba al final y
    //  no volvía a empezar.
    //
    //  Con la intención guardada aparte, después de cada salto basta con mirar si
    //  se quería que sonara y volver a darle.
    property bool sonando: false

    readonly property bool reproduciendo: sonando
    readonly property int pistaAudio: mp.activeAudioTrack

    function indiceEn(t) {
        for (let i = 0; i < tramos.length; ++i)
            if (t >= tramos[i].inicio && t < tramos[i].fin)
                return i
        return tramos.length > 0 ? tramos.length - 1 : -1
    }

    //  El instante que hay que pedirle al fichero para estar en `t` de la línea.
    //
    //  Con velocidad, un segundo de línea vale `velocidad` segundos de fichero.
    //  El tope sigue siendo el trozo entero en tiempo de FUENTE, que es lo que
    //  entiende el medio.
    function enFuente(t, tr) {
        const v = tr.velocidad || 1
        return tr.desde + Math.max(0, Math.min(tr.hasta - tr.desde,
                                               (t - tr.inicio) * v))
    }

    //  Lo que se le pidió al medio antes de que estuviera cargado.
    //
    //  Escribir `position` sobre un medio que aún no ha cargado no hace nada y
    //  no avisa: el vídeo arrancaba desde el principio y parecía que el salto se
    //  había perdido.
    property real pendiente: -1

    //  Una tregua corta después de cada salto.
    //
    //  Buscar no es instantáneo, y hasta que surte efecto el medio sigue emitiendo
    //  la posición VIEJA. Si se le cree, pasan dos cosas y las dos se ven: el
    //  cabezal va al sitio nuevo y vuelve un instante al viejo, y —peor— si venías
    //  del final del vídeo, esa posición vieja dispara el «se acabó el trozo» y la
    //  línea da la vuelta sola.
    //
    //  Durante la tregua no se le cree y punto. `cabezal` ya lo ha puesto `irA`,
    //  así que la vista está bien; lo único que se pierde son doscientos
    //  milisegundos de seguimiento.
    //
    //  Y al terminar, si tenía que sonar y no suena, se le vuelve a dar: escribir
    //  `position` deja el medio parado en algunos estados —no siempre, y ahí está
    //  la gracia—, y sin esto el vídeo se quedaba muerto tras un salto de cada
    //  tantos. Antes intenté adivinar en cuáles y no hay forma; preguntar después
    //  sí funciona.
    property bool enTregua: false

    Timer {
        id: tregua
        interval: 200
        onTriggered: {
            repro.enTregua = false
            if (repro.sonando && mp.playbackState !== MediaPlayer.PlayingState)
                mp.play()
        }
    }

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

        enTregua = true
        tregua.restart()

        const fuente = "file://" + tr.ruta
        if (mp.source !== fuente) {
            pendiente = enFuente(limpio, tr)
            mp.source = fuente
        } else {
            mp.position = enFuente(limpio, tr) * 1000
            if (sonando)
                mp.play()
        }
    }

    // Al siguiente trozo, o al principio si era el último.
    function avanzar() {
        if (indice + 1 < tramos.length) {
            irA(tramos[indice + 1].inicio)
            return
        }

        //  Dar la vuelta, y con `stop()` por delante.
        //
        //  En el final del fichero el medio está parado en su último fotograma, y
        //  en ese estado **escribir `position` no hace nada**: se queda donde
        //  estaba y no avisa. Comprobado con una traza —al llegar al final, `pos`
        //  seguía valiendo 8000 después de pedirle 0—, y el efecto era que el
        //  vídeo se quedaba congelado en negro al terminar, con el reloj en cero.
        //  `stop()` sí devuelve el medio al principio, y desde ahí `play()` vale.
        mp.stop()
        irA(0)
        if (sonando)
            mp.play()
    }

    function reproducir() { sonando = true; mp.play() }
    function pausar() { sonando = false; mp.pause() }
    function alternar() { sonando ? pausar() : reproducir() }

    //  Rascar: buscar un instante con el ratón.
    //
    //  Mientras dura, el medio está en pausa. No es un adorno: escribir `position`
    //  con el vídeo en marcha se cumple unas veces y otras no —medido, en pausa
    //  ocho clics cayeron exactos donde decía la regla, y en marcha ninguno—, y
    //  perseguir eso con reintentos y treguas fue una sucesión de parches que
    //  arreglaban un síntoma y sacaban otro.
    //
    //  Pausar mientras se busca es además lo que hace cualquier editor, y de paso
    //  arrastrar por la regla sale suave en vez de pelearse con la reproducción.
    //  `sonando` no se toca, así que el botón sigue diciendo la verdad y al soltar
    //  se reanuda solo si tocaba.
    property bool rascando: false

    function empezarRasca() {
        if (rascando)
            return
        rascando = true
        mp.pause()
    }

    function terminarRasca() {
        if (!rascando)
            return
        rascando = false
        if (sonando)
            mp.play()
    }

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

        //  La previa va a la velocidad del trozo que se esté viendo.
        //
        //  Qt hace esto en el reproductor y conserva el tono, igual que hace
        //  `atempo` en el render; no son el mismo algoritmo, así que la previa
        //  se parece pero el fichero manda. Enganchado como binding para que
        //  cambiar la velocidad se note sin tener que volver a saltar.
        playbackRate: repro.tramo ? (repro.tramo.velocidad || 1) : 1

        //  Con parámetro declarado y no usando el `position` que Qt inyecta:
        //  la inyección está en desahucio y avisa por consola en cada carga.
        onPositionChanged: function (ms) {
            if (!repro.tramo || playbackState === MediaPlayer.StoppedState)
                return
            // Recién saltado no se le cree: lo que dice es de antes.
            if (repro.enTregua)
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

            //  De vuelta a tiempo de línea, deshaciendo la velocidad. Con un
            //  clip a 2× el fichero avanza el doble de deprisa, y sin dividir
            //  aquí el cabezal se iría al doble de rápido que el vídeo.
            repro.cabezal = repro.tramo.inicio
                + (s - repro.tramo.desde) / (repro.tramo.velocidad || 1)
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
            if (repro.sonando)
                play()
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
        // `sonando` primero: `irA` cambia de medio y el arranque de verdad ocurre
        // al terminar de cargar, mirando esta bandera.
        sonando = true
        irA(Editor.posicionEditor > 0.2 ? Editor.posicionEditor : 0)
    }
}
