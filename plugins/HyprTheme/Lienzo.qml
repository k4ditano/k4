//  El lienzo: el fondo de escritorio, dibujado por la propia barra.
//
//  Hasta ahora el fondo lo ponía swaybg y la barra solo le pasaba una ruta. Eso
//  deja fuera tres cosas a la vez: no hay transiciones —el propio módulo lo
//  admitía en su pie, «instala awww para tenerlas»—, no hay vídeo, y la barra
//  no sabe qué está enseñando, así que no puede sacarle los colores. Pintándolo
//  aquí, en una K4.Ventana en la capa de abajo —que la API aprendió para esto—,
//  el fondo pasa a estar DENTRO del mismo motor que dibuja la island.
//
//  Y sin una sola dependencia nueva: `AnimatedImage` viene en QtQuick y
//  `MediaPlayer` en QtMultimedia, que ya es dependencia declarada desde que el
//  editor de vídeo necesita su descodificador.
//
//  ── swaybg NO se retira: se queda de SUELO ───────────────────────
//
//  Lo que dibuja la barra vive mientras vive la barra, y entre que entras a la
//  sesión y arranca quickshell hay un rato en el que no hay nadie. Si en ese
//  rato el fondo es un rectángulo negro, hemos empeorado algo que funcionaba. Y
//  si un día la barra se cae, lo mismo. Así que a swaybg se le sigue dando el
//  fotograma quieto —para un vídeo, su póster— y el lienzo pinta encima: al
//  entrar ves la foto, y cuando la barra llega se pone en marcha.
//
//  ── lo que cuesta, medido antes de escribirlo ────────────────────
//
//  En un banco aparte, monitor a 60 Hz, sobre el proceso y no a ojo:
//
//      quieto            0,5 % de un núcleo  (y de esos, casi todo es el
//                                             contador de fps del banco)
//      GIF 960 · 20 fps  11,9 %
//      vídeo 1080p60     14–18 %   ·  o sea el 1,5 % de una máquina de 12
//
//  Un GIF cuesta casi lo mismo que un vídeo por la cuarta parte de calidad: se
//  descomprime en CPU y no hay descodificador que valga. Quien traiga un GIF
//  grande hace mejor en convertirlo, y eso es cosa de la pantalla que vendrá.

import QtQuick
import QtMultimedia
import K4 as K4
import "../../services"

K4.PorPantalla {
    id: lienzo

    //  Quien sabe qué fondo va en cada pantalla. Se le pregunta en vez de
    //  guardarlo aquí porque el estado es del plugin —lo guarda, lo carga y lo
    //  publica por IPC— y esto solo pinta.
    required property var plugin

    //  Por la extensión y no preguntando al usuario: nadie quiere elegir en un
    //  desplegable si su fichero es un vídeo. `webp` va por el camino animado a
    //  propósito — uno quieto se pinta igual de bien ahí, y adivinar cuál es
    //  cuál pide abrir el fichero.
    //  ── cuánto se ve, y por tanto si merece la pena moverse ──────
    //
    //  Un fondo animado NO se para solo cuando lo tapan. Medido antes de
    //  escribir nada: 16 % de un núcleo descodificando un vídeo con un terminal
    //  de 1900×1026 encima. Eso es todo el día gastando por nadie, y es la
    //  única de las tres cosas de esta fase que ningún demonio de fondo te da
    //  hecha — de ahí que valga la pena dibujarlo aquí.
    //
    //  Se mide MUESTREANDO y no calculando la unión de rectángulos: la unión
    //  exacta de N ventanas superpuestas es un algoritmo con casos raros, y lo
    //  que hace falta aquí no es un área exacta sino una respuesta a «¿queda
    //  algo de fondo a la vista?». Una rejilla de 16×9 son 144 puntos, se
    //  resuelve con cuatro comparaciones cada uno, y se equivoca como mucho en
    //  un dieciseisavo de pantalla.
    readonly property int rejillaX: 16
    readonly property int rejillaY: 9

    //  Por debajo de esto se para. No es 0 %: con las ventanas en mosaico y los
    //  huecos de Hyprland siempre asoman unas rendijas de fondo, y dejar un
    //  vídeo corriendo por ocho píxeles de rendija es justo lo que se quería
    //  evitar. Un 8 % de pantalla ya es una franja que se ve.
    readonly property real umbralVisible: 0.08

    //  Las ventanas que hay delante, en coordenadas de escritorio.
    function cajasVistas() {
        const cajas = []
        const lista = Ventanas.lista
        for (let i = 0; i < lista.length; ++i) {
            const t = lista[i]
            if (!Ventanas.seVe(t))
                continue
            const d = Ventanas.datos(t)
            if (!d || !d.at || !d.size || d.hidden === true)
                continue
            cajas.push([d.at[0], d.at[1], d.at[0] + d.size[0], d.at[1] + d.size[1]])
        }
        return cajas
    }

    function libresEn(x0, y0, ancho, alto) {
        const cajas = lienzo.cajasVistas()
        let libres = 0
        for (let ix = 0; ix < lienzo.rejillaX; ++ix) {
            const px = x0 + ancho * (ix + 0.5) / lienzo.rejillaX
            for (let iy = 0; iy < lienzo.rejillaY; ++iy) {
                const py = y0 + alto * (iy + 0.5) / lienzo.rejillaY
                let tapado = false
                for (let c = 0; c < cajas.length; ++c) {
                    const b = cajas[c]
                    if (px >= b[0] && px < b[2] && py >= b[1] && py < b[3]) { tapado = true; break }
                }
                if (!tapado) libres += 1
            }
        }
        return libres
    }

    //  Y la respuesta: ¿queda bastante fondo a la vista como para que valga la
    //  pena moverse?
    function seVeAlgoEn(pantalla, x0, y0, ancho, alto) {
        if (!pantalla || ancho <= 0 || alto <= 0)
            return true
        if (lienzo.cajasVistas().length === 0)
            return true
        return lienzo.libresEn(x0, y0, ancho, alto)
            / (lienzo.rejillaX * lienzo.rejillaY) > lienzo.umbralVisible
    }

    function tipoDe(ruta) {
        const r = String(ruta || "").toLowerCase()
        if (/\.(mp4|webm|mkv|mov|m4v|avi)$/.test(r))
            return "video"
        if (/\.(gif|webp|apng)$/.test(r))
            return "animado"
        if (r.length === 0)
            return "nada"
        return "quieto"
    }

    delegate: K4.Ventana {
        id: tela

        required property var modelData
        screen: modelData

        nombre: "k4-fondo"

        //  Debajo de las ventanas. Y sin recoger un solo clic: sin `zonaActiva`
        //  el mask se queda en `null` y esta superficie se lleva TODOS los clics
        //  del escritorio — que en la capa de abajo significa un escritorio que
        //  deja de responder y nadie sabe por qué (ver api/K4/Ventana.qml).
        capa: "fondo"

        //  Y a pantalla COMPLETA, saltándose las reservas ajenas.
        //
        //  Con `reserva: 0` —lo de fábrica— la ventana no reserva sitio pero sí
        //  respeta el de los demás, así que la franja de 34 px de la barra la
        //  empujaba: medido, salía `1920x1046 en (…,34)`. Un fondo de escritorio
        //  que empieza donde acaba la barra deja una banda muerta arriba y
        //  descuadra el encaje de la imagen. `-1` es no reservar nada Y además
        //  saltarse lo ajeno, que es justo lo que hace falta debajo de todo.
        reserva: -1

        zonaActiva: nada

        Item { id: nada; width: 0; height: 0 }

        readonly property string cual: modelData ? modelData.name : ""
        readonly property string ruta: lienzo.plugin
            ? lienzo.plugin.fondoDe(cual) : ""
        readonly property string tipo: lienzo.tipoDe(ruta)

        //  ¿Se ve algo de este fondo? Se recalcula solo: depende de
        //  `Ventanas.lista`, que es reactiva, así que abrir o cerrar una ventana
        //  y cambiar de escritorio ya disparan la cuenta. Un fondo quieto no
        //  pregunta: no gasta nada aunque no se vea.
        readonly property bool aLaVista: tela.tipo === "quieto"
            || tela.tipo === "nada"
            || !tela.screen
            || lienzo.seVeAlgoEn(tela.screen, tela.screen.x, tela.screen.y,
                                 tela.screen.width, tela.screen.height)

        //  Solo existe si hay algo que pintar. Sin fondo asignado no se crea la
        //  superficie: entonces se ve el suelo de swaybg, que es exactamente lo
        //  que había antes de todo esto.
        visible: tela.tipo !== "nada"

        //  Negro debajo de todo: si la imagen no llena la pantalla —una foto
        //  vertical en un monitor apaisado con encaje «entera»— lo que asoma es
        //  esto y no el escritorio de detrás.
        color: "black"

        // ── quieto ──────────────────────────────────────────────
        Image {
            anchors.fill: parent
            visible: tela.tipo === "quieto"
            source: tela.tipo === "quieto" ? "file://" + tela.ruta : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            //  A la resolución de la pantalla y no a la del fichero: una foto
            //  de 6000 px en un monitor de 1920 son 140 MB de textura para
            //  enseñar exactamente lo mismo.
            sourceSize.width: tela.screen ? tela.screen.width : 1920
            sourceSize.height: tela.screen ? tela.screen.height : 1080
        }

        // ── animado (gif, webp) ─────────────────────────────────
        AnimatedImage {
            anchors.fill: parent
            visible: tela.tipo === "animado"
            source: tela.tipo === "animado" ? "file://" + tela.ruta : ""
            fillMode: Image.PreserveAspectCrop
            //  Solo late si se ve, y «verse» es dos cosas: que le toque a este
            //  tipo de fondo Y que no lo tape una ventana. Un AnimatedImage
            //  sigue descomprimiendo fotogramas aunque no lo mire nadie.
            playing: visible && tela.aLaVista
            //  Sin caché: un GIF de fondo son megas que no se van a reusar y
            //  que se quedarían en la caché de imágenes de todo el motor.
            cache: false
        }

        // ── vídeo ───────────────────────────────────────────────
        VideoOutput {
            id: salida
            anchors.fill: parent
            visible: tela.tipo === "video"
            fillMode: VideoOutput.PreserveAspectCrop
        }

        MediaPlayer {
            id: reproductor
            videoOutput: salida
            loops: MediaPlayer.Infinite
            source: tela.tipo === "video" ? "file://" + tela.ruta : ""

            //  Sin AudioOutput a propósito, y no es un olvido: un fondo no
            //  suena. Sin salida de audio el descodificador ni siquiera abre la
            //  pista.
            onSourceChanged: if (source != "") play()

            //  Y se para cuando no se ve. `pause` y no `stop`: parar rebobina,
            //  así que al destapar la ventana el fondo volvería a empezar desde
            //  el principio en vez de seguir donde estaba.
            Component.onCompleted: tela.acompasar()
        }

        //  El vídeo va por función y no por un `playing:` enlazado porque
        //  MediaPlayer no tiene tal property: se le manda `play()` o `pause()`.
        function acompasar() {
            if (tela.tipo !== "video")
                return
            if (tela.aLaVista)
                reproductor.play()
            else
                reproductor.pause()
        }

        onALaVistaChanged: tela.acompasar()
        onTipoChanged: tela.acompasar()

        //  Para poder mirarle las tripas desde fuera: qué pinta cada pantalla,
        //  si se ve y si el vídeo está de verdad en marcha.
        function estado() {
            return { pantalla: tela.cual, tipo: tela.tipo, ruta: tela.ruta,
                     aLaVista: tela.aLaVista,
                     ventanasDelante: lienzo.cajasVistas().length,
                     libres: tela.screen ? lienzo.libresEn(tela.screen.x, tela.screen.y, tela.screen.width, tela.screen.height) : -1,
                     reproduciendo: reproductor.playbackState
                         === MediaPlayer.PlayingState,
                     error: String(reproductor.errorString || "") }
        }
    }
}
