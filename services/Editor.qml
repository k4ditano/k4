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

    // ── la pista base ─────────────────────────────────────────────
    //
    //  Los trozos, en el orden en que se ven. Cada uno dice de qué fichero sale
    //  y qué parte de él.
    property var clips: []
    property var fuentes: []

    function rutaDe(idFuente) {
        for (let i = 0; i < fuentes.length; ++i)
            if (fuentes[i].id === idFuente)
                return fuentes[i].ruta
        return fuentes.length > 0 ? fuentes[0].ruta : ""
    }

    //  Dónde cae cada trozo en la línea.
    //
    //  Es la misma cuenta que hace `mapa()` en tools/editar.py, y sí, están las
    //  dos. La alternativa era esperar a que python contestara para poder
    //  dibujar, y arrastrar el borde de un clip a cinco fotogramas por segundo
    //  no es editar. Esta cuenta es la DEFINICIÓN del modelo —los trozos van en
    //  orden y la línea es su suma—, no un algoritmo con parámetros que puedan
    //  separarse: para que discrepen habría que cambiar la definición en un
    //  sitio y no en el otro. La easing de la cámara, que sí podría irse, sigue
    //  calculándose en un solo lado.
    readonly property var tramos: {
        let t = 0
        const r = []
        for (let i = 0; i < clips.length; ++i) {
            const c = clips[i]
            const d = Math.max(0, c.hasta - c.desde)
            if (d <= 0)
                continue
            r.push({ clip: c.id, fuente: c.fuente, ruta: rutaDe(c.fuente),
                     inicio: t, fin: t + d, desde: c.desde, hasta: c.hasta,
                     indice: i })
            t += d
        }
        return r
    }

    readonly property real duracionLinea: tramos.length > 0
        ? tramos[tramos.length - 1].fin : 0

    function tramoEn(t) {
        for (let i = 0; i < tramos.length; ++i)
            if (t >= tramos[i].inicio && t < tramos[i].fin)
                return tramos[i]
        return null
    }

    // Qué puesto ocupa un clip en la línea, saltándose los vacíos.
    function tramoDe(id) {
        for (let i = 0; i < tramos.length; ++i)
            if (tramos[i].clip === id)
                return i
        return 0
    }

    function indiceDeClip(id) {
        for (let i = 0; i < clips.length; ++i)
            if (clips[i].id === id)
                return i
        return -1
    }

    function nuevoIdClip() {
        let mayor = 0
        for (let i = 0; i < clips.length; ++i)
            mayor = Math.max(mayor, clips[i].id)
        return mayor + 1
    }

    //  Partir en dos el trozo que haya bajo el cabezal.
    //
    //  No hace nada si el corte cae en un borde: partir un clip en «todo» y
    //  «nada» deja un trozo de duración cero, que ni se ve ni sirve para nada.
    function cortar(t) {
        const tr = tramoEn(t)
        if (!tr)
            return false
        const enFuente = tr.desde + (t - tr.inicio)
        if (enFuente - tr.desde < 0.1 || tr.hasta - enFuente < 0.1)
            return false

        const izq = Object.assign({}, clips[tr.indice], { hasta: enFuente })
        const der = Object.assign({}, clips[tr.indice],
                                  { id: nuevoIdClip(), desde: enFuente })
        const nuevos = clips.slice()
        nuevos.splice(tr.indice, 1, izq, der)
        clips = nuevos
        persistir()
        seleccionar("clip", der.id)
        return true
    }

    //  Llevar un trozo a otro sitio del orden.
    //
    //  Los momentos de zoom NO se mueven con él, y es a propósito: el zoom se
    //  coloca mirando la línea, igual que un rótulo. Arrastrarlo con el clip
    //  significaría que reordenar te descoloca todo lo que hubiera después.
    function moverClip(id, destino) {
        const desde = indiceDeClip(id)
        if (desde < 0)
            return
        const n = Math.max(0, Math.min(clips.length - 1, destino))
        if (n === desde)
            return
        const nuevos = clips.slice()
        nuevos.splice(n, 0, nuevos.splice(desde, 1)[0])
        clips = nuevos
        persistir()
    }

    //  Cambiar por dónde entra y por dónde sale un trozo, en tiempo de FUENTE.
    function recortarClip(id, desde, hasta) {
        const i = indiceDeClip(id)
        if (i < 0)
            return
        const tope = duracionDeFuente(clips[i].fuente)
        const a = Math.max(0, Math.min(tope - 0.1, desde))
        const b = Math.max(a + 0.1, Math.min(tope, hasta))
        clips = clips.map(function (c, j) {
            return j === i ? Object.assign({}, c, { desde: a, hasta: b }) : c
        })
        persistir()
    }

    function duracionDeFuente(idFuente) {
        for (let i = 0; i < fuentes.length; ++i)
            if (fuentes[i].id === idFuente)
                return fuentes[i].dur
        return 0
    }

    //  Quitar un trozo. El hueco se cierra solo: la línea es la suma de lo que
    //  quede, así que no hay nada que recolocar.
    function quitarClip(id) {
        // El último no se puede quitar: una línea sin trozos no es una línea
        // vacía, es un editor sin nada que enseñar y sin forma de volver.
        if (clips.length <= 1)
            return
        clips = clips.filter(function (c) { return c.id !== id })
        persistir()
        seleccionar("", 0)
    }

    // ── las capas ─────────────────────────────────────────────────
    //
    //  Lo que va ENCIMA del vídeo: por ahora imágenes, y después texto, audio y
    //  vídeo dentro de vídeo. Un solo modelo con un `tipo` que los distinga, y
    //  no una lista por cada cosa: es lo que hace que esto sea un editor y no
    //  una colección de funciones que no se hablan entre ellas.
    //
    //  `x`, `y` y `escala` van en fracción del fotograma, y `x`/`y` apuntan al
    //  CENTRO. Así el plan no depende de la resolución.
    property var capas: []

    function nuevoIdCapa() {
        let mayor = 0
        for (let i = 0; i < capas.length; ++i)
            mayor = Math.max(mayor, capas[i].id)
        return mayor + 1
    }

    function crearImagen(ruta, t0) {
        if (!ruta || ruta.length === 0)
            return 0
        // Tres segundos desde donde estés, o lo que quepa si estás al final.
        const a = Math.max(0, Math.min(t0, Math.max(0, duracionLinea - 1)))
        const nueva = {
            id: nuevoIdCapa(),
            tipo: "imagen",
            ruta: ruta,
            t0: a,
            t1: Math.min(duracionLinea, a + 3),
            // Arriba a la derecha y a un cuarto de ancho: es donde va un logo, y
            // desde ahí se mueve con el ratón en un gesto.
            x: 0.8, y: 0.15, escala: 0.25, opacidad: 1.0,
            z: capas.length + 1
        }
        capas = capas.concat([nueva])
        persistir()
        seleccionar("capa", nueva.id)
        return nueva.id
    }

    function fijarCapa(id, campos) {
        capas = capas.map(function (c) {
            if (c.id !== id)
                return c
            return Object.assign({}, c, campos)
        })
        persistir()
    }

    function quitarCapa(id) {
        capas = capas.filter(function (c) { return c.id !== id })
        persistir()
        seleccionar("", 0)
    }

    // ── qué está seleccionado ─────────────────────────────────────
    //
    //  Un solo sitio para toda la línea, y no un índice por pista: con varias
    //  pistas «el elegido» tiene que decir también de qué es.
    property string tipoSel: ""             // "" · clip · momento
    property int idSel: 0

    function seleccionar(tipo, id) {
        tipoSel = tipo
        idSel = id
    }

    readonly property var momentoSel: {
        for (let i = 0; i < momentos.length; ++i)
            if (tipoSel === "momento" && momentos[i].id === idSel)
                return momentos[i]
        return null
    }

    readonly property var clipSel: {
        for (let i = 0; i < clips.length; ++i)
            if (tipoSel === "clip" && clips[i].id === idSel)
                return clips[i]
        return null
    }

    readonly property var capaSel: {
        for (let i = 0; i < capas.length; ++i)
            if (tipoSel === "capa" && capas[i].id === idSel)
                return capas[i]
        return null
    }

    property var momentos: []

    //  La trayectoria de la cámara, para poder enseñar el zoom en vivo sin
    //  renderizar. Son los MISMOS puntos que se convierten en la expresión de
    //  ffmpeg, así que lo que se ve en el editor y lo que sale al fichero
    //  coinciden por construcción.
    property var camara: []

    //  Las pistas de audio del vídeo, con su volumen y su silencio.
    //  [{ i, titulo, volumen, mudo }]
    property var pistasAudio: []

    // Tamaño del lienzo: hace falta para pasar de píxeles del vídeo a píxeles
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
        anchoVideo = d.w || 1920
        altoVideo = d.h || 1080
        fuentes = d.fuentes || []
        clips = d.clips || []
        capas = d.capas || []
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
            t1: Math.min(duracionLinea, Math.max(t0, t1)),
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
            d.t1 = Math.min(duracionLinea, d.t1 + delta)
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
            //  Una lista vacía significa «el plan aún no ha terminado de
            //  cargarse», no «quítale el audio» ni «quítale los trozos»: no hay
            //  forma de borrar una pista, solo de silenciarla, ni de dejar la
            //  línea sin ningún clip. Sin estos `or`, un guardado que llegara
            //  antes que la carga dejaba el plan vacío para siempre.
            "p['fuentes'][0]['pistas']=d['pistas'] or p['fuentes'][0]['pistas']; " +
            "p['clips']=d['clips'] or p['clips']; " +
            //  Las capas SÍ se escriben aunque estén vacías, al revés que las
            //  otras: no tener ninguna es un estado legítimo, y con el `or` no
            //  habría forma de quitar la última.
            "p['capas']=d['capas']; " +
            "json.dump(p, open(sys.argv[1],'w'), ensure_ascii=False, indent=1)",
            rutaPlan,
            JSON.stringify({ momentos: momentos, pistas: pistasAudio,
                             clips: clips, capas: capas })]
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
                        editor.anchoVideo = d.w || editor.anchoVideo
                        editor.altoVideo = d.h || editor.altoVideo
                        if (d.fuentes && d.fuentes.length > 0)
                            editor.fuentes = d.fuentes
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
