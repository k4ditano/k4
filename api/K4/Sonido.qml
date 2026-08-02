//  Un sonido: el clic, el aviso, el «has perdido».
//
//  Por dentro hay dos motores y se elige solo, porque ninguno vale para todo:
//
//  - **WAV → SoundEffect.** Carga el fichero en memoria al arrancar y lo
//    dispara sin latencia. Es lo que necesita un efecto de juego, donde el
//    sonido tiene que ir CON el golpe y no un cuarto de segundo después.
//  - **Lo demás → MediaPlayer.** SoundEffect solo admite WAV sin comprimir, y
//    esto no lo dice al fallar: se queda en `status: Error` y no suena nada.
//    Me pasó con los sonidos del escritorio, que son .oga — un rato mirando
//    por qué la campana no sonaba. Ahora esos van por MediaPlayer, que abre
//    el fichero al reproducir y por eso llega un pelín tarde, pero suena.
//
//  Para música o algo largo esto no es lo suyo: un plugin que quiera
//  reproducir música lo que quiere es ser un reproductor, y para eso está
//  MPRIS y K4.Medios.
//
//  Requiere declarar el permiso `sonido`: hacer ruido en el escritorio de
//  alguien es un efecto, y los efectos se declaran.
//
//      K4.Sonido { id: campana; fuente: campana.delSistema("bell") }
//      // …
//      campana.sonar()
//
//  Ojo con esa línea, que aquí ponía `K4.Sonido.delSistema("bell")` y NO
//  funciona: `delSistema` es un método del objeto, no del tipo. Llamarlo
//  sobre `K4.Sonido` da «Property 'delSistema' of object Sonido is not a
//  function», y como el fallo ocurre dentro de un enlace, no rompe nada: te
//  deja sin sonido y en silencio. Se tardó en ver porque hasta hoy ningún
//  módulo de la barra usaba esto — el primero que lo estrenó copió el
//  ejemplo y se comió el fallo.

import QtQuick
import QtMultimedia

QtObject {
    id: sonido

    //  Un fichero: ruta absoluta con file://, o relativa a tu carpeta con
    //  Qt.resolvedUrl.
    property string fuente: ""

    //  De 0 a 1. Esto no toca el volumen del sistema: si el usuario quiere
    //  menos ruido, baja el suyo.
    property real volumen: 0.5

    readonly property bool _esWav: fuente.toLowerCase().indexOf(".wav") ===
                                   fuente.length - 4 && fuente.length >= 4

    //  Listo para sonar, y ahí es donde se mira cuando «no suena y no dice
    //  nada». Cada motor sabe fallar de una manera:
    //
    //  - el WAV avisa en cuanto carga, así que se espera a `Ready`;
    //  - el resto solo se entera al abrir el fichero, así que se mira su
    //    `error`. Se mira el error y NO se espera a `LoadedMedia` a
    //    propósito: hay motores que no cargan hasta que se les pide
    //    reproducir, y esperando la carga esto se quedaría en false para
    //    siempre — que es peor mentira que la de antes.
    //
    //  Antes, para todo lo que no fuera WAV, esto valía `true` con solo tener
    //  la propiedad puesta: un .oga inexistente daba `listo` igual, y quien
    //  lo usara de guarda no se enteraba de nada.
    readonly property bool listo: fuente.length > 0
        && (_esWav ? _efecto.status === SoundEffect.Ready
                   : _repro.error === MediaPlayer.NoError)

    property SoundEffect _efecto: SoundEffect {
        source: sonido._esWav ? sonido.fuente : ""
        volume: sonido.volumen
    }

    property MediaPlayer _repro: MediaPlayer {
        source: sonido._esWav ? "" : sonido.fuente
        audioOutput: AudioOutput { volume: sonido.volumen }
    }

    function sonar() {
        if (fuente.length === 0)
            return
        if (_esWav) {
            _efecto.play()
        } else {
            //  Desde el principio: sin esto, la segunda vez arranca donde se
            //  quedó —que en un efecto de medio segundo es no sonar.
            _repro.position = 0
            _repro.play()
        }
    }

    //  Los sonidos del escritorio, ya instalados y con el mismo carácter que
    //  el resto del sistema: "bell", "message", "complete", "dialog-error"…
    function delSistema(nombre) {
        return "file:///usr/share/sounds/freedesktop/stereo/" + nombre + ".oga"
    }
}
