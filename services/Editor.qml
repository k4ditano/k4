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
//
//  Y tampoco lanza procesos: los diez que hablan con python viven en
//  EditorProcesos.qml y contestan por señales. Este fichero decide qué hacer
//  con cada respuesta, que es lo que le toca a una máquina de estados.

import QtQuick
import Quickshell

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

    // Historial del plan. Se guardan instantáneas JSON pequeñas y se agrupan
    // los eventos rápidos (arrastrar una capa o escribir un rótulo) para que
    // Ctrl+Z sea útil y no recorra cada píxel del gesto.
    property var historial: []
    property var rehacerHistorial: []
    property bool restaurandoHistorial: false
    property string ultimoHistorial: ""
    property var marcadores: []

    function instantanea() {
        return JSON.stringify({ clips: clips, capas: capas, bandas: bandas,
                                momentos: momentos, pistasAudio: pistasAudio,
                                transcripcion: transcripcion,
                                marcadores: marcadores,
                                clicsActivos: clicsActivos,
                                colorClics: colorClics,
                                fundidoEntrada: fundidoEntrada,
                                fundidoSalida: fundidoSalida,
                                fundidoEntre: fundidoEntre,
                                transicionTipo: transicionTipo,
                                transicionDur: transicionDur })
    }

    function iniciarHistorial() {
        const s = instantanea()
        historial = [s]
        rehacerHistorial = []
        ultimoHistorial = s
    }

    function registrarHistorial() {
        if (restaurandoHistorial)
            return
        const s = instantanea()
        if (s === ultimoHistorial)
            return
        const h = historial.slice()
        h.push(s)
        while (h.length > 80)
            h.shift()
        historial = h
        ultimoHistorial = s
        rehacerHistorial = []
    }

    readonly property bool puedeDeshacer: historial.length > 1
    readonly property bool puedeRehacer: rehacerHistorial.length > 0

    function restaurarInstantanea(s) {
        if (!s)
            return
        let d = null
        try { d = JSON.parse(s) } catch (e) { return }
        restaurandoHistorial = true
        clips = d.clips || []
        capas = d.capas || []
        bandas = d.bandas || []
        momentos = d.momentos || []
        pistasAudio = d.pistasAudio || []
        transcripcion = d.transcripcion || []
        marcadores = d.marcadores || []
        clicsActivos = !!d.clicsActivos
        colorClics = d.colorClics || "#ffd60a"
        fundidoEntrada = d.fundidoEntrada || 0
        fundidoSalida = d.fundidoSalida || 0
        fundidoEntre = d.fundidoEntre || 0
        transicionTipo = d.transicionTipo || ""
        transicionDur = d.transicionDur || 0.5
        restaurandoHistorial = false
        ultimoHistorial = s
        persistir()
        procesos.recalcularCamara()
    }

    function deshacer() {
        if (!puedeDeshacer)
            return
        const h = historial.slice()
        const actual = h.pop()
        rehacerHistorial = rehacerHistorial.concat([actual])
        historial = h
        restaurarInstantanea(h[h.length - 1])
        seleccionar("", 0)
    }

    function rehacer() {
        if (!puedeRehacer)
            return
        const r = rehacerHistorial.slice()
        const s = r.pop()
        rehacerHistorial = r
        historial = historial.concat([s])
        restaurarInstantanea(s)
        seleccionar("", 0)
    }

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

    // Bandas persistentes: una puede existir aunque todavía no tenga ningún
    // elemento. Así se puede preparar la organización del montaje antes de
    // traer imágenes, rótulos o vídeos a ella.
    // [{ banda: 2, nombre: "Presentación" }, ...]
    property var bandas: []

    //  Una capa sin banda va a la 2, que es la primera que le corresponde: la
    //  1 es del vídeo. Un plan de los de antes se sube entero al abrirlo, así
    //  que aquí no llegan capas en la 1 salvo que alguien edite el JSON a mano.
    function bandaDe(c) {
        const b = c.banda !== undefined ? c.banda : primeraBandaLibre
        return Math.max(primeraBandaLibre, b)
    }

    //  Cuántas bandas hay, contando la 1, que es SIEMPRE la del vídeo.
    //
    //  El vídeo es la capa 1: nace con el plan y no se puede quitar. Las capas
    //  que añades empiezan en la 2 y se apilan por encima. Antes había tres
    //  cosas apilándose por caminos distintos —los trozos con su fila fija, el
    //  zoom con la suya y las capas con las bandas— y eran cuatro filas para dos
    //  capas.
    readonly property int cuantasBandas: {
        let n = 2
        for (let i = 0; i < capas.length; ++i)
            n = Math.max(n, bandaDe(capas[i]))
        for (let i = 0; i < bandas.length; ++i)
            n = Math.max(n, Number(bandas[i].banda) || 0)
        return n
    }

    //  La primera banda donde puede ir una capa. La 1 es del vídeo.
    readonly property int primeraBandaLibre: 2

    // Las capas de una banda, en el orden en que se apilan dentro de ella.
    function capasDeBanda(b) {
        return capas.filter(function (c) { return bandaDe(c) === b })
    }

    function infoBanda(b) {
        for (let i = 0; i < bandas.length; ++i)
            if (Number(bandas[i].banda) === b)
                return bandas[i]
        return null
    }

    function bandaVisible(b) {
        const info = infoBanda(b)
        return !info || info.visible !== false
    }

    function bandaBloqueada(b) {
        const info = infoBanda(b)
        return !!(info && info.bloqueada)
    }

    function haySolo() {
        for (let i = 0; i < bandas.length; ++i)
            if (bandas[i].solo)
                return true
        return false
    }

    function capaVisible(c) {
        if (!c)
            return false
        const info = infoBanda(bandaDe(c))
        if (info && info.visible === false)
            return false
        if (haySolo() && !(info && info.solo))
            return false
        return c.visible !== false
    }

    function capaBloqueada(c) {
        return !!(c && (c.bloqueada || bandaBloqueada(bandaDe(c))))
    }

    function alternarVisibilidadCapa(id) {
        const c = capaPorId(id)
        if (!c) return
        fijarCapa(id, { visible: c.visible === false })
    }

    function alternarBloqueoCapa(id) {
        const c = capaPorId(id)
        if (!c) return
        fijarCapa(id, { bloqueada: !c.bloqueada })
    }

    function alternarVisibilidadBanda(b) {
        const info = infoBanda(b) || { banda: b, nombre: nombreBanda(b) }
        if (infoBanda(b) === null)
            bandas = bandas.concat([info])
        fijarBanda(b, { visible: info.visible === false })
    }

    function alternarBloqueoBanda(b) {
        const info = infoBanda(b) || { banda: b, nombre: nombreBanda(b) }
        if (infoBanda(b) === null)
            bandas = bandas.concat([info])
        fijarBanda(b, { bloqueada: !info.bloqueada })
    }

    function alternarSoloBanda(b) {
        const info = infoBanda(b) || { banda: b, nombre: nombreBanda(b) }
        if (infoBanda(b) === null)
            bandas = bandas.concat([info])
        fijarBanda(b, { solo: !info.solo })
    }

    function nombreBanda(b) {
        const info = infoBanda(b)
        return info && info.nombre
            ? info.nombre
            : Idioma.t("Capa ") + (b - primeraBandaLibre + 1)
    }

    function crearBanda(nombre) {
        let b = primeraBandaLibre
        while (b <= cuantasBandas
               && (infoBanda(b) !== null || capasDeBanda(b).length > 0))
            b += 1
        bandas = bandas.concat([{ banda: b,
                                  nombre: nombre || nombreBanda(b) }])
        bandaObjetivo = b
        bandaSeleccionada = b
        persistir()
        seleccionar("", 0)
        return b
    }

    function fijarBanda(b, campos) {
        bandas = bandas.map(function (x) {
            return Number(x.banda) === b ? Object.assign({}, x, campos) : x
        })
        persistir()
    }

    // El destino de la siguiente capa: el grupo elegido, o el primer hueco
    // temporal disponible. Si no queda sitio se crea un grupo nuevo.
    function bandaParaNueva(t0, t1) {
        let b = bandaObjetivo > 0 ? bandaObjetivo : bandaLibre(t0, t1)
        if (b > cuantasBandas) {
            bandas = bandas.concat([{ banda: b, nombre: nombreBanda(b) }])
        }
        bandaObjetivo = 0
        return b
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
        for (let b = primeraBandaLibre; b <= cuantasBandas; ++b) {
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
            banda: bandaParaNueva(a, b),
            // Arriba a la derecha y a un cuarto de ancho: es donde va un logo, y
            // desde ahí se mueve con el ratón en un gesto.
            x: 0.8, y: 0.15, escala: 0.25, opacidad: 1.0, rotacion: 0
        }
        capas = capas.concat([nueva])
        persistir()
        seleccionar("capa", nueva.id)
        return nueva.id
    }

    //  Sacar el audio de un trozo a su propia capa.
    //
    //  Es lo que permite recortar el sonido por su cuenta: dejar la voz sonando
    //  por encima del corte siguiente, adelantarla, o bajarle el volumen solo en
    //  ese cacho. Reusa las capas de audio que ya existen —no hay una pista de
    //  audio aparte— y lo único nuevo es que una capa de audio puede llevar
    //  recorte, igual que ya lo llevaba un vídeo dentro del vídeo.
    //
    //  El trozo se queda mudo, no vacío: el vídeo sigue ahí y lo que se ha
    //  movido es su sonido. Deshacerlo es quitar la capa y desmarcar el trozo.
    function separarAudio(id) {
        const i = indiceDeClip(id)
        if (i < 0 || clips[i].mudo)
            return 0
        const c = clips[i]
        const tr = tramoDe(id) >= 0 && tramos.length > 0
            ? tramos[tramoDe(id)] : null
        if (!tr)
            return 0

        const nueva = {
            id: nuevoIdCapa(),
            tipo: "audio",
            ruta: rutaDe(c.fuente),
            //  Dónde se oye en la línea, y qué parte del fichero se oye.
            t0: tr.inicio,
            t1: tr.fin,
            recorte: [c.desde, c.hasta],
            volumen: 1.0,
            dur: Math.max(0.1, c.hasta - c.desde),
            banda: bandaLibre(tr.inicio, tr.fin)
        }
        capas = capas.concat([nueva])
        clips = clips.map(function (x, j) {
            return j === i ? Object.assign({}, x, { mudo: true }) : x
        })
        persistir()
        seleccionar("capa", nueva.id)
        return nueva.id
    }

    //  Devolverle el sonido a un trozo. No borra la capa: quitarle a alguien
    //  algo que ha movido y ajustado sería peor que dejarle dos sonidos.
    function devolverAudio(id) {
        const i = indiceDeClip(id)
        if (i < 0)
            return
        clips = clips.map(function (x, j) {
            if (j !== i)
                return x
            const d = Object.assign({}, x)
            delete d.mudo
            return d
        })
        persistir()
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
    readonly property bool congelando: procesos.congelando

    function congelar(t, segundos) {
        if (rutaPlan.length === 0 || congelando)
            return
        procesos.congelar(t, segundos)
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
        procesos.buscarSilencios()
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

    //  Callar un tramo del sonido, o taparlo con un pitido.
    function crearCensura(t0, modo) {
        const a = Math.max(0, Math.min(t0, Math.max(0, duracionLinea - 0.5)))
        const b = Math.min(duracionLinea, a + 2)
        const nueva = {
            id: nuevoIdCapa(),
            tipo: "censura",
            modo: modo || "silencio",
            t0: a, t1: b,
            banda: bandaParaNueva(a, b)
        }
        capas = capas.concat([nueva])
        persistir()
        seleccionar("capa", nueva.id)
        return nueva.id
    }

    //  Cuánto dura un fundido. `cual` es "entrada", "salida" o "entre".
    //  La transición de los cortes. Tipo vacío es corte seco.
    function ponerTransicion(tipo, segundos) {
        transicionTipo = tipo || ""
        if (segundos !== undefined)
            transicionDur = Math.max(0.15, Math.min(1, Number(segundos) || 0.5))
        persistir()
    }

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
        procesos.recalcularCamara()
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
            banda: bandaParaNueva(a, b),
            // En medio y de buen tamaño: desde ahí se coloca en un gesto.
            x: 0.5, y: 0.5, an: 0.3, al: 0.25,
            fuerza: 0.6
        }
        capas = capas.concat([nueva])
        persistir()
        seleccionar("capa", nueva.id)
        return nueva.id
    }

    //  Una forma para señalar: flecha, círculo o marco.
    //
    //  No lleva fichero detrás: la dibuja python al renderizar, con su modo y
    //  su color, y la previa la pinta con el mismo trazo. Nace en medio, roja
    //  y de buen tamaño: desde ahí se coloca, se gira y se anima como
    //  cualquier imagen, que es exactamente lo que es por dentro.
    function crearForma(t0, modo) {
        const a = Math.max(0, Math.min(t0, Math.max(0, duracionLinea - 1)))
        const b = Math.min(duracionLinea, a + 3)
        const nueva = {
            id: nuevoIdCapa(),
            tipo: "forma",
            modo: modo || "flecha",
            color: "#ff453a",
            t0: a, t1: b,
            banda: bandaParaNueva(a, b),
            x: 0.5, y: 0.5, escala: 0.18, opacidad: 1.0, rotacion: 0
        }
        capas = capas.concat([nueva])
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
        procesos.medir(ruta)
    }

    //  Lo que contesta el medidor: la medida que faltaba para crear la capa
    //  que quedó pendiente, o un fallo que la cancela.
    function recibirMedida(d) {
        if (!d || !d.ok || audioPendiente.length === 0) {
            fallo(d && d.motivo ? d.motivo : "no-se-puede-medir")
            audioPendiente = ""
            return
        }
        if (tipoPendiente === "video" && !d.w) {
            // Sin flujo de vídeo no es un vídeo, diga lo que diga el nombre.
            fallo("sin-video")
            audioPendiente = ""
            return
        }
        anadirMedio(audioPendiente, audioPendienteEn, d, tipoPendiente)
        audioPendiente = ""
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
            banda: bandaParaNueva(a, b)
        }
        if (tipo === "audio") {
            nueva.volumen = 0.8
        } else {
            // Abajo a la derecha y a un tercio: donde va una cámara.
            nueva.x = 0.76
            nueva.y = 0.74
            nueva.escala = 0.3
            nueva.opacidad = 1.0
            nueva.rotacion = 0
            nueva.w = medida.w
            nueva.h = medida.h
            //  De qué parte del fichero se coge. Empieza siendo todo, y se
            //  recorta estirando el bloque: `t1 - t0` es lo que se ve, así que el
            //  recorte se deduce de ahí.
            nueva.recorte = [0, medida.dur]
        }
        capas = capas.concat([nueva])
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
            banda: bandaParaNueva(a, b),
            // Abajo y centrado, que es donde va un rótulo.
            x: 0.5, y: 0.85, tam: 0.06,
            color: "#ffffff",
            //  Con caja detrás por defecto. Un rótulo blanco sobre un vídeo
            //  claro no se lee, y descubrirlo al renderizar es tarde.
            fondo: 0.5, colorFondo: "#000000"
        }
        capas = capas.concat([nueva])
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
        if (c.tipo === "forma")
            return c.modo === "circulo" ? Idioma.t("Círculo")
                 : c.modo === "marco"   ? Idioma.t("Marco")
                                        : Idioma.t("Flecha")
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
        if (c.tipo === "forma")
            return c.modo === "circulo" ? 0x000F0130    // md-checkbox_blank_circle_outline
                 : c.modo === "marco"   ? 0x000F01A2    // md-crop_square
                                        : 0x000F09C6    // md-arrow_top_right_thick
        return 0x000F02E9
    }

    function fijarCapa(id, campos) {
        const actual = capaPorId(id)
        const esControl = campos && (Object.prototype.hasOwnProperty.call(campos, "visible")
                                     || Object.prototype.hasOwnProperty.call(campos, "bloqueada"))
        if (actual && capaBloqueada(actual) && !esControl)
            return
        capas = capas.map(function (c) {
            if (c.id !== id)
                return c
            return Object.assign({}, c, campos)
        })
        persistir()
    }

    function ponerTransformacion(id, campos) {
        const c = capaPorId(id)
        if (!c || capaBloqueada(c))
            return
        fijarCapa(id, campos)
    }

    //  Con qué entra y con qué sale una capa: desvanecer o deslizar.
    //
    //  `cual` es "entrada" o "salida" y un tipo vacío quita el efecto. La
    //  duración la acotan por igual python al renderizar y la previa al
    //  pintar: media ventana de la capa como mucho, que más que eso ya no es
    //  un efecto sino la capa entera apareciendo.
    function fijarEfecto(id, cual, tipo, dur) {
        const campos = {}
        campos[cual] = tipo && tipo.length > 0
            ? { tipo: tipo,
                dur: Math.max(0.1, Math.min(2, Number(dur) || 0.4)) }
            : null
        fijarCapa(id, campos)
    }

    //  El modo «trazar movimiento»: pinchar el recorrido sobre el vídeo.
    function alternarRuta() {
        const c = capaSel
        if (!c || capaBloqueada(c)
            || (c.tipo !== "imagen" && c.tipo !== "texto" && c.tipo !== "video")) {
            trazandoRuta = false
            return
        }
        trazandoRuta = !trazandoRuta
    }

    //  Un punto más del recorrido, pinchado sobre el vídeo.
    //
    //  El tiempo se reparte solo: los puntos quedan equiespaciados en la
    //  ventana de la capa, así que la velocidad la pone la DISTANCIA — dos
    //  puntos juntos van despacio, dos separados van deprisa — y después se
    //  afina moviendo los rombos en la línea de tiempo. Añadir un punto
    //  vuelve a repartir: un recorrido nuevo es un plan nuevo.
    function anadirPuntoRuta(id, x, y) {
        const c = capaPorId(id)
        if (!c || capaBloqueada(c))
            return
        const nuevo = { t: 0,
                        x: Math.max(0, Math.min(1, Number(x) || 0)),
                        y: Math.max(0, Math.min(1, Number(y) || 0)),
                        escala: c.escala !== undefined ? c.escala : 0.3,
                        tam: c.tam !== undefined ? c.tam : 0.06,
                        rotacion: c.rotacion !== undefined ? c.rotacion : 0,
                        opacidad: c.opacidad !== undefined ? c.opacidad : 1 }
        let ks = (c.keyframes || []).concat([nuevo])
        const t0 = Number(c.t0) || 0
        const t1 = Math.max(t0 + 0.1, Number(c.t1) || 0)
        ks = ks.map(function (k, i) {
            return Object.assign({}, k, {
                t: ks.length === 1 ? t0
                   : t0 + (t1 - t0) * i / (ks.length - 1) })
        })
        fijarCapa(id, { keyframes: ks })
    }

    //  Llevar un punto del recorrido a otro sitio del fotograma.
    function moverPuntoRuta(id, indice, x, y) {
        const c = capaPorId(id)
        if (!c || capaBloqueada(c) || !c.keyframes
            || indice < 0 || indice >= c.keyframes.length)
            return
        const ks = c.keyframes.slice()
        ks[indice] = Object.assign({}, ks[indice], {
            x: Math.max(0, Math.min(1, Number(x) || 0)),
            y: Math.max(0, Math.min(1, Number(y) || 0)) })
        fijarCapa(id, { keyframes: ks })
    }

    //  Mover un fotograma clave a otro instante. Se reordena por si el
    //  arrastre lo ha cruzado con un vecino: la lista va siempre por tiempo.
    function moverKeyframe(id, indice, t) {
        const c = capaPorId(id)
        if (!c || capaBloqueada(c) || !c.keyframes
            || indice < 0 || indice >= c.keyframes.length)
            return
        const ks = c.keyframes.slice()
        ks[indice] = Object.assign({}, ks[indice],
            { t: Math.max(0, Math.min(duracionLinea, Number(t) || 0)) })
        ks.sort(function (a, b) { return a.t - b.t })
        fijarCapa(id, { keyframes: ks })
    }

    //  Quitar uno. El último se lleva la lista entera: una capa con cero
    //  claves es una capa quieta, no una animación vacía.
    function quitarKeyframe(id, indice) {
        const c = capaPorId(id)
        if (!c || capaBloqueada(c) || !c.keyframes)
            return
        const ks = c.keyframes.filter(function (x, j) { return j !== indice })
        fijarCapa(id, { keyframes: ks.length > 0 ? ks : null })
    }

    function crearKeyframe(id, t) {
        const c = capaPorId(id)
        if (!c || capaBloqueada(c)) return
        const k = { t: Math.max(0, Math.min(duracionLinea, Number(t) || 0)),
                    x: c.x !== undefined ? c.x : 0.5,
                    y: c.y !== undefined ? c.y : 0.5,
                    escala: c.escala !== undefined ? c.escala : 0.3,
                    tam: c.tam !== undefined ? c.tam : 0.06,
                    rotacion: c.rotacion !== undefined ? c.rotacion : 0,
                    opacidad: c.opacidad !== undefined ? c.opacidad : 1 }
        const ks = (c.keyframes || []).filter(function (x) {
            return Math.abs(Number(x.t) - k.t) > 0.02
        }).concat([k]).sort(function (a, b) { return a.t - b.t })
        fijarCapa(id, { keyframes: ks })
    }

    function ajustarTiempo(v, excluirId) {
        let t = Math.max(0, Math.min(duracionLinea, Number(v) || 0))
        const puntos = [0, duracionLinea]
        for (let i = 0; i < tramos.length; ++i) {
            puntos.push(tramos[i].inicio, tramos[i].fin)
        }
        for (let i = 0; i < marcadores.length; ++i)
            puntos.push(Number(marcadores[i].t) || 0)
        let mejor = t
        let distancia = 0.08
        for (let i = 0; i < puntos.length; ++i) {
            const d = Math.abs(puntos[i] - t)
            if (d < distancia) {
                distancia = d
                mejor = puntos[i]
            }
        }
        return mejor
    }

    function crearMarcador(t, nombre) {
        const a = Math.max(0, Math.min(duracionLinea, Number(t) || 0))
        let mayor = 0
        for (let i = 0; i < marcadores.length; ++i)
            mayor = Math.max(mayor, Number(marcadores[i].id) || 0)
        marcadores = marcadores.concat([{ id: mayor + 1, t: a,
                                          nombre: nombre || "Marcador" }])
            .sort(function (x, y) { return x.t - y.t })
        persistir()
        return mayor + 1
    }

    function quitarMarcador(id) {
        marcadores = marcadores.filter(function (m) { return m.id !== id })
        persistir()
    }

    function quitarCapa(id) {
        capas = capas.filter(function (c) { return c.id !== id })
        seleccionar("", 0)
        persistir()
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
        //  hacia arriba crea una capa nueva sin tener que pedirla aparte. Por
        //  abajo el tope es la 2: la 1 es del vídeo y no admite inquilinos.
        const b = Math.max(primeraBandaLibre,
                           Math.min(cuantasBandas + 1, banda))
        if (bandaBloqueada(b))
            return
        if (b > cuantasBandas)
            bandas = bandas.concat([{ banda: b, nombre: nombreBanda(b) }])
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
        persistir()
    }

    //  Llevar una banda a otro puesto del apilado, con todo lo que lleve.
    //
    //  Se reordena la lista de números de banda y luego se renumera, en vez de
    //  intercambiar de dos en dos: arrastrar la banda 4 hasta la 1 es un solo
    //  gesto, no tres intercambios, y con intercambios el resultado depende del
    //  orden en que se hagan.
    //  Solo se barajan las bandas de capas: la 1 es del vídeo y se queda
    //  abajo. Un vídeo que se pudiera poner encima de todo taparía el resto y
    //  no significaría nada.
    function ponerBandaEn(b, destino) {
        const n = cuantasBandas
        const primera = primeraBandaLibre
        const d = Math.max(primera, Math.min(n, destino))
        if (b < primera || b > n || d === b || bandaBloqueada(b)
                || bandaBloqueada(d))
            return

        const orden = []
        for (let i = primera; i <= n; ++i)
            orden.push(i)
        orden.splice(d - primera, 0, orden.splice(b - primera, 1)[0])

        // `orden[k]` es la banda vieja que pasa a ser la k-ésima de capas.
        const nueva = {}
        for (let k = 0; k < orden.length; ++k)
            nueva[orden[k]] = k + primera

        capas = capas.map(function (c) {
            return Object.assign({}, c, { banda: nueva[bandaDe(c)] })
        })
        bandas = bandas.map(function (x) {
            return Object.assign({}, x, { banda: nueva[Number(x.banda)] })
        })
        persistir()
    }

    // Banda objetivo para el siguiente elemento que se añada desde el panel,
    // y banda que se ha dejado seleccionada cuando está vacía.
    property int bandaObjetivo: 0
    property int bandaSeleccionada: 0

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

    function transcribir() {
        if (rutaVideo.length === 0 || estadoTranscripcion === "transcribiendo")
            return
        estadoTranscripcion = "comprobando"
        procesos.comprobarTranscripcion()
    }

    //  Lo que dice la comprobación: falta algo, o se puede empezar de verdad.
    function recibirComprobacion(d) {
        if (!d) {
            estadoTranscripcion = "fallo"
            return
        }
        comoInstalar = d.como || ""
        if (d.falta && d.falta.length > 0) {
            faltaTranscripcion = d.falta
            estadoTranscripcion = "falta"
            return
        }
        faltaTranscripcion = ""
        estadoTranscripcion = "extrayendo"
        procesos.transcribir(rutaVideo, Idioma.codigo || "es", carpetaAdjunta)
    }

    //  La carpeta que acompaña al plan, donde van los ficheros que hace falta
    //  tener en disco: el texto de los rótulos, el SRT, el grafo.
    readonly property string carpetaAdjunta:
        rutaPlan.length > 5 ? rutaPlan.substring(0, rutaPlan.length - 5) : ""

    //  Cada línea del transcriptor: estados intermedios, el fallo con su
    //  remedio, o el fin con los segmentos.
    function recibirTranscripcion(d) {
        if (d.estado && d.estado !== "fin") {
            estadoTranscripcion = d.estado
            return
        }
        if (d.ok === false) {
            estadoTranscripcion = d.motivo === "sin-whisper"
                || d.motivo === "sin-modelo" ? "falta" : "fallo"
            if (d.como)
                comoInstalar = d.como
            return
        }
        if (d.estado === "fin") {
            transcripcion = d.segmentos || []
            estadoTranscripcion = ""
            persistir()
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

    //  Toda la transcripción, de golpe, como rótulos.
    //
    //  Con estilo de subtítulo —abajo, centrado, con caja detrás— y no con el de
    //  un rótulo suelto, que nace grande y en medio. A partir de ahí son capas
    //  normales: se retocan una a una si hace falta.
    //
    //  Todas a la MISMA banda: son subtítulos, nunca se solapan entre sí, y una
    //  banda por segmento llenaría la línea de tiempo de filas inútiles.
    function quemarTranscripcion() {
        if (transcripcion.length === 0)
            return 0
        const banda = bandaLibre(0, duracionLinea)
        let id = nuevoIdCapa()
        const nuevas = []
        for (let i = 0; i < transcripcion.length; ++i) {
            const seg = transcripcion[i]
            const t = String(seg.texto || "").trim()
            if (t.length === 0)
                continue
            nuevas.push({
                id: id++, tipo: "texto", texto: t, banda: banda,
                t0: seg.t0, t1: Math.max(seg.t0 + 0.4, seg.t1),
                x: 0.5, y: 0.88, tam: 0.045,
                color: "#ffffff", colorFondo: "#000000", fondo: 0.55,
                opacidad: 1.0
            })
        }
        if (nuevas.length === 0)
            return 0
        capas = capas.concat(nuevas)
        persistir()
        return nuevas.length
    }

    // ── qué está seleccionado ─────────────────────────────────────
    //
    //  Un solo sitio para toda la línea, y no un índice por pista: con varias
    //  pistas «el elegido» tiene que decir también de qué es.
    property string tipoSel: ""             // "" · clip · momento
    property int idSel: 0
    property bool recortandoCapa: false
    //  Si se está pinchando el recorrido de la capa sobre el vídeo.
    property bool trazandoRuta: false

    function seleccionar(tipo, id) {
        if (tipo === "capa") {
            for (let i = 0; i < capas.length; ++i)
                if (capas[i].id === id) {
                    bandaSeleccionada = bandaDe(capas[i])
                    break
                }
        }
        // Si el usuario abandona el panel y selecciona otra cosa, no debe
        // quedarse una preparación pendiente para la siguiente capa.
        if (tipo !== "")
            bandaObjetivo = 0
        if (tipo !== "capa")
            recortandoCapa = false
        //  Cambiar de selección corta el trazado: pinchar puntos sobre otra
        //  capa de la que uno cree es de las peores sorpresas posibles.
        if (tipo !== "capa" || id !== idSel)
            trazandoRuta = false
        tipoSel = tipo
        idSel = id
    }

    function seleccionarBanda(b) {
        const n = Number(b)
        if (n < primeraBandaLibre || n > cuantasBandas)
            return
        if (infoBanda(n) === null)
            bandas = bandas.concat([{ banda: n, nombre: nombreBanda(n) }])
        bandaSeleccionada = n
        bandaObjetivo = n
        recortandoCapa = false
        tipoSel = ""
        idSel = 0
        persistir()
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

    function alternarRecorte() {
        if (!capaSel || capaSel.tipo !== "video") {
            recortandoCapa = false
            return
        }
        recortandoCapa = !recortandoCapa
    }

    function fijarRecorteFuente(id, rect) {
        if (!rect || rect.length !== 4)
            return
        const x = Math.max(0, Math.min(0.99, Number(rect[0]) || 0))
        const y = Math.max(0, Math.min(0.99, Number(rect[1]) || 0))
        const w = Math.max(0.01, Math.min(1 - x, Number(rect[2]) || 1))
        const h = Math.max(0.01, Math.min(1 - y, Number(rect[3]) || 1))
        const base = capaSel && capaSel.id === id && capaSel.recorteFuente
            && capaSel.recorteFuente.length === 4
            ? capaSel.recorteFuente : [0, 0, 1, 1]
        fijarCapa(id, { recorteFuente: [base[0] + x * base[2],
                                         base[1] + y * base[3],
                                         w * base[2], h * base[3]] })
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
    //  La transición de los cortes: "" es corte seco; encadenado, deslizar o
    //  barrido la ponen en TODOS los cortes, que es una decisión del montaje
    //  como los fundidos. La cola que necesita la entrega el trozo anterior
    //  —material que ya existía— y la línea no se mueve un fotograma.
    property string transicionTipo: ""
    property real transicionDur: 0.5
    property string colorClics: "#ffd60a"

    //  Las pistas de audio del vídeo, con su volumen y su silencio.
    //  [{ i, titulo, volumen, mudo }]
    property var pistasAudio: []

    //  Cuánto suena cada pista: pico y media en dB, medidos en segundo plano
    //  al abrir el plan. Para saber si el micro satura ANTES del render.
    //  {0: {pico, media}, …} por índice de pista.
    property var nivelesPistas: ({})

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
    signal miniaturaGuardada(string ruta)
    signal fallo(string motivo)

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
        procesos.abrir(video, rastro, argsCamara())
    }

    function proponer(video, rastro) {
        if (!video || video.length === 0 || !rastro || rastro.length === 0)
            return
        preparar(video)
        procesos.proponer(rastro, video, zoomNivel, argsCamara())
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
        marcadores = []
        posicionEditor = 0
        progreso = 0
        bandas = []
        bandaObjetivo = 0
        bandaSeleccionada = 0
    }

    function recibirPlan(d) {
        anchoVideo = d.w || 1920
        altoVideo = d.h || 1080
        fuentes = d.fuentes || []
        clips = d.clips || []
        capas = d.capas || []
        bandas = d.bandas || []
        bandaObjetivo = 0
        bandaSeleccionada = 0
        transcripcion = d.transcripcion || []
        clicsActivos = !!(d.clics && d.clics.activo)
        fundidoEntrada = (d.fundidos && d.fundidos.entrada) || 0
        fundidoSalida = (d.fundidos && d.fundidos.salida) || 0
        fundidoEntre = (d.fundidos && d.fundidos.entre) || 0
        transicionTipo = (d.transicion && d.transicion.tipo) || ""
        transicionDur = (d.transicion && d.transicion.dur) || 0.5
        colorClics = (d.clics && d.clics.color) || "#ffd60a"
        estadoTranscripcion = ""
        pistasAudio = (d.fuentes && d.fuentes.length > 0
                       ? d.fuentes[0].pistas : d.audio) || []
        momentos = d.momentos || []
        marcadores = d.marcadores || []
        //  El editor se abre SIEMPRE, haya momentos o no.
        //
        //  Antes solo se abría si el rastro del cursor había propuesto alguno,
        //  así que una grabación sin clics —enseñar algo sin tocar nada, que es
        //  media razón para grabar— no se podía ni abrir. El zoom es una cosa
        //  que se le hace a un vídeo, no el motivo de que exista el editor.
        estado = "editando"
        iniciarHistorial()
        procesos.recalcularCamara()
        nivelesPistas = {}
        procesos.medirNiveles(rutaVideo)
        planListo()
    }

    // ── quién habla con python ────────────────────────────────────
    //
    //  Todos los procesos viven en EditorProcesos.qml: aquí solo queda decidir
    //  qué hacer con lo que contestan, que es exactamente lo que un estado
    //  tiene que decidir. Este bloque es el mapa completo de esa conversación.
    EditorProcesos {
        id: procesos
        rutaPlan: editor.rutaPlan

        onPlanRecibido: function (d) { editor.recibirPlan(d) }

        onAbrirFallo: function (motivo) {
            editor.estado = ""
            editor.fallo(motivo)
        }

        //  Sin rastro no hay zoom que proponer, pero sí vídeo que editar: se
        //  abre igual, que para eso está.
        onProponerFallo: editor.abrir(editor.rutaVideo, "")

        //  El plan lo ha cambiado python, así que hay que releerlo: lo que hay
        //  en memoria se ha quedado viejo.
        onCongelado: editor.abrir(editor.rutaVideo, "")
        onCongelarFallo: function (motivo) { editor.fallo(motivo) }

        onSilenciosListos: function (tramos) { editor.aplicarSilencios(tramos) }
        onSilenciosFallo: editor.estadoSilencios = "fallo"

        onMedido: function (d) { editor.recibirMedida(d) }

        onNivelesListos: function (d) {
            const n = {}
            const lista = d.pistas || []
            for (let i = 0; i < lista.length; ++i)
                n[lista[i].i] = lista[i]
            editor.nivelesPistas = n
        }

        onMiniaturaLista: function (d) {
            if (!d || !d.ok) {
                editor.fallo(d && d.motivo ? d.motivo : "miniatura")
                return
            }
            editor.miniaturaGuardada(d.ruta)
        }

        onTranscripcionComprobada: function (d) { editor.recibirComprobacion(d) }
        onTranscripcionLinea: function (d) { editor.recibirTranscripcion(d) }

        onCamaraLista: function (d) {
            editor.camara = d.camara || []
            editor.clics = d.clics || []
            editor.anchoVideo = d.w || editor.anchoVideo
            editor.altoVideo = d.h || editor.altoVideo
            if (d.fuentes && d.fuentes.length > 0)
                editor.fuentes = d.fuentes
            if (d.audio && editor.pistasAudio.length === 0)
                editor.pistasAudio = d.audio
        }

        onRenderProgreso: function (progreso) { editor.progreso = progreso }

        onRenderFin: function (ruta) {
            editor.estado = ""
            editor.rutaRenderizada = ruta
            editor.renderListo(ruta)
        }

        onRenderFallo: function (motivo) {
            //  Un render descartado a medias puede seguir muriéndose por
            //  detrás; su despedida ya no le importa a nadie.
            if (editor.estado !== "renderizando")
                return
            editor.estado = ""
            editor.fallo(motivo)
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
    function persistir() {
        historializador.restart()
        persistidor.restart()
    }

    Timer {
        id: historializador
        interval: 260
        onTriggered: editor.registrarHistorial()
    }

    Timer {
        id: persistidor
        interval: 200
        onTriggered: {
            // Si el anterior sigue escribiendo, se espera: dos procesos sobre
            // el mismo fichero acaban con uno pisando al otro.
            if (procesos.escribiendo)
                restart()
            else
                editor.guardarPlan()
        }
    }

    //  Aquí se arma QUÉ se guarda; el cómo —el parcheo del JSON en disco— es
    //  cosa de los procesos. Escrito el plan, la trayectoria se rehace sola.
    function guardarPlan() {
        if (rutaPlan.length === 0)
            return
        procesos.escribirPlan(
            JSON.stringify({ momentos: momentos, pistas: pistasAudio,
                             clips: clips, capas: capas, bandas: bandas,
                             transcripcion: transcripcion,
                             marcadores: marcadores,
                             clics: { activo: clicsActivos,
                                      color: colorClics },
                             fundidos: { entrada: fundidoEntrada,
                                         salida: fundidoSalida,
                                         entre: fundidoEntre },
                             transicion: { tipo: transicionTipo,
                                           dur: transicionDur } }))
    }

    // ── renderizar ────────────────────────────────────────────────
    //  En qué formato sale. Se elige justo antes de renderizar y no en Ajustes:
    //  el mismo vídeo se saca en mp4 para archivar y en gif para pegarlo en una
    //  incidencia, y eso no es una preferencia, es una decisión de cada vez.
    property string formatoSalida: "mp4"      // mp4 · webm · gif
    //  Salida 9:16 para Shorts: recorte centrado —que sigue a la cámara del
    //  zoom por construcción— y a 1080×1920. Decisión de cada render, como
    //  el formato.
    property bool salidaVertical: false

    function renderizar() {
        if (rutaPlan.length === 0)
            return
        rutaRenderizada = rutaVideo.replace(/\.[^./]+$/, "")
                          + (salidaVertical ? "-shorts." : "-k4.")
                          + formatoSalida
        progreso = 0
        estado = "renderizando"
        procesos.renderizar(rutaRenderizada, codec, formatoSalida,
                            Settings.editorSonoridad, salidaVertical)
    }

    //  El fotograma bajo el cabezal, a un PNG a resolución completa y con
    //  todo puesto: es el mismo grafo del render. Para la miniatura del vídeo.
    function miniatura(t) {
        if (rutaPlan.length === 0)
            return
        procesos.miniatura(t)
    }

    //  Los capítulos de YouTube, desde los marcadores: «00:00 Intro» y una
    //  línea por marcador, listos para pegar en la descripción. YouTube exige
    //  que el primero sea 00:00: si el primer marcador no lo es, se antepone.
    function capitulosYoutube() {
        if (marcadores.length === 0)
            return ""
        function sello(t) {
            //  Al segundo de ABAJO: un capítulo que empieza en el 3,5 tiene
            //  que llevar al 3, no al 4 — mejor llegar un pelo antes.
            const s = Math.max(0, Math.floor(Number(t) || 0))
            const h = Math.floor(s / 3600)
            const m = Math.floor(s / 60) % 60
            const seg = s % 60
            const mm = (h > 0 && m < 10 ? "0" : "") + m
            const ss = (seg < 10 ? "0" : "") + seg
            return (h > 0 ? h + ":" : "") + mm + ":" + ss
        }
        const piezas = []
        if (Number(marcadores[0].t) > 2)
            piezas.push("00:00 " + Idioma.t("Inicio"))
        for (let i = 0; i < marcadores.length; ++i)
            piezas.push(sello(marcadores[i].t) + " "
                        + (marcadores[i].nombre || Idioma.t("Capítulo")))
        return piezas.join("\n")
    }

    function copiarCapitulos() {
        const texto = capitulosYoutube()
        if (texto.length > 0)
            Quickshell.execDetached(["wl-copy", texto])
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
