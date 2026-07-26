pragma Singleton

//  El juego: estado y simulación.
//
//  Vive aquí y no en el plugin porque la vista solo existe mientras el módulo
//  está abierto, y un idle que solo avanza cuando lo miras no es un idle. El
//  tick corre siempre, y lo que pasa con la barra cerrada se recupera al
//  arrancar comparando marcas de tiempo.
//
//  Las curvas están todas arriba, en un solo sitio, porque el balance se
//  afina jugando y conviene tener los números a mano.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: game

    // ── curvas ────────────────────────────────────────────────────
    readonly property int monstruosPorZona: 10
    readonly property real vidaBase: 12
    readonly property real vidaCrecimiento: 1.55
    readonly property real oroBase: 2
    // Por debajo del crecimiento de la vida (1,55) a propósito: si el oro
    // creciera al mismo ritmo no habría muro nunca, y el muro es lo que da
    // sentido a esperar, a las expediciones y al prestigio.
    readonly property real oroCrecimiento: 1.40
    readonly property real jefeMultiplicadorVida: 4.5
    readonly property int jefeSegundos: 30
    readonly property real costeCrecimiento: 1.15
    readonly property int topeOfflineSegundos: 8 * 3600

    readonly property var mejorasDef: [
        { id: "ataque",    nombre: "Espada",     desc: "Daño por golpe",      base: 10,  glifo: 0xF04E5 },
        { id: "ayudantes", nombre: "Compañeros", desc: "Daño por segundo",    base: 25,  glifo: 0xF0849 },
        { id: "botin",     nombre: "Botín",      desc: "Oro por muerte",      base: 60,  glifo: 0xF0A54 }
    ]

    // ── estado ────────────────────────────────────────────────────
    property int zona: 1
    property int muertes: 0             // en la zona actual
    property real oro: 0
    property real vidaActual: vidaBase
    property bool enJefe: false
    property real jefeRestante: 0
    property var niveles: ({ ataque: 0, ayudantes: 0, botin: 0 })
    property real totalOro: 0
    property int totalMuertes: 0
    property int zonaMaxima: 1

    property real ultimoTick: 0         // epoch en segundos
    property bool cargado: false

    // informe de lo ocurrido con la barra cerrada, para enseñarlo al abrir
    property var resumenOffline: null

    // ── derivados ─────────────────────────────────────────────────
    readonly property real vidaMaxima: {
        const base = vidaBase * Math.pow(vidaCrecimiento, zona - 1)
        return enJefe ? base * jefeMultiplicadorVida : base
    }

    // Exponencial pura, no `nivel · r^nivel`: eso crece más rápido que la vida
    // de los monstruos y en veinte compras ya no hay juego. Con el daño y el
    // coste creciendo al mismo ritmo, cada compra cunde lo mismo siempre y el
    // avance de zonas queda parejo.
    readonly property real dañoGolpe: Math.pow(1.16, niveles.ataque)
    readonly property real dps: niveles.ayudantes === 0
        ? 0 : 1.5 * Math.pow(1.16, niveles.ayudantes - 1)
    // Este sí es lineal, y a propósito: un multiplicador de oro exponencial
    // con coste exponencial más lento se realimenta —más oro compra más
    // multiplicador, que da más oro— y en veinte compras el juego se acaba.
    readonly property real multiplicadorOro: 1 + niveles.botin * 0.5

    readonly property real oroPorMuerte:
        oroBase * Math.pow(oroCrecimiento, zona - 1) * multiplicadorOro * (enJefe ? 8 : 1)

    readonly property bool esZonaDeJefe: zona % 10 === 0

    readonly property int spriteMonstruo: enJefe
        ? (Math.floor(zona / 10) * 3) % 20
        : (zona * 7 + muertes) % 20

    function coste(id) {
        for (let i = 0; i < mejorasDef.length; ++i) {
            if (mejorasDef[i].id === id)
                return Math.ceil(mejorasDef[i].base * Math.pow(costeCrecimiento, niveles[id]))
        }
        return Infinity
    }

    function puedePagar(id) { return oro >= coste(id) }

    function comprar(id) {
        const precio = coste(id)
        if (oro < precio)
            return false

        oro -= precio
        const copia = Object.assign({}, niveles)
        copia[id] = copia[id] + 1
        niveles = copia
        guardar()
        return true
    }

    // ── combate ───────────────────────────────────────────────────
    signal golpeado(real daño, bool critico)
    signal muerto(real oroGanado)
    signal jefeFallado()

    function golpear() {
        if (!cargado)
            return

        // 10% de críticos: da algo que mirar sin complicar el balance
        const critico = Math.random() < 0.10
        const daño = dañoGolpe * (critico ? 3 : 1)
        aplicar(daño)
        golpeado(daño, critico)
    }

    function aplicar(daño) {
        vidaActual -= daño
        if (vidaActual > 0)
            return

        const ganado = oroPorMuerte
        oro += ganado
        totalOro += ganado
        totalMuertes += 1
        muerto(ganado)
        avanzar()
    }

    function avanzar() {
        if (enJefe) {
            // jefe derrotado: se pasa de zona
            enJefe = false
            zona += 1
            muertes = 0
        } else {
            muertes += 1
            if (muertes >= monstruosPorZona) {
                if (esZonaDeJefe) {
                    enJefe = true
                    jefeRestante = jefeSegundos
                } else {
                    zona += 1
                    muertes = 0
                }
            }
        }

        if (zona > zonaMaxima)
            zonaMaxima = zona

        vidaActual = vidaMaxima
        guardar()
    }

    function fallarJefe() {
        enJefe = false
        muertes = 0                     // hay que volver a limpiar la zona
        vidaActual = vidaMaxima
        jefeFallado()
        guardar()
    }

    // ── tick ──────────────────────────────────────────────────────
    function ahora() { return Date.now() / 1000 }

    Timer {
        interval: 1000
        repeat: true
        running: game.cargado
        onTriggered: {
            const t = game.ahora()
            const delta = Math.max(0, Math.min(5, t - game.ultimoTick))
            game.ultimoTick = t

            if (game.enJefe) {
                game.jefeRestante -= delta
                if (game.jefeRestante <= 0) {
                    game.fallarJefe()
                    return
                }
            }

            if (game.dps > 0)
                game.aplicar(game.dps * delta)
        }
    }

    // guardado periódico: si no, un corte de luz se lleva el rato jugado
    Timer {
        interval: 30000
        repeat: true
        running: game.cargado
        onTriggered: game.guardar()
    }

    // ── progreso con la barra cerrada ─────────────────────────────
    // No se simula zona a zona: se calcula cuánto oro habrían dado los
    // ayudantes matando monstruos de la zona actual. Avanzar de zona sin
    // mirar convertiría una semana fuera en un salto absurdo.
    function recuperarOffline(desde) {
        const transcurrido = Math.min(topeOfflineSegundos, Math.max(0, ahora() - desde))
        if (transcurrido < 60 || dps <= 0)
            return null

        const vidaUnidad = vidaBase * Math.pow(vidaCrecimiento, zona - 1)
        const muertesOffline = Math.floor(dps * transcurrido / vidaUnidad)
        if (muertesOffline <= 0)
            return null

        const ganado = muertesOffline * oroBase * Math.pow(oroCrecimiento, zona - 1) * multiplicadorOro
        oro += ganado
        totalOro += ganado
        totalMuertes += muertesOffline

        return {
            segundos: Math.floor(transcurrido),
            muertes: muertesOffline,
            oro: ganado,
            tope: transcurrido >= topeOfflineSegundos
        }
    }

    // ── persistencia ──────────────────────────────────────────────
    readonly property string ruta: Quickshell.env("HOME") + "/.local/state/k4/partida.json"

    function instantanea() {
        return JSON.stringify({
            version: 1,
            zona: zona, muertes: muertes, oro: oro,
            vidaActual: vidaActual, enJefe: enJefe, jefeRestante: jefeRestante,
            niveles: niveles,
            totalOro: totalOro, totalMuertes: totalMuertes, zonaMaxima: zonaMaxima,
            guardadoEn: ahora()
        }, null, 1)
    }

    // Escritura atómica: se vuelca a un temporal y se renombra. Con FileView
    // escribiendo directamente, un cierre a destiempo deja la partida a medias
    // y sin recuperación.
    // Nunca se corta una escritura a medias para empezar otra: si llega un
    // guardado con el anterior en vuelo, se apunta y se lanza al terminar. Al
    // reiniciar el proceso en caliente quedaba el .tmp huérfano y la partida
    // sin renombrar.
    property string pendiente: ""
    property bool relanzar: false

    function guardar() {
        if (!cargado)
            return

        pendiente = instantanea()
        if (escritor.running) {
            relanzar = true
            return
        }
        escritor.running = true
    }

    Process {
        id: escritor
        command: ["sh", "-c",
            "cat > '" + game.ruta + ".tmp' && mv -f '" + game.ruta + ".tmp' '" + game.ruta + "'"]
        stdinEnabled: true

        onStarted: {
            write(game.pendiente)
            stdinEnabled = false        // cierra stdin: si no, cat no termina
        }

        onExited: {
            stdinEnabled = true         // rearmado para la siguiente escritura
            if (game.relanzar) {
                game.relanzar = false
                running = true
            }
        }
    }

    FileView { id: lector; path: game.ruta; blockLoading: true }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: game.cargar()
    }

    function cargar() {
        const bruto = lector.text()
        let s = null

        if (bruto.length > 0) {
            try {
                s = JSON.parse(bruto)
            } catch (e) {
                s = null                // partida ilegible: se empieza de cero
            }
        }

        if (s) {
            zona = s.zona || 1
            muertes = s.muertes || 0
            oro = s.oro || 0
            enJefe = s.enJefe === true
            jefeRestante = s.jefeRestante || 0
            niveles = s.niveles || ({ ataque: 0, ayudantes: 0, botin: 0 })
            totalOro = s.totalOro || 0
            totalMuertes = s.totalMuertes || 0
            zonaMaxima = s.zonaMaxima || zona
            // Se recorta al máximo actual: una partida guardada con otras
            // curvas —o tocada a mano— deja vidas por encima de lo posible, y
            // entonces la barra sale llena y el bicho parece inmortal.
            vidaActual = Math.min(s.vidaActual > 0 ? s.vidaActual : vidaMaxima, vidaMaxima)
            // el temporizador del jefe no corre con la barra cerrada: sería
            // perder la pelea sin verla
            if (enJefe)
                jefeRestante = jefeSegundos
        } else {
            vidaActual = vidaMaxima
        }

        ultimoTick = ahora()
        cargado = true

        if (s && s.guardadoEn)
            resumenOffline = recuperarOffline(s.guardadoEn)
    }

    // ── formato ───────────────────────────────────────────────────
    readonly property var sufijos: ["", "K", "M", "B", "T", "aa", "ab", "ac", "ad", "ae", "af"]

    function cifra(n) {
        if (!isFinite(n))
            return "∞"
        if (n < 1000)
            return String(Math.floor(n))

        let i = 0
        while (n >= 1000 && i < sufijos.length - 1) {
            n /= 1000
            i += 1
        }
        return (n < 10 ? n.toFixed(2) : n < 100 ? n.toFixed(1) : Math.floor(n)) + sufijos[i]
    }

    function duracion(segundos) {
        const h = Math.floor(segundos / 3600)
        const m = Math.floor((segundos % 3600) / 60)
        if (h > 0)
            return h + " h " + m + " min"
        if (m > 0)
            return m + " min"
        return Math.floor(segundos) + " s"
    }
}
