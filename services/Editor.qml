pragma Singleton

//  El editor de vídeo.
//
//  Esto vivía dentro de services/Captura.qml, y estar ahí decía algo que ya no
//  es verdad: que editar es lo que pasa DESPUÉS de grabar. Se puede abrir un
//  vídeo que no haya grabado k4, y entonces el grabador no pinta nada.
//
//  El estado vive en un singleton y no en el plugin por el motivo de siempre: un
//  plugin solo existe mientras es el módulo activo, y aquí se puede apartar el
//  editor, seguir con otra cosa media hora y retomarlo por donde ibas. Además un
//  render tarda minutos y tiene que seguir avanzando con la island cerrada.
//
//  Todo el trabajo de verdad —la trayectoria de la cámara, el grafo de filtros,
//  llamar a ffmpeg— lo hace tools/editar.py. Aquí solo está el estado y quién lo
//  toca. En particular, **este fichero no sabe aritmética de tiempos**: no
//  traduce entre el tiempo de la línea y el de dentro de cada fichero, porque
//  entonces habría dos implementaciones de lo mismo que se irían separando.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: editor

    // ── ajustes ───────────────────────────────────────────────────
    // De momento con valores de fábrica; en E8 los lee de Settings.
    property string codec: "h264"             // h264 · hevc
    property bool zoomAuto: true
    property real zoomNivel: 2.5

    // ── estado ────────────────────────────────────────────────────
    //  "" · editando · renderizando
    property string estado: ""

    readonly property bool abierto: estado === "editando"
        || estado === "renderizando"

    //  El plan se guarda junto al vídeo, así que se puede reeditar mañana. Lo
    //  que se renderiza es un fichero nuevo: el original no se toca, porque
    //  equivocarse editando y haberse cargado la grabación sería mucho peor que
    //  tener dos ficheros.
    property string rutaVideo: ""
    property string rutaPlan: ""
    property string rutaRenderizada: ""
    property real progreso: 0

    property var momentos: []

    //  La trayectoria de la cámara, para poder enseñar el zoom en vivo sin
    //  renderizar. Son los MISMOS puntos que se convierten en la expresión de
    //  ffmpeg, así que lo que se ve en el editor y lo que sale al fichero
    //  coinciden por construcción.
    property var camara: []

    //  Las pistas de audio del vídeo, con su volumen y su silencio.
    //  [{ i, titulo, volumen, mudo }]
    property var pistasAudio: []

    property real duracionVideo: 0
    // Tamaño del vídeo: hace falta para pasar de píxeles del fichero a píxeles
    // del marco donde se previsualiza.
    property int anchoVideo: 1920
    property int altoVideo: 1080

    //  Por dónde iba la reproducción.
    //
    //  Cada vista del editor tiene su propio reproductor —nunca hay dos a la
    //  vez, porque al abrir una se destruye la otra—, así que en vez de
    //  compartir el sumidero de vídeo entre ventanas, que es delicado, basta
    //  con apuntar el instante y volver a él. Se paga un reabrir de medio
    //  segundo al cambiar de tamaño, y a cambio no hay nada que sincronizar.
    property real posicionEditor: 0

    signal planListo()
    signal renderListo(string ruta)
    signal fallo(string motivo)

    readonly property string guion: Quickshell.shellPath("tools/editar.py")

    // ── abrir ─────────────────────────────────────────────────────
    //
    //  Dos formas de llegar aquí y una sola de salir. `abrir` sirve para
    //  cualquier vídeo; `proponer` es lo que hace el grabador cuando acaba, que
    //  además le pide al rastro del cursor que sugiera unos momentos de zoom.
    function abrir(video, rastro) {
        if (!video || video.length === 0)
            return
        preparar(video)
        abridor.command = [guion, "abrir", video,
                           "--rastro", rastro || "",
                           "--guardar", rutaPlan]
        abridor.running = true
    }

    function proponer(video, rastro) {
        if (!video || video.length === 0 || !rastro || rastro.length === 0)
            return
        preparar(video)
        proponedor.command = [guion, "proponer", rastro,
                              "--video", video,
                              "--guardar", rutaPlan,
                              "--nivel", String(zoomNivel)]
        proponedor.running = true
    }

    //  El plan se llama como el vídeo pero con otra extensión, así que abrir dos
    //  veces el mismo fichero recupera lo que dejaste editado.
    function preparar(video) {
        rutaVideo = video
        rutaPlan = video.replace(/\.[^./]+$/, "") + ".k4.json"
        //  Nada de arrastrar el estado del vídeo anterior: los momentos de otra
        //  grabación pintados sobre esta serían un fantasma difícil de
        //  entender.
        momentos = []
        pistasAudio = []
        camara = []
        posicionEditor = 0
        progreso = 0
    }

    function recibirPlan(d) {
        duracionVideo = d.duracion !== undefined ? d.duracion
            : (d.clips && d.clips.length > 0
               ? d.clips[0].hasta - d.clips[0].desde : 0)
        anchoVideo = d.w || 1920
        altoVideo = d.h || 1080
        pistasAudio = (d.fuentes && d.fuentes.length > 0
                       ? d.fuentes[0].pistas : d.audio) || []
        momentos = d.momentos || []
        //  El editor se abre SIEMPRE, haya momentos o no.
        //
        //  Antes solo se abría si el rastro del cursor había propuesto alguno,
        //  así que una grabación sin clics —enseñar algo sin tocar nada, que es
        //  media razón para grabar— no se podía ni abrir. El zoom es una cosa
        //  que se le hace a un vídeo, no el motivo de que exista el editor.
        estado = "editando"
        recalcular.restart()
        planListo()
    }

    Process {
        id: abridor
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (!d || !d.ok) {
                    editor.estado = ""
                    editor.fallo(d && d.motivo ? d.motivo : "fallo")
                    return
                }
                editor.recibirPlan(d)
            }
        }
    }

    Process {
        id: proponedor
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { return }
                if (!d.ok) {
                    //  Sin rastro no hay zoom que proponer, pero sí vídeo que
                    //  editar: se abre igual, que para eso está.
                    editor.abrir(editor.rutaVideo, "")
                    return
                }
                editor.recibirPlan(d)
            }
        }
    }

    // ── los momentos de zoom ──────────────────────────────────────
    function quitarMomento(id) {
        momentos = momentos.filter(function (m) { return m.id !== id })
        persistir()
    }

    //  Cambiar campos sueltos de un momento.
    //
    //  Se reasigna el array entero y se copia el objeto: mutar en su sitio no
    //  emite el cambio y la vista se quedaría como estaba. Es la misma trampa
    //  de siempre en QML y sigue costando lo mismo encontrarla.
    function fijarMomento(id, campos) {
        momentos = momentos.map(function (m) {
            if (m.id !== id)
                return m
            return Object.assign({}, m, campos)
        })
        persistir()
    }

    //  Un momento nuevo, dibujado a mano en un hueco de la línea de tiempo.
    //
    //  Nace con `seguir: false`: si lo has puesto tú, el encuadre es una
    //  decisión tuya y no tiene sentido que la cámara se vaya detrás del cursor.
    function crearMomento(t0, t1) {
        let mayor = 0
        for (let i = 0; i < momentos.length; ++i)
            mayor = Math.max(mayor, momentos[i].id)

        const nuevo = {
            id: mayor + 1,
            t0: Math.max(0, Math.min(t0, t1)),
            t1: Math.min(duracionVideo, Math.max(t0, t1)),
            cx: Math.round(anchoVideo / 2),
            cy: Math.round(altoVideo / 2),
            z: zoomNivel,
            seguir: false
        }
        momentos = momentos.concat([nuevo]).sort(function (a, b) {
            return a.t0 - b.t0
        })
        persistir()
        return nuevo.id
    }

    // Mover el encuadre a mano deja de seguir al cursor, por lo mismo.
    function moverCentro(id, cx, cy) {
        fijarMomento(id, {
            cx: Math.round(Math.max(0, Math.min(anchoVideo, cx))),
            cy: Math.round(Math.max(0, Math.min(altoVideo, cy))),
            seguir: false
        })
    }

    function moverMomento(id, delta) {
        momentos = momentos.map(function (m) {
            if (m.id !== id)
                return m
            const d = Object.assign({}, m)
            d.t0 = Math.max(0, d.t0 + delta)
            d.t1 = Math.min(duracionVideo, d.t1 + delta)
            return d
        })
        persistir()
    }

    function ajustarNivel(id, delta) {
        momentos = momentos.map(function (m) {
            if (m.id !== id)
                return m
            const d = Object.assign({}, m)
            d.z = Math.max(1.1, Math.min(4, Math.round((d.z + delta) * 100) / 100))
            return d
        })
        persistir()
    }

    // ── las pistas de audio ───────────────────────────────────────
    function fijarPista(i, campos) {
        pistasAudio = pistasAudio.map(function (p) {
            if (p.i !== i)
                return p
            return Object.assign({}, p, campos)
        })
        persistir()
    }

    // ── guardar ───────────────────────────────────────────────────
    //
    //  Con rebote: arrastrar un bloque son sesenta eventos por segundo, y cada
    //  uno lanzaba un `python3`. Con esto son cinco por segundo como mucho, y
    //  solo se escribe el último estado, que es el único que importa.
    function persistir() { persistidor.restart() }

    Timer {
        id: persistidor
        interval: 200
        onTriggered: {
            // Si el anterior sigue escribiendo, se espera: dos procesos sobre
            // el mismo fichero acaban con uno pisando al otro.
            if (escritorPlan.running)
                restart()
            else
                editor.guardarPlan()
        }
    }

    function guardarPlan() {
        if (rutaPlan.length === 0)
            return
        escritorPlan.command = ["python3", "-c",
            //  Se parchean las claves que conocemos y se deja el resto como
            //  esté: así lo que añada una fase futura no se pierde por pasar
            //  por aquí. Las pistas de audio cuelgan de la fuente, no del plan,
            //  y por eso van por su propio camino.
            "import json,sys; p=json.load(open(sys.argv[1])); " +
            "d=json.loads(sys.argv[2]); " +
            "p['momentos']=d['momentos']; " +
            //  Una lista de pistas vacía significa «el plan aún no ha
            //  terminado de cargarse», no «quítale el audio»: no hay forma de
            //  borrar una pista, solo de silenciarla. Sin este `or`, un guardado
            //  que llegara antes que la carga dejaba el vídeo mudo para siempre.
            "p['fuentes'][0]['pistas']=d['pistas'] or p['fuentes'][0]['pistas']; " +
            "json.dump(p, open(sys.argv[1],'w'), ensure_ascii=False, indent=1)",
            rutaPlan,
            JSON.stringify({ momentos: momentos, pistas: pistasAudio })]
        escritorPlan.running = true
    }

    Process {
        id: escritorPlan
        // La trayectoria depende del plan, así que se rehace cuando el plan ya
        // está escrito en disco y no antes.
        onExited: recalcular.restart()
    }

    //  Al editar hay que rehacer la trayectoria, pero no a cada tecla: si
    //  mantienes pulsada una flecha se lanzarían veinte procesos. Un respiro
    //  corto y solo se calcula la última.
    Timer {
        id: recalcular
        interval: 180
        onTriggered: {
            if (editor.rutaPlan.length === 0)
                return
            camarero.command = ["python3", editor.guion, "camara", editor.rutaPlan]
            camarero.running = true
        }
    }

    Process {
        id: camarero
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    if (d.ok) {
                        editor.camara = d.camara || []
                        editor.duracionVideo = d.duracion || editor.duracionVideo
                        editor.anchoVideo = d.w || editor.anchoVideo
                        editor.altoVideo = d.h || editor.altoVideo
                        if (d.audio && editor.pistasAudio.length === 0)
                            editor.pistasAudio = d.audio
                    }
                } catch (e) { }
            }
        }
    }

    // ── renderizar ────────────────────────────────────────────────
    function renderizar() {
        if (rutaPlan.length === 0)
            return
        rutaRenderizada = rutaVideo.replace(/\.[^./]+$/, "") + "-k4.mp4"
        progreso = 0
        estado = "renderizando"
        renderizador.command = ["python3", guion, "render",
                                rutaPlan, rutaRenderizada, "--codec", codec]
        renderizador.running = true
    }

    Process {
        id: renderizador
        stdout: SplitParser {
            onRead: function (linea) {
                let d = null
                try { d = JSON.parse(linea) } catch (e) { return }
                if (d.progreso !== undefined)
                    editor.progreso = d.progreso
                if (d.estado === "fin" && d.ruta) {
                    editor.estado = ""
                    editor.rutaRenderizada = d.ruta
                    editor.renderListo(d.ruta)
                }
                if (d.ok === false) {
                    editor.estado = ""
                    editor.fallo(d.motivo || "fallo")
                }
            }
        }
    }

    //  Descartar es tirarlo todo: los momentos, el estado y la cápsula de
    //  «pendiente» de la píldora. Antes solo vaciaba los momentos, así que la
    //  cápsula se quedaba ahí diciendo «0 momentos» para siempre y no había
    //  forma de librarse de ella.
    //
    //  El vídeo sin tocar sigue guardado; lo que se tira es el plan.
    function descartar() {
        momentos = []
        pistasAudio = []
        camara = []
        rutaVideo = ""
        rutaPlan = ""
        estado = ""
        Modulos.quitar("editor")
    }
}
