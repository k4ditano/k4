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
                     //  Si el trozo se quedó mudo al separarle el audio. Sin
                     //  esto la previa no se enteraba: seguía sacando el sonido
                     //  del vídeo —la Mezcla— mientras las capas separadas
                     //  sonaban ADEMÁS, así que bajarle el volumen a una no se
                     //  notaba. El render sí lo respetaba; el que mentía era el
                     //  reproductor.
                     mudo: !!c.mudo,
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

    //  Cambiar campos de un trozo. Lo que ya hacía `fijarCapa` para las capas.
    function fijarClip(id, campos) {
        clips = clips.map(function (c) {
            return c.id === id ? Object.assign({}, c, campos) : c
        })
        persistir()
    }

    //  El fundido de un trozo por su lado, en segundos.
    //
    //  Los fundidos eran de la LÍNEA entera: desvanecías el montaje al principio
    //  y al final y nada más. Desvanecer UN trozo —que es lo que se pide casi
    //  siempre— no se podía ni decir. Ahora cada uno lleva el suyo y se arrastra
    //  desde la esquina del bloque, como en cualquier editor.
    //
    //  Sin el campo manda el ajuste global, así que un montaje de antes funde
    //  exactamente igual que fundía.
    function fundidoDe(clip, entrando) {
        if (!clip)
            return 0
        const v = entrando ? clip.fundeEntra : clip.fundeSale
        return v !== undefined ? Math.max(0, v) : 0
    }

    function fijarFundido(id, entrando, segundos) {
        const i = indiceDeClip(id)
        if (i < 0)
            return
        const c = clips[i]
        //  No más de la mitad del trozo por lado: dos fundidos que se cruzan
        //  dejan el trozo entero en negro, y eso no es un fundido, es un
        //  agujero. Es el mismo reparto que ya hace python al renderizar.
        const dur = Math.max(0.05, (c.hasta - c.desde) / velocidadDe(c))
        const v = Math.max(0, Math.min(dur / 2, Number(segundos) || 0))
        const campos = {}
        campos[entrando ? "fundeEntra" : "fundeSale"] = Math.round(v * 100) / 100
        fijarClip(id, campos)
    }

    //  Partir por el cabezal LO QUE TOQUE.
    //
    //  `S` cortaba siempre la pista de vídeo, eligieras lo que eligieras. Con
    //  una música o un rótulo seleccionado eso no es lo que uno pide: partías el
    //  vídeo por debajo y la capa seguía entera cruzando el corte, así que había
    //  que estirarla a mano y crear otra igual al otro lado.
    //
    //  Con capas elegidas se parten ESAS —todas las que el cabezal cruce, que
    //  con selección múltiple es lo que se espera— y el vídeo se queda quieto.
    //  Sin nada elegido, o con un trozo, sigue partiendo el vídeo como siempre.
    function cortarEnCabezal(t) {
        const todo = todoLoElegido
        const capasElegidas = todo.filter(function (s) {
            return s.tipo === "capa"
        })
        if (capasElegidas.length === 0)
            return cortar(t)

        let alguna = false
        for (let i = 0; i < capasElegidas.length; ++i)
            if (partirCapa(capasElegidas[i].id, t))
                alguna = true
        return alguna
    }

    //  Partir una capa en dos por un instante de la línea.
    //
    //  Lo que hay que repartir, y no solo los tiempos:
    //
    //  - El RECORTE. Una capa de audio o de vídeo mira un tramo de su fichero;
    //    la mitad de la derecha tiene que empezar por donde iba, no por el
    //    principio del fichero. Sin esto la segunda mitad repetiría el mismo
    //    audio en vez de continuarlo, que es un fallo que suena rarísimo y
    //    cuesta ver.
    //  - Los FOTOGRAMAS CLAVE, que van en tiempo de línea: cada uno se queda del
    //    lado que le toca. Los que caen justo en el corte van al primero.
    function partirCapa(id, t) {
        const c = capaPorId(id)
        if (!c || capaBloqueada(c))
            return false
        //  Cortar a menos de una décima de un borde deja un trozo que no se ve
        //  ni se puede agarrar: eso no es partir, es ensuciar.
        if (t <= c.t0 + 0.1 || t >= c.t1 - 0.1)
            return false

        const dentro = t - c.t0
        const claves = c.keyframes || []

        const izq = Object.assign({}, c, {
            t1: t,
            keyframes: claves.filter(function (k) { return k.t <= t })
        })
        const der = Object.assign({}, c, {
            id: nuevoIdCapa(),
            t0: t,
            keyframes: claves.filter(function (k) { return k.t > t })
        })
        if (c.recorte && c.recorte.length === 2) {
            //  El recorte va en tiempo de FICHERO, así que el punto de corte se
            //  traslada con la velocidad de la capa si la tuviera.
            const v = Number(c.velocidad) > 0 ? Number(c.velocidad) : 1
            const corteFuente = c.recorte[0] + dentro * v
            izq.recorte = [c.recorte[0], corteFuente]
            der.recorte = [corteFuente, c.recorte[1]]
        }

        capas = capas.map(function (x) {
            return x.id === id ? izq : x
        }).concat([der])
        persistir()
        seleccionar("capa", der.id)
        return true
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

    // ── cómo se llama el montaje ──────────────────────────────────
    //
    //  El nombre ES el del fichero, no una etiqueta guardada aparte. Así lo
    //  encuentras por su nombre en el buscador, que es para lo que sirve
    //  ponerle uno; una etiqueta escondida dentro del plan se vería en la
    //  cabecera y en ningún otro sitio.
    //
    //  De fábrica el plan se llama como el vídeo, así que hasta que le pongas
    //  uno esto enseña el nombre de la grabación. No es un caso especial: es
    //  literalmente cómo se llama el fichero.
    readonly property string nombreProyecto: {
        if (rutaPlan.length === 0)
            return ""
        const hoja = rutaPlan.split("/").pop()
        return hoja.endsWith(".k4v") ? hoja.slice(0, -4) : hoja
    }

    //  Uno cada vez.
    //
    //  Confirmar salía por dos puertas —perder el foco y pulsar el ✓— y con el
    //  botón se disparan LAS DOS: al pulsarlo el campo pierde el foco primero.
    //  La primera renombraba bien; la segunda llegaba con el nombre todavía sin
    //  actualizar —python no había contestado— y pedía renombrar un fichero que
    //  ya no existía. De ahí el «no se pudo editar» apareciendo después de que
    //  el nombre SÍ hubiera cambiado.
    property bool renombrando: false

    function renombrarProyecto(nombre) {
        const limpio = String(nombre || "").trim()
        if (renombrando || limpio.length === 0 || limpio === nombreProyecto)
            return
        renombrando = true
        procesos.renombrar(limpio)
    }

    //  Hasta dónde se puede subir un volumen.
    //
    //  Era 2 y se quedaba corto: una grabación con el micro lejos necesita más
    //  del doble para oírse, y ponerle un techo por si distorsiona es decidir
    //  por quien está delante. Que distorsione si quiere; el número se ve
    //  escrito y lo elige él.
    //
    //  Lo que NO puede hacer es oírse en la previa por encima del 100 %:
    //  `AudioOutput.volume` de Qt está limitado a 1 y no hay forma de pasar de
    //  ahí. En el render sí —el `volume=` de ffmpeg no tiene tope—, así que por
    //  encima de 100 % el panel lo dice en vez de fingir que se oye.
    readonly property real volumenMaximo: 4

    //  Cómo se llama la pista de la que sale una capa: «Sistema», «Micrófono».
    //
    //  Se resuelve al mirarlo y no se guarda en el plan: el nombre lo trae el
    //  fichero, y tener una copia dentro del plan es garantizar que un día
    //  discrepen. Vale también para los planes de antes, que no lo llevaban.
    //  Devuelve "" para una capa de audio suelta —una canción— que no sale de
    //  ninguna pista del vídeo.
    function nombreDePista(capa) {
        if (!capa || capa.tipo !== "audio" || capa.pista === undefined)
            return ""
        for (let i = 0; i < pistasAudio.length; ++i)
            if (pistasAudio[i].i === capa.pista && pistasAudio[i].titulo)
                return pistasAudio[i].titulo
        return ""
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

        //  Una capa POR PISTA, no una sola del fichero.
        //
        //  Sistema y micro se graban separados justamente para poder
        //  equilibrarlos después; sacarlos en una capa única los volvía a
        //  juntar, y encima por la puerta de atrás: una capa que no dice de
        //  qué pista es se mapeaba `[N:a]`, y eso ffmpeg lo resuelve a la
        //  PRIMERA del fichero — la Mezcla, que es la suma de las dos. De ahí
        //  que silenciar una pista no callara nada.
        //
        //  Un vídeo de fuera —una pista y sin nombre— sigue dando una capa y
        //  una sola: es el caso de la lista vacía.
        const cuales = pistasAudio.length > 0 ? pistasAudio : [{ i: 0 }]

        let primera = 0
        for (let n = 0; n < cuales.length; ++n) {
            const nueva = {
                id: nuevoIdCapa(),
                tipo: "audio",
                ruta: rutaDe(c.fuente),
                //  De qué pista sale. Sin esto se lleva la mezcla.
                pista: cuales[n].i,
                //  Dónde se oye en la línea, y qué parte del fichero se oye.
                t0: tr.inicio,
                t1: tr.fin,
                recorte: [c.desde, c.hasta],
                volumen: 1.0,
                dur: Math.max(0.1, c.hasta - c.desde),
                banda: bandaLibre(tr.inicio, tr.fin)
            }
            //  Se añade en el momento y no todas al final: `nuevoIdCapa` y
            //  `bandaLibre` miran la lista, y con dos a la vez saldrían con el
            //  mismo id y apiladas en la misma banda.
            capas = capas.concat([nueva])
            if (n === 0)
                primera = nueva.id
        }

        clips = clips.map(function (x, j) {
            return j === i ? Object.assign({}, x, { mudo: true }) : x
        })
        persistir()
        seleccionar("capa", primera)
        return primera
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

    function crearAudio(ruta, t0, extra) { medirYCrear(ruta, t0, "audio", extra) }

    //  Un vídeo dentro del vídeo.
    //
    //  Se mide igual que el audio y por lo mismo, más una razón extra: hace falta
    //  su tamaño para dibujar el recuadro con la proporción que va a tener al
    //  renderizar.
    function crearPip(ruta, t0) { medirYCrear(ruta, t0, "video") }

    //  `extra` son campos que la capa nueva lleva ya puestos, y que se ponen
    //  DESPUÉS de los de serie para que puedan corregirlos. Lo pide la
    //  locución: nace con un recorte de cabeza —lo que tardó el vídeo en
    //  arrancar tras abrirse el micro— y eso cambia también su duración y su
    //  final, que no se pueden calcular aquí porque dependen de la toma.
    property var extraPendiente: null

    function medirYCrear(ruta, t0, tipo, extra) {
        if (!ruta || ruta.length === 0)
            return
        audioPendiente = ruta
        audioPendienteEn = Math.max(0, Math.min(t0, duracionLinea))
        tipoPendiente = tipo
        extraPendiente = extra || null
        procesos.medir(ruta)
    }

    //  Lo que contesta el medidor: la medida que faltaba para crear la capa
    //  que quedó pendiente, o un fallo que la cancela.
    function recibirMedida(d) {
        if (!d || !d.ok || audioPendiente.length === 0) {
            fallo(d && d.motivo ? d.motivo : "no-se-puede-medir",
                  (d && d.detalle) || "")
            audioPendiente = ""
            extraPendiente = null
            return
        }
        if (tipoPendiente === "video" && !d.w) {
            // Sin flujo de vídeo no es un vídeo, diga lo que diga el nombre.
            fallo("sin-video")
            audioPendiente = ""
            extraPendiente = null
            return
        }
        anadirMedio(audioPendiente, audioPendienteEn, d, tipoPendiente,
                    extraPendiente)
        audioPendiente = ""
        extraPendiente = null
    }

    function anadirMedio(ruta, t0, medida, tipo, extra) {
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
            //  Y suena, si tiene con qué. Un vídeo que metes en el montaje se
            //  espera que traiga su sonido; que entrase mudo obligaba a añadir
            //  el mismo fichero otra vez como capa de audio y a cuadrarlo a
            //  mano. Los planes viejos no llevan el campo y siguen mudos, que
            //  cambiarle el sonido a un montaje hecho sería peor.
            nueva.puedeSonar = !!medida.audio
            nueva.sonido = !!medida.audio
            nueva.volumen = 1.0
        }
        //  `recorteDesde`: cuánto se le quita al PRINCIPIO del fichero. No es
        //  un campo de la capa —no se copia— sino una petición, porque para
        //  resolverla hace falta la duración, y la duración solo se sabe aquí.
        //  Recortar la cabeza cambia además lo que dura y dónde acaba, y las
        //  tres cosas tienen que salir de la misma cuenta o el bloque de la
        //  línea de tiempo dejaría de medir lo que se oye.
        if (extra && extra.recorteDesde > 0 && tipo === "audio") {
            const quita = Math.min(extra.recorteDesde,
                                   Math.max(0, medida.dur - 0.1))
            nueva.recorte = [quita, medida.dur]
            nueva.dur = medida.dur - quita
            nueva.t1 = Math.min(duracionLinea, a + nueva.dur)
        }
        //  Y al final los de quien la pidió, que mandan sobre los de serie.
        if (extra)
            for (const k in extra)
                if (k !== "recorteDesde")
                    nueva[k] = extra[k]
        capas = capas.concat([nueva])
        persistir()
        seleccionar("capa", nueva.id)
    }

    // ── la locución ───────────────────────────────────────────────
    //
    //  Ver el vídeo y hablarle encima. Al parar, lo dicho entra como una capa
    //  de audio más —se coloca, se recorta, se le baja el volumen— porque una
    //  voz pegada al vídeo sería irreversible, que es lo mismo que ya se evitó
    //  al grabar el micro aparte del sistema.
    //
    //  **El orden es al revés de lo que parece, y la razón está medida.**
    //  Primero se abre el micro y solo después se manda reproducir. Al revés,
    //  el vídeo llevaría un rato andando antes de que nadie escuchara, y ese
    //  rato no se recupera luego.
    //
    //  Pero «el proceso ha arrancado» no es «el micro está capturando»: entre
    //  las dos cosas ffmpeg abre PulseAudio, y eso son un puñado largo de
    //  milisegundos (medido aquí: 160–250 ms de arranque más cierre). Fiándose
    //  del arranque del proceso, la voz caía como un décimo de segundo
    //  ADELANTADA sobre lo que estabas mirando.
    //
    //  La incógnita se quita preguntándosela a quien la sabe: ffmpeg informa
    //  por `-progress` de cuánto audio lleva metido, y es SU primer parte el
    //  que dispara la reproducción. Así el trozo de fichero que es «de antes de
    //  que el vídeo se moviera» no se estima, viene dicho, y es lo que se le
    //  recorta a la cabeza de la toma. Ver `grabarVoz` en EditorProcesos.
    //
    //  Encima de eso se mide lo poco que aún tarde el vídeo en echar a andar
    //  (medido: 13 ms, y hacia el otro lado, así que en la práctica cero). No
    //  sobra: con un fichero que tarde en cargar deja de ser cero, y entonces
    //  es lo único que salva la sincronía. Es la misma honradez que
    //  `desfaseCamara` en Captura, pero aquí sí se pudo cerrar del todo.
    property string estadoVoz: ""            // "" | "abriendo" | "grabando" | "cerrando"
    readonly property bool grabandoVoz: estadoVoz === "grabando"
    property real vozDesde: 0                // el segundo de la LÍNEA donde entra
    property string rutaVoz: ""
    property real vozMicroEn: 0              // cuándo avisó el micro
    property real vozVideoEn: 0              // cuándo echó a andar el vídeo
    property real vozCapturado: 0            // lo que ya llevaba grabado al avisar

    //  La vista es quien tiene el reproductor: aquí se pide y allí se obedece.
    signal vozPreparada()
    signal vozParada()

    function grabarVozAlternar(t) {
        if (estadoVoz === "") grabarVoz(t)
        else pararVoz()
    }

    function grabarVoz(t) {
        if (estadoVoz !== "")
            return
        if (rutaPlan.length === 0) {
            fallo("sin-proyecto")
            return
        }
        estadoVoz = "abriendo"
        vozDesde = Math.max(0, Math.min(Number(t) || 0, duracionLinea))
        vozMicroEn = 0
        vozVideoEn = 0
        vozCapturado = 0
        esperaMicro.restart()
        rutaVoz = carpetaAdjunta + "/" + nombreLibreDeVoz()
        //  Qué micro hay se pregunta AHORA y no se da por sabido: es el mismo
        //  motivo por el que la grabación de pantalla lo pregunta antes de cada
        //  toma. Un nombre de dispositivo viejo no da una locución muda, da una
        //  locución que no existe.
        Captura.refrescarAudios(function () {
            if (editor.estadoVoz !== "abriendo")
                return
            procesos.grabarVoz(editor.rutaVoz, Captura.microElegido,
                               editor.carpetaAdjunta)
        })
    }

    function pararVoz() {
        if (estadoVoz === "" || estadoVoz === "cerrando")
            return
        //  Si aún no había abierto el micro no hay nada que cerrar: cancelar es
        //  simplemente no empezar.
        if (estadoVoz === "abriendo") {
            estadoVoz = ""
            rutaVoz = ""
            return
        }
        estadoVoz = "cerrando"
        vozParada()
        procesos.pararVoz()
    }

    //  Tirar la toma en vez de recogerla.
    //
    //  Se usa al abrir otro vídeo: el fichero de la voz vive en la carpeta del
    //  proyecto que se está dejando, y recogerla ahora la pegaría al montaje
    //  equivocado. Se limpia el estado ANTES de pedir el cierre para que
    //  `recibirVozCerrada` la encuentre ya sin dueño y no cree nada.
    function cancelarVoz() {
        if (estadoVoz === "")
            return
        estadoVoz = ""
        rutaVoz = ""
        vozParada()
        procesos.pararVoz()
    }

    //  Lo llama la vista cuando el vídeo se mueve DE VERDAD, no cuando se le
    //  pide que se mueva: son cosas distintas y la diferencia es justo lo que
    //  hay que descontar.
    //
    //  Dos trampas, las dos medidas mirando el rastro y no supuestas:
    //
    //  - **El salto al punto de partida TAMBIÉN mueve el cabezal.** `irA(2)` lo
    //    pone en 2 y avisa, y eso no es «ya está andando»: es haber llegado a la
    //    casilla de salida. Contándolo, el hueco medido salía siempre cero y la
    //    corrección no corregía nada. Lo que vale es el primer avance que lo
    //    PASA.
    //  - **El reproductor avisa a saltos**, no en el instante: cuando nos
    //    enteramos, el vídeo ya lleva un pedazo andando. Ese pedazo se resta,
    //    que para eso se sabe cuánto es.
    function vozEmpezoASonar(donde) {
        if (estadoVoz !== "grabando" || vozVideoEn > 0)
            return
        const avance = Number(donde) - vozDesde
        if (!(avance > 0))
            return
        vozVideoEn = Date.now() - avance * 1000
    }

    //  Un nombre que no pise otro. Se miran las capas que ya hay y no el disco:
    //  una toma tirada deja su fichero, y reusar su nombre sería borrar algo
    //  que a lo mejor se quería recuperar.
    function nombreLibreDeVoz() {
        let n = 0
        for (let i = 0; i < capas.length; ++i) {
            const m = String(capas[i].ruta || "").match(/locucion-(\d+)\.m4a$/)
            if (m)
                n = Math.max(n, parseInt(m[1], 10))
        }
        return "locucion-" + (n + 1) + ".m4a"
    }

    function recibirVozAbierta(capturado) {
        if (estadoVoz !== "abriendo")
            return
        esperaMicro.stop()
        vozCapturado = Math.max(0, Number(capturado) || 0)
        vozMicroEn = Date.now()
        estadoVoz = "grabando"
        vozPreparada()
    }

    //  Si el micro no da señales de vida, no se puede dejar al usuario delante
    //  de un vídeo parado esperando a nada. Cinco segundos es de sobra: el
    //  primer parte de ffmpeg llega en menos de medio.
    Timer {
        id: esperaMicro
        interval: 5000
        onTriggered: {
            if (editor.estadoVoz !== "abriendo")
                return
            editor.cancelarVoz()
            editor.fallo("sin-microfono")
        }
    }

    function recibirVozCerrada(codigo, queja) {
        const ruta = rutaVoz
        const t0 = vozDesde
        //  Qué parte de la cabeza del fichero es de ANTES de que el vídeo se
        //  moviera, y por tanto sobra. Son dos sumandos y los dos están medidos:
        //
        //  - lo que ffmpeg ya llevaba capturado cuando avisó (lo dice él), y
        //  - lo que aún tardó el vídeo en arrancar después de eso.
        //
        //  Lo segundo sale casi siempre cero —el play se manda en el mismo
        //  latido en que llega el aviso; medido: 13 ms, y hacia el otro lado—,
        //  pero no se da por hecho: con un fichero que tarde en cargar deja de
        //  serlo, y entonces es lo único que salva la sincronía.
        const hueco = (vozMicroEn > 0 ? vozCapturado : 0)
            + (vozVideoEn > 0 && vozMicroEn > 0
                ? Math.max(0, (vozVideoEn - vozMicroEn) / 1000) : 0)
        const estabaGrabando = estadoVoz !== ""
        estadoVoz = ""
        rutaVoz = ""
        if (!estabaGrabando || ruta.length === 0)
            return
        //  ffmpeg sale con 255 cuando lo paras con SIGINT, y eso aquí es el
        //  final normal de una toma, no un fallo.
        if (codigo !== 0 && codigo !== 255) {
            fallo(queja && queja.length > 0 ? queja : "no-se-pudo-grabar-la-voz")
            return
        }
        crearAudio(ruta, t0, { recorteDesde: hueco })
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

        //  Una capa de audio se llamaba como su FICHERO, y eso no distingue
        //  nada donde más falta hace: «separar el audio» saca dos capas del
        //  mismo vídeo —el sistema y el micro— y las dos salían con el nombre
        //  del mp4, idénticas. Elegir una así es elegir a ciegas, que es la
        //  queja de la que sale esto.
        //
        //  Lo que las distingue es de qué PISTA salen, y eso el plan lo sabe:
        //  la fuente lleva el título que puso quien grabó.
        if (c.tipo === "audio") {
            const t = tituloDePista(c)
            if (t.length > 0)
                return t
            //  Una locución se llama por lo que es y no `locucion-2.m4a`.
            const loc = String(c.ruta || "").match(/locucion-(\d+)\.m4a$/)
            if (loc)
                return Idioma.t("Locución") + " " + loc[1]
            //  Y lo demás, el fichero sin la extensión: en un chip, «.mp3» no
            //  aporta y quita sitio al nombre.
            const f = String(c.ruta || "").split("/").pop()
            return f.replace(/\.[^.]+$/, "")
        }
        return String(c.ruta || "").split("/").pop()
    }

    //  El título de la pista de la que sale una capa de audio separada, si lo
    //  lleva. La capa guarda su `ruta` y su `pista`, no de qué fuente vino, así
    //  que la fuente se busca por la ruta.
    function tituloDePista(c) {
        if (!c || c.pista === undefined)
            return ""
        for (let i = 0; i < fuentes.length; ++i) {
            if (fuentes[i].ruta !== c.ruta)
                continue
            const ps = fuentes[i].pistas || []
            for (let j = 0; j < ps.length; ++j)
                if (ps[j].i === c.pista)
                    return String(ps[j].titulo || "").trim()
        }
        return ""
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
        const c = capaPorId(id)
        const antes = c ? c[cual] : null
        const campos = {}
        campos[cual] = tipo && tipo.length > 0
            ? { tipo: tipo,
                dur: Math.max(0.1, Math.min(2, Number(dur) || 0.4)),
                //  La velocidad se conserva al cambiar de efecto: es una
                //  preferencia tuya, no una propiedad del efecto.
                curva: antes && antes.curva ? antes.curva : "recta" }
            : null
        fijarCapa(id, campos)
    }

    //  Cómo reparte el efecto su tiempo: recta, suave o de golpe. La duración
    //  dice cuánto tarda; esto, a qué velocidad va por el camino.
    function fijarCurva(id, cual, curva) {
        const c = capaPorId(id)
        if (!c || !c[cual] || !c[cual].tipo)
            return
        const campos = {}
        campos[cual] = Object.assign({}, c[cual], { curva: curva })
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

    //  Dónde se ha pegado el imán, para poder PINTARLO. -1 si no se ha pegado.
    //
    //  Un imán invisible es adivinar: se te pega o no se te pega y no sabes a
    //  qué. En cualquier editor sale una guía en el punto al que te has
    //  enganchado, y esa línea es la mitad de por qué el imán se siente bien.
    property real imanEn: -1

    function soltarIman() { imanEn = -1 }

    //  A qué se pega el imán.
    //
    //  Antes solo a los bordes de los TROZOS y a los marcadores. Faltaban las
    //  dos cosas a las que más se alinea uno:
    //
    //  - El CABEZAL. Es el punto de referencia de cualquier editor —lo colocas
    //    donde quieres que pase algo y arrastras hasta ahí— y no estaba.
    //  - Los bordes de las otras CAPAS y de los ZOOMS. Encadenar dos rótulos o
    //    hacer que un zoom empiece donde acaba una música era a ojo, y a ojo en
    //    una línea de tiempo comprimida son décimas de error.
    //
    //  `excluirId` es lo que se está arrastrando: sin eso un bloque se pegaría a
    //  sus propios bordes y no habría forma de despegarlo de donde está.
    function ajustarTiempo(v, excluirId) {
        let t = Math.max(0, Math.min(duracionLinea, Number(v) || 0))
        const puntos = [0, duracionLinea, posicionEditor]
        for (let i = 0; i < tramos.length; ++i)
            puntos.push(tramos[i].inicio, tramos[i].fin)
        for (let i = 0; i < marcadores.length; ++i)
            puntos.push(Number(marcadores[i].t) || 0)
        for (let i = 0; i < capas.length; ++i)
            if (capas[i].id !== excluirId)
                puntos.push(capas[i].t0, capas[i].t1)
        for (let i = 0; i < momentos.length; ++i)
            if (momentos[i].id !== excluirId)
                puntos.push(momentos[i].t0, momentos[i].t1)

        //  El radio en SEGUNDOS no puede ser fijo: con la línea muy acercada,
        //  ocho centésimas son medio dedo de pantalla y el imán no te deja
        //  colocar nada; muy alejada, son un pixel y no se pega nunca. Se
        //  reparte entre el acercamiento para que en pantalla mida siempre lo
        //  mismo, unos ocho píxeles.
        const radio = 0.08 / Math.max(1, acercamientoLinea)

        let mejor = t
        let distancia = radio
        for (let i = 0; i < puntos.length; ++i) {
            const d = Math.abs(puntos[i] - t)
            if (d < distancia) {
                distancia = d
                mejor = puntos[i]
            }
        }
        imanEn = mejor !== t ? mejor : -1
        return mejor
    }

    //  A cuántos fotogramas por segundo va esto.
    //
    //  Sale del plan, que lo trae medido del fichero. Hace falta para poder
    //  moverse DE FOTOGRAMA EN FOTOGRAMA: un editor se afina así, y saltar de
    //  segundo en segundo —que es lo que hacían las flechas— es no poder
    //  colocar un corte donde va.
    readonly property real fpsVideo: {
        const f = fuentes.length > 0 ? Number(fuentes[0].fps) : 0
        return f > 0 && f < 1000 ? f : 30
    }

    readonly property real unFotograma: 1 / Math.max(1, fpsVideo)

    //  El instante escrito como lo escribe un editor: `m:ss.ff`.
    //
    //  Con décimas no se puede decir en qué fotograma estás, que es justo lo
    //  que hace falta saber cuando afinas un corte.
    function reloj(t) {
        const seg = Math.max(0, Number(t) || 0)
        const m = Math.floor(seg / 60)
        const s = Math.floor(seg % 60)
        const f = Math.floor((seg - Math.floor(seg)) * fpsVideo)
        return m + ":" + (s < 10 ? "0" : "") + s
                 + "." + (f < 10 ? "0" : "") + f
    }

    //  Cuánto está acercada la línea de tiempo. Lo escribe la vista.
    //
    //  El Editor no pinta nada, pero el radio del imán se mide en píxeles de
    //  pantalla y eso solo se sabe aquí si alguien lo cuenta.
    property real acercamientoLinea: 1

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
        //  Y soltar la selección si era este: desde que un marcador se puede
        //  elegir, borrarlo sin soltarla dejaba `tipoSel` apuntando a un id que
        //  ya no existe, y la siguiente copia habría copiado nada.
        if (tipoSel === "marcador" && idSel === id)
            seleccionar("", 0)
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
    //
    //  Las mismas cuentas que `carpeta_de()` en tools/editar.py, y aquí no
    //  estaban: se quitaban cinco letras SIEMPRE, que era lo correcto cuando el
    //  plan se llamaba `<vídeo>.k4.json` y dejó de serlo al pasar a `.k4v`. Con
    //  el nombre de hoy daba `<víde>` —el nombre del vídeo con una letra
    //  comida— en vez de `<vídeo>.k4`, así que los dos lados discrepaban sobre
    //  dónde vive el SRT y el texto de los rótulos.
    readonly property string carpetaAdjunta:
        rutaPlan.endsWith(".k4v")
            ? rutaPlan.substring(0, rutaPlan.length - 1)
        : rutaPlan.endsWith(".json")
            ? rutaPlan.substring(0, rutaPlan.length - 5)
        : rutaPlan.length > 0 ? rutaPlan + ".k4" : ""

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
    property string tipoSel: ""     // "" · clip · capa · momento · marcador
    property int idSel: 0
    property bool recortandoCapa: false
    //  Si se está pinchando el recorrido de la capa sobre el vídeo.
    property bool trazandoRuta: false

    // ── las ondas de los bloques de audio ─────────────────────────
    //
    //  Un bloque de audio que es un rectángulo de color no dice dónde habla
    //  nadie: para saberlo hay que reproducir y esperar. Con la onda pintada se
    //  ve, y editar deja de ser a ciegas.
    //
    //  Se piden cuando cambian las capas y NO desde el binding que las dibuja:
    //  un binding que lanza procesos se dispara cada vez que se reevalúa, que es
    //  muchas veces por segundo mientras arrastras. Aquí se pide una vez por
    //  fichero y pista, y el resultado se queda.
    property var ondas: ({})
    //  Cuánto dura el fichero de cada onda. No es lo mismo que el `dur` de la
    //  capa: ese es lo que se OYE, y una capa recortada oye un trozo.
    property var ondasDur: ({})
    property var ondasPedidas: ({})

    function claveOnda(capa) {
        if (!capa || !capa.ruta)
            return ""
        if (capa.tipo !== "audio" && !(capa.tipo === "video" && capa.sonido))
            return ""
        return capa.ruta + "|" + (capa.pista !== undefined ? capa.pista : 0)
    }

    //  Lo que dibuja el bloque: un array de picos, o null si aún no está.
    function ondaDe(capa) {
        const c = claveOnda(capa)
        return c.length > 0 && ondas[c] !== undefined ? ondas[c] : null
    }

    function asegurarOndas() {
        for (let i = 0; i < capas.length; ++i) {
            const c = claveOnda(capas[i])
            if (c.length === 0 || ondasPedidas[c])
                continue
            ondasPedidas[c] = true
            procesos.pedirOnda(capas[i].ruta,
                               capas[i].pista !== undefined ? capas[i].pista : 0)
        }
        //  Y la del propio vídeo, que no se dibuja en ningún bloque pero es la
        //  llave por defecto del agachado: sin ella, una música puesta a
        //  agacharse «con el vídeo» no se agacharía en la previa.
        //
        //  La pista 0, que es la Mezcla: es la que suena al reproducir.
        for (let j = 0; j < tramos.length; ++j) {
            const tr = tramos[j]
            if (!tr.ruta || tr.imagen)
                continue
            const k = tr.ruta + "|0"
            if (ondasPedidas[k])
                continue
            ondasPedidas[k] = true
            procesos.pedirOnda(tr.ruta, 0)
        }
    }

    onCapasChanged: { asegurarOndas(); asegurarLimpias() }
    onClipsChanged: asegurarOndas()

    // ── la escoba, oída y no prometida ────────────────────────────
    //
    //  «Quitar ruido de fondo» solo se notaba al renderizar, y un botón que no
    //  se oye no sirve para decidir: lo que hace falta es escucharlo y ver si
    //  te gusta cómo queda la voz. Qt no sabe filtrar mientras reproduce, así
    //  que se prepara una COPIA ya limpia del audio y la previa reproduce esa.
    //
    //  El render no la usa: sigue aplicando el filtro él sobre el original. Los
    //  dos salen de `FILTRO_ESCOBA`, la misma constante en editar.py, así que
    //  no pueden separarse.
    //
    //  Se guarda por (fichero, pista) y no por capa: dos capas del mismo sitio
    //  —el mismo micro separado en dos trozos— comparten la copia y el trabajo
    //  se hace una vez.
    property var limpias: ({})
    property var limpiasPedidas: ({})

    //  La ganancia que hay que meter EN EL FICHERO, o 1 si no hace falta.
    //
    //  Qt recorta `AudioOutput.volume` en 1 y por encima no sube nada —medido:
    //  pedirle 3,0 deja la propiedad en 1 y el sonido igual—, así que de 0 a
    //  100 % lo hace Qt en el momento y de ahí para arriba va en la copia. Se
    //  redondea al mismo paso que el deslizador (0,05) para no rehacer el
    //  fichero por diferencias que no existen.
    function gananciaDe(capa) {
        if (!capa || capa.tipo !== "audio")
            return 1
        const v = capa.volumen !== undefined ? capa.volumen : 1
        return v > 1 ? Math.round(v * 20) / 20 : 1
    }

    function necesitaCopia(capa) {
        return !!capa && capa.tipo === "audio"
            && (!!capa.limpia || gananciaDe(capa) > 1)
    }

    //  La clave lleva TODO lo que cambia el fichero: quién es, qué pista, si
    //  lleva escoba y con cuánta ganancia. Si cambia cualquiera de las cuatro,
    //  la copia de antes ya no sirve y se hace otra.
    function claveLimpia(capa) {
        if (!capa || !capa.ruta || capa.tipo !== "audio")
            return ""
        return capa.ruta + "|" + (capa.pista !== undefined ? capa.pista : 0)
             + "|" + (capa.limpia ? "1" : "0")
             + "|" + gananciaDe(capa).toFixed(2)
    }

    //  ¿Es una ruta de fichero, o un protocolo disfrazado de ruta?
    //
    //  Lo que abre un proyecto es lo que diga su JSON, y un `.k4v` te lo pasan
    //  como te pasan un vídeo. Con `http://…` aquí, abrirlo hacía que ffprobe
    //  pidiera esa dirección: un servidor local registró el GET. Esta es la
    //  segunda cerradura —el guion ya rechaza el plan entero al cargarlo, y
    //  ffmpeg va con `-protocol_whitelist file,crypto,data`—, pero el sitio
    //  donde una ruta ajena se convierte en LA ruta del vídeo merece la suya.
    function esRutaLocal(r) {
        const t = String(r || "")
        if (t.length === 0 || /^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(t))
            return false
        return t.split("/")[0].indexOf(":") < 0
    }

    //  El id de una capa acaba dentro de un NOMBRE DE FICHERO, y esa es la
    //  única razón de esta función. El id normal es `capa-3` y no da problemas;
    //  el de un proyecto que te hayan pasado es lo que quiera quien lo escribió,
    //  y con `../../` dentro la copia de la previa salía de la carpeta del
    //  proyecto y caía donde dijera el id — comprobado, el fichero apareció en
    //  /tmp. Aquí sólo pasan letras, cifras, guion y raya baja; lo demás se
    //  vuelve raya. Si no queda nada, el número de la fila, que siempre sirve.
    //
    //  El guion además comprueba que la salida cae dentro de la carpeta
    //  (`--dentro`). Son dos vueltas a la misma llave a propósito: esta compone
    //  bien el nombre, aquélla se niega a escribir si aun así se escapase.
    function nombreSeguro(t, respaldo) {
        const crudo = String(t === undefined || t === null ? "" : t)
        const s = crudo.replace(/[^A-Za-z0-9_-]/g, "-").substring(0, 48)
                       .replace(/-+/g, "-").replace(/^-|-$/g, "")
        if (s === crudo)
            return s || ("c" + respaldo)
        //  Al limpiarlo puede coincidir con otro: `a/b` y `a-b` daban el mismo
        //  nombre, y dos capas distintas compartiendo copia significa oír la
        //  de al lado. Si hubo que tocarlo, se le pega un resumen del id de
        //  verdad, que vuelve a separarlos. Un id normal —`capa-3`— no pasa
        //  por aquí y conserva su nombre de siempre.
        let h = 5381
        for (let i = 0; i < crudo.length; ++i)
            h = ((h * 33) ^ crudo.charCodeAt(i)) >>> 0
        return (s || "c" + respaldo) + "-" + h.toString(36)
    }

    function asegurarLimpias() {
        if (carpetaAdjunta.length === 0)
            return
        for (let i = 0; i < capas.length; ++i) {
            const c = capas[i]
            if (!necesitaCopia(c))
                continue
            const k = claveLimpia(c)
            if (k.length === 0 || limpiasPedidas[k])
                continue
            limpiasPedidas[k] = true
            //  El nombre lleva la ganancia porque el fichero es distinto, y el
            //  guion borra las demás de esta capa al acabar: mover el
            //  deslizador haría una copia por valor y llenaría la carpeta.
            const g = Math.round(gananciaDe(c) * 100)
            const pref = "previa-" + nombreSeguro(c.id, i) + "-"
            procesos.pedirLimpia(k, c.ruta,
                                 c.pista !== undefined ? c.pista : 0,
                                 carpetaAdjunta + "/" + pref + "g" + g + ".flac",
                                 !!c.limpia, gananciaDe(c), pref,
                                 carpetaAdjunta)
        }
    }

    //  Qué fichero tiene que sonar en la previa por esta capa: el limpio si ya
    //  está hecho, y el de siempre mientras no lo esté. Nunca se queda callada
    //  esperando: oyes el original y en un segundo se cambia solo.
    function rutaSonando(capa) {
        if (!capa)
            return ""
        if (!necesitaCopia(capa))
            return capa.ruta
        const k = claveLimpia(capa)
        return limpias[k] ? limpias[k] : capa.ruta
    }

    //  A qué volumen tiene que sonar el reproductor de esta capa.
    //
    //  Si la copia que suena ya lleva la ganancia dentro, aquí va 1: subirlo
    //  otra vez sería aplicarla dos veces. Y mientras la copia se hace todavía
    //  no la lleva, así que se pide lo que Qt sepa dar —hasta 100 %— y al
    //  llegar el fichero el salto lo completa él.
    function volumenSonando(capa) {
        if (!capa)
            return 0
        const v = capa.volumen !== undefined ? capa.volumen : 1
        if (necesitaCopia(capa) && limpias[claveLimpia(capa)]
                && gananciaDe(capa) > 1)
            return 1
        return Math.max(0, Math.min(1, v))
    }

    //  Y por qué pista. La copia limpia lleva UNA sola —la que se pidió— así
    //  que dentro de ella es la 0, no la que era en el original.
    function pistaSonando(capa) {
        if (!capa)
            return 0
        if (necesitaCopia(capa) && limpias[claveLimpia(capa)])
            return 0
        return capa.pista !== undefined ? capa.pista : 0
    }

    //  Para que el botón pueda decir «un momento» en vez de mentir.
    function limpiandoCapa(capa) {
        return necesitaCopia(capa) && !limpias[claveLimpia(capa)]
    }

    // ── el agachado, en la previa ─────────────────────────────────
    //
    //  El compresor del render no existe aquí: la previa son reproductores
    //  sueltos siguiendo el mismo reloj, y no hay forma de que uno OIGA a otro
    //  para agacharse. Pero sí hay las ondas —los picos que ya se calculan para
    //  dibujar los bloques—, así que el nivel de quien manda se LEE en vez de
    //  escucharse, y con él se le baja el volumen a quien obedece.
    //
    //  No es el compresor: es su curva, medida. Y medida **a través del render
    //  de verdad**, no en un banco aparte, que es la diferencia entre parecerse
    //  y mentir: un banco con `sidechaincompress` suelto daba −11,7 dB donde el
    //  render hace −25, porque por el camino el audio pasa por la mezcla, por
    //  las normas de formato y por un detector que mira energía y no picos.
    //  Calibrar contra el resultado final absorbe todo eso de una vez.
    //
    //  La tabla es «pico que se lee en la onda» → «dB que baja el render»:
    //
    //      0,012 →  0 dB     0,025 → −0,3     0,036 →  −1,7
    //      0,061 → −5,1      0,122 → −10,4    0,245 → −15,6
    //      0,426 → −19,9     0,610 → −22,6    0,850 → −25,1
    //
    //  Cada vez que la llave dobla, baja unos 4,5 dB más, que es lo que le toca
    //  a un `ratio=8`. Y por debajo de 0,012 no pasa nada: ahí está el umbral.
    //
    //  La medida lleva CONTROL: el mismo montaje renderizado con el agachado
    //  apagado tiene que dar la misma cifra en las dos ventanas. Sin ese
    //  control, la primera tanda salió no-monótona —la llave se colaba por el
    //  filtro con el que intentaba aislar la música— y me la habría creído.
    //
    //  La misma curva vale con la llave siendo el vídeo o siendo otra capa:
    //  comprobado, las dos dan −25,1 dB con la llave a 0,85.
    //
    //  La previa nunca fue la verdad —lo dice la cabecera de AudioExtra— pero
    //  ahora se le parece, que es de lo que se trata: poder decidir el volumen
    //  de la música oyéndola agacharse en vez de renderizando para enterarte.
    //
    //  **Dónde se queda corta, dicho a las claras.** La onda se saca a 2 kHz
    //  (ver `orden_onda`), así que lo que viva por encima del kilohercio largo
    //  no cuenta: una llave sibilante o muy brillante manda aquí menos de lo
    //  que mandará en el render. Se descubrió midiendo, no pensando —un tono de
    //  prueba a 900 Hz llegaba a la onda como 0,11 en vez de 1—. Para voz
    //  hablada, que es de lo que va esto, la energía está muy por debajo de ese
    //  techo y la imitación cuadra.
    readonly property var curvaAgachado: [
        [0.012,   0.0], [0.025,  -0.3], [0.036,  -1.7],
        [0.061,  -5.1], [0.122, -10.4], [0.245, -15.6],
        [0.426, -19.9], [0.610, -22.6], [0.850, -25.1]
    ]

    function reduccionDb(nivel) {
        const c = curvaAgachado
        if (nivel <= c[0][0])
            return 0
        for (let i = 1; i < c.length; ++i)
            if (nivel <= c[i][0]) {
                const f = (nivel - c[i - 1][0]) / (c[i][0] - c[i - 1][0])
                return c[i - 1][1] + f * (c[i][1] - c[i - 1][1])
            }
        return c[c.length - 1][1]
    }

    //  El pico de una onda en un instante DEL FICHERO. -1 es «todavía no se
    //  sabe»: la onda se calcula en segundo plano y hasta que llega es mejor no
    //  agachar nada que agachar a ciegas.
    function picoDe(clave, enFichero) {
        const picos = ondas[clave]
        const dur = ondasDur[clave] || 0
        if (!picos || picos.length === 0 || dur <= 0)
            return -1
        const i = Math.floor(enFichero / dur * picos.length)
        return i >= 0 && i < picos.length ? picos[i] : 0
    }

    //  Lo que suena del VÍDEO en un instante de la línea. Hay que pasar por el
    //  mapa de tramos: la línea está cortada, reordenada y a veces acelerada,
    //  así que el segundo 8 de lo que ves no es el segundo 8 de ningún fichero.
    function nivelDelVideoEn(t) {
        const tr = tramoEn(t)
        if (!tr || tr.imagen || tr.mudo)
            return 0
        return picoDe(tr.ruta + "|0",
                      tr.desde + (t - tr.inicio) * tr.velocidad)
    }

    //  El nivel de quien manda sobre esta capa, en un instante de la línea.
    function nivelLlaveEn(capa, t) {
        if (!capa || !capa.agachar)
            return -1
        const otra = capa.llave > 0 ? capaPorId(capa.llave) : null
        if (!otra || otra.id === capa.id)
            return nivelDelVideoEn(t)
        //  Fuera de su bloque no manda: una locución que ya acabó no puede
        //  seguir agachando la música.
        if (t < otra.t0 || t >= otra.t1 || otra.mudo)
            return 0
        const c = claveOnda(otra)
        if (c.length === 0)
            return -1
        const desde = otra.recorte && otra.recorte.length === 2
            ? otra.recorte[0] : 0
        const p = picoDe(c, desde + (t - otra.t0))
        //  Con su volumen puesto: si bajas la locución, manda menos. Es lo que
        //  hace el render, donde el `volume` va antes del compresor.
        return p < 0 ? -1
            : p * (otra.volumen !== undefined ? otra.volumen : 1)
    }

    //  Por cuánto hay que multiplicar el volumen de una capa que se agacha.
    function gananciaAgachado(capa, t) {
        const n = nivelLlaveEn(capa, t)
        return n < 0 ? 1 : Math.pow(10, reduccionDb(n) / 20)
    }

    // ── copiar y pegar ────────────────────────────────────────────
    //
    //  Vale para las cuatro cosas que viven en la línea —trozo, capa, zoom y
    //  marcador— porque «copia esto» no debería depender de qué fila hayas
    //  pulsado. Cada una se pega distinto, y esa diferencia está aquí abajo y no
    //  repartida por las vistas.
    //
    //  Se guarda una COPIA del objeto, no una referencia: si guardáramos el
    //  original, editarlo o borrarlo después cambiaría —o vaciaría— lo que
    //  tienes copiado, y nadie espera que el portapapeles se mueva solo.
    //
    //  Vive en memoria y no en el plan: un portapapeles guardado en disco es un
    //  trozo de otro montaje esperando para pegarse donde no toca.
    property var portapapeles: null

    readonly property bool hayQuePegar:
        portapapeles !== null && portapapeles.length > 0

    // ── elegir varias cosas a la vez ──────────────────────────────
    //
    //  `tipoSel`/`idSel` siguen siendo la selección PRINCIPAL —la que manda en
    //  la ficha de la derecha, que solo puede enseñar una— y esto es lo que se
    //  le suma con Ctrl+clic. Se hace así y no cambiando `idSel` por una lista
    //  porque media docena de ficheros leen esas dos propiedades: convertirlas
    //  en lista era tocarlo todo para ganar lo mismo.
    //
    //  Elegir a secas la vacía. Es lo que uno espera: un clic normal empieza de
    //  cero, y Ctrl añade.
    property var seleccionExtra: []

    function claveSel(tipo, id) { return tipo + ":" + id }

    function estaSeleccionado(tipo, id) {
        if (tipoSel === tipo && idSel === id)
            return true
        const k = claveSel(tipo, id)
        for (let i = 0; i < seleccionExtra.length; ++i)
            if (claveSel(seleccionExtra[i].tipo, seleccionExtra[i].id) === k)
                return true
        return false
    }

    function alternarEnSeleccion(tipo, id) {
        //  Sin nada elegido, Ctrl+clic elige a secas: no hay a qué sumar.
        if (tipoSel.length === 0) {
            seleccionar(tipo, id)
            return
        }
        //  Quitar la principal de la selección la pasa a otra, si queda alguna:
        //  dejar `idSel` apuntando a algo deseleccionado sería mentir a la ficha.
        if (tipoSel === tipo && idSel === id) {
            if (seleccionExtra.length === 0)
                return
            const s = seleccionExtra[0]
            seleccionExtra = seleccionExtra.slice(1)
            tipoSel = s.tipo
            idSel = s.id
            return
        }
        const k = claveSel(tipo, id)
        const fuera = seleccionExtra.filter(function (s) {
            return claveSel(s.tipo, s.id) !== k
        })
        seleccionExtra = fuera.length !== seleccionExtra.length
            ? fuera : seleccionExtra.concat([{ tipo: tipo, id: id }])
    }

    //  Todo lo elegido, la principal primero.
    readonly property var todoLoElegido: {
        const r = []
        if (tipoSel.length > 0)
            r.push({ tipo: tipoSel, id: idSel })
        for (let i = 0; i < seleccionExtra.length; ++i)
            r.push(seleccionExtra[i])
        return r
    }

    function datoDe(tipo, id) {
        if (tipo === "clip") {
            const i = indiceDeClip(id)
            return i >= 0 ? clips[i] : null
        }
        if (tipo === "capa")
            return capaPorId(id)
        if (tipo === "momento") {
            for (let i = 0; i < momentos.length; ++i)
                if (momentos[i].id === id)
                    return momentos[i]
        }
        if (tipo === "marcador") {
            for (let i = 0; i < marcadores.length; ++i)
                if (marcadores[i].id === id)
                    return marcadores[i]
        }
        return null
    }

    function copiarSeleccion() {
        const trozos = []
        const todo = todoLoElegido
        for (let i = 0; i < todo.length; ++i) {
            const d = datoDe(todo[i].tipo, todo[i].id)
            if (d)
                trozos.push({ tipo: todo[i].tipo,
                              dato: JSON.parse(JSON.stringify(d)) })
        }
        if (trozos.length === 0)
            return false
        portapapeles = trozos
        return true
    }

    function quitarSeleccion() {
        const todo = todoLoElegido
        //  De atrás adelante y por id, no por índice: quitar el primero
        //  renumeraría los demás y el segundo borrado se llevaría a otro.
        for (let i = 0; i < todo.length; ++i) {
            if (todo[i].tipo === "clip")
                quitarClip(todo[i].id)
            else if (todo[i].tipo === "capa")
                quitarCapa(todo[i].id)
            else if (todo[i].tipo === "momento")
                quitarMomento(todo[i].id)
            else if (todo[i].tipo === "marcador")
                quitarMarcador(todo[i].id)
        }
        seleccionar("", 0)
    }

    //  Mover con lo elegido: el mismo desplazamiento a todo lo demás.
    //
    //  Arrastrar uno de tres rótulos elegidos mueve los tres, conservando la
    //  distancia entre ellos. Solo se aplica a lo que tiene instante propio
    //  —capas, zooms y marcadores—; un trozo vive en una secuencia y no se
    //  desliza.
    function arrastrarSeleccion(idArrastrado, delta) {
        if (Math.abs(delta) < 0.0005)
            return
        const todo = todoLoElegido
        for (let i = 0; i < todo.length; ++i) {
            const s = todo[i]
            if (s.tipo === "capa" && s.id !== idArrastrado) {
                const c = capaPorId(s.id)
                if (c)
                    fijarCapa(s.id, { t0: Math.max(0, c.t0 + delta),
                                      t1: Math.max(0.1, c.t1 + delta) })
            } else if (s.tipo === "momento" && s.id !== idArrastrado) {
                const m = datoDe("momento", s.id)
                if (m)
                    fijarMomento(s.id, { t0: Math.max(0, m.t0 + delta),
                                         t1: Math.max(0.1, m.t1 + delta) })
            } else if (s.tipo === "marcador" && s.id !== idArrastrado) {
                const k = datoDe("marcador", s.id)
                if (k)
                    marcadores = marcadores.map(function (x) {
                        return x.id === s.id
                            ? Object.assign({}, x,
                                { t: Math.max(0, x.t + delta) }) : x
                    })
            }
        }
    }

    //  Pegar donde esté el cabezal, todo lo que se copió.
    //
    //  Con varias cosas se conserva la DISTANCIA entre ellas: el cabezal marca
    //  dónde cae la primera y las demás guardan su hueco. Pegarlas todas
    //  encima del cabezal las amontonaría y habría que volver a separarlas a
    //  mano, que es justo el trabajo que copiar en grupo venía a ahorrar.
    function pegar(t) {
        if (!portapapeles || portapapeles.length === 0)
            return false
        const donde = Math.max(0, Math.min(duracionLinea, Number(t) || 0))

        let base = Infinity
        for (let i = 0; i < portapapeles.length; ++i) {
            const x = portapapeles[i].dato
            const cuando = x.t0 !== undefined ? x.t0 : x.t
            if (cuando !== undefined)
                base = Math.min(base, cuando)
        }
        if (!isFinite(base))
            base = 0

        let alguno = false
        for (let i = 0; i < portapapeles.length; ++i)
            if (pegarUno(portapapeles[i], donde, base))
                alguno = true
        return alguno
    }

    function pegarUno(trozo, cabezal, base) {
        const d = trozo.dato
        const propio = d.t0 !== undefined ? d.t0
                     : (d.t !== undefined ? d.t : base)
        const donde = Math.max(0, Math.min(duracionLinea,
                                           cabezal + (propio - base)))
        return pegarDato(trozo.tipo, d, donde)
    }

    function pegarDato(tipo, d, donde) {
        const portapapelesTipo = tipo

        if (portapapelesTipo === "marcador") {
            crearMarcador(donde, d.nombre)
            return true
        }

        if (portapapelesTipo === "momento") {
            //  Un zoom no puede solaparse con otro, así que el hueco manda: se
            //  respeta la duración original mientras quepa, y si no, se recorta
            //  a lo que haya. Dentro de otro zoom no se pega nada.
            const hueco = huecoDeZoom(donde)
            if (!hueco)
                return false
            const dur = Math.min((d.t1 - d.t0) || 1, hueco[1] - hueco[0])
            const id = crearMomento(hueco[0], hueco[0] + dur)
            fijarMomento(id, { cx: d.cx, cy: d.cy, z: d.z,
                               seguir: !!d.seguir })
            seleccionar("momento", id)
            return true
        }

        if (portapapelesTipo === "capa") {
            //  Conserva lo que dura y todo lo demás —posición, efectos,
            //  volumen—; lo único que cambia es CUÁNDO empieza, y la banda, que
            //  se busca libre para no apilarla encima de otra en el mismo
            //  instante.
            const dur = Math.max(0.1, (d.t1 - d.t0) || 1)
            const t0 = Math.min(donde, Math.max(0, duracionLinea - dur))
            const nueva = Object.assign({}, d, {
                id: nuevoIdCapa(),
                t0: t0,
                t1: t0 + dur,
                banda: bandaLibre(t0, t0 + dur)
            })
            capas = capas.concat([nueva])
            persistir()
            seleccionar("capa", nueva.id)
            return true
        }

        if (portapapelesTipo === "clip") {
            //  Un trozo no se superpone: la línea es una secuencia, así que
            //  pegar es INSERTAR. Se parte por el cabezal y la copia entra por
            //  ese corte; pegar justo en un borde no necesita partir nada.
            //
            //  `cortar` ya se niega a partir a menos de una décima del borde,
            //  que es exactamente cuando no hace falta.
            const tr = tramoEn(donde)
            if (!tr)
                return false
            cortar(donde)
            //  Después de cortar, los índices son otros: se vuelve a preguntar
            //  quién está bajo el cabezal en vez de fiarse del de antes.
            const ahora = tramoEn(donde)
            const puesto = ahora ? ahora.indice : clips.length
            const copia = Object.assign({}, d, { id: nuevoIdClip() })
            const nuevos = clips.slice()
            nuevos.splice(puesto, 0, copia)
            clips = nuevos
            persistir()
            seleccionar("clip", copia.id)
            return true
        }

        return false
    }

    function seleccionar(tipo, id) {
        //  Un clic normal empieza de cero: lo que hubiera elegido además se
        //  suelta. Ctrl+clic va por `alternarEnSeleccion`, que no pasa por aquí.
        seleccionExtra = []
        //  Y se desarma la herramienta: si has armado el zoom y luego pinchas
        //  otra cosa, has cambiado de idea. Dejarla puesta sería que el
        //  siguiente arrastre sobre el vídeo hiciera un zoom que no pediste.
        herramienta = ""
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
    signal fallo(string motivo, string detalle)

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
    //
    //  `.k4v` es el proyecto de k4: un JSON por dentro, pero con nombre propio
    //  para que se vea de un vistazo en la carpeta que eso es un montaje y no
    //  un fichero suelto de datos. Los proyectos guardados con el nombre viejo
    //  —`.k4.json`— se renombran solos al abrirlos, en python.
    //  Si lo que te han dado es el proyecto y no el vídeo.
    //
    //  Desde que el selector lista `.k4v` se puede abrir un montaje guardado
    //  directamente. Por el camino de siempre eso dejaba `rutaVideo` apuntando
    //  al propio proyecto, y `rutaVideo` es de quien tiran la transcripción, la
    //  medida de niveles y el nombre del fichero renderizado: los tres se
    //  habrían puesto a trabajar sobre un JSON.
    //
    //  El vídeo de verdad no se adivina del nombre —el plan puede llamarse
    //  igual que un `.mkv` o que un `.mp4`— así que se saca del propio plan
    //  cuando llega, en `recibirPlan`.
    readonly property bool abriendoProyecto: rutaVideo.endsWith(".k4v")

    function preparar(video) {
        //  Si había una toma de voz en marcha, se tira: pertenece al proyecto
        //  que se está cerrando.
        cancelarVoz()
        //  Y las copias sin ruido, que viven en la carpeta ADJUNTA del proyecto
        //  que se deja: sus rutas no valen aquí. Guardarlas apuntaría a
        //  ficheros de otro montaje —o a ficheros que ya no están— y la capa se
        //  quedaría muda sin decir por qué.
        limpias = ({})
        limpiasPedidas = ({})
        rutaVideo = video
        rutaPlan = video.replace(/\.[^./]+$/, "") + ".k4v"
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
        //  Dónde vive el plan de verdad, dicho por python.
        //
        //  Ya no se puede deducir del nombre del vídeo: un proyecto renombrado
        //  se llama como quiso su dueño, y python lo encuentra leyendo los
        //  `.k4v` de la carpeta. Sin quedarnos con lo que contesta, guardar
        //  volvería a escribir en el nombre de fábrica y el montaje se
        //  bifurcaría en dos ficheros sin avisar.
        if (d.plan && String(d.plan).length > 0)
            rutaPlan = d.plan
        //  Y si veníamos de un `.k4v`, el vídeo es la primera fuente del plan.
        //  Se hace aquí y no antes porque hasta que el plan no llega no hay de
        //  dónde sacarlo. Si el plan viniera sin fuentes se queda como estaba:
        //  peor es dejarlo vacío y que no se pueda ni renombrar el render.
        if (abriendoProyecto && fuentes.length > 0
                && esRutaLocal(fuentes[0].ruta))
            rutaVideo = fuentes[0].ruta
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
        //  La foto de cómo estaba, para poder volver a ella al cerrar. Va
        //  aquí y no en `abrir`: hasta que no ha llegado el plan no hay nada
        //  que fotografiar.
        planAlAbrir = planSerializado()
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

        //  El plan pasa a llamarse como te haya dado la gana, y la carpeta
        //  adjunta con él. No hay que recargar nada: por dentro es el mismo
        //  montaje, solo cambia dónde se guarda a partir de ahora.
        onRenombrado: function (plan) {
            editor.renombrando = false
            editor.rutaPlan = plan
            editor.planAlAbrir = editor.planSerializado()
        }

        onRenombrarFallo: function (motivo, detalle) {
            editor.renombrando = false
            editor.fallo(motivo, detalle)
        }

        //  Reasignando el objeto entero y no escribiendo dentro: QML solo emite
        //  el cambio cuando la propiedad se asigna, así que tocar una clave del
        //  mapa no repintaría ninguna onda.
        onLimpiaLista: function (clave, ruta) {
            const m = {}
            for (const k in editor.limpias)
                m[k] = editor.limpias[k]
            m[clave] = ruta
            editor.limpias = m
        }

        //  Si no se pudo limpiar, se sigue oyendo el original y se dice. No se
        //  desmarca el botón: al renderizar el filtro sí se va a aplicar, y
        //  apagarlo por un fallo de la PREVIA sería cambiarle el montaje.
        onLimpiaFallo: function (clave) {
            editor.fallo("no-se-pudo-limpiar")
        }

        onOndaLista: function (clave, picos, dur) {
            const m = {}
            for (const k in editor.ondas)
                m[k] = editor.ondas[k]
            m[clave] = picos
            editor.ondas = m
            //  En un mapa aparte para no cambiarle la forma a `ondas`, que es
            //  lo que dibujan los bloques y espera un array a secas.
            const n = {}
            for (const k in editor.ondasDur)
                n[k] = editor.ondasDur[k]
            n[clave] = dur
            editor.ondasDur = n
        }

        onAbrirFallo: function (motivo, detalle) {
            editor.estado = ""
            editor.fallo(motivo, detalle)
        }

        //  Sin rastro no hay zoom que proponer, pero sí vídeo que editar: se
        //  abre igual, que para eso está.
        onProponerFallo: editor.abrir(editor.rutaVideo, "")

        //  El plan lo ha cambiado python, así que hay que releerlo: lo que hay
        //  en memoria se ha quedado viejo.
        onCongelado: editor.abrir(editor.rutaVideo, "")
        onCongelarFallo: function (motivo, detalle) {
            editor.fallo(motivo, detalle)
        }

        onSilenciosListos: function (tramos) { editor.aplicarSilencios(tramos) }
        onSilenciosFallo: editor.estadoSilencios = "fallo"

        onMedido: function (d) { editor.recibirMedida(d) }

        onVozAbierta: function (capturado) {
            editor.recibirVozAbierta(capturado)
        }
        onVozCerrada: function (codigo, queja) {
            editor.recibirVozCerrada(codigo, queja)
        }

        onNivelesListos: function (d) {
            const n = {}
            const lista = d.pistas || []
            for (let i = 0; i < lista.length; ++i)
                n[lista[i].i] = lista[i]
            editor.nivelesPistas = n
        }

        onMiniaturaLista: function (d) {
            if (!d || !d.ok) {
                editor.fallo(d && d.motivo ? d.motivo : "miniatura",
                             (d && d.detalle) || "")
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

        onRenderFallo: function (motivo, detalle) {
            //  Un render descartado a medias puede seguir muriéndose por
            //  detrás; su despedida ya no le importa a nadie.
            if (editor.estado !== "renderizando")
                return
            editor.estado = ""
            editor.fallo(motivo, detalle)
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

    //  Un momento de zoom dibujado SOBRE EL VÍDEO.
    //
    //  Hasta ahora un zoom se creaba arrastrando en un hueco de la línea de
    //  tiempo y solo después apuntabas en la previa. O sea que decidías el
    //  CUÁNDO mirando la línea y el DÓNDE mirando el vídeo, en dos gestos y en
    //  dos sitios, cuando lo que uno quiere decir es «enfoca ahí».
    //
    //  Aquí el rectángulo dice las dos cosas de golpe: dónde y cuánto —el nivel
    //  sale de lo ancho que lo dibujes— y el cuándo empieza en el cabezal.
    //
    //  El nivel se acota igual que la rueda: por debajo de 1,1 no es un zoom y
    //  por encima de 4 es un mosaico. Dibujar un rectángulo casi tan ancho como
    //  el vídeo no crea un zoom de ×1,02 que no se ve; crea el mínimo.
    // ── la herramienta armada ─────────────────────────────────────
    //
    //  Pulsar «Zoom» creaba el momento ahí mismo, dos segundos desde el cabezal
    //  y encuadrado al centro; luego había que ir a la previa a apuntarlo y a la
    //  línea a cuadrarlo. O sea que el botón adivinaba las tres cosas y acertaba
    //  ninguna.
    //
    //  Ahora ARMA la herramienta: el botón dice qué vas a hacer y el gesto sobre
    //  el vídeo dice dónde y cuánto, que es lo que ya se podía hacer arrastrando
    //  y no se sabía. El botón deja de ser un atajo que estorba y pasa a ser la
    //  puerta de entrada al gesto.
    //
    //  Se desarma sola al usarla, al cambiar de selección o con Escape: una
    //  herramienta que se queda armada sin decirlo es un modo escondido, y un
    //  modo escondido acaba en «¿por qué no puedo arrastrar el encuadre?».
    property string herramienta: ""

    function armar(cual) {
        herramienta = herramienta === cual ? "" : cual
    }

    function desarmar() { herramienta = "" }

    function crearZoomEn(t, cx, cy, z) {
        const hueco = huecoDeZoom(t)
        if (!hueco)
            return 0
        const id = crearMomento(hueco[0], hueco[1])
        fijarMomento(id, {
            cx: Math.round(Math.max(0, Math.min(anchoVideo, cx))),
            cy: Math.round(Math.max(0, Math.min(altoVideo, cy))),
            z: Math.max(1.1, Math.min(4, Math.round(z * 100) / 100)),
            seguir: false
        })
        seleccionar("momento", id)
        return id
    }

    //  Desde el cabezal hasta donde quepa, con un tope de tres segundos.
    //
    //  Los momentos no se solapan —dos encuadres a la vez no significan nada—
    //  así que el hueco acaba donde empiece el siguiente. Si estás DENTRO de uno
    //  no hay nada que crear: ahí lo que se hace es mover el que ya está.
    //  Devuelve null cuando no cabe ni medio segundo, y entonces no se crea
    //  nada en vez de dejar un momento de duración ridícula.
    function huecoDeZoom(t) {
        const desde = Math.max(0, Math.min(duracionLinea, t))
        let hasta = Math.min(duracionLinea, desde + 3)
        for (let i = 0; i < momentos.length; ++i) {
            const m = momentos[i]
            if (desde >= m.t0 && desde <= m.t1)
                return null
            if (m.t0 > desde)
                hasta = Math.min(hasta, m.t0)
        }
        return hasta - desde >= 0.5 ? [desde, hasta] : null
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
    //  Lo que se guarda, armado en un solo sitio: lo escribe el guardado, lo
    //  fotografía el «tal como estaba al abrir» y lo compara el «¿hay cambios?».
    //  Tres usos de la misma verdad; con tres copias, una se queda atrás.
    function planSerializado() {
        return JSON.stringify({ momentos: momentos, pistas: pistasAudio,
                             clips: clips, capas: capas, bandas: bandas,
                             transcripcion: transcripcion,
                             marcadores: marcadores,
                             clics: { activo: clicsActivos,
                                      color: colorClics },
                             fundidos: { entrada: fundidoEntrada,
                                         salida: fundidoSalida,
                                         entre: fundidoEntre },
                             transicion: { tipo: transicionTipo,
                                           dur: transicionDur } })
    }

    function guardarPlan() {
        if (rutaPlan.length === 0)
            return
        procesos.escribirPlan(planSerializado())
    }

    //  ── no perder lo último ───────────────────────────────────────
    //
    //  El guardado va con rebote de 200 ms, así que cerrar justo después de
    //  tocar algo dejaba ese último cambio sin escribir: el temporizador
    //  saltaba con el plan ya olvidado y no hacía nada. Antes de cerrar, se
    //  vuelca.
    function volcar() {
        if (rutaPlan.length === 0)
            return
        persistidor.stop()
        guardarPlan()
    }

    //  Cómo estaba el proyecto al abrirlo. Es lo que permite decir «descartar
    //  los cambios» y que signifique algo teniendo guardado automático: se
    //  vuelve a escribir esto y el fichero queda como estaba.
    property string planAlAbrir: ""

    readonly property bool hayCambios: planAlAbrir.length > 0
                                       && planAlAbrir !== planSerializado()

    function descartarCambios() {
        if (rutaPlan.length === 0 || planAlAbrir.length === 0)
            return
        persistidor.stop()
        procesos.escribirPlan(planAlAbrir)
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
        //  El fichero que sale se llama como el PROYECTO, no como el vídeo.
        //
        //  Salía con el nombre del vídeo, así que renombrar el montaje a «Tutorial
        //  del island» y exportarlo daba `grabacion-20260805-165407-k4.mp4`. El
        //  nombre se le pone al montaje precisamente para no tener que reconocer
        //  cuál era por su marca de tiempo.
        //
        //  Del plan y no del nombre visible: el plan ya vive donde toca y con el
        //  nombre bueno, así que el render cae al lado de su proyecto.
        rutaRenderizada = (rutaPlan.length > 4
                            ? rutaPlan.replace(/\.k4v$/, "")
                            : rutaVideo.replace(/\.[^./]+$/, ""))
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
    //  `volcando` es false cuando se cierra DESHACIENDO la sesión: ahí lo
    //  último que se ha escrito es la foto de cómo estaba al abrir, y volcar
    //  encima el estado actual deshacía el deshacer. Pasó, y sin ruido: el
    //  fichero se quedaba con los cambios que acababas de tirar.
    function descartar(volcando) {
        if (volcando !== false)
            volcar()
        planAlAbrir = ""
        momentos = []
        pistasAudio = []
        camara = []
        rutaVideo = ""
        rutaPlan = ""
        estado = ""
        Modulos.quitar("editor")
    }
}
