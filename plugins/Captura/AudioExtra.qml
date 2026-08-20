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
//
//  El agachado también suena aquí, y también es una imitación. Un reproductor
//  no puede OÍR a otro, así que el nivel de quien manda se lee de su onda y la
//  curva del compresor está medida punto a punto (ver `gananciaAgachado` en
//  Editor). Sirve para ajustar a oído; el que manda de verdad sigue siendo el
//  render.

import QtQuick
import QtMultimedia
import "../../services"

Item {
    id: extra

    // El instante de la línea y si la reproducción va en marcha.
    property real segundos: 0
    property bool sonando: false
    property bool silenciado: false

    //  El modelo son los IDENTIFICADORES, no las capas.
    //
    //  Y no es un capricho de estilo. Tocar cualquier cosa de una capa reasigna
    //  el array entero de `Editor.capas` —es la única forma de que QML emita el
    //  cambio—, lo que destruye y recrea todos los delegados. Con las capas de
    //  modelo, eso mataba y volvía a crear el `MediaPlayer` en cada píxel de
    //  arrastre de la barra de volumen: se oía un corte por cada movimiento del
    //  ratón, que es justo lo que uno NO puede tener mientras ajusta un volumen
    //  a oído. Es la misma trampa que documenta `BloqueTiempo` en su cabecera.
    //
    //  Con la lista de ids, mientras no aparezca ni desaparezca una capa el
    //  modelo es el mismo y el reproductor sigue vivo; el volumen entra por un
    //  enlace normal y cambia sin cortar nada.
    property var idsAudio: []

    readonly property var pistas: {
        const r = []
        for (let i = 0; i < Editor.capas.length; ++i)
            if (Editor.capas[i].tipo === "audio")
                r.push(Editor.capas[i])
        return r
    }

    //  Se reasigna solo cuando la LISTA cambia, no cuando cambia una capa: si
    //  se escribiera siempre volveríamos a recrear los delegados y no habríamos
    //  arreglado nada.
    onPistasChanged: {
        const nuevos = pistas.map(function (c) { return c.id })
        if (nuevos.length !== idsAudio.length
                || nuevos.some(function (v, i) { return v !== idsAudio[i] }))
            idsAudio = nuevos
    }

    Repeater {
        model: extra.idsAudio

        delegate: Item {
            id: voz
            required property int modelData

            //  La capa se busca por su id en cada vuelta. Es un enlace, así que
            //  se rehace sola cuando la capa cambia, sin recrear nada.
            readonly property var capa: Editor.capaPorId(modelData)

            readonly property bool dentro: !!capa
                && extra.segundos >= capa.t0 && extra.segundos <= capa.t1
            readonly property bool debeSonar: dentro && extra.sonando
                && !extra.silenciado && !capa.mudo

            //  ── el agachado ───────────────────────────────────────
            //
            //  Cuánto debería estar bajada esta capa AHORA, leyendo la onda de
            //  quien manda (ver `gananciaAgachado` en Editor). Fuera de su
            //  bloque o con el agachado apagado, uno: no se toca nada.
            readonly property real objetivoAgachado:
                capa && capa.agachar && dentro
                    ? Editor.gananciaAgachado(capa, extra.segundos) : 1

            //  Y cuánto lo está de verdad, que no salta: persigue al objetivo.
            property real agachado: 1

            //  Se persigue con un `Behavior` y no con un enlace directo porque
            //  un enlace daría escalones —el objetivo se recalcula a cada tic
            //  del reproductor, y la onda tiene un pico cada pocos milisegundos—
            //  y eso no suena a compresor, suena a interruptor.
            //
            //  Deprisa al bajar y despacio al subir, como el del render (attack
            //  80 ms, release 600 ms): una música que vuelve de golpe en cuanto
            //  callas suena a puerta y no a técnico. Es la misma asimetría que
            //  ya está documentada en `ramas_audio_extra`.
            onObjetivoAgachadoChanged: agachado = objetivoAgachado

            Behavior on agachado {
                NumberAnimation {
                    duration: voz.objetivoAgachado < voz.agachado ? 80 : 600
                    easing.type: Easing.OutQuad
                }
            }

            //  Colocarse solo al empezar a sonar, no en cada fotograma.
            //
            //  Perseguir el cabezal a cada cambio sería mandarle un `seek` treinta
            //  veces por segundo, y un reproductor al que se le pide buscar todo
            //  el rato no llega a reproducir nada. Se coloca al entrar y se deja
            //  correr; el desfase que salga es el precio.
            //  La pista se fija a mano y no con un enlace declarado: Qt la
            //  reinicia a la primera del fichero cada vez que carga el medio,
            //  así que el enlace se lo comía la carga. Por eso se dice en los
            //  dos momentos en que puede haberse perdido: al acabar de cargar y
            //  justo antes de sonar.
            function fijarPista() {
                if (capa && capa.pista !== undefined
                        && mp.activeAudioTrack !== capa.pista)
                    mp.activeAudioTrack = capa.pista
            }

            //  Dónde debería ir el fichero para el instante de línea de ahora.
            readonly property real donde: capa
                ? Math.max(0, extra.segundos - capa.t0) : 0

            //  Con `stop()` por delante cuando el fichero se acabó.
            //
            //  La misma trampa que documenta `Reproductor.avanzar()`: parado en
            //  el último fotograma, escribir `position` NO HACE NADA y encima no
            //  avisa. Sin esto el vigía de abajo llamaría aquí cuatro veces por
            //  segundo, para siempre, sin conseguir mover el medio ni un
            //  milisegundo. `stop()` sí lo devuelve al principio.
            function colocarse() {
                if (mp.mediaStatus === MediaPlayer.EndOfMedia)
                    mp.stop()
                fijarPista()
                mp.position = donde * 1000
                mp.play()
            }

            onDebeSonarChanged: {
                if (debeSonar)
                    colocarse()
                else
                    mp.pause()
            }

            //  Y volver a colocarse cuando el cabezal da un salto.
            //
            //  «Se coloca al entrar y se deja correr» valía mientras la capa
            //  fuera un trozo de música en mitad del vídeo. Con las capas que
            //  salen de separar el audio la capa dura TODO el vídeo, así que
            //  `debeSonar` no cambia nunca y no había ningún momento en que
            //  recolocarse. Dos consecuencias, las dos vistas:
            //
            //  - Al llegar al final el reproductor de arriba da la vuelta; este
            //    se quedaba parado en el fin del fichero y no volvía a sonar en
            //    lo que quedaba de sesión.
            //  - Saltar por la línea mientras suena movía la imagen y dejaba el
            //    sonido donde estaba.
            //
            //  Un vigía flojo, no perseguir el cabezal: si está parado cuando
            //  debería sonar, se coloca y arranca; y si se ha ido más de medio
            //  segundo de donde toca, se recoloca. Medio segundo es holgado a
            //  propósito —dos reproductores independientes derivan solos, y
            //  corregir cada décima sería un chasquido continuo—, pero corta de
            //  raíz la deriva que este fichero daba por inevitable.
            Timer {
                interval: 400
                repeat: true
                running: voz.debeSonar
                onTriggered: {
                    if (mp.playbackState !== MediaPlayer.PlayingState) {
                        voz.colocarse()
                        return
                    }
                    //  Y para recolocar, pausa antes. Escribir `position` con
                    //  el medio en marcha se cumple unas veces y otras no —lo
                    //  midió `Reproductor` y por eso rasca en pausa—, y aquí
                    //  fallar en silencio significaría reintentarlo cada 400 ms
                    //  sin moverse. Un salto ya suena a salto, así que el
                    //  parpadeo de la pausa no añade nada malo.
                    if (Math.abs(mp.position / 1000 - voz.donde) > 0.5) {
                        mp.pause()
                        mp.position = voz.donde * 1000
                        mp.play()
                    }
                }
            }

            MediaPlayer {
                id: mp
                source: voz.capa && voz.capa.ruta
                    ? "file://" + voz.capa.ruta : ""

                onMediaStatusChanged: {
                    if (mediaStatus === MediaPlayer.LoadedMedia)
                        fijarPista()
                }

                //  De qué pista del fichero sale se dice arriba, al empezar a
                //  sonar. Sin decirlo, las dos capas que salen de «separar el
                //  audio» reproducían la misma cosa: la pista por defecto del
                //  fichero, que es la Mezcla —sistema y micro sumados—. Se oían
                //  las dos igual, y bajarle el volumen a la del micro bajaba
                //  media mezcla, no el micro. El render nunca tuvo este fallo
                //  porque allí la pista va dicha por número.
                audioOutput: AudioOutput {
                    //  El volumen del render, recortado en 1.
                    //
                    //  Qt no pasa de ahí y por encima recorta, así que amplificar
                    //  en la previa no se puede: lo que sobra del 100 % solo
                    //  existe en el fichero renderizado, y el panel lo dice.
                    //
                    //  Se intentó por el nodo de Pipewire, que sí pasa de 1, y se
                    //  descartó: WirePlumber PERSISTE el volumen por aplicación,
                    //  así que dejar los nodos de k4 a 3× los deja a 3× también
                    //  en el próximo arranque. Matar la barra con la ganancia
                    //  puesta —que aquí se hace a diario— la grababa para siempre.
                    //  Y por último el agachado, que multiplica: primero
                    //  cuánto quieres que suene, y luego cuánto la deja sonar
                    //  quien manda. En ese orden y no al revés, que es como lo
                    //  hace el render —el `volume` va ANTES del compresor—.
                    volume: !voz.capa ? 0
                        : Math.min(1, voz.capa.volumen !== undefined
                            ? voz.capa.volumen : 0.8) * voz.agachado
                }
            }
        }
    }
}
