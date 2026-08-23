//  Una capa del fondo: lo que se pinta de UN fichero.
//
//  Sale del lienzo porque para hacer transiciones hacen falta DOS a la vez —la
//  que se va y la que llega— y tener el juego entero de dibujantes duplicado a
//  mano en el mismo fichero era pedir que se descuadraran.
//
//  No sabe nada de transiciones ni de pantallas: se le da una ruta, un tipo y
//  si le toca moverse, y pinta. Quién está delante y cuánto se ve lo decide el
//  lienzo, que es quien tiene las dos.

import QtQuick
import QtMultimedia
import K4 as K4

Item {
    id: capa

    property string ruta: ""
    property string tipo: "nada"

    //  ¿Le toca moverse? Es la pausa por oclusión, que decide el lienzo. Una
    //  capa que no se ve no descomprime ni un fotograma.
    property bool animando: true

    //  Para que la foto se pida al tamaño de la pantalla y no al del fichero.
    property int anchoPantalla: 1920
    property int altoPantalla: 1080

    //  Negro debajo: si la imagen no llena —una foto vertical en un monitor
    //  apaisado— lo que asoma es esto y no el escritorio de detrás.
    Rectangle {
        anchors.fill: parent
        color: "black"
        visible: capa.tipo !== "nada"
    }

    Image {
        anchors.fill: parent
        visible: capa.tipo === "quieto"
        source: capa.tipo === "quieto" ? "file://" + capa.ruta : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        //  A la resolución de la pantalla y no a la del fichero: una foto de
        //  6000 px en un monitor de 1920 son 140 MB de textura para enseñar
        //  exactamente lo mismo.
        sourceSize.width: capa.anchoPantalla
        sourceSize.height: capa.altoPantalla
    }

    AnimatedImage {
        anchors.fill: parent
        visible: capa.tipo === "animado"
        source: capa.tipo === "animado" ? "file://" + capa.ruta : ""
        fillMode: Image.PreserveAspectCrop
        //  Un AnimatedImage sigue descomprimiendo fotogramas aunque su Item
        //  esté invisible, así que la pausa tiene que decírselo.
        playing: visible && capa.animando
        //  Sin caché: un GIF de fondo son megas que no se van a reusar y que se
        //  quedarían en la caché de imágenes de todo el motor.
        cache: false
    }

    VideoOutput {
        id: salida
        anchors.fill: parent
        visible: capa.tipo === "video"
        fillMode: VideoOutput.PreserveAspectCrop
    }

    MediaPlayer {
        id: reproductor
        videoOutput: salida
        loops: MediaPlayer.Infinite
        source: capa.tipo === "video" ? "file://" + capa.ruta : ""
        //  Sin AudioOutput a propósito, y no es un olvido: un fondo no suena.
        //  Sin salida de audio el descodificador ni abre la pista.
        onSourceChanged: if (source != "") capa.acompasar()
    }

    //  `pause` y no `stop`: parar rebobina, así que al destapar la ventana el
    //  fondo volvería a empezar desde el principio en vez de seguir donde
    //  estaba.
    function acompasar() {
        if (capa.tipo !== "video" || capa.ruta.length === 0)
            return
        if (capa.animando)
            reproductor.play()
        else
            reproductor.pause()
    }

    onAnimandoChanged: capa.acompasar()
    onTipoChanged: capa.acompasar()

    readonly property bool reproduciendo:
        reproductor.playbackState === MediaPlayer.PlayingState
    readonly property string fallo: String(reproductor.errorString || "")

    //  ¿Ya hay algo que enseñar? Lo pregunta el lienzo antes de empezar una
    //  transición: fundir hacia un vídeo que todavía no ha descodificado su
    //  primer fotograma es fundir hacia negro y luego dar un salto.
    readonly property bool listo: capa.tipo === "nada" ? true
        : capa.tipo === "video" ? reproductor.hasVideo
        : true
}
