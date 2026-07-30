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
    // Vienen de Settings, que es donde se tocan.
    readonly property string codec: Settings.editorCodec
    readonly property bool zoomAuto: Settings.zoomAuto
    readonly property real zoomNivel: Settings.zoomNivel

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

    //  La velocidad de un clip, acotada a lo que sabe hacer el audio.
    //
    //  El mismo rango que `velocidad_de()` en tools/editar.py: `atempo`
    //  encadenado cubre de 0,25× a 4× y más allá la voz deja de ser una voz.
    function velocidadDe(c) {
        const v = Number(c && c.velocidad)
        if (!isFinite(v) || v <= 0)
            return 1
        return Math.max(0.25, Math.min(4, v))
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
    //
    //  Toma la lista como argumento para poder trabajar sobre una copia sin
    //  publicarla: cortar por diez silencios seguidos reasignando `clips` diez
    //  veces destruiría y recrearía los delegates cada vez, y de paso guardaría
    //  el plan diez veces.
    function tramosDe(lista) {
        let t = 0
        const r = []
        for (let i = 0; i < lista.length; ++i) {
            const c = lista[i]
            const v = velocidadDe(c)
            const d = Math.max(0, c.hasta - c.desde) / v
            if (d <= 0)
                continue
            const ruta = rutaDe(c.fuente)
            r.push({ clip: c.id, fuente: c.fuente, ruta: ruta,
                     inicio: t, fin: t + d, desde: c.desde, hasta: c.hasta,
                     velocidad: v, indice: i,
                     //  Un trozo puede ser una imagen —un congelado, una
                     //  portada—, y eso el reproductor tiene que saberlo: un
                     //  `MediaPlayer` no reproduce un PNG.
                     imagen: esImagen(ruta) })
            t += d
        }
        return r
    }

    readonly property var tramos: tramosDe(clips)

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
        // A tiempo de fuente: un segundo de línea vale `velocidad` de fichero.
        const enFuente = tr.desde + (t - tr.inicio) * tr.velocidad
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

    //  Cambiar a qué velocidad se ve un trozo.
    //
    //  No se toca `desde` ni `hasta`: el trozo del fichero sigue siendo el
    //  mismo, lo que cambia es cuánto ocupa en la línea. Por eso todo lo que va
    //  detrás —zooms, rótulos, capas— se recoloca solo: la línea es la suma de
    //  las duraciones y `tramos` ya la calcula dividiendo.
    function ponerVelocidad(id, v) {
        const i = indiceDeClip(id)
        if (i < 0)
            return
        const limpio = Math.max(0.25, Math.min(4, Number(v) || 1))
        clips = clips.map(function (c, j) {
            return j === i ? Object.assign({}, c, { velocidad: limpio }) : c
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
    //  Cada capa pertenece a una **banda** (`banda: 1, 2, 3…`), y las bandas son
    //  lo que se apila: la 1 abajo, la última arriba. Dentro de una banda caben
    //  varias capas, normalmente en instantes distintos.
    //
    //  Al principio una capa era una banda —una cosa suelta con su fila propia—
    //  y se quedó corto por los dos lados: no había nada que mover de una banda
    //  a otra, que es lo primero que uno intenta, y con seis imágenes salían
    //  seis filas cuando lo natural son dos bandas con tres cada una.
    //
    //  `x`, `y` y `escala` van en fracción del fotograma, y `x`/`y` apuntan al
    //  CENTRO. Así el plan no depende de la resolución.
    property var capas: []

    function bandaDe(c) { return c.banda !== undefined ? c.banda : 1 }

    //  Cuántas bandas hay. Al menos una, aunque esté vacía: si no, al quitar la
    //  última capa desaparecería la fila y no habría dónde soltar la siguiente.
    readonly property int cuantasBandas: {
        let n = 1
        for (let i = 0; i < capas.length; ++i)
            n = Math.max(n, bandaDe(capas[i]))
        return n
    }

    // Las capas de una banda, en el orden en que se apilan dentro de ella.
    function capasDeBanda(b) {
        return capas.filter(function (c) { return bandaDe(c) === b })
    }

    //  Las capas en el orden en que se PINTAN: por banda, y dentro de una banda
    //  por el orden de la lista.
    //
    //  Tiene que dar exactamente lo mismo que `capas_de()` en tools/editar.py, y
    //  no es un detalle: la previa iba por el orden crudo de la lista mientras
    //  ffmpeg iba por banda, así que bajar una capa cambiaba el fichero pero no
    //  lo que se veía en el editor. La vista decía una cosa y el render otra, que
    //  es exactamente lo que todo este modelo existe para que no pase.
    //
    //  Se ordena por (banda, posición) en vez de fiarse de que `sort` sea estable:
    //  lo es en el motor de QML, pero decirlo explícitamente cuesta una línea y
    //  quita una suposición de en medio.
    readonly property var capasApiladas: {
        return capas
            .map(function (c, i) { return { capa: c, pos: i } })
            .sort(function (a, b) {
                const d = bandaDe(a.capa) - bandaDe(b.capa)
                return d !== 0 ? d : a.pos - b.pos
            })
            .map(function (x) { return x.capa })
    }

    //  Una banda donde quepa algo entre t0 y t1 sin pisar a nadie.
    //
    //  Es lo que hace que meter tres logos seguidos no cree tres bandas: si en
    //  la 1 hay hueco en ese tramo, va a la 1.
    function bandaLibre(t0, t1) {
        for (let b = 1; b <= cuantasBandas; ++b) {
            const dentro = capasDeBanda(b)
            let choca = false
            for (let i = 0; i < dentro.length; ++i)
                if (t0 < dentro[i].t1 && t1 > dentro[i].t0)
                    choca = true
            if (!choca)
                return b
        }
        return cuantasBandas + 1
    }

    function nuevoIdCapa() {
        let mayor = 0
        for (let i = 0; i < capas.length; ++i)
            mayor = Math.max(mayor, capas[i].id)
        return mayor + 1
    }

    //  Lo que ffmpeg va a saber abrir como imagen.
    //
    //  Se comprueba la extensión y no solo que el fichero exista: `grafo()` salta
    //  las capas cuyo fichero falta, pero uno que existe y no es una imagen se le
    //  pasa a ffmpeg tal cual y tumba el render entero. Sale un fotograma negro y
    //  ni una pista de por qué. Me pasó apuntando una capa a /dev/null.
    readonly property var extensionesImagen: ["png", "jpg", "jpeg", "webp",
                                              "gif", "bmp", "avif", "tiff"]

    function esImagen(ruta) {
        const punto = ruta.lastIndexOf(".")
        if (punto < 0)
            return false
        return extensionesImagen.indexOf(
            ruta.slice(punto + 1).toLowerCase()) >= 0
    }

    function crearImagen(ruta, t0) {
        if (!ruta || ruta.length === 0)
            return 0
        if (!esImagen(ruta)) {
            fallo("no-es-imagen")
            return 0
        }
        // Tres segundos desde donde estés, o lo que quepa si estás al final.
        const a = Math.max(0, Math.min(t0, Math.max(0, duracionLinea - 1)))
        const b = Math.min(duracionLinea, a + 3)
        const nueva = {
            id: nuevoIdCapa(),
            tipo: "imagen",
            ruta: ruta,
            t0: a,
            t1: b,
            //  A la banda de más abajo donde no pise a nadie: tres logos
            //  seguidos en instantes distintos comparten fila, que es lo que se
            //  espera. Salvo que se haya pedido una capa nueva, y entonces va
            //  encima de todo.
            banda: proximaEnBandaNueva ? cuantasBandas + 1 : bandaLibre(a, b),
            // Arriba a la derecha y a un cuarto de ancho: es donde va un logo, y
            // desde ahí se mueve con el ratón en un gesto.
            x: 0.8, y: 0.15, escala: 0.25, opacidad: 1.0
        }
        capas = capas.concat([nueva])
        proximaEnBandaNueva = false
        persistir()
        seleccionar("capa", nueva.id)
        return nueva.id
    }

    // ── congelar ──────────────────────────────────────────────────
    //
    //  Parar la imagen unos segundos sin parar de hablar. El fotograma se saca
    //  a un PNG, se da de alta como fuente y se mete como un trozo más: una
    //  imagen es una fuente igual que un vídeo desde que existen los clips de
    //  imagen, así que aquí no hay ningún caso especial.
    //
    //  Lo hace python entero —sacar el fotograma, partir y recolocar— porque es
    //  aritmética de tiempos, y de eso hay un solo dueño.
    property bool congelando: false

    function congelar(t, segundos) {
        if (rutaPlan.length === 0 || congelando)
            return
        congelando = true
        congelador.command = ["python3", guion, "congelar", rutaPlan,
                              String(t), "--dur", String(segundos || 2)]
        congelador.running = true
    }

    Process {
        id: congelador
        stdout: StdioCollector {
            onStreamFinished: {
                editor.congelando = false
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (!d || !d.ok) {
                    editor.fallo(d && d.motivo ? d.motivo : "congelar")
                    return
                }
                //  El plan lo ha cambiado python, así que hay que releerlo: lo
                //  que hay en memoria se ha quedado viejo.
                editor.abrir(editor.rutaVideo, "")
            }
        }
    }

    // ── silencios ─────────────────────────────────────────────────
    //
    //  Se buscan, se parten los trozos por sus bordes y se MARCAN. No se borran:
    //  sin un deshacer, quitarle a alguien pedazos de su grabación porque un
    //  umbral dijo que ahí no se hablaba es jugársela. Marcados se ven en la
    //  línea de tiempo, se revisan, y quitarlos es otro botón.
    property string estadoSilencios: ""      // "" · buscando · fallo
    readonly property int cuantosSilencios: {
        let n = 0
        for (let i = 0; i < clips.length; ++i)
            if (clips[i].silencio)
                ++n
        return n
    }

    function buscarSilencios() {
        if (rutaPlan.length === 0 || estadoSilencios === "buscando")
            return
        estadoSilencios = "buscando"
        buscador.command = ["python3", guion, "silencios", rutaPlan]
        buscador.running = true
    }

    //  Partir la lista por un instante de LÍNEA, devolviendo la lista nueva.
    //
    //  Trabaja sobre una copia y no sobre `clips` porque hay que dar muchos
    //  cortes seguidos; publicar entre uno y otro sería recalcularlo todo cada
    //  vez y guardar el plan diez veces.
    function partirLista(lista, t, siguienteId) {
        const tramos = tramosDe(lista)
        let tr = null
        for (let i = 0; i < tramos.length; ++i)
            if (t > tramos[i].inicio && t < tramos[i].fin)
                tr = tramos[i]
        if (!tr)
            return lista
        const enFuente = tr.desde + (t - tr.inicio) * tr.velocidad
        //  Un corte pegado a un borde deja un trozo de duración cero, que ni se
        //  ve ni sirve. 20 ms es menos de un fotograma a 30 fps.
        if (enFuente - tr.desde < 0.02 || tr.hasta - enFuente < 0.02)
            return lista
        const izq = Object.assign({}, lista[tr.indice], { hasta: enFuente })
        const der = Object.assign({}, lista[tr.indice],
                                  { id: siguienteId, desde: enFuente })
        const nueva = lista.slice()
        nueva.splice(tr.indice, 1, izq, der)
        return nueva
    }

    function aplicarSilencios(tramos) {
        if (!tramos || tramos.length === 0) {
            estadoSilencios = ""
            return
        }
        //  Todos los bordes de una vez, y de mayor a menor no hace falta: partir
        //  no mueve de sitio a nadie, la línea sigue durando lo mismo.
        let lista = clips.slice()
        let id = nuevoIdClip()
        const bordes = []
        for (let i = 0; i < tramos.length; ++i) {
            bordes.push(tramos[i][0])
            bordes.push(tramos[i][1])
        }
        for (let i = 0; i < bordes.length; ++i) {
            const antes = lista.length
            lista = partirLista(lista, bordes[i], id)
            if (lista.length > antes)
                ++id
        }

        //  Y ahora marcar los que hayan quedado dentro de un silencio. Se mira
        //  el centro del trozo: un borde puede caer justo en la frontera.
        const conMarcas = tramosDe(lista)
        const dentro = {}
        for (let i = 0; i < conMarcas.length; ++i) {
            const medio = (conMarcas[i].inicio + conMarcas[i].fin) / 2
            for (let j = 0; j < tramos.length; ++j)
                if (medio > tramos[j][0] && medio < tramos[j][1])
                    dentro[conMarcas[i].clip] = true
        }
        clips = lista.map(function (c) {
            return dentro[c.id] ? Object.assign({}, c, { silencio: true })
                                : c
        })
        estadoSilencios = ""
        persistir()
    }

    //  Quitar de golpe todo lo marcado. Esto sí borra, pero ya lo has visto.
    function quitarSilencios() {
        const quedan = clips.filter(function (c) { return !c.silencio })
        if (quedan.length === 0 || quedan.length === clips.length)
            return
        clips = quedan
        seleccionar("", 0)
        persistir()
    }

    //  Y desmarcarlos, por si el umbral se pasó de listo.
    function olvidarSilencios() {
        clips = clips.map(function (c) {
            if (!c.silencio)
                return c
            const d = Object.assign({}, c)
            delete d.silencio
            return d
        })
        persistir()
    }

    Process {
        id: buscador
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (!d || !d.ok) {
                    editor.estadoSilencios = "fallo"
                    return
                }
                editor.aplicarSilencios(d.tramos || [])
            }
        }
    }

    //  Callar un tramo del sonido, o taparlo con un pitido.
    function crearCensura(t0, modo) {
        const a = Math.max(0, Math.min(t0, Math.max(0, duracionLinea - 0.5)))
        const b = Math.min(duracionLinea, a + 2)
        const nueva = {
            id: nuevoIdCapa(),
            tipo: "censura",
            modo: modo || "silencio",
            t0: a, t1: b,
            banda: proximaEnBandaNueva ? cuantasBandas + 1 : bandaLibre(a, b)
        }
        capas = capas.concat([nueva])
        proximaEnBandaNueva = false
        persistir()
        seleccionar("capa", nueva.id)
        return nueva.id
    }

    //  Cuánto dura un fundido. `cual` es "entrada", "salida" o "entre".
    function ponerFundido(cual, segundos) {
        const v = Math.max(0, Math.min(5, Number(segundos) || 0))
        if (cual === "entrada")      fundidoEntrada = v
        else if (cual === "salida")  fundidoSalida = v
        else                         fundidoEntre = v
        persistir()
    }

    //  El color de UN trozo: brillo, contraste y saturación.
    //
    //  Por clip y no por línea a propósito: sirve para que dos grabaciones que
    //  no casan se junten sin que se note, y eso es cosa de cada trozo.
    function ponerColor(id, campos) {
        const i = indiceDeClip(id)
        if (i < 0)
            return
        const antes = clips[i].color || {}
        clips = clips.map(function (c, j) {
            return j === i
                ? Object.assign({}, c, { color: Object.assign({}, antes, campos) })
                : c
        })
        persistir()
    }

    //  Los tres valores de color de un clip, con sus valores de fábrica.
    //  Ojo con el cero: `x || 1` lo convertiría en 1, que es justo lo que se
    //  quiere evitar al pedir saturación cero.
    function colorDe(clip, clave) {
        const d = clave === "brillo" ? 0 : 1
        if (!clip || !clip.color)
            return d
        const v = Number(clip.color[clave])
        return isFinite(v) ? v : d
    }

    //  Quitar el fondo verde de una capa de vídeo.
    //
    //  Solo tiene sentido con fondo de croma detrás; sin él, apagado, la cámara
    //  sale en su recuadro y ya. Por eso es un interruptor y no algo que venga
    //  puesto.
    function alternarCroma(id) {
        const c = capaPorId(id)
        if (!c || c.tipo !== "video")
            return
        fijarCapa(id, c.croma && c.croma.color
            ? { croma: null }
            : { croma: { color: "#00ff00", tolerancia: 0.25,
                         suavizado: 0.05 } })
    }

    function ponerToleranciaCroma(id, v) {
        const c = capaPorId(id)
        if (!c || !c.croma)
            return
        fijarCapa(id, { croma: Object.assign({}, c.croma, {
            tolerancia: Math.max(0.01, Math.min(1, Number(v) || 0.25)) }) })
    }

    function capaPorId(id) {
        for (let i = 0; i < capas.length; ++i)
            if (capas[i].id === id)
                return capas[i]
        return null
    }

    //  Resaltar dónde se ha pulsado.
    //
    //  No crea ninguna capa: los clics ya están apuntados en el rastro de la
    //  grabación, con su instante, así que esto es solo un interruptor. Un
    //  vídeo abierto del disco no tiene rastro y la lista sale vacía sin que
    //  haya que avisar de nada.
    function alternarClics() {
        clicsActivos = !clicsActivos
        persistir()
        recalcular.restart()
    }

    //  Tapar o destacar un trozo del fotograma.
    //
    //  No tiene fichero detrás: se hace con la propia imagen, así que es la
    //  única capa que se crea sin pedirle nada a nadie. Los tres modos
    //  —desenfoque, pixelado y foco— son la misma capa con distinto `modo`,
    //  porque comparten todo: sitio, tamaño, ventana de tiempo y fuerza.
    //
    //  `an` y `al` son fracción del fotograma como `escala` en las demás, pero
    //  hacen falta las dos: una zona que tapa una barra de direcciones es ancha
    //  y baja, y con un solo número no se puede decir eso.
    function crearZona(t0, modo) {
        const a = Math.max(0, Math.min(t0, Math.max(0, duracionLinea - 1)))
        const b = Math.min(duracionLinea, a + 3)
        const nueva = {
            id: nuevoIdCapa(),
            tipo: "zona",
            modo: modo || "desenfoque",
            t0: a, t1: b,
            banda: proximaEnBandaNueva ? cuantasBandas + 1 : bandaLibre(a, b),
            // En medio y de buen tamaño: desde ahí se coloca en un gesto.
            x: 0.5, y: 0.5, an: 0.3, al: 0.25,
            fuerza: 0.6
        }
        capas = capas.concat([nueva])
        proximaEnBandaNueva = false
        persistir()
        seleccionar("capa", nueva.id)
        return nueva.id
    }

    //  Una pista de audio añadida: música, una voz, lo que sea.
    //
    //  Antes de crearla hay que saber cuánto dura, y eso hay que preguntárselo al
    //  fichero: un bloque de duración inventada se arrastra mal y engaña sobre
    //  cuándo se acaba la música. Así que primero se mide y luego se crea.
    property string audioPendiente: ""
    property real audioPendienteEn: 0
    // "audio" o "video": las dos cosas hay que medirlas antes de crearlas.
    property string tipoPendiente: "audio"

    function crearAudio(ruta, t0) { medirYCrear(ruta, t0, "audio") }

    //  Un vídeo dentro del vídeo.
    //
    //  Se mide igual que el audio y por lo mismo, más una razón extra: hace falta
    //  su tamaño para dibujar el recuadro con la proporción que va a tener al
    //  renderizar.
    function crearPip(ruta, t0) { medirYCrear(ruta, t0, "video") }

    function medirYCrear(ruta, t0, tipo) {
        if (!ruta || ruta.length === 0)
            return
        audioPendiente = ruta
        audioPendienteEn = Math.max(0, Math.min(t0, duracionLinea))
        tipoPendiente = tipo
        medidor.command = ["python3", guion, "medir", ruta]
        medidor.running = true
    }

    Process {
        id: medidor
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (!d || !d.ok || editor.audioPendiente.length === 0) {
                    editor.fallo(d && d.motivo ? d.motivo : "no-se-puede-medir")
                    editor.audioPendiente = ""
                    return
                }
                if (editor.tipoPendiente === "video" && !d.w) {
                    // Sin flujo de vídeo no es un vídeo, diga lo que diga el nombre.
                    editor.fallo("sin-video")
                    editor.audioPendiente = ""
                    return
                }
                editor.anadirMedio(editor.audioPendiente,
                                   editor.audioPendienteEn, d,
                                   editor.tipoPendiente)
                editor.audioPendiente = ""
            }
        }
    }

    function anadirMedio(ruta, t0, medida, tipo) {
        const a = Math.max(0, Math.min(t0, Math.max(0, duracionLinea - 0.5)))
        //  El bloque acaba donde acabe el fichero o donde acabe el vídeo, lo que
        //  llegue antes: la parte que se sale no se va a ver ni oír, así que
        //  enseñarla en la línea de tiempo sería mentir.
        const b = Math.min(duracionLinea, a + medida.dur)
        const nueva = {
            id: nuevoIdCapa(),
            tipo: tipo,
            ruta: ruta,
            t0: a,
            t1: b,
            dur: medida.dur,
            banda: proximaEnBandaNueva ? cuantasBandas + 1 : bandaLibre(a, b)
        }
        if (tipo === "audio") {
            nueva.volumen = 0.8
        } else {
            // Abajo a la derecha y a un tercio: donde va una cámara.
            nueva.x = 0.76
            nueva.y = 0.74
            nueva.escala = 0.3
            nueva.opacidad = 1.0
            nueva.w = medida.w
            nueva.h = medida.h
            //  De qué parte del fichero se coge. Empieza siendo todo, y se
            //  recorta estirando el bloque: `t1 - t0` es lo que se ve, así que el
            //  recorte se deduce de ahí.
            nueva.recorte = [0, medida.dur]
        }
        capas = capas.concat([nueva])
        proximaEnBandaNueva = false
        persistir()
        seleccionar("capa", nueva.id)
    }

    //  Un rótulo.
    //
    //  Nace con texto de relleno y no vacío: una capa invisible en un sitio que
    //  no sabes es imposible de encontrar, y lo primero que se hace es
    //  reescribirlo de todas formas.
    function crearTexto(t0) {
        const a = Math.max(0, Math.min(t0, Math.max(0, duracionLinea - 1)))
        const b = Math.min(duracionLinea, a + 3)
        const nueva = {
            id: nuevoIdCapa(),
            tipo: "texto",
            texto: Idioma.t("Escribe aquí"),
            t0: a,
            t1: b,
            banda: proximaEnBandaNueva ? cuantasBandas + 1 : bandaLibre(a, b),
            // Abajo y centrado, que es donde va un rótulo.
            x: 0.5, y: 0.85, tam: 0.06,
            color: "#ffffff",
            //  Con caja detrás por defecto. Un rótulo blanco sobre un vídeo
            //  claro no se lee, y descubrirlo al renderizar es tarde.
            fondo: 0.5, colorFondo: "#000000"
        }
        capas = capas.concat([nueva])
        proximaEnBandaNueva = false
        persistir()
        seleccionar("capa", nueva.id)
        return nueva.id
    }

    //  Cómo se llama una capa en una lista.
    //
    //  Una imagen por su fichero y un rótulo por lo que dice: es lo que
    //  distingue dos rótulos, y el nombre de un fichero que no existe no
    //  distinguiría nada.
    function nombreCapa(c) {
        if (!c)
            return ""
        if (c.tipo === "texto") {
            const t = String(c.texto || "").trim()
            return t.length > 0 ? t : Idioma.t("Rótulo")
        }
        // Una zona no tiene fichero: lo que la distingue es qué le hace.
        if (c.tipo === "zona")
            return c.modo === "pixelado" ? Idioma.t("Pixelado")
                 : c.modo === "foco"     ? Idioma.t("Foco")
                                         : Idioma.t("Desenfoque")
        if (c.tipo === "censura")
            return c.modo === "pitido" ? Idioma.t("Pitido")
                                       : Idioma.t("Silenciado")
        return String(c.ruta || "").split("/").pop()
    }

    // El icono que le toca a una capa según de qué sea.
    function glifoCapa(c) {
        if (!c)
            return 0x000F02E9                  // md-image
        if (c.tipo === "texto")
            return 0x000F0284                  // md-format_text
        if (c.tipo === "audio")
            return 0x000F075A                  // md-music
        if (c.tipo === "video")
            return 0x000F0E57                  // md-picture_in_picture_bottom_right
        //  Codepoints comprobados contra los nombres de la propia fuente, no de
        //  memoria: los tres primeros que puse eran un tenedor, un rayo y una
        //  pila. Se miran con fontTools sobre MesloLGSNerdFontMono-Regular.ttf.
        if (c.tipo === "censura")
            return c.modo === "pitido" ? 0x000F1479     // md-cosine_wave
                                       : 0x000F075F     // md-volume_mute
        if (c.tipo === "zona")
            return c.modo === "pixelado" ? 0x000F00B6   // md-blur_linear
                 : c.modo === "foco"     ? 0x000F04C9   // md-spotlight_beam
                                         : 0x000F00B5   // md-blur
        return 0x000F02E9
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
        // Quitar la última de una banda deja la banda vacía; que no se quede.
        compactarBandas()
        seleccionar("", 0)
    }

    //  Llevar una capa a otra banda.
    //
    //  `d` va en el sentido del PLAN: +1 la sube una banda. La lista de la
    //  interfaz se enseña del revés —arriba lo que está delante, que es lo que
    //  espera cualquiera—, y esa vuelta se da una sola vez, en la vista.
    //
    //  Se puede subir una banda por encima de las que hay: así se crea una nueva
    //  sin tener que pedirla aparte. Bajar de la 1 no lleva a ninguna parte.
    function ponerCapaEnBanda(id, banda) {
        const i = capas.findIndex(function (c) { return c.id === id })
        if (i < 0)
            return
        //  Se puede pasar una banda por encima de las que hay: así arrastrar algo
        //  hacia arriba crea una capa nueva sin tener que pedirla aparte.
        const b = Math.max(1, Math.min(cuantasBandas + 1, banda))
        if (b === bandaDe(capas[i]))
            return
        const d = b - bandaDe(capas[i])

        //  Y también al principio o al final de la lista, según el sentido.
        //
        //  Dentro de una banda manda el orden de la lista, así que bajar de banda
        //  sin tocarla dejaría la capa por encima de las que ya estaban abajo:
        //  «bajar» y quedarse delante es lo contrario de lo que dice el botón.
        //  Con dos capas que se pisen en el tiempo esto se ve a la primera.
        const nuevas = capas.slice()
        const capa = Object.assign({}, nuevas.splice(i, 1)[0], { banda: b })
        if (d > 0)
            nuevas.push(capa)
        else
            nuevas.unshift(capa)
        capas = nuevas
        compactarBandas()
    }

    //  Quitar las bandas que se hayan quedado vacías.
    //
    //  Sin esto, mover la única capa de la banda 2 a la 3 deja la 2 como una fila
    //  vacía para siempre, y a los cuatro movimientos la línea de tiempo es un
    //  paisaje de filas en blanco.
    function compactarBandas() {
        const usadas = []
        for (let i = 0; i < capas.length; ++i) {
            const b = bandaDe(capas[i])
            if (usadas.indexOf(b) < 0)
                usadas.push(b)
        }
        usadas.sort(function (a, b) { return a - b })

        capas = capas.map(function (c) {
            return Object.assign({}, c,
                                 { banda: usadas.indexOf(bandaDe(c)) + 1 })
        })
        persistir()
    }

    //  Llevar una banda a otro puesto del apilado, con todo lo que lleve.
    //
    //  Se reordena la lista de números de banda y luego se renumera, en vez de
    //  intercambiar de dos en dos: arrastrar la banda 4 hasta la 1 es un solo
    //  gesto, no tres intercambios, y con intercambios el resultado depende del
    //  orden en que se hagan.
    function ponerBandaEn(b, destino) {
        const n = cuantasBandas
        const d = Math.max(1, Math.min(n, destino))
        if (b < 1 || b > n || d === b)
            return

        const orden = []
        for (let i = 1; i <= n; ++i)
            orden.push(i)
        orden.splice(d - 1, 0, orden.splice(b - 1, 1)[0])

        // `orden[k]` es la banda vieja que pasa a ser la k+1.
        const nueva = {}
        for (let k = 0; k < orden.length; ++k)
            nueva[orden[k]] = k + 1

        capas = capas.map(function (c) {
            return Object.assign({}, c, { banda: nueva[bandaDe(c)] })
        })
        persistir()
    }

    //  «Añadir una capa» es añadir algo en una banda nueva encima.
    //
    //  Estuve a punto de hacer bandas vacías que se pudieran crear a mano, y no
    //  tiene sentido: en este modelo una banda sin nada dentro no existe en el
    //  plan, así que sería una fila fantasma que se pierde al cerrar. Lo que de
    //  verdad se quiere al preguntar «¿cómo añado una capa?» es poner algo
    //  ENCIMA de lo que ya hay sin tener que colocarlo después.
    property bool proximaEnBandaNueva: false

    // ── la transcripción ──────────────────────────────────────────
    //
    //  Lo que se dice en el vídeo, en segmentos con sus tiempos. Sirve para
    //  subtitular y —más útil de lo que parece— para sacar rótulos de lo que ya
    //  dijiste en voz alta: un botón por segmento y ya está escrito.
    //
    //  Los segmentos van al plan, así que al reabrir mañana están ahí sin tener
    //  que volver a transcribir, que es lo caro.
    property var transcripcion: []
    property string estadoTranscripcion: ""   // "" · comprobando · extrayendo
                                              // transcribiendo · falta · fallo
    //  Qué falta para poder transcribir, y el mandato exacto para tenerlo.
    //  whisper.cpp son 1,4 GB entre binario y modelo: no se instala solo.
    property string faltaTranscripcion: ""    // binario · modelo
    property string comoInstalar: ""

    readonly property string guionTranscribir:
        Quickshell.shellPath("tools/transcribir.py")

    function transcribir() {
        if (rutaVideo.length === 0 || estadoTranscripcion === "transcribiendo")
            return
        estadoTranscripcion = "comprobando"
        comprobador.running = true
    }

    Process {
        id: comprobador
        command: ["python3", editor.guionTranscribir, "comprobar"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (!d) {
                    editor.estadoTranscripcion = "fallo"
                    return
                }
                editor.comoInstalar = d.como || ""
                if (d.falta && d.falta.length > 0) {
                    editor.faltaTranscripcion = d.falta
                    editor.estadoTranscripcion = "falta"
                    return
                }
                editor.faltaTranscripcion = ""
                editor.estadoTranscripcion = "extrayendo"
                transcriptor.command = ["python3", editor.guionTranscribir,
                                        "hacer", editor.rutaVideo,
                                        "--idioma", Idioma.codigo || "es",
                                        "--salida", editor.carpetaAdjunta]
                transcriptor.running = true
            }
        }
    }

    //  La carpeta que acompaña al plan, donde van los ficheros que hace falta
    //  tener en disco: el texto de los rótulos, el SRT, el grafo.
    readonly property string carpetaAdjunta:
        rutaPlan.length > 5 ? rutaPlan.substring(0, rutaPlan.length - 5) : ""

    Process {
        id: transcriptor
        stdout: SplitParser {
            onRead: function (linea) {
                let d = null
                try { d = JSON.parse(linea) } catch (e) { return }
                if (d.estado && d.estado !== "fin") {
                    editor.estadoTranscripcion = d.estado
                    return
                }
                if (d.ok === false) {
                    editor.estadoTranscripcion = d.motivo === "sin-whisper"
                        || d.motivo === "sin-modelo" ? "falta" : "fallo"
                    if (d.como)
                        editor.comoInstalar = d.como
                    return
                }
                if (d.estado === "fin") {
                    editor.transcripcion = d.segmentos || []
                    editor.estadoTranscripcion = ""
                    editor.persistir()
                }
            }
        }
    }

    //  Un segmento en un rótulo, con sus mismos tiempos.
    //
    //  Es el puente que hace que la transcripción sirva para algo más que
    //  subtitular: lo dijiste, ya está escrito, y ahora se ve.
    function rotuloDesde(seg) {
        const id = crearTexto(seg.t0)
        fijarCapa(id, { texto: seg.texto,
                        t0: seg.t0,
                        t1: Math.max(seg.t0 + 0.4, seg.t1) })
        return id
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

    //  Los clics del rastro, ya en tiempo de línea y en píxeles del lienzo.
    //
    //  Los calcula python junto con la trayectoria porque los dos dependen del
    //  rastro Y del mapa de clips: al cortar un trozo, los clics que caían ahí
    //  desaparecen solos y los de después se recolocan.
    property var clics: []
    property bool clicsActivos: false

    //  Fundidos de la línea: al entrar, al salir y en cada corte.
    //
    //  Van en el plan y no por clip porque son una decisión del montaje entero.
    //  «Entre» no es un encadenado de verdad: es fundir a negro al final de un
    //  trozo y desde negro al principio del siguiente. Un `xfade` solaparía los
    //  trozos y ACORTARÍA la línea, y eso descolocaría el mapa y con él todos
    //  los rótulos y los zooms.
    property real fundidoEntrada: 0
    property real fundidoSalida: 0
    property real fundidoEntre: 0
    property string colorClics: "#ffd60a"

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

    //  La cámara que se grabó a la vez, si la hubo.
    //
    //  Se pasa por argumento y no se busca sola en python porque hace falta
    //  también el desfase, y ese solo lo sabe quien arrancó los dos procesos:
    //  dos ffmpeg no empiezan en el mismo milisegundo y fingir que sí sería
    //  mentir sobre la sincronía. Se apunta al grabar y se olvida al usarlo.
    property string camaraPendiente: ""
    property real desfasePendiente: 0

    function argsCamara() {
        if (camaraPendiente.length === 0)
            return []
        const a = ["--camara", camaraPendiente,
                   "--desfase", String(desfasePendiente.toFixed(3))]
        camaraPendiente = ""
        desfasePendiente = 0
        return a
    }

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
                           "--guardar", rutaPlan].concat(argsCamara())
        abridor.running = true
    }

    function proponer(video, rastro) {
        if (!video || video.length === 0 || !rastro || rastro.length === 0)
            return
        preparar(video)
        proponedor.command = [guion, "proponer", rastro,
                              "--video", video,
                              "--guardar", rutaPlan,
                              "--nivel", String(zoomNivel)].concat(argsCamara())
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
        clics = []
        posicionEditor = 0
        progreso = 0
    }

    function recibirPlan(d) {
        anchoVideo = d.w || 1920
        altoVideo = d.h || 1080
        fuentes = d.fuentes || []
        clips = d.clips || []
        capas = d.capas || []
        transcripcion = d.transcripcion || []
        clicsActivos = !!(d.clics && d.clics.activo)
        fundidoEntrada = (d.fundidos && d.fundidos.entrada) || 0
        fundidoSalida = (d.fundidos && d.fundidos.salida) || 0
        fundidoEntre = (d.fundidos && d.fundidos.entre) || 0
        colorClics = (d.clics && d.clics.color) || "#ffd60a"
        estadoTranscripcion = ""
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
            "p['transcripcion']=d['transcripcion']; " +
            "p['clics']=d['clics']; " +
            "p['fundidos']=d['fundidos']; " +
            "json.dump(p, open(sys.argv[1],'w'), ensure_ascii=False, indent=1)",
            rutaPlan,
            JSON.stringify({ momentos: momentos, pistas: pistasAudio,
                             clips: clips, capas: capas,
                             transcripcion: transcripcion,
                             clics: { activo: clicsActivos,
                                      color: colorClics },
                             fundidos: { entrada: fundidoEntrada,
                                         salida: fundidoSalida,
                                         entre: fundidoEntre } })]
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
                        editor.clics = d.clics || []
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
