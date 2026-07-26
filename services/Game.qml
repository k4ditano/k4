pragma Singleton

//  La mazmorra: simulación de un roguelite por oleadas.
//
//  Vive aquí y no en el plugin porque la vista solo existe mientras el módulo
//  está abierto, y un idle que solo avanza cuando lo miras no es un idle.
//
//  El combate es automático, al estilo de TBH: tú decides con qué grupo y en
//  qué gastas el oro, no los golpes. Las habilidades se pueden lanzar a mano,
//  pero si no intervienes se lanzan solas: la barra no debe exigir atención.
//
//  Al morir el grupo se acaba la partida. Se pierde el oro y las mejoras de
//  esa partida, y se conservan los cofres y las reliquias.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: game

    // ── curvas ────────────────────────────────────────────────────
    readonly property int tickMs: 1000
    readonly property real enemigoVidaBase: 26
    readonly property real enemigoVidaCrec: 1.17
    readonly property real enemigoDañoBase: 4
    readonly property real enemigoDañoCrec: 1.115
    readonly property real oroBase: 6
    readonly property real oroCrec: 1.14
    readonly property real costeCrec: 1.19
    readonly property real jefeVida: 5
    readonly property real jefeDaño: 1.8
    readonly property int oleadasPorJefe: 10
    readonly property int topeOfflineSegundos: 8 * 3600
    readonly property int segundosPorCofre: 900        // uno cada 15 min fuera
    readonly property int oleadasPorCofre: 5

    // Segundos que espera una habilidad lista antes de lanzarse sola. Da margen
    // para usarla tú si estás mirando, sin castigarte si no.
    readonly property int autoHabilidad: 5

    // ── clases ────────────────────────────────────────────────────
    readonly property var clases: [
        {
            id: "tanque", nombre: "Guardián", sprite: "h00",
            vida: 260, daño: 9, armadura: 6, papel: "Aguanta los golpes",
            habilidad: "Provocar", habilidadDesc: "Atrae todo y reduce el daño",
            recarga: 18, glifo: 0xF0498
        },
        {
            id: "mago", nombre: "Hechicero", sprite: "h02",
            vida: 110, daño: 26, armadura: 0, papel: "Daño en área",
            habilidad: "Llamarada", habilidadDesc: "Golpea a toda la oleada",
            recarga: 14, glifo: 0xF0E20
        },
        {
            id: "clerigo", nombre: "Clériga", sprite: "h04",
            vida: 160, daño: 11, armadura: 3, papel: "Cura al grupo",
            habilidad: "Bendición", habilidadDesc: "Cura a todos de golpe",
            recarga: 22, glifo: 0xF05E1
        }
    ]

    readonly property var mejorasDef: [
        { id: "ataque",   nombre: "Afilar",   desc: "+15% de daño al grupo",  base: 22, glifo: 0xF04E5 },
        { id: "vitalidad", nombre: "Vigor",   desc: "+12% de vida máxima",    base: 30, glifo: 0xF1076 },
        { id: "armadura", nombre: "Blindar",  desc: "+2 de armadura",         base: 40, glifo: 0xF0498 }
    ]

    // ── estado de la partida ──────────────────────────────────────
    property int oleada: 1
    property real oro: 0
    property var niveles: ({ ataque: 0, vitalidad: 0, armadura: 0 })
    property var grupo: []              // héroes vivos o caídos de esta partida
    property var enemigos: []
    property bool viva: false           // ¿hay partida en curso?
    property string finalizada: ""      // texto del resumen al morir

    // ── permanente ────────────────────────────────────────────────
    property int cofres: 0
    property real reliquias: 0
    property int mejorOleada: 0
    property int partidas: 0
    property int oleadasDesdeCofre: 0

    property real ultimoTick: 0
    property bool cargado: false
    property var resumenOffline: null

    // ── derivados ─────────────────────────────────────────────────
    readonly property real multDaño: Math.pow(1.15, niveles.ataque)
    readonly property real multVida: Math.pow(1.12, niveles.vitalidad)
    readonly property int armaduraExtra: niveles.armadura * 2

    readonly property bool esJefe: oleada % oleadasPorJefe === 0
    readonly property bool grupoVivo: grupo.some(function (h) { return h.vida > 0 })

    function coste(id) {
        for (let i = 0; i < mejorasDef.length; ++i) {
            if (mejorasDef[i].id === id)
                return Math.ceil(mejorasDef[i].base * Math.pow(costeCrec, niveles[id]))
        }
        return Infinity
    }

    function puedePagar(id) { return oro >= coste(id) }

    function comprar(id) {
        const precio = coste(id)
        if (oro < precio || !viva)
            return false

        oro -= precio
        const copia = Object.assign({}, niveles)
        copia[id] = copia[id] + 1
        niveles = copia

        // vitalidad sube también la vida actual, si no comprarla en plena
        // pelea no salvaría a nadie
        if (id === "vitalidad") {
            const g = grupo.slice()
            for (let i = 0; i < g.length; ++i) {
                if (g[i].vida <= 0)
                    continue
                const nuevoMax = vidaMaxDe(g[i])
                g[i].vida = Math.min(nuevoMax, g[i].vida * 1.12)
            }
            grupo = g
        }

        guardar()
        return true
    }

    function vidaMaxDe(heroe) {
        return Math.round(claseDe(heroe.clase).vida * multVida)
    }

    function claseDe(id) {
        for (let i = 0; i < clases.length; ++i) {
            if (clases[i].id === id)
                return clases[i]
        }
        return clases[0]
    }

    // ── señales para la vista ─────────────────────────────────────
    signal impacto(int indiceEnemigo, real daño)
    signal heroeHerido(int indiceHeroe, real daño)
    signal enemigoMuerto(int indiceEnemigo)
    signal curado(int indiceHeroe, real cantidad)
    signal habilidadLanzada(int indiceHeroe)
    signal oleadaSuperada(int numero)
    signal partidaTerminada(int oleadaAlcanzada, int cofresGanados, real reliquiasGanadas)

    // ── ciclo de partida ──────────────────────────────────────────
    function nuevaPartida() {
        oleada = 1
        oro = 0
        niveles = ({ ataque: 0, vitalidad: 0, armadura: 0 })
        oleadasDesdeCofre = 0
        finalizada = ""

        const g = []
        for (let i = 0; i < clases.length; ++i) {
            const c = clases[i]
            g.push({
                clase: c.id,
                vida: c.vida,
                recargaRestante: c.recarga,
                listaDesde: 0,          // instante en que quedó lista
                provocando: 0           // segundos que le quedan de provocación
            })
        }
        grupo = g

        generarOleada()
        viva = true
        ultimoTick = ahora()
        guardar()
    }

    function generarOleada() {
        const cuantos = esJefe ? 1 : Math.min(3, 1 + Math.floor(oleada / 7))
        const lista = []

        for (let i = 0; i < cuantos; ++i) {
            const vida = enemigoVidaBase * Math.pow(enemigoVidaCrec, oleada - 1) * (esJefe ? jefeVida : 1)
            lista.push({
                vida: vida,
                vidaMax: vida,
                daño: enemigoDañoBase * Math.pow(enemigoDañoCrec, oleada - 1) * (esJefe ? jefeDaño : 1),
                sprite: esJefe
                    ? "b" + String((Math.floor(oleada / oleadasPorJefe) * 3) % 20).padStart(2, "0")
                    : "m" + String((oleada * 7 + i * 3) % 20).padStart(2, "0"),
                jefe: esJefe
            })
        }
        enemigos = lista
    }

    function terminarPartida() {
        viva = false
        partidas += 1

        const ganadosCofres = Math.floor(oleada / oleadasPorCofre)
        const ganadasReliquias = Math.floor(Math.pow(oleada, 1.4))

        cofres += ganadosCofres
        reliquias += ganadasReliquias
        if (oleada > mejorOleada)
            mejorOleada = oleada

        finalizada = "Has caído en la oleada " + oleada
        partidaTerminada(oleada, ganadosCofres, ganadasReliquias)
        guardar()
    }

    // ── combate ───────────────────────────────────────────────────
    // Un tic por segundo: suficiente para que se vea vivo y ridículo en coste.
    function tic(delta) {
        if (!viva || !cargado)
            return

        const g = grupo.slice()
        const e = enemigos.slice()

        // ¿alguien provocó? el tanque acapara mientras dure
        let objetivoForzado = -1
        for (let i = 0; i < g.length; ++i) {
            if (g[i].provocando > 0) {
                g[i].provocando -= delta
                objetivoForzado = i
            }
        }

        // ── golpean los héroes
        for (let i = 0; i < g.length; ++i) {
            if (g[i].vida <= 0)
                continue

            const c = claseDe(g[i].clase)
            const daño = c.daño * multDaño * delta

            const blanco = primerVivo(e)
            if (blanco >= 0) {
                e[blanco].vida -= daño
                impacto(blanco, daño)
                if (e[blanco].vida <= 0)
                    enemigoMuerto(blanco)
            }

            // la clériga cura de fondo, sin gastar habilidad
            if (c.id === "clerigo") {
                const herido = masHerido(g)
                if (herido >= 0) {
                    const cura = 5 * multVida * delta
                    g[herido].vida = Math.min(vidaMaxDe(g[herido]), g[herido].vida + cura)
                    curado(herido, cura)
                }
            }

            // recarga de habilidades
            if (g[i].recargaRestante > 0) {
                g[i].recargaRestante -= delta
                if (g[i].recargaRestante <= 0)
                    g[i].listaDesde = ahora()
            } else if (ahora() - g[i].listaDesde >= autoHabilidad) {
                lanzarInterno(g, e, i)
            }
        }

        // ── pegan los enemigos
        for (let j = 0; j < e.length; ++j) {
            if (e[j].vida <= 0)
                continue

            let blanco = objetivoForzado >= 0 && g[objetivoForzado].vida > 0
                ? objetivoForzado : primerVivo(g)
            if (blanco < 0)
                break

            const c = claseDe(g[blanco].clase)
            const armadura = c.armadura + armaduraExtra + (g[blanco].provocando > 0 ? 8 : 0)
            const recibido = Math.max(1, e[j].daño * delta - armadura * delta)
            g[blanco].vida -= recibido
            heroeHerido(blanco, recibido)
        }

        grupo = g
        enemigos = e

        // ── resolución
        if (!enemigos.some(function (x) { return x.vida > 0 })) {
            const ganado = oroBase * Math.pow(oroCrec, oleada - 1) * enemigos.length
            oro += ganado
            oleadaSuperada(oleada)

            oleadasDesdeCofre += 1
            if (oleadasDesdeCofre >= oleadasPorCofre) {
                oleadasDesdeCofre = 0
                cofres += 1
            }

            oleada += 1
            generarOleada()
            guardar()
        } else if (!grupo.some(function (h) { return h.vida > 0 })) {
            terminarPartida()
        }
    }

    function primerVivo(lista) {
        for (let i = 0; i < lista.length; ++i) {
            if (lista[i].vida > 0)
                return i
        }
        return -1
    }

    function masHerido(g) {
        let peor = -1, ratio = 1
        for (let i = 0; i < g.length; ++i) {
            if (g[i].vida <= 0)
                continue
            const r = g[i].vida / vidaMaxDe(g[i])
            if (r < ratio) { ratio = r; peor = i }
        }
        return ratio < 0.98 ? peor : -1
    }

    // ── habilidades ───────────────────────────────────────────────
    function habilidadLista(i) {
        return viva && grupo[i] && grupo[i].vida > 0 && grupo[i].recargaRestante <= 0
    }

    function lanzar(i) {
        if (!habilidadLista(i))
            return

        const g = grupo.slice()
        const e = enemigos.slice()
        lanzarInterno(g, e, i)
        grupo = g
        enemigos = e
    }

    function lanzarInterno(g, e, i) {
        const c = claseDe(g[i].clase)

        if (c.id === "tanque") {
            g[i].provocando = 6
        } else if (c.id === "mago") {
            const daño = c.daño * multDaño * 6
            for (let j = 0; j < e.length; ++j) {
                if (e[j].vida <= 0)
                    continue
                e[j].vida -= daño
                impacto(j, daño)
                if (e[j].vida <= 0)
                    enemigoMuerto(j)
            }
        } else if (c.id === "clerigo") {
            for (let j = 0; j < g.length; ++j) {
                if (g[j].vida <= 0)
                    continue
                const cura = vidaMaxDe(g[j]) * 0.35
                g[j].vida = Math.min(vidaMaxDe(g[j]), g[j].vida + cura)
                curado(j, cura)
            }
        }

        g[i].recargaRestante = c.recarga
        habilidadLanzada(i)
    }

    Timer {
        interval: game.tickMs
        repeat: true
        running: game.cargado && game.viva
        onTriggered: {
            const t = game.ahora()
            const delta = Math.max(0, Math.min(5, t - game.ultimoTick))
            game.ultimoTick = t
            game.tic(delta)
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: game.cargado
        onTriggered: game.guardar()
    }

    // ── con la barra cerrada ──────────────────────────────────────
    // La partida no avanza sin mirar —moriría sin que la vieras— pero sí caen
    // cofres con el tiempo: es lo que da sentido a volver.
    function recuperarOffline(desde) {
        const transcurrido = Math.min(topeOfflineSegundos, Math.max(0, ahora() - desde))
        if (transcurrido < segundosPorCofre)
            return null

        const ganados = Math.floor(transcurrido / segundosPorCofre)
        cofres += ganados

        return {
            segundos: Math.floor(transcurrido),
            cofres: ganados,
            tope: transcurrido >= topeOfflineSegundos
        }
    }

    // ── persistencia ──────────────────────────────────────────────
    readonly property string ruta: Quickshell.env("HOME") + "/.local/state/k4/partida.json"

    function ahora() { return Date.now() / 1000 }

    function instantanea() {
        return JSON.stringify({
            version: 2,
            oleada: oleada, oro: oro, niveles: niveles,
            grupo: grupo, enemigos: enemigos, viva: viva,
            cofres: cofres, reliquias: reliquias,
            mejorOleada: mejorOleada, partidas: partidas,
            oleadasDesdeCofre: oleadasDesdeCofre,
            guardadoEn: ahora()
        }, null, 1)
    }

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

    // Escritura atómica: temporal y renombrado. Y nunca se corta una a medias
    // para empezar otra, que dejaba el .tmp huérfano.
    Process {
        id: escritor
        command: ["sh", "-c",
            "cat > '" + game.ruta + ".tmp' && mv -f '" + game.ruta + ".tmp' '" + game.ruta + "'"]
        stdinEnabled: true

        onStarted: {
            write(game.pendiente)
            stdinEnabled = false
        }

        onExited: {
            stdinEnabled = true
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
                s = null
            }
        }

        // el formato viejo (clicker de zonas) no se migra: era otro juego
        if (s && s.version === 2) {
            oleada = s.oleada || 1
            oro = s.oro || 0
            niveles = s.niveles || ({ ataque: 0, vitalidad: 0, armadura: 0 })
            grupo = s.grupo || []
            enemigos = s.enemigos || []
            viva = s.viva === true && grupo.length > 0
            cofres = s.cofres || 0
            reliquias = s.reliquias || 0
            mejorOleada = s.mejorOleada || 0
            partidas = s.partidas || 0
            oleadasDesdeCofre = s.oleadasDesdeCofre || 0
        }

        ultimoTick = ahora()
        cargado = true

        if (s && s.guardadoEn)
            resumenOffline = recuperarOffline(s.guardadoEn)

        if (!viva && grupo.length === 0)
            nuevaPartida()
    }

    // ── formato ───────────────────────────────────────────────────
    readonly property var sufijos: ["", "K", "M", "B", "T", "aa", "ab", "ac", "ad"]

    function cifra(n) {
        if (!isFinite(n))
            return "∞"
        if (n < 1000)
            return String(Math.max(0, Math.floor(n)))

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
