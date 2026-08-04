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
            //  Al vencer, la comprobación que faltaba: ¿el salto se HIZO?
            //  Una búsqueda se pierde a veces —pausado y todo, medido: la
            //  segunda vuelta de una línea con reorden la perdía— y el medio
            //  sigue reproduciendo el trozo viejo; al creerle otra vez, esas
            //  posiciones se mapeaban por el tramo nuevo y el cabezal saltaba
            //  hacia atrás. Si está fuera del trozo, se reintenta y se da
            //  otra tregua, las veces que haga falta: converge en una o dos.
            if (repro.tramo && !repro.tramo.imagen) {
                const s = mp.position / 1000
                if (s < repro.tramo.desde - 0.25
                        || s > repro.tramo.hasta + 0.25) {
                    mp.pause()
                    mp.position = repro.enFuente(repro.cabezal,
                                                 repro.tramo) * 1000
                    tregua.restart()
                    return
                }
            }
            repro.enTregua = false
            if (repro.sonando && mp.playbackState !== MediaPlayer.PlayingState)
                mp.play()
        }
    }

    //  El reloj del cabezal, y no el medio.
    //
    //  Un `MediaPlayer` avisa de su posición cada 50 ms —medido: mediana 50,
    //  máximo 54— y eso es lo que se veía como vibración: a lo ancho de la línea
    //  son saltos de cuatro o cinco píxeles, tres veces por segundo, en vez de
    //  un cabezal que se desliza. La microparada de los cortes era lo mismo,
    //  solo que ahí el hueco es más largo.
    //
    //  Así que el cabezal lo lleva este reloj, que va a 16 ms, y el medio pasa a
    //  ser quien CORRIGE: si se han separado, se acerca poco a poco. Es lo que
    //  hace cualquier reproductor con la barra de progreso, y por lo mismo.
    //
    //  Vale también para los trozos que son una imagen: ahí no hay medio que
    //  avise de nada, y antes hacía falta un segundo temporizador solo para eso.
    property real ultimoTic: 0
    //  Dónde dice el medio que está, y cuándo lo dijo. El reloj lo usa para
    //  corregirse sin dar nunca un paso atrás.
    property real objetivo: -1
    property real objetivoEn: 0

    Timer {
        id: reloj
        interval: 16
        repeat: true
        running: repro.sonando && !repro.rascando && repro.tramos.length > 0
        onTriggered: {
            const ahora = Date.now()
            //  Con el tiempo de verdad y no con `interval`: si el hilo se
            //  entretiene, el reloj no se queda atrás.
            const paso = repro.ultimoTic > 0
                ? Math.min(0.25, (ahora - repro.ultimoTic) / 1000) : 0
            repro.ultimoTic = ahora
            if (paso <= 0 || !repro.tramo)
                return

            //  El ritmo se ajusta para acercarse a lo que dice el medio, pero
            //  nunca baja de cero: si va rezagado se anda más despacio y si va
            //  adelantado más deprisa, y en un segundo se han juntado. Lo que
            //  no se hace es mover el cabezal hacia atrás, que es justo lo que
            //  se veía como vibración.
            let ritmo = 1.0
            if (repro.objetivo >= 0 && !repro.enTregua) {
                const donde = repro.objetivo
                    + (ahora - repro.objetivoEn) / 1000
                const error = donde - repro.cabezal
                ritmo = Math.max(0.5, Math.min(1.5, 1 + error * 2))
            }

            //  Sin multiplicar por la velocidad del trozo: el cabezal va en
            //  tiempo de LÍNEA, y la línea avanza a un segundo por segundo
            //  aunque lo de debajo se esté viendo al cuádruple. Quien corre más
            //  es el fichero, no el reloj.
            const t = repro.cabezal + paso * ritmo
            if (t >= repro.tramo.fin - 0.001) {
                repro.avanzar()
                return
            }
            repro.cabezal = t
            Editor.posicionEditor = t
        }
        onRunningChanged: if (running) repro.ultimoTic = Date.now()
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
        //  El objetivo viejo apuntaba a otro sitio: hasta que el medio vuelva a
        //  hablar, el reloj va solo y a ritmo normal.
        objetivo = -1

        enTregua = true
        tregua.restart()

        //  Un trozo que es una imagen no pasa por el medio: se pinta y punto, y
        //  al reloj lo lleva el `Timer` de abajo. Y se para lo que estuviera
        //  sonando, que si no el vídeo anterior seguiría oyéndose por debajo.
        if (tr.imagen) {
            mp.pause()
            return
        }

        const fuente = "file://" + tr.ruta
        if (mp.source !== fuente) {
            pendiente = enFuente(limpio, tr)
            mp.source = fuente
        } else {
            //  Quieto ANTES de buscar, siempre. Es la lección medida del
            //  rascado —«escribir position con el vídeo en marcha se cumple
            //  unas veces y otras no»— aplicada a los cortes, que hasta hoy
            //  buscaban en marcha: cuando la búsqueda se perdía, el medio
            //  seguía reproduciendo el trozo VIEJO, y al expirar la tregua
            //  esas posiciones se mapeaban por el tramo nuevo y el cabezal
            //  saltaba HACIA ATRÁS. Y en el final del fichero ni la pausa
            //  basta: parado en su último fotograma, `position` no hace nada
            //  —la trampa documentada al dar la vuelta— y `play()` rebobina a
            //  cero él solo; `stop()` sí lo devuelve a un estado que obedece.
            //  Con un trozo reordenado que acaba justo donde acaba el fichero
            //  —lo más normal del mundo—, eso era la línea reiniciándose.
            if (mp.mediaStatus === MediaPlayer.EndOfMedia)
                mp.stop()
            else if (mp.playbackState === MediaPlayer.PlayingState)
                mp.pause()
            mp.position = enFuente(limpio, tr) * 1000
            if (sonando)
                mp.play()
        }
    }

    //  ¿El trozo `b` es la continuación exacta de `a` en el mismo fichero?
    //
    //  Cortar un vídeo por la mitad y no mover nada deja dos trozos que en el
    //  fichero van pegados. En ese caso no hay NADA que buscar: el medio ya
    //  está reproduciendo justo ahí.
    function continua(a, b) {
        return a && b && !a.imagen && !b.imagen && a.ruta === b.ruta
            && Math.abs(b.desde - a.hasta) < 0.05
            && Math.abs(b.velocidad - a.velocidad) < 0.001
    }

    // Al siguiente trozo, o al principio si era el último.
    function avanzar() {
        if (indice + 1 < tramos.length) {
            //  Si el siguiente sigue donde lo dejó el anterior, se pasa de uno a
            //  otro sin tocar el reproductor: ni `position`, ni tregua, ni el
            //  parón que traían. Es el caso más corriente —cortar sin
            //  reordenar— y era donde más se notaba el tirón.
            const sig = tramos[indice + 1]
            if (continua(tramos[indice], sig)) {
                indice = indice + 1
                cabezal = sig.inicio
                //  Mismo fichero y misma posición, pero el instante de LÍNEA es
                //  otro: el objetivo se recalcula con el primer aviso que llegue.
                objetivo = -1
                return
            }
            irA(sig.inicio)
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

    //  La mezcla no cuenta como pista que monitorizar: existe para el mundo de
    //  fuera. Si es la que está sonando —lo es de fábrica, por ir la primera—
    //  se cambia a la primera de las que el editor sí enseña.
    function monitorizarUnaDeVerdad() {
        const pistas = Editor.pistasAudio
        if (!pistas || pistas.length === 0)
            return
        for (let i = 0; i < pistas.length; ++i)
            if (pistas[i].i === mp.activeAudioTrack)
                return
        fijarPistaAudio(primeraQueSuena(pistas))
    }

    //  Cuál monitorizar: la primera que no esté silenciada Y QUE SUENE.
    //
    //  Lo segundo importa más de lo que parece. En una grabación de pantalla
    //  con micro es normalísimo que la pista del sistema esté a silencio
    //  digital —no sonaba nada por los altavoces— y monitorizar esa es abrir
    //  el editor y no oír nada, que es justo la queja de la que sale todo
    //  esto. Los niveles ya se miden al abrir; aquí solo se aprovechan.
    //
    //  Mientras no hayan llegado, vale la primera no silenciada: mejor eso que
    //  esperar callado.
    function primeraQueSuena(pistas) {
        const niveles = Editor.nivelesPistas
        for (let i = 0; i < pistas.length; ++i) {
            const n = niveles[pistas[i].i]
            if (!pistas[i].mudo && n !== undefined && n.pico > -60)
                return pistas[i].i
        }
        for (let i = 0; i < pistas.length; ++i)
            if (!pistas[i].mudo)
                return pistas[i].i
        return pistas[0].i
    }

    //  Y si silencias la que estás oyendo, se pasa a otra en el momento: no
    //  hay que saber que existe un botón de monitor para que esto se porte
    //  como uno espera.
    //  Los niveles llegan unos segundos después de abrir —se miden en
    //  segundo plano—, así que cuando llegan se vuelve a elegir: si la que
    //  estaba sonando resulta ser la muda, se cambia sola.
    property Connections nivelesLlegan: Connections {
        target: Editor
        function onNivelesPistasChanged() {
            const pistas = Editor.pistasAudio
            if (!pistas || pistas.length === 0)
                return
            const n = Editor.nivelesPistas[mp.activeAudioTrack]
            if (n !== undefined && n.pico <= -60)
                repro.fijarPistaAudio(repro.primeraQueSuena(pistas))
        }
    }

    property Connections pistasCambian: Connections {
        target: Editor
        function onPistasAudioChanged() {
            const pistas = Editor.pistasAudio
            if (!pistas || pistas.length === 0)
                return
            //  La lista llega DESPUÉS que el medio —el plan lo trae python—,
            //  así que al cargar el fichero todavía no había con qué decidir y
            //  se quedaba sonando la mezcla. Ahora se decide también aquí.
            repro.monitorizarUnaDeVerdad()
            for (let i = 0; i < pistas.length; ++i)
                if (pistas[i].i === mp.activeAudioTrack && pistas[i].mudo) {
                    repro.fijarPistaAudio(repro.primeraQueSuena(pistas))
                    return
                }
        }
    }

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

            //  Si lo que toca es una imagen, el medio no pinta nada aquí.
            //
            //  Al entrar en un congelado se le da `pause()`, pero todavía llega
            //  algún aviso de posición del vídeo anterior. Como el tramo ya es
            //  el de la imagen, ese instante se comparaba con el `hasta` de la
            //  imagen —que es otro número, de otro fichero— y disparaba el «se
            //  acabó»: el congelado se saltaba entero sin llegar a verse.
            if (repro.enImagen)
                return

            const s = ms / 1000

            //  Recién saltado no se le cree… hasta que diga algo coherente.
            //
            //  La tregua existe porque tras un salto el medio sigue informando
            //  de DÓNDE ESTABA, y hacerle caso descolocaba el cabezal. Pero
            //  esperar los 200 ms enteros cuando el decodificador ya está listo
            //  es tiempo tirado. Así que los 200 ms pasan a ser el TOPE: en
            //  cuanto la posición cae dentro del trozo nuevo y no va por detrás
            //  de lo que ya se ha pintado, se le vuelve a creer.
            if (repro.enTregua) {
                const dentro = s >= repro.tramo.desde - 0.05
                            && s <= repro.tramo.hasta + 0.05
                const enLinea = repro.tramo.inicio
                    + (s - repro.tramo.desde) / (repro.tramo.velocidad || 1)
                if (!dentro || enLinea + 0.02 < repro.cabezal)
                    return
                repro.enTregua = false
                tregua.stop()
            }

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
            const t = repro.tramo.inicio
                + (s - repro.tramo.desde) / (repro.tramo.velocidad || 1)

            //  Y aquí NO se manda, se apunta a dónde debería estar.
            //
            //  Quien mueve el cabezal es el reloj de arriba, que va suave. Este
            //  aviso llega cada 50 ms y si escribiera el valor directamente
            //  volvería a verse a saltos, que es de lo que se venía.
            //
            //  Con la diferencia grande —un salto, un tirón del decodificador—
            //  se hace caso y punto. Con la pequeña, el reloj corrige el RITMO,
            //  que es lo único que no da marcha atrás. Poner aquí
            //  `cabezal += error * 0.1` parecía lo natural y medí 56 retrocesos:
            //  con el error negativo, eso ES un paso atrás.
            repro.objetivo = t
            repro.objetivoEn = Date.now()
            if (Math.abs(t - repro.cabezal) > 0.25) {
                repro.cabezal = t
                Editor.posicionEditor = t
            }
        }

        onMediaStatusChanged: {
            //  Que se acabe el FICHERO no es que se acabe la línea: puede
            //  quedar otro trozo, y puede estar en el mismo fichero más atrás.
            //
            //  Pero un fin de fichero RECIÉN SALTADO no vale: cuando un trozo
            //  acaba donde acaba el fichero, el aviso de posición ya ha hecho
            //  el avance y este EndOfMedia llega rezagado, del sitio VIEJO.
            //  Hacerle caso era avanzar dos veces —la segunda desde el último
            //  tramo—, o sea dar la vuelta entera: la línea se reiniciaba
            //  sola en mitad de la reproducción. La tregua ya dice «acabamos
            //  de saltar»: durante ella, los finales viejos se ignoran.
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                if (!repro.enTregua)
                    repro.avanzar()
                return
            }
            if (mediaStatus !== MediaPlayer.LoadedMedia
                    && mediaStatus !== MediaPlayer.BufferedMedia)
                return

            //  Monitorizar una pista de VERDAD, no la mezcla.
            //
            //  Las grabaciones llevan delante una pista mezclada para que
            //  suenen al abrirlas en cualquier reproductor, y esa es la que
            //  Qt elige sola por ser la primera. Aquí estorba: se oirían las
            //  dos siempre, sin saber cuál estás tocando y sin que se note
            //  cuál has silenciado. Así que si la que suena no está en la
            //  lista del editor, se pasa a la primera que sí.
            repro.monitorizarUnaDeVerdad()

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
        visible: !repro.enImagen
    }

    readonly property bool enImagen: tramo && tramo.imagen === true

    //  El trozo que es una imagen, pintado tal cual.
    //
    //  `PreserveAspectFit` como el vídeo: en el render la imagen pasa por la
    //  misma normalización —escalar sin deformar y rellenar con negro— así que
    //  aquí hay que hacer lo mismo o la previa mentiría sobre el encuadre.
    Image {
        anchors.fill: parent
        visible: repro.enImagen
        source: repro.enImagen ? "file://" + repro.tramo.ruta : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
    }

    //  Los trozos que son una imagen no necesitan nada aparte: el reloj de
    //  arriba los lleva igual que a los demás. Antes tenían su propio
    //  temporizador porque el cabezal lo movía el medio, y una imagen no tiene
    //  medio que lo mueva.

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
