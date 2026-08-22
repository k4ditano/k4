pragma Singleton

//  Capturas de pantalla y grabación.
//
//  Todo el estado vive aquí y no en el plugin, por una razón concreta: se puede
//  estar grabando diez minutos con la island cerrada, y un plugin solo existe
//  mientras es el módulo activo. El singleton está siempre, así que la píldora
//  de «grabando» puede leerlo desde cualquier vista.
//
//  El trabajo sucio —construir la orden de grim, decidir el nombre, copiar al
//  portapapeles— lo hace tools/captura.py, que contesta con una línea JSON. Eso
//  permite distinguir «lo has cancelado» de «ha fallado», que con el simple
//  código de salida son lo mismo.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: captura

    // ── ajustes ───────────────────────────────────────────────────
    //
    //  Vienen de Settings, que es donde se tocan. Aquí eran valores a fuego con
    //  un comentario prometiendo que algún día los leerían de ahí.
    //
    //  Solo de lectura, y el menú de la island escribe la PREFERENCIA.
    //
    //  Antes el menú escribía aquí directamente, y eso tenía dos problemas a la
    //  vez: rompía el binding —así que dejar de seguir a Settings para siempre—
    //  y la elección no sobrevivía a reiniciar la barra. Elegir «Copiar» en el
    //  menú quiere decir «esta y las siguientes», o sea exactamente cambiar la
    //  preferencia.
    readonly property string destino: Settings.capturaDestino
    readonly property bool conCursor: Settings.capturaCursor

    // ── estado ────────────────────────────────────────────────────
    //  "" · capturando · cuenta · grabando · cerrando
    //
    //  Editar tiene su propio estado, en services/Editor.qml: se puede estar
    //  renderizando un vídeo de hace un rato y grabando otro a la vez.
    property string estado: ""

    property string ultimaRuta: ""
    property int ultimaAncho: 0
    property int ultimaAlto: 0
    property bool ultimaCopiada: false
    property string ultimoFallo: ""         // clave, no frase

    readonly property bool ocupado: estado.length > 0

    // Se emite cuando una foto acaba bien: el plugin la usa para asomarse un
    // momento con la miniatura.
    signal fotoLista(string ruta)
    signal fotoFallida(string motivo, string detalle)

    // ── carpetas ──────────────────────────────────────────────────
    property string carpetaFotos: ""
    property string carpetaVideos: ""

    // ── elegir una región ─────────────────────────────────────────
    //
    //  El selector no pregunta sobre el escritorio vivo sino sobre un
    //  fotograma congelado, y eso arregla de raíz un problema que tiene
    //  slurp: si lo que quieres recortar es un menú desplegado o algo que
    //  cambia, se te mueve mientras lo encuadras.
    property bool seleccionando: false
    property string motivoSeleccion: "foto"   // foto · grabar

    //  Destino de ESTA captura, si se pidió uno distinto del habitual. Hay que
    //  guardarlo aparte porque entre pedir la región y confirmarla pasa un
    //  rato largo —el que tardes en encuadrar— y la llamada original ya
    //  terminó hace tiempo.
    property string destinoPuntual: ""
    property string congelado: ""
    property int serieCongelado: 0

    signal regionElegida(int x, int y, int w, int h)

    //  ── el escudo ─────────────────────────────────────────────────
    //
    //  Entre que pides una captura y que el fotograma está congelado pasan casi
    //  200 ms, y en ese rato el escritorio está vivo: el clic con el que ibas a
    //  encuadrar se lo llevaba la aplicación de debajo —pausaba el vídeo que
    //  querías capturar, por ejemplo—. Y al revés al terminar: el selector se
    //  quita al soltar y el segundo clic del impaciente cae en la ventana.
    //
    //  Así que el cristal se pone ANTES de congelar y se quita un poco DESPUÉS
    //  de disparar. Es transparente mientras no hay nada que enseñar, así que
    //  no sale en la foto; lo único que hace es tragarse los clics.
    property bool tapando: false

    Timer {
        id: destapar
        interval: 350
        onTriggered: captura.tapando = false
    }

    function pedirRegion(motivo) {
        if (ocupado || seleccionando)
            return
        motivoSeleccion = motivo || "foto"
        estado = "capturando"
        tapando = true
        destapar.stop()
        Island.escondida = true

        //  Pedir a Hyprland las medidas de las ventanas otra vez. Las que trae
        //  de serie son las de la última vez que pasó algo, y «algo» puede ser
        //  de hace horas: al arrancar la barra reserva su franja y las ventanas
        //  encogen, pero esa lista se quedó con las de antes. Señalar una
        //  ventana recortaba 34 px de más y salía una tira de escritorio arriba.
        //  Aquí sobra tiempo —el congelado tarda su rato— para que llegue.
        Ventanas.refrescar()
        congelar.restart()
    }

    function cancelarRegion() {
        seleccionando = false
        tapando = false
        destapar.stop()
        destinoPuntual = ""
        estado = ""
    }

    function confirmarRegion(x, y, w, h) {
        if (w < 1 || h < 1) {
            seleccionando = false
            tapando = false
            estado = ""
            return
        }

        regionElegida(x, y, w, h)

        if (motivoSeleccion === "foto") {
            // Se recorta del congelado, no se vuelve a capturar: lo que sale
            // es exactamente lo que estabas viendo al encuadrar.
            estado = "capturando"
            pendienteOrden = ["python3", Quickshell.shellPath("tools/captura.py"),
                              "foto", "--ambito", "region",
                              "--destino", destinoPuntual.length > 0
                                                ? destinoPuntual : destino,
                              "--desde", congelado,
                              "--geometria", x + "," + y + " " + w + "x" + h]
            disparo.command = pendienteOrden
            disparo.running = true
        } else if (motivoSeleccion === "grabar") {
            estado = ""
            grabar(x + "," + y + " " + w + "x" + h)
        } else {
            estado = ""
        }
        destinoPuntual = ""

        // Lo último: bajar esta bandera destruye la ventana del selector, que
        // es justo desde donde se ha llamado aquí. El cristal se queda un poco
        // más, tragándose lo que venga detrás del clic que acaba de disparar.
        seleccionando = false
        destapar.restart()
    }

    Timer {
        id: congelar
        interval: 90
        onTriggered: {
            captura.serieCongelado += 1
            // El número que sube no es un capricho: Qt cachea las imágenes por
            // ruta, y reutilizar el mismo nombre devuelve el fotograma de la
            // captura anterior.
            const ruta = "/tmp/k4-captura/congelado-" + captura.serieCongelado + ".ppm"
            congelador.command = ["grim", "-t", "ppm", ruta]
            congelador.pendiente = ruta
            congelador.running = true
        }
    }

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        id: congelador
        property string pendiente: ""

        onExited: function (codigo) {
            Island.escondida = false
            captura.estado = ""
            if (codigo === 0) {
                captura.congelado = pendiente
                captura.seleccionando = true
            } else {
                // Sin fotograma no hay nada que encuadrar: fuera el cristal, o
                // el escritorio se queda sordo a los clics sin explicación.
                captura.tapando = false
                captura.ultimoFallo = "fallo"
                captura.fotoFallida("fallo")
            }
        }
    }

    // ── hacer una foto ────────────────────────────────────────────
    //
    //  `ambito` es pantalla | region | ventana. La geometría se puede dar hecha
    //  —es lo que hará el selector propio— o dejar que el guion la pregunte.
    //  `aDonde` es opcional y vale para una sola foto: capturar «para anotar»
    //  no debe cambiarte el destino de todas las capturas siguientes.
    function foto(ambito, geometria, aDonde) {
        if (ocupado)
            return

        ultimoFallo = ""
        estado = "capturando"

        const args = ["python3", Quickshell.shellPath("tools/captura.py"), "foto",
                      "--ambito", ambito || "pantalla",
                      "--destino", (aDonde && aDonde.length > 0) ? aDonde : destino]
        if (conCursor)
            args.push("--cursor")
        if (geometria && geometria.length > 0)
            args.push("--geometria", geometria)
        else if (ambito === "pantalla")
            args.push("--salida", monitorActual())

        //  La island se aparta y se espera un frame largo antes de disparar.
        //  Si no, grim sale corriendo antes de que el compositor haya
        //  compuesto el fotograma sin ella y la barra acaba en la foto.
        pendienteOrden = args
        Island.escondida = true
        apartarse.restart()
    }

    property var pendienteOrden: []

    Timer {
        id: apartarse
        interval: 90
        onTriggered: {
            disparo.command = captura.pendienteOrden
            disparo.running = true
        }
    }

    // Red de seguridad: si el guion se queda colgado, la barra no puede
    // quedarse invisible para siempre.
    Timer {
        id: reaparecer
        interval: 20000
        running: Island.escondida
        onTriggered: Island.escondida = false
    }

    // ── grabar ────────────────────────────────────────────────────
    //
    //  Quien graba es wf-recorder, y se para con SIGINT y no matándolo: un
    //  contenedor MP4 necesita que le escriban el índice al final, y un vídeo
    //  sin índice no lo abre nadie. De ahí que el fichero no se dé por bueno
    //  hasta `onExited`.
    property bool grabando: false
    property double inicio: 0
    property int duracion: 0                  // segundos, para el cronómetro
    property string rutaVideo: ""
    property string regionActual: ""          // "" = pantalla entera

    // De Settings, igual que los de arriba. Ver el comentario de los ajustes.
    readonly property string audio: Settings.grabarAudio
    readonly property string codec: Settings.grabarCodec
    readonly property int fps: Settings.grabarFps
    // NVENC no existe en todos los equipos aunque ffmpeg liste el códec: si
    // se fuerza en una máquina Intel/AMD, wf-recorder muere al arrancar y la
    // barra solo parece «cerrar» la grabación. Se comprueba el driver real y
    // se cae a libx264/libx265 cuando no hay NVIDIA.
    property bool nvencDisponible: false

    property int cuentaAtras: 0

    signal videoListo(string ruta)
    signal videoFallido(string motivo, string detalle)

    readonly property string duracionTexto: {
        const m = Math.floor(duracion / 60)
        const sg = duracion % 60
        return (m < 10 ? "0" : "") + m + ":" + (sg < 10 ? "0" : "") + sg
    }

    function grabar(region) {
        if (grabando || estado === "cuenta")
            return
        regionActual = region || ""
        // Tres segundos de cortesía: da tiempo a colocar la ventana y a apartar
        // el ratón, y ocurre ANTES de arrancar wf-recorder, así que la cuenta
        // atrás no sale en el vídeo.
        cuentaAtras = 3
        estado = "cuenta"
        tictac.restart()
    }

    function grabarRegion() {
        if (grabando)
            return
        pedirRegion("grabar")
    }

    function parar() {
        if (estado === "cuenta") {
            // Aún no había empezado: cancelar es simplemente no empezar.
            tictac.stop()
            cuentaAtras = 0
            estado = ""
            return
        }
        if (!grabando)
            return
        estado = "cerrando"
        grabador.signal(2)                    // SIGINT
        rescate.restart()
    }

    function alternarGrabacion() { grabando || estado === "cuenta" ? parar() : grabar("") }

    function arrancarGrabador() {
        //  Por si has enchufado una webcam desde que arrancó la barra, que es
        //  lo normal: se mira ahora y no solo al principio.
        buscarCamaras()
        //  Y el sonido, por lo mismo y con más motivo: no se arranca el
        //  grabador hasta tener la lista de dispositivos de este momento. Un
        //  nombre de hace horas no da una grabación muda —eso sería lo de
        //  menos—, da una grabación que no existe: gpu-screen-recorder se
        //  niega a arrancar si el dispositivo que le nombras no está, y sale
        //  en cincuenta milisegundos sin escribir un solo fotograma.
        refrescarAudios(function () { pedirNombreVideo.running = true })
    }

    Timer {
        id: tictac
        interval: 1000
        repeat: true
        onTriggered: {
            captura.cuentaAtras -= 1
            if (captura.cuentaAtras <= 0) {
                stop()
                captura.estado = ""
                captura.arrancarGrabador()
            }
        }
    }

    // El nombre lo decide el guion, que es quien sabe esquivar colisiones.
    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        id: pedirNombreVideo
        command: ["python3", Quickshell.shellPath("tools/captura.py"),
                  "nombre", "--que", "video"]
        stdout: StdioCollector {
            onStreamFinished: {
                let ruta = ""
                try { ruta = JSON.parse(this.text).ruta || "" } catch (e) { }
                if (ruta.length === 0) {
                    captura.videoFallido("fallo")
                    return
                }
                captura.rutaVideo = ruta
                const orden = captura.ordenGrabar(ruta)
                // No arranques un grabador sin salida: wf-recorder/gsr crean
                // un MP4 vacío y el fallo acaba pareciendo una grabación negra.
                if (orden.length === 0) {
                    captura.rutaVideo = ""
                    captura.videoFallido("sin-monitor")
                    return
                }
                grabador.command = orden
                grabador.running = true
            }
        }
    }

    // ── dos pistas de verdad, cuando se puede ─────────────────────
    //
    //  wf-recorder solo acepta UN dispositivo de audio. Para tener sistema y
    //  micro por separado había que arrancar un segundo ffmpeg para el micro y
    //  juntarlos al final; y ahí estaba el fallo que se oía: dos procesos son
    //  DOS RELOJES. Cada uno empieza a contar cuando arranca, el juntado los
    //  pegaba en el instante cero sin compensar nada, y el micro quedaba por
    //  detrás del vídeo.
    //
    //  Medir ese desfase y restarlo sería mentir: el número dependería de esta
    //  máquina, de este códec y de este día. Lo que se arregla no es el desfase,
    //  es que haya dos relojes.
    //
    //  gpu-screen-recorder acepta `-a` repetido y saca una pista por cada uno
    //  DESDE UN SOLO PROCESO. Un reloj, ningún desfase que compensar, nada que
    //  calibrar. Se usa solo cuando hace falta —«ambos»— y solo si está: para
    //  todo lo demás wf-recorder ya iba bien y no se toca.
    property bool gsrDisponible: false

    readonly property bool grabaDosPistas: gsrDisponible && audio === "ambos"

    Process {
        id: comprobarGsr
        command: ["sh", "-c", "command -v gpu-screen-recorder >/dev/null 2>&1"]
        running: true
        onExited: function (codigo) { captura.gsrDisponible = codigo === 0 }
    }

    //  gpu-screen-recorder charla por stderr aunque vaya todo bien: un «update
    //  fps» por segundo, más el saludo del servidor de KMS al arrancar. Sin
    //  filtrar, diez minutos de grabación dejan seiscientos avisos en el log y
    //  entierran el error del día que sí falle.
    function ruidoDeGrabador(l) {
        const t = String(l).trim()
        return t.length === 0
                || t.startsWith("gsr info:")
                || t.startsWith("kms server info:")
                || t.startsWith("update fps:")
    }

    function ordenGrabarGsr(ruta) {
        const orden = ["gpu-screen-recorder"]

        if (regionActual.length > 0) {
            //  wf-recorder pide «x,y wxh» y gsr pide «WxH+X+Y»: es la misma
            //  región dicha del revés, y `regionActual` se guarda en el formato
            //  del primero porque también lo usa la foto.
            const partes = regionActual.split(" ")
            const xy = (partes[0] || "0,0").split(",")
            orden.push("-w", "region",
                       "-region", (partes[1] || "0x0")
                                  + "+" + (xy[0] || "0") + "+" + (xy[1] || "0"))
        } else {
            const pantalla = monitorActual()
            if (pantalla.length === 0)
                return []
            orden.push("-w", pantalla)
        }

        //  `-fm cfr` por el mismo motivo que el `-D` de wf-recorder: a ritmo
        //  variable el `t` del vídeo deja de corresponderse con el tiempo real
        //  y el zoom en posproceso cae descuadrado. El defecto de gsr es vfr.
        orden.push("-f", String(fps),
                   "-k", codec === "hevc" ? "hevc" : "h264",
                   "-q", "very_high",
                   "-fm", "cfr",
                   "-ac", "aac",
                   //  Aquí no se comprueba NVENC a mano: gsr sabe usar la GPU
                   //  de AMD e Intel además de la de NVIDIA, así que decidirlo
                   //  nosotros solo podría estropearlo. Si no puede, que baje a
                   //  CPU en vez de morirse.
                   "-fallback-cpu-encoding", "yes")

        //  Una pista por cada `-a`, y en este orden: sistema primero y micro
        //  después, que es como las espera el juntado.
        orden.push("-a", audioParaGsr(monitorElegido, false),
                   "-a", audioParaGsr(microElegido, true),
                   "-o", ruta)
        return orden
    }

    //  El nombre de un dispositivo tal y como lo entiende gsr.
    //
    //  `@DEFAULT_MONITOR@` y `@DEFAULT_SOURCE@` son comodines de PulseAudio, y
    //  ffmpeg los resuelve; gsr no. Para él son un nombre cualquiera, no lo
    //  encuentra, y se muere en el sitio en vez de coger el de por defecto.
    //  Los suyos se llaman de otra forma, y son los que hay que darle mientras
    //  no sepamos el nombre de verdad.
    function audioParaGsr(nombre, esMicro) {
        const n = String(nombre)
        if (n.length === 0 || n.indexOf("@") === 0)
            return esMicro ? "default_input" : "default_output"
        return "device:" + n
    }

    function ordenGrabar(ruta) {
        if (grabaDosPistas)
            return ordenGrabarGsr(ruta)

        const esNvenc = nvencDisponible
        const codificador = esNvenc
                ? (codec === "hevc" ? "hevc_nvenc" : "h264_nvenc")
                : (codec === "hevc" ? "libx265" : "libx264")
        const orden = ["wf-recorder", "-f", ruta, "-c", codificador]

        if (esNvenc) {
            orden.push("-p", "preset=p5", "-p", "rc=vbr", "-p", "cq=23")
        } else {
            // `cq` y `rc` son opciones de NVENC; libx264/libx265 usan CRF.
            // veryfast evita que la CPU se quede atrás en grabaciones a 60 Hz.
            orden.push("-p", "preset=veryfast", "-p", "crf="
                       + (codec === "hevc" ? "28" : "23"))
        }
        orden.push("-r", String(fps),
                       // Fotogramas a ritmo constante. No es opcional: sin
                       // esto wf-recorder solo emite cuando algo cambia, y
                       // entonces el `t` de un vídeo no se corresponde con el
                       // tiempo real. El zoom en posproceso caería descuadrado.
                       "-D")

        if (regionActual.length > 0)
            orden.push("-g", regionActual)
        else {
            const pantalla = monitorActual()
            if (pantalla.length === 0)
                return []
            orden.push("-o", pantalla)
        }

        //  `--audio=<dispositivo>` y no `-a <dispositivo>`.
        //
        //  wf-recorder documenta `-a[=DEVICE]` con el valor PEGADO: pasarlo
        //  suelto hace que tome el dispositivo por defecto y se coma el nombre
        //  como argumento posicional. El resultado era una pista de audio
        //  perfectamente válida y en silencio digital —-91 dB—, porque el
        //  dispositivo por defecto es el micro y está mudo. Grababa sin sonido
        //  sin quejarse una sola vez.
        //  «ambos» graba el SISTEMA aquí; el micro va por su cuenta en otro
        //  proceso y se junta al final. Sin esta rama wf-recorder no recibía
        //  fuente ninguna y el vídeo salía mudo, con lo que el juntado
        //  producía vídeo + micro: una sola pista, y encima la equivocada.
        if (audio === "sistema" || audio === "ambos")
            orden.push("--audio=" + monitorElegido)
        else if (audio === "micro")
            orden.push("--audio=" + microElegido)

        return orden
    }

    // El monitor del sink por defecto, que es por donde sale el sonido del
    // sistema. Se pregunta antes de cada grabación —lo hace `refrescarAudios`,
    // desde `arrancarGrabador`— y no solo al arrancar la barra: cambia al
    // enchufar unos auriculares, y también al despertar un monitor por HDMI,
    // que trae su propia salida de sonido y se la lleva al irse.
    //
    // El comentario de antes ya decía «se pregunta cada vez que empieza una
    // grabación». No era verdad: se preguntaba una vez, al arrancar, en un
    // Process suelto sin nombre que nadie podía volver a lanzar.
    property string sinkMonitor: "@DEFAULT_MONITOR@"

    // El micrófono por defecto, por el mismo motivo y por el mismo camino.
    property string fuenteMicro: "@DEFAULT_SOURCE@"

    // ── qué dispositivos hay, y cuál se usa ───────────────────────
    //
    //  En Ajustes se puede fijar un micrófono y una salida concretos; en
    //  «auto» se sigue al del sistema, que es lo de siempre. Las listas las
    //  trae pactl vía tools/captura.py, con su etiqueta legible, y se
    //  refrescan al arrancar y al abrir Ajustes: enchufar unos auriculares a
    //  mitad de sesión es lo normal.
    property var microfonos: []
    property var salidasAudio: []

    //  Y cuáles son los del sistema ahora mismo. Hacen falta para poder decir
    //  en Ajustes QUÉ va a grabar «automático»: sin el nombre delante, elegir
    //  automático es elegir a ciegas —y en esta casa el defecto resultó ser el
    //  micro de unos cascos, así que la grabación salía muda sin una pista de
    //  por qué—.
    property string microDefecto: ""
    property string salidaDefecto: ""

    function etiquetaDe(nombre, lista) {
        for (let i = 0; i < lista.length; ++i)
            if (lista[i].nombre === nombre)
                return lista[i].etiqueta
        return ""
    }

    readonly property string etiquetaMicroDefecto: etiquetaDe(microDefecto, microfonos)
    readonly property string etiquetaSalidaDefecto: etiquetaDe(salidaDefecto, salidasAudio)

    function buscarAudios() { refrescarAudios(null) }

    //  Preguntar qué hay enchufado, y avisar cuando se sepa.
    //
    //  Lo segundo es la mitad importante: quien va a grabar necesita ESPERAR a
    //  la respuesta, no lanzarla y seguir con los nombres de antes. `despues`
    //  se llama una sola vez, venga la lista o no venga.
    property var trasAudios: null

    function refrescarAudios(despues) {
        trasAudios = despues || null
        if (trasAudios)
            esperaAudios.restart()
        if (!buscadorAudios.running)
            buscadorAudios.running = true
    }

    function seguirTrasAudios() {
        const seguir = trasAudios
        if (!seguir)
            return
        trasAudios = null
        esperaAudios.stop()
        seguir()
    }

    //  Y si pactl se atasca, la cuenta atrás no puede acabar en nada: se sigue
    //  con lo último que se sepa, que es lo que se hacía siempre.
    Timer {
        id: esperaAudios
        interval: 1500
        onTriggered: captura.seguirTrasAudios()
    }

    Process {
        id: buscadorAudios
        command: ["python3", Quickshell.shellPath("tools/captura.py"), "audios"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (d && d.ok) {
                    captura.microfonos = d.microfonos || []
                    captura.salidasAudio = d.salidas || []
                    captura.microDefecto = d.micro_defecto || ""
                    captura.salidaDefecto = d.salida_defecto || ""

                    //  El dispositivo por defecto sale de la MISMA consulta que
                    //  la lista, y no de dos `pactl` sueltos como antes: eran
                    //  dos fotos del sonido en dos instantes distintos que
                    //  luego se comparaban entre sí como si fueran la misma.
                    if (captura.salidaDefecto.length > 0)
                        captura.sinkMonitor = captura.salidaDefecto + ".monitor"
                    if (captura.microDefecto.length > 0)
                        captura.fuenteMicro = captura.microDefecto
                }
                captura.seguirTrasAudios()
            }
        }
        //  Por si el guion se cae antes de escribir nada: el que espera tiene
        //  que enterarse igual.
        onExited: captura.seguirTrasAudios()
    }

    //  El dispositivo que se usa de verdad: el fijado en Ajustes, si sigue
    //  enchufado, y si no el del sistema. Un micro fijado y desenchufado no
    //  debe dejar la grabación muda ni rota: se vuelve al de siempre.
    function entreLos(nombre, lista) {
        for (let i = 0; i < lista.length; ++i)
            if (lista[i].nombre === nombre)
                return true
        return false
    }

    readonly property string microElegido:
        Settings.grabarMicro !== "auto" && entreLos(Settings.grabarMicro, microfonos)
            ? Settings.grabarMicro : fuenteMicro

    readonly property string monitorElegido: salidaViva(
        Settings.grabarSalida !== "auto" && entreLos(Settings.grabarSalida, salidasAudio)
            ? Settings.grabarSalida + ".monitor" : sinkMonitor)

    //  Y la última red: que el nombre que se va a usar esté en la lista de
    //  ahora mismo.
    //
    //  El micro fijado ya se comprobaba; la salida no se comprobaba nunca,
    //  porque venía del sistema y se daba por buena. Pero la salida del sistema
    //  también se puede ir: la del monitor por HDMI desaparece con el monitor,
    //  y si era la de por defecto el nombre guardado apunta a un hueco. Si el
    //  que toca no está, se coge el primero que sí, que es lo que hace el resto
    //  de la casa cuando se desenchufa algo.
    function salidaViva(nombre) {
        if (salidasAudio.length === 0)
            return nombre
        const base = String(nombre).replace(/\.monitor$/, "")
        if (entreLos(base, salidasAudio))
            return nombre
        return salidasAudio[0].nombre + ".monitor"
    }

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        id: comprobarNvenc
        command: ["sh", "-c",
                  "command -v nvidia-smi >/dev/null 2>&1 && "
                  + "nvidia-smi -L >/dev/null 2>&1"]
        running: true
        onExited: function (codigo) {
            captura.nvencDisponible = codigo === 0
        }
    }

    //  Aquí vivían dos `Process` sueltos que preguntaban por el sink y por la
    //  fuente por defecto. Corrían una vez, al arrancar la barra, y no tenían
    //  ni nombre: no había forma de volver a lanzarlos. Ahora los dos nombres
    //  salen de `buscadorAudios`, que ya preguntaba las dos listas en la misma
    //  llamada y sí se puede repetir.

    //  El rastro del cursor, que es la materia prima del zoom automático.
    //
    //  Va en su propio proceso y no aquí porque hay que muestrear a 30 Hz sin
    //  competir con el hilo de dibujo de la barra. Se le hablan los clics por
    //  la entrada estándar: Hyprland no los publica por su socket de eventos,
    //  así que los recoge un atajo global y se los pasamos.
    property string rutaRastro: ""

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        id: rastreador
        stdinEnabled: true
    }

    function marcarClic(boton) {
        if (grabando && rastreador.running)
            rastreador.write("clic " + boton + "\n")
    }

    //  El micro, grabado aparte.
    //
    //  El respaldo para cuando no hay gpu-screen-recorder. wf-recorder solo
    //  acepta UN dispositivo de audio, así que sistema y micro por separado
    //  obligan a un segundo proceso.
    //
    //  Aquí decía que el desfase eran «decenas de milisegundos, que en un clip
    //  corto no se nota», y era falso: se oía. Son dos relojes distintos, el
    //  juntado los pega en el cero sin compensar y el micro va por detrás. No
    //  tiene arreglo por este camino —cualquier número que se restara valdría
    //  para una máquina y no para la siguiente—; el arreglo es no tener dos
    //  procesos, y eso es lo que hace `grabaDosPistas`.
    //
    //  Separado y no mezclado: mezclarlo al grabar es irreversible, y lo que se
    //  quiere es poder bajarle el volumen a uno de los dos después.
    property string rutaMicro: ""

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        id: grabadorMicro

        //  Es SU salida la que dispara el juntado, no un temporizador.
        //
        //  Con un respiro de 900 ms se juntaba el m4a mientras ffmpeg todavía
        //  lo estaba cerrando, y salía un fichero con una sola pista sin que
        //  nada se quejara. Esperar a que el proceso muera es la única forma de
        //  saber que el fichero está entero.
        //
        //  El 255 es lo que devuelve ffmpeg al recibir un SIGINT: es una parada
        //  limpia, no un fallo.
        onExited: function (codigo) {
            if (captura.estado === "cerrando")
                captura.juntarPistas()
        }
    }

    function ordenMicro(ruta) {
        return ["ffmpeg", "-v", "error", "-y",
                "-f", "pulse", "-i", microElegido,
                "-c:a", "aac", "-b:a", "160k", ruta]
    }

    // ── la cámara ─────────────────────────────────────────────────
    //
    //  Se graba en un fichero APARTE, no incrustada en el vídeo. Así en el
    //  editor es una capa más: se coloca, se escala, se le quita el fondo o se
    //  tira. Incrustarla al grabar es irreversible, que es justo lo que se ha
    //  evitado también con el micro.
    //
    //  Qué cámaras hay se pregunta al kernel, no a ffmpeg: `/sys/class/video4linux`
    //  las lista aunque ffmpeg no esté compilado con v4l2, y hay que saberlo
    //  ANTES de ofrecer el interruptor. Se mira al arrancar y cada vez que se va
    //  a grabar, que es cuando importa: enchufar una webcam a mitad de sesión es
    //  lo normal.
    property var camaras: []
    readonly property bool hayCamara: camaras.length > 0
    property string rutaCamara: ""

    function buscarCamaras() { rastreoCamaras.running = true }

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        id: rastreoCamaras
        running: true
        //  El nombre bonito sale de `name`, que es lo que enseña el sistema; si
        //  no está, el nodo a secas ya distingue una de otra.
        command: ["sh", "-c",
            "for d in /sys/class/video4linux/video*; do " +
            "[ -e \"$d\" ] || continue; " +
            "n=$(cat \"$d/name\" 2>/dev/null || echo); " +
            "echo \"/dev/$(basename $d)|$n\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const salida = []
                const lineas = String(this.text).trim().split("\n")
                for (let i = 0; i < lineas.length; ++i) {
                    const l = lineas[i].trim()
                    if (l.length === 0)
                        continue
                    const p = l.split("|")
                    salida.push({ nodo: p[0], nombre: p[1] || p[0] })
                }
                captura.camaras = salida
            }
        }
    }

    //  Qué dispositivo usar: el elegido si sigue estando, y si no el primero.
    //
    //  «Si sigue estando» importa: los nodos se renumeran al enchufar y
    //  desenchufar, y guardarse un /dev/video2 que ya no existe dejaría la
    //  grabación sin cámara sin decir por qué.
    readonly property string camaraElegida: {
        const puesto = Settings.camaraDispositivo
        if (puesto.startsWith("lavfi:"))
            return puesto
        for (let i = 0; i < camaras.length; ++i)
            if (camaras[i].nodo === puesto)
                return puesto
        return camaras.length > 0 ? camaras[0].nodo : ""
    }

    function ordenCamara(ruta) {
        const orden = ["ffmpeg", "-v", "error", "-y"]
        //  `lavfi:` es una cámara de mentira, para poder probar todo esto sin
        //  tener una enchufada: `lavfi:testsrc2=s=640x480:r=30`. No es un apaño
        //  de laboratorio, también vale para grabar una demo sin salir en ella.
        if (camaraElegida.startsWith("lavfi:"))
            //  `-re` para que vaya a ritmo real: una fuente de lavfi genera tan
            //  deprisa como el codificador trague, y sin esto seis segundos de
            //  grabación salían veinte minutos de vídeo. Una cámara de verdad
            //  la limita el hardware; esta hay que limitarla a mano, y con eso
            //  se comporta igual.
            orden.push("-re", "-f", "lavfi", "-i", camaraElegida.substring(6))
        else
            orden.push("-f", "v4l2", "-framerate", "30", "-i", camaraElegida)
        //  `ultrafast` y sin audio: la cámara es una esquina del fotograma, no
        //  hace falta apretarla, y el sonido ya lo lleva el micro.
        return orden.concat(["-c:v", "libx264", "-preset", "ultrafast",
                             "-pix_fmt", "yuv420p", "-an", ruta])
    }

    //  Cuánto se ha adelantado la pantalla a la cámara, en segundos.
    //
    //  Dos procesos no arrancan en el mismo milisegundo, y lo honesto es
    //  medirlo y apuntarlo en vez de fingir que sí. La capa nace con ese
    //  desfase ya restado; si aún baila, el recorte se ajusta a mano.
    property real desfaseCamara: 0
    property real inicioPantalla: 0

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        id: grabadorCamara
        //  El instante en que la cámara empezó de verdad, para saber cuánto se
        //  le adelantó la pantalla. Son decenas de milisegundos.
        onStarted: captura.desfaseCamara =
            Math.max(0, (Date.now() - captura.inicioPantalla) / 1000)
    }

    //  Se le entrega al editor junto con el vídeo, y solo una vez.
    function pasarCamaraAlEditor() {
        if (rutaCamara.length === 0)
            return
        Editor.camaraPendiente = rutaCamara
        Editor.desfasePendiente = desfaseCamara
        rutaCamara = ""
    }

    //  La PRIMERA queja del grabador, que es la que dice qué ha pasado: gsr
    //  escupe el error y detrás la lista entera de dispositivos válidos, así
    //  que quedarse con la última línea sería quedarse con un nombre suelto.
    //
    //  Hasta ahora esto solo iba al log, y el log de la barra se va a /dev/null
    //  en cuanto se arranca con `setsid`. Un grabador que se moría al nacer no
    //  dejaba rastro en ninguna parte: la grabación «se paraba sola».
    property string quejaGrabador: ""

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra y en `quejaGrabador`.
        stderr: SplitParser {
            onRead: function (l) {
                if (captura.ruidoDeGrabador(l))
                    return
                console.warn("captura:", l)
                if (captura.quejaGrabador.length === 0)
                    captura.quejaGrabador = String(l).trim()
            }
        }
        id: grabador

        onStarted: {
            captura.grabando = true
            captura.estado = "grabando"
            captura.inicio = Date.now()
            captura.duracion = 0
            captura.quejaGrabador = ""
            crono.start()

            // El rastro se llama como el vídeo: así siguen emparejados aunque
            // pasen semanas y se hayan movido de carpeta.
            captura.rutaRastro = captura.rutaVideo.replace(/\.mp4$/, ".rastro.jsonl")
            rastreador.command = ["python3", Quickshell.shellPath("tools/rastro.py"),
                                  "--salida", captura.rutaRastro,
                                  "--hz", "30",
                                  "--region", captura.regionActual]
            rastreador.running = true

            //  Con gsr el micro ya viene dentro, en su propia pista y con el
            //  mismo reloj: no hay segundo proceso que arrancar ni fichero
            //  suelto que juntar.
            if (captura.audio === "ambos" && !captura.grabaDosPistas) {
                captura.rutaMicro = captura.rutaVideo.replace(/\.mp4$/, ".micro.m4a")
                grabadorMicro.command = captura.ordenMicro(captura.rutaMicro)
                grabadorMicro.running = true
            } else {
                captura.rutaMicro = ""
            }

            //  Y la cámara, si se pidió y hay alguna.
            //
            //  Se apunta el instante de cada arranque para saber cuánto se
            //  adelantó una a la otra: son decenas de milisegundos, pero
            //  fingir que son cero sería mentir sobre la sincronía.
            captura.inicioPantalla = Date.now()
            captura.desfaseCamara = 0
            if (Settings.grabarCamara && captura.camaraElegida.length > 0) {
                captura.rutaCamara = captura.rutaVideo.replace(/\.mp4$/, ".cam.mp4")
                grabadorCamara.command = captura.ordenCamara(captura.rutaCamara)
                grabadorCamara.running = true
            } else {
                captura.rutaCamara = ""
            }
        }

        onExited: function (codigo) {
            crono.stop()
            rescate.stop()
            // Al rastreador también por las buenas: cierra el fichero al
            // recibir el SIGINT, y matarlo dejaría la última línea a medias.
            if (rastreador.running)
                rastreador.signal(2)

            //  Un grabador que se va con código de error no ha dejado vídeo.
            //
            //  Antes daba igual cómo hubiera salido: se seguía adelante, se
            //  intentaba juntar un fichero que no existía y se acababa
            //  emitiendo `videoListo` con la ruta de un vídeo que nunca se
            //  escribió. Por fuera eso es exactamente «empieza y se para»:
            //  ni vídeo, ni aviso, ni nada que mirar.
            if (codigo !== 0) {
                if (grabadorCamara.running)
                    grabadorCamara.signal(2)
                if (grabadorMicro.running)
                    grabadorMicro.signal(2)
                captura.fracasarGrabacion(codigo)
                return
            }
            //  Y a la cámara: un mp4 sin cerrar no lo abre nadie. No se espera
            //  a que muera —el juntado no la necesita— pero sí se le pide por
            //  las buenas, que es lo que cierra el contenedor.
            if (grabadorCamara.running)
                grabadorCamara.signal(2)
            // Y al micro, por lo mismo: un m4a sin cerrar no lo abre nadie.
            if (grabadorMicro.running) {
                // El juntado lo dispara `grabadorMicro.onExited`, cuando el
                // fichero del micro ya está cerrado de verdad.
                captura.estado = "cerrando"
                grabadorMicro.signal(2)
                return
            }
            //  Con gsr no hay a quién esperar —las dos pistas salieron de este
            //  mismo proceso— pero el juntado se hace igual: es quien pone la
            //  mezcla delante y les da nombre.
            if (captura.grabaDosPistas) {
                captura.estado = "cerrando"
                captura.juntarPistas()
                return
            }
            // wf-recorder sale con 0 al recibir el SIGINT que le mandamos: eso
            // es una parada limpia, no un fallo.
            captura.rematarGrabacion()
        }
    }

    //  Juntar el micro con el vídeo, como pista aparte.
    //
    //  Un respiro antes: ffmpeg acaba de recibir su SIGINT y todavía está
    //  escribiendo la cabecera del m4a. Sin esperar, se junta un fichero a
    //  medias.
    function juntarPistas() {
        {
            const salida = captura.rutaVideo.replace(/\.mp4$/, ".dos.mp4")
            juntador.destino = salida
            //  `-c copy`: no se recodifica nada, solo se reempaqueta. Es
            //  instantáneo y no pierde calidad.
            //
            //  Las dos pistas van SEPARADAS y no mezcladas: mezclar al grabar
            //  es irreversible, y lo que se quiere es poder bajarle el volumen
            //  a una de las dos más tarde.
            //  Y DELANTE, una mezcla de las dos.
            //
            //  Las dos siguen ahí y separadas —mezclar al grabar es
            //  irreversible—, pero un reproductor cualquiera pone la primera
            //  pista y ya: si esa era «Sistema» y no sonaba nada, abrías el
            //  vídeo y no oías tu voz aunque estuviera grabada. Pasó, y la
            //  única pista era mirar el fichero con ffprobe.
            //
            //  La mezcla va la primera para que sea la que suena sola, y el
            //  editor la ignora por su título: allí lo que se quiere son las
            //  dos de verdad, para poder equilibrarlas.
            //
            //  Ir la primera NO basta: un MP4 se guarda cuál es la pista
            //  «predeterminada», y las dos que se copian traen esa bandera
            //  puesta de sus ficheros originales. El reproductor no coge la
            //  primera, coge la primera marcada —«Sistema»— y si ese día no
            //  sonaba nada en el ordenador, abrías el vídeo, no oías tu voz y
            //  parecía que el micro no se había grabado. Estaba grabado. Así
            //  que la bandera se pone a mano: la mezcla sí, las otras dos no.
            //
            //  `normalize=0`: sumar sin repartir el volumen. Con el reparto de
            //  fábrica, dos pistas suenan a la mitad cada una y la voz queda
            //  lejos.
            //
            //  Dos entradas o una según de dónde vengan las pistas. Con gsr las
            //  dos están ya dentro del mismo fichero y en el mismo reloj, así
            //  que esto solo reordena y bautiza; con wf-recorder hay que traer
            //  el micro de su fichero aparte, y es ahí donde nace el desfase que
            //  este camino no tiene.
            const entradas = captura.grabaDosPistas
                    ? ["-i", captura.rutaVideo]
                    : ["-i", captura.rutaVideo, "-i", captura.rutaMicro]
            const fuentes = captura.grabaDosPistas
                    ? ["[0:a:0]", "[0:a:1]"]
                    : ["[0:a]", "[1:a]"]

            juntador.command = ["ffmpeg", "-v", "error", "-y"].concat(entradas).concat([
                                "-filter_complex",
                                fuentes[0] + fuentes[1]
                                + "amix=inputs=2:normalize=0:duration=longest[mez]",
                                "-map", "0:v", "-map", "[mez]",
                                "-map", fuentes[0].slice(1, -1),
                                "-map", fuentes[1].slice(1, -1),
                                "-c:v", "copy", "-c:a:1", "copy", "-c:a:2", "copy",
                                "-disposition:a:0", "default",
                                "-disposition:a:1", "0",
                                "-disposition:a:2", "0",
                                "-metadata:s:a:0", "title=Mezcla",
                                "-metadata:s:a:1", "title=Sistema",
                                "-metadata:s:a:2", "title=Micrófono",
                                salida])
            juntador.running = true
        }
    }

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        id: juntador
        property string destino: ""

        onExited: function (codigo) {
            if (codigo === 0 && destino.length > 0) {
                // El fichero con las dos pistas ocupa el sitio del original, y
                // los trozos sueltos se van.
                //  El borrado del micro solo si hubo micro suelto: por el camino
                //  de gsr no hay fichero aparte, y un `rm -f ''` es un error
                //  gratuito en el log.
                let orden = "mv -f " + captura.entrecomillar(destino) + " "
                          + captura.entrecomillar(captura.rutaVideo)
                if (captura.rutaMicro.length > 0)
                    orden += " && rm -f " + captura.entrecomillar(captura.rutaMicro)
                limpiador.command = ["sh", "-c", orden]
                limpiador.running = true
            } else {
                // Si falla, el vídeo original sigue ahí con su pista de
                // sistema: se pierde el micro, no la grabación.
                captura.rematarGrabacion()
            }
        }
    }

    Process {
        id: limpiador
        onExited: captura.rematarGrabacion()
    }

    //  El final de una grabación que no ha llegado a serlo.
    //
    //  Se deshace lo poco que se había hecho —el rastro del cursor se queda
    //  huérfano si no, y en la carpeta se acumulan `.rastro.jsonl` sueltos sin
    //  su vídeo al lado— y se dice qué ha pasado, con las palabras del propio
    //  grabador. El aviso lo enseña el plugin, que ya escuchaba `videoFallido`
    //  para las fotos.
    function fracasarGrabacion(codigo) {
        grabando = false
        estado = ""
        if (rutaRastro.length > 0) {
            Quickshell.execDetached(["rm", "-f", rutaRastro])
            rutaRastro = ""
        }
        rutaVideo = ""
        rutaMicro = ""
        const motivo = quejaGrabador.length > 0
                ? quejaGrabador
                : "el grabador se cerró con el código " + codigo
        quejaGrabador = ""
        videoFallido(motivo)
    }

    //  El final de una grabación, una vez el fichero ya está como debe.
    //
    //  Aquí acaba el trabajo del grabador y se avisa al plugin, que enseña el
    //  preview y deja elegir si abrirlo, llevarlo al editor o abrir la carpeta.
    //  El editor sigue pudiendo abrir vídeos que no ha grabado nadie de aquí.
    function rematarGrabacion() {
        grabando = false
        estado = ""
        if (rutaVideo.length > 0) {
            videoListo(rutaVideo)
        } else {
            videoFallido("fallo")
        }
    }

    Timer {
        id: crono
        interval: 1000
        repeat: true
        onTriggered: captura.duracion = Math.floor((Date.now() - captura.inicio) / 1000)
    }

    // Si no cierra por las buenas en cinco segundos, se insiste. Más allá de
    // eso el contenedor ya estaría roto de todas formas.
    Timer {
        id: rescate
        interval: 5000
        onTriggered: if (captura.grabando) grabador.signal(15)
    }

    // El monitor donde está el ratón. Con una sola pantalla da igual, pero en
    // cuanto hay dos, capturar «la pantalla» sin decir cuál captura las dos
    // pegadas, que no es lo que nadie espera.
    function monitorActual() {
        const m = Hyprland.focusedMonitor
        if (m && m.name)
            return m.name

        // En algunas versiones de Quickshell `focusedMonitor` puede quedarse
        // nulo al cambiar de configuración de pantallas. El modelo de
        // monitores sí conserva el monitor enfocado; úsalo antes de caer a la
        // primera pantalla como último recurso.
        const monitores = Hyprland.monitors && Hyprland.monitors.values
            ? Hyprland.monitors.values : []
        for (let i = 0; i < monitores.length; ++i) {
            const monitor = monitores[i]
            const datos = monitor && monitor.lastIpcObject
            if (monitor && monitor.name
                    && (monitor.focused || (datos && datos.focused)))
                return monitor.name
        }

        const pantallas = Quickshell.screens
        return pantallas && pantallas.length > 0 && pantallas[0].name
            ? pantallas[0].name : ""
    }

    function copiar(ruta) {
        if (!ruta || ruta.length === 0)
            return
        Quickshell.execDetached(["sh", "-c",
            "wl-copy -t image/png < " + entrecomillar(ruta)])
    }

    function abrirCarpeta() {
        if (carpetaFotos.length > 0)
            Quickshell.execDetached(["xdg-open", carpetaFotos])
    }

    function abrirCarpetaVideos() {
        if (carpetaVideos.length > 0)
            Quickshell.execDetached(["xdg-open", carpetaVideos])
    }

    function abrir(ruta) {
        if (ruta && ruta.length > 0)
            Quickshell.execDetached(["xdg-open", ruta])
    }

    function anotar(ruta) {
        if (!ruta || ruta.length === 0)
            return
        Quickshell.execDetached(["satty", "-f", ruta, "-o", ruta,
                                 "--copy-command", "wl-copy",
                                 "--early-exit", "save",
                                 "--initial-tool", "arrow"])
    }

    // Comillas simples al estilo del shell, doblando las que vengan dentro. Las
    // rutas las genera el guion sin espacios ni acentos, pero el usuario puede
    // cambiar la carpeta de imágenes y entonces esto es lo único que separa una
    // ruta con espacios de un comando roto.
    function entrecomillar(s) {
        return "'" + String(s).split("'").join("'\\''") + "'"
    }

    // ── el proceso de la foto ─────────────────────────────────────
    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        id: disparo

        stdout: StdioCollector {
            onStreamFinished: {
                Island.escondida = false
                captura.estado = ""
                let d = null
                try {
                    d = JSON.parse(this.text)
                } catch (e) {
                    captura.ultimoFallo = "respuesta-ilegible"
                    captura.fotoFallida(captura.ultimoFallo)
                    return
                }

                if (!d.ok) {
                    captura.ultimoFallo = d.motivo || "fallo"
                    // Cancelar no es un fallo del que haya que avisar: es que
                    // has cambiado de idea.
                    if (d.motivo !== "cancelado")
                        captura.fotoFallida(captura.ultimoFallo)
                    return
                }

                captura.ultimaRuta = d.ruta || ""
                captura.ultimaAncho = d.w || 0
                captura.ultimaAlto = d.h || 0
                captura.ultimaCopiada = d.copiada === true
                captura.fotoLista(captura.ultimaRuta)
            }
        }

        // Si el guion se va sin decir nada por stdout, el estado se quedaría
        // colgado en "capturando" y el módulo no aceptaría otra captura nunca
        // más.
        onExited: function (codigo) {
            Island.escondida = false
            if (captura.estado === "capturando")
                captura.estado = ""
        }
    }

    // ── dónde guardar, preguntado una vez al arrancar ─────────────
    Process {
        command: ["python3", Quickshell.shellPath("tools/captura.py"),
                  "carpeta", "--que", "fotos"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { captura.carpetaFotos = JSON.parse(this.text).ruta || "" }
                catch (e) { }
            }
        }
    }

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        command: ["python3", Quickshell.shellPath("tools/captura.py"),
                  "carpeta", "--que", "videos"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { captura.carpetaVideos = JSON.parse(this.text).ruta || "" }
                catch (e) { }
            }
        }
    }
}
