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
    signal fotoFallida(string motivo)

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

    function pedirRegion(motivo) {
        if (ocupado || seleccionando)
            return
        motivoSeleccion = motivo || "foto"
        estado = "capturando"
        Island.escondida = true
        congelar.restart()
    }

    function cancelarRegion() {
        seleccionando = false
        destinoPuntual = ""
        estado = ""
    }

    function confirmarRegion(x, y, w, h) {
        if (w < 1 || h < 1) {
            seleccionando = false
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
        // es justo desde donde se ha llamado aquí.
        seleccionando = false
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
    signal videoFallido(string motivo)

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
        pedirNombreVideo.running = true
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
                grabador.command = captura.ordenGrabar(ruta)
                grabador.running = true
            }
        }
    }

    function ordenGrabar(ruta) {
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
        else
            orden.push("-o", monitorActual())

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
    // sistema. Se pregunta cada vez que empieza una grabación porque cambia al
    // enchufar unos auriculares.
    property string sinkMonitor: "@DEFAULT_MONITOR@"

    // El micrófono por defecto, por el mismo motivo: cambia al enchufar unos
    // auriculares y hay que preguntarlo, no darlo por sabido.
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

    function buscarAudios() { buscadorAudios.running = true }

    Process {
        id: buscadorAudios
        command: ["python3", Quickshell.shellPath("tools/captura.py"), "audios"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { return }
                if (!d || !d.ok)
                    return
                captura.microfonos = d.microfonos || []
                captura.salidasAudio = d.salidas || []
            }
        }
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

    readonly property string monitorElegido:
        Settings.grabarSalida !== "auto" && entreLos(Settings.grabarSalida, salidasAudio)
            ? Settings.grabarSalida + ".monitor" : sinkMonitor

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

    Process {
        command: ["sh", "-c", "echo \"$(pactl get-default-sink).monitor\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const n = String(this.text).trim()
                if (n.length > 8)
                    captura.sinkMonitor = n
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
        command: ["sh", "-c", "pactl get-default-source"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const n = String(this.text).trim()
                if (n.length > 3)
                    captura.fuenteMicro = n
            }
        }
    }

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
    //  wf-recorder solo acepta UN dispositivo de audio, así que para tener
    //  sistema y micro por separado no queda otra que un segundo proceso. Se
    //  arrancan en el mismo tic y se paran en el mismo tic; el desfase que
    //  quede son decenas de milisegundos, que en un clip corto no se nota.
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

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("captura:", l)
            }
        }
        id: grabador

        onStarted: {
            captura.grabando = true
            captura.estado = "grabando"
            captura.inicio = Date.now()
            captura.duracion = 0
            crono.start()

            // El rastro se llama como el vídeo: así siguen emparejados aunque
            // pasen semanas y se hayan movido de carpeta.
            captura.rutaRastro = captura.rutaVideo.replace(/\.mp4$/, ".rastro.jsonl")
            rastreador.command = ["python3", Quickshell.shellPath("tools/rastro.py"),
                                  "--salida", captura.rutaRastro,
                                  "--hz", "30",
                                  "--region", captura.regionActual]
            rastreador.running = true

            if (captura.audio === "ambos") {
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
            juntador.command = ["ffmpeg", "-v", "error", "-y",
                                "-i", captura.rutaVideo,
                                "-i", captura.rutaMicro,
                                "-map", "0:v", "-map", "0:a?", "-map", "1:a",
                                "-c", "copy",
                                "-metadata:s:a:0", "title=Sistema",
                                "-metadata:s:a:1", "title=Micrófono",
                                salida]
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
                limpiador.command = ["sh", "-c",
                    "mv -f " + captura.entrecomillar(destino) + " "
                    + captura.entrecomillar(captura.rutaVideo)
                    + " && rm -f " + captura.entrecomillar(captura.rutaMicro)]
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
        return m && m.name ? m.name : ""
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
