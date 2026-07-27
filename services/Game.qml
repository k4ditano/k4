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
    readonly property real enemigoVidaBase: 48
    readonly property real enemigoVidaCrec: 1.115
    readonly property real enemigoDañoBase: 3.2
    readonly property real enemigoDañoCrec: 1.07
    readonly property real oroBase: 11
    readonly property real oroCrec: 1.15
    // Por encima del crecimiento del oro a propósito: si comprar diera daño al
    // mismo ritmo al que crece la vida enemiga, quien se pusiera por delante una
    // vez no volvería a quedarse atrás nunca —medido: llegaba a la oleada 3500—.
    // Así cada oleada se pierde algo de terreno y el muro siempre acaba llegando.
    readonly property real costeCrec: 1.24
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
            vida: 300, daño: 4, armadura: 6, papel: "Aguanta los golpes",
            ataque: "Mandoble", glifo: 0xF0498,
            // Cada nivel sube lo suyo: el guardián gana sobre todo aguante.
            porNivel: { vida: 0.11, daño: 0.06, armadura: 0.6 },
            habilidades: [
                { nivel: 1,  id: "provocar",  nombre: "Provocar",
                  desc: "Atrae los golpes y reduce el daño 6 s", recarga: 18, glifo: 0xF0498 },
                { nivel: 5,  id: "muro",      nombre: "Muro de escudos",
                  desc: "Escudo para todo el grupo", recarga: 26, glifo: 0xF0A38 },
                { nivel: 12, id: "represalia", nombre: "Represalia",
                  desc: "Devuelve parte del daño recibido", recarga: 22, glifo: 0xF04E5 },
                { nivel: 20, id: "bastion",   nombre: "Bastión",
                  desc: "Inmune unos segundos", recarga: 40, glifo: 0xF0498 }
            ]
        },
        {
            id: "mago", nombre: "Hechicero", sprite: "h02",
            vida: 130, daño: 12, armadura: 0, papel: "Daño en área",
            ataque: "Dardo arcano", glifo: 0xF0E20,
            porNivel: { vida: 0.06, daño: 0.13, armadura: 0.1 },
            habilidades: [
                { nivel: 1,  id: "llamarada", nombre: "Llamarada",
                  desc: "Golpea a toda la oleada", recarga: 14, glifo: 0xF0E20 },
                { nivel: 6,  id: "cadena",    nombre: "Cadena arcana",
                  desc: "Rebota entre enemigos, más fuerte cada salto", recarga: 18, glifo: 0xF0593 },
                { nivel: 14, id: "meteoro",   nombre: "Meteoro",
                  desc: "Un golpe enorme al más sano", recarga: 30, glifo: 0xF0F1B },
                { nivel: 22, id: "quietud",   nombre: "Quietud",
                  desc: "La oleada deja de atacar 5 s", recarga: 45, glifo: 0xF04AB }
            ]
        },
        {
            id: "clerigo", nombre: "Clériga", sprite: "h04",
            vida: 190, daño: 5, armadura: 3, papel: "Cura al grupo",
            ataque: "Fulgor", glifo: 0xF05E1,
            porNivel: { vida: 0.09, daño: 0.07, armadura: 0.35 },
            habilidades: [
                { nivel: 1,  id: "bendicion", nombre: "Bendición",
                  desc: "Cura a todo el grupo de golpe", recarga: 22, glifo: 0xF05E1 },
                { nivel: 7,  id: "egida",     nombre: "Égida",
                  desc: "Escudo al más malherido", recarga: 20, glifo: 0xF0A38 },
                { nivel: 15, id: "renovar",   nombre: "Renovación",
                  desc: "Cura poco a poco durante 10 s", recarga: 28, glifo: 0xF058C },
                { nivel: 24, id: "volver",    nombre: "Volver a la vida",
                  desc: "Levanta a un caído con media vida", recarga: 90, glifo: 0xF05E1 }
            ]
        }
    ]

    // El oro dejó de comprar estadísticas —subirlas a mano no era una decisión,
    // era un peaje— y ahora compra cofres: qué te llevas, no cuánto pegas.
    readonly property var tiendaDef: [
        { tipo: 0, nombre: "Cofre corriente", base: 120,  glifo: 0xF04D6 },
        { tipo: 1, nombre: "Cofre de jefe",   base: 900,  glifo: 0xF04D7 },
        { tipo: 2, nombre: "Cofre de acto",   base: 6500, glifo: 0xF0A75 }
    ]

    property var comprados: [0, 0, 0]

    function costeCofre(tipo) {
        return Math.ceil(tiendaDef[tipo].base * Math.pow(1.55, comprados[tipo]))
    }

    function comprarCofre(tipo) {
        const precio = costeCofre(tipo)
        if (oro < precio)
            return false

        oro -= precio
        const c = comprados.slice()
        c[tipo] += 1
        comprados = c
        sumarCofre(tipo)
        guardar()
        return true
    }

    // ── equipo y bolsa ────────────────────────────────────────────
    // Persisten entre partidas: es lo que hace que la siguiente llegue más
    // lejos. Lo que se pierde al morir es el oro y las mejoras de la partida.
    // Nivel y experiencia por clase, PERMANENTES: sobreviven a la muerte igual
    // que el equipo. Si se reiniciaran, farmear no serviría de nada y cada
    // partida acabaría exactamente donde la anterior.
    property var heroes: ({})           // clase → { nivel, exp }

    function datosHeroe(clase) {
        return heroes[clase] || ({ nivel: 1, exp: 0 })
    }

    // ── puntos de partida ─────────────────────────────────────────
    // Cada bioma superado abre un punto donde empezar. Con el grupo ya subido
    // no tiene sentido rehacer ochenta oleadas que ya no ofrecen nada.
    property int inicioElegido: 1

    readonly property var iniciosDisponibles: {
        const lista = [1]
        for (let i = 1; i * oleadasPorBioma <= mejorOleada; ++i)
            lista.push(i * oleadasPorBioma + 1)
        return lista
    }

    function elegirInicio(oleadaInicio) {
        if (iniciosDisponibles.indexOf(oleadaInicio) === -1)
            return
        inicioElegido = oleadaInicio
        guardar()
    }

    property var equipo: ({})           // clase → { hueco: objeto }
    property var bolsa: []              // objetos sin equipar
    property var cofresPorTipo: [0, 0, 0]
    property var meta: ({ vida: 0, daño: 0, fortuna: 0 })
    readonly property int topeBolsa: 60

    readonly property var metaDef: [
        { id: "vida",    nombre: "Linaje robusto", desc: "+8% vida del grupo",     base: 40, glifo: 0xF1076 },
        { id: "daño",    nombre: "Filo ancestral", desc: "+8% daño del grupo",     base: 40, glifo: 0xF04E5 },
        { id: "fortuna", nombre: "Fortuna",        desc: "Mejores rarezas",        base: 60, glifo: 0xF0BC2 }
    ]

    readonly property real metaMultVida: Math.pow(1.08, meta.vida)
    readonly property real metaMultDaño: Math.pow(1.08, meta.daño)
    readonly property real fortuna: meta.fortuna * 0.03

    function costeMeta(id) {
        for (let i = 0; i < metaDef.length; ++i) {
            if (metaDef[i].id === id)
                return Math.ceil(metaDef[i].base * Math.pow(1.6, meta[id]))
        }
        return Infinity
    }

    function comprarMeta(id) {
        const precio = costeMeta(id)
        if (reliquias < precio)
            return false
        reliquias -= precio
        const copia = Object.assign({}, meta)
        copia[id] = copia[id] + 1
        meta = copia
        guardar()
        return true
    }

    // ── experiencia ───────────────────────────────────────────────
    // Sustituye a las mejoras compradas con oro: los héroes suben solos
    // matando, y al subir aprenden. El oro pasa a comprar cofres, que es
    // decidir qué te llevas y no cuánta vida tienes.
    readonly property real expBase: 46
    readonly property real expCrec: 1.19

    function expParaNivel(nivel) {
        return Math.ceil(expBase * Math.pow(expCrec, nivel - 1))
    }

    function habilidadesDe(heroe) {
        const c = claseDe(heroe.clase)
        const nivel = heroe.nivel || 1
        return c.habilidades.filter(function (h) { return nivel >= h.nivel })
    }

    function proximaHabilidad(clase, nivel) {
        const c = claseDe(clase)
        for (let i = 0; i < c.habilidades.length; ++i) {
            if (c.habilidades[i].nivel > nivel)
                return c.habilidades[i]
        }
        return null
    }

    // Reparte sobre el array que se le pasa, no sobre `grupo`.
    //
    // Llamar aquí a `grupo = …` en mitad de un tic no servía de nada: el tic
    // trabaja con su propia copia y al terminar la reasigna entera, tirando
    // por la borda la experiencia recién dada. Nadie subía de nivel.
    function aplicarExp(g, cantidad) {
        let subio = false

        for (let i = 0; i < g.length; ++i) {
            if (g[i].vida <= 0)
                continue                // los caídos no aprenden

            g[i].exp = (g[i].exp || 0) + cantidad
            while (g[i].exp >= expParaNivel(g[i].nivel || 1)) {
                g[i].exp -= expParaNivel(g[i].nivel || 1)
                g[i].nivel = (g[i].nivel || 1) + 1
                subio = true
                // subir de nivel cura lo proporcional a lo que crece la vida
                g[i].vida = Math.min(vidaMaxDe(g[i]), g[i].vida * 1.11)
                subioNivel(i, g[i].nivel)
            }
        }

        if (subio)
            anotarHeroes(g)

        return subio
    }

    // Vuelca nivel y experiencia del grupo en curso a lo permanente.
    function anotarHeroes(g) {
        const h = Object.assign({}, heroes)
        for (let i = 0; i < g.length; ++i)
            h[g[i].clase] = { nivel: g[i].nivel, exp: g[i].exp }
        heroes = h
    }

    function darExperiencia(cantidad) {
        const g = clonar(grupo)
        if (aplicarExp(g, cantidad))
            guardar()
        grupo = g
    }

    // ── estado de la partida ──────────────────────────────────────
    property int oleada: 1
    property real oro: 0
    property var grupo: []              // héroes vivos o caídos de esta partida
    property var enemigos: []
    property bool viva: false           // ¿hay partida en curso?
    property string finalizada: ""      // texto del resumen al morir

    // ── permanente ────────────────────────────────────────────────
    readonly property int cofres: cofresPorTipo[0] + cofresPorTipo[1] + cofresPorTipo[2]
    property real reliquias: 0
    property int mejorOleada: 0
    property int partidas: 0
    property int oleadasDesdeCofre: 0

    property real ultimoTick: 0
    property bool cargado: false
    property var resumenOffline: null

    // ── derivados ─────────────────────────────────────────────────
    // Pausa: el combate corre siempre, pero a veces uno quiere mirar el
    // inventario con calma o dejar de perder héroes.
    property bool pausada: false

    // ── biomas ────────────────────────────────────────────────────
    // Cada 80 oleadas cambia el escenario y con él la fauna. Los monstruos no
    // son sheets distintas: se reparte la que hay por afinidad, que da variedad
    // temática sin generar arte nuevo por bioma.
    readonly property int oleadasPorBioma: 80
    readonly property var biomas: ["bosque", "cueva", "infierno", "cosmos"]
    readonly property var faunaPorBioma: [
        [0, 3, 10, 13, 16, 14, 2],      // bosque: limos, mariposa, jabalí, seta…
        [6, 9, 8, 19, 11, 18, 1],       // cueva: araña, murciélago, rata, goblin…
        [12, 15, 5, 2, 19, 6],          // infierno: diablillo, limos ardientes…
        [7, 4, 17, 5, 18, 9]            // cosmos: fantasma, esqueleto, zombi…
    ]

    readonly property int bioma: Math.floor((oleada - 1) / oleadasPorBioma) % biomas.length
    readonly property string fondo: biomas[bioma]

    readonly property bool esJefe: oleada % oleadasPorJefe === 0
    readonly property bool grupoVivo: grupo.some(function (h) { return h.vida > 0 })

    // Estadísticas finales de un héroe: su clase, más lo que lleve puesto,
    // más las mejoras permanentes, más las de esta partida.
    function statsDe(heroe) {
        const c = claseDe(heroe.clase)
        const eq = equipo[heroe.clase] || ({})

        // lo que da el nivel: compuesto, distinto para cada clase
        const nivel = (heroe.nivel || 1) - 1
        const p = c.porNivel

        let daño = c.daño * Math.pow(1 + p.daño, nivel)
        let vida = c.vida * Math.pow(1 + p.vida, nivel)
        let armadura = c.armadura + p.armadura * nivel
        let cura = (c.id === "clerigo" ? 5 : 0) * Math.pow(1 + p.vida, nivel)

        const huecos = ["arma", "escudo", "armadura", "amuleto"]
        for (let i = 0; i < huecos.length; ++i) {
            const it = eq[huecos[i]]
            if (!it)
                continue
            daño += it.stats.daño || 0
            vida += it.stats.vida || 0
            armadura += it.stats.armadura || 0
            cura += it.stats.cura || 0
        }

        return {
            daño: daño * metaMultDaño,
            vida: Math.round(vida * metaMultVida),
            armadura: armadura,
            cura: cura
        }
    }

    function vidaMaxDe(heroe) {
        return statsDe(heroe).vida
    }

    // ── equipar y desguazar ───────────────────────────────────────
    function puedeEquipar(objeto, claseId) {
        if (!objeto)
            return false
        return datosHeroe(claseId).nivel >= Items.nivelRequerido(objeto)
    }

    // A quién le vale de los tres, para avisar en la bolsa sin abrir fichas
    function algunoPuede(objeto) {
        for (let i = 0; i < clases.length; ++i) {
            if (puedeEquipar(objeto, clases[i].id))
                return true
        }
        return false
    }

    function equipar(objeto, claseId) {
        if (!objeto || !puedeEquipar(objeto, claseId))
            return

        const eq = Object.assign({}, equipo)
        const actual = Object.assign({}, eq[claseId] || ({}))
        const anterior = actual[objeto.hueco] || null

        actual[objeto.hueco] = objeto
        eq[claseId] = actual
        equipo = eq

        // fuera de la bolsa lo nuevo, dentro lo que llevaba puesto
        const b = bolsa.filter(function (x) { return x.id !== objeto.id })
        if (anterior)
            b.push(anterior)
        bolsa = b

        recalcularVidas()
        guardar()
    }

    function quitar(claseId, hueco) {
        const eq = Object.assign({}, equipo)
        const actual = Object.assign({}, eq[claseId] || ({}))
        const objeto = actual[hueco]
        if (!objeto)
            return

        delete actual[hueco]
        eq[claseId] = actual
        equipo = eq
        bolsa = bolsa.concat([objeto])

        recalcularVidas()
        guardar()
    }

    // Reordenar la bolsa a mano. El orden es el del array, así que moverlo es
    // sacar y volver a insertar; se guarda para que sobreviva al reinicio.
    function moverEnBolsa(desde, hasta) {
        if (desde === hasta || desde < 0 || hasta < 0
            || desde >= bolsa.length || hasta >= bolsa.length)
            return

        const lista = bolsa.slice()
        const pieza = lista.splice(desde, 1)[0]
        lista.splice(hasta, 0, pieza)
        bolsa = lista
        guardar()
    }

    function desguazar(objeto) {
        if (!objeto)
            return
        reliquias += Items.valorDesguace(objeto)
        bolsa = bolsa.filter(function (x) { return x.id !== objeto.id })
        guardar()
    }

    // Desguaza de golpe todo lo que no supere a lo equipado. Con la bolsa
    // llena de piezas comunes, ir una a una es insufrible.
    function desguazarSobrantes() {
        let ganado = 0
        const quedan = []

        for (let i = 0; i < bolsa.length; ++i) {
            const it = bolsa[i]
            let mejorQueAlguno = false

            for (let c = 0; c < clases.length; ++c) {
                const puesto = (equipo[clases[c].id] || ({}))[it.hueco]
                if (!puesto || Items.puntuacion(it) > Items.puntuacion(puesto)) {
                    mejorQueAlguno = true
                    break
                }
            }

            if (mejorQueAlguno)
                quedan.push(it)
            else
                ganado += Items.valorDesguace(it)
        }

        bolsa = quedan
        reliquias += ganado
        guardar()
        return ganado
    }

    // Al cambiar el equipo la vida máxima cambia; se conserva la proporción
    // para que ponerse una coraza no cure ni mate a nadie.
    function recalcularVidas() {
        const g = clonar(grupo)
        for (let i = 0; i < g.length; ++i) {
            if (g[i].vida <= 0)
                continue
            const max = vidaMaxDe(g[i])
            g[i].vida = Math.min(max, Math.max(1, g[i].vida))
        }
        grupo = g
    }

    // ── cofres ────────────────────────────────────────────────────
    function abrirCofre(tipo) {
        if (cofresPorTipo[tipo] <= 0)
            return null

        const c = cofresPorTipo.slice()
        c[tipo] -= 1
        cofresPorTipo = c

        const objeto = Items.generar(tipo, Math.max(oleada, mejorOleada), fortuna)

        if (bolsa.length >= topeBolsa) {
            // bolsa llena: se desguaza solo, mejor eso que perderlo sin más
            reliquias += Items.valorDesguace(objeto)
        } else {
            bolsa = bolsa.concat([objeto])
        }

        guardar()
        return objeto
    }

    function sumarCofre(tipo) {
        const c = cofresPorTipo.slice()
        c[tipo] += 1
        cofresPorTipo = c
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
    signal subioNivel(int indiceHeroe, int nivel)
    signal escudoPuesto(int indiceHeroe)

    // ── ciclo de partida ──────────────────────────────────────────
    function nuevaPartida() {
        relevoEn = 0
        oleada = Math.max(1, Math.min(inicioElegido,
            iniciosDisponibles[iniciosDisponibles.length - 1]))
        oro = 0
        comprados = [0, 0, 0]
        oleadasDesdeCofre = 0
        finalizada = ""

        const g = []
        for (let i = 0; i < clases.length; ++i) {
            const c = clases[i]
            const recargas = ({})
            for (let h = 0; h < c.habilidades.length; ++h)
                recargas[c.habilidades[h].id] = c.habilidades[h].recarga

            const guardado = datosHeroe(c.id)

            g.push({
                clase: c.id,
                vida: 0,
                nivel: guardado.nivel || 1,
                exp: guardado.exp || 0,
                escudo: 0,              // absorbe antes que la vida
                recargas: recargas,
                provocando: 0,
                reflejando: 0,
                invulnerable: 0,
                regenerando: 0
            })
        }
        grupo = g

        // la vida sale de statsDe, que necesita el grupo ya asignado
        const conVida = clonar(grupo)
        for (let i = 0; i < conVida.length; ++i)
            conVida[i].vida = vidaMaxDe(conVida[i])
        grupo = conVida

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
                    : "m" + String(faunaPorBioma[bioma][(oleada * 3 + i) % faunaPorBioma[bioma].length])
                        .padStart(2, "0"),
                jefe: esJefe,
                quieto: 0
            })
        }
        enemigos = lista
    }

    // Segundos que se queda el resumen antes de arrancar sola la siguiente.
    readonly property int segundosRelevo: 20
    property real relevoEn: 0
    readonly property int relevoRestante: relevoEn > 0 ? Math.max(0, Math.ceil(relevoEn - ahora())) : 0

    function terminarPartida() {
        viva = false
        partidas += 1

        const ganadosCofres = Math.max(1, Math.floor(oleada / 12))
        const ganadasReliquias = Math.floor(Math.pow(oleada, 1.45))

        for (let i = 0; i < ganadosCofres; ++i)
            sumarCofre(oleada >= 30 ? 1 : 0)
        reliquias += ganadasReliquias
        if (oleada > mejorOleada)
            mejorOleada = oleada

        finalizada = "Has caído en la oleada " + oleada
        // El combate corre siempre, mires o no: si la partida se quedara
        // muerta esperándote, cada vez que abrieras la barra encontrarías
        // horas tiradas. Se encadena sola, y el resumen se queda un rato por
        // si estabas delante.
        // solo si lo has dejado activado en Ajustes
        relevoEn = Settings.juegoContinuar ? ahora() + segundosRelevo : 0
        partidaTerminada(oleada, ganadosCofres, ganadasReliquias)
        guardar()
    }

    // ── combate ───────────────────────────────────────────────────
    // Un tic por segundo: suficiente para que se vea vivo y ridículo en coste.
    function tic(delta) {
        if (!viva || !cargado || pausada)
            return

        const g = clonar(grupo)
        const e = clonar(enemigos)

        let objetivoForzado = -1
        for (let i = 0; i < g.length; ++i) {
            // los estados temporales corren aunque el héroe no actúe
            for (const estado of ["provocando", "reflejando", "invulnerable", "regenerando"]) {
                if (g[i][estado] > 0) {
                    g[i][estado] -= delta
                    if (estado === "provocando")
                        objetivoForzado = i
                }
            }
            if (g[i].regenerando > 0 && g[i].vida > 0)
                g[i].vida = Math.min(vidaMaxDe(g[i]), g[i].vida + statsDe(g[i]).cura * 1.2 * delta)
        }

        // ── golpean los héroes
        for (let i = 0; i < g.length; ++i) {
            if (g[i].vida <= 0)
                continue

            const c = claseDe(g[i].clase)
            const st = statsDe(g[i])
            const blanco = primerVivo(e)

            if (blanco >= 0) {
                e[blanco].vida -= st.daño * delta
                impacto(blanco, st.daño * delta)
                if (e[blanco].vida <= 0) {
                    enemigoMuerto(blanco)
                    aplicarExp(g, Math.ceil(8 * Math.pow(1.11, oleada - 1)))
                }
            }

            if (st.cura > 0) {
                const herido = masHerido(g)
                if (herido >= 0) {
                    const cura = st.cura * delta
                    g[herido].vida = Math.min(vidaMaxDe(g[herido]), g[herido].vida + cura)
                    curado(herido, cura)
                }
            }

            // cada habilidad desbloqueada lleva su propia recarga
            const suyas = habilidadesDe(g[i])
            for (let h = 0; h < suyas.length; ++h) {
                const id = suyas[h].id
                if (g[i].recargas[id] === undefined)
                    g[i].recargas[id] = suyas[h].recarga

                if (g[i].recargas[id] > 0) {
                    g[i].recargas[id] -= delta
                } else {
                    lanzarInterno(g, e, i, id)
                }
            }
        }

        // ── pegan los enemigos
        for (let j = 0; j < e.length; ++j) {
            if (e[j].vida <= 0 || e[j].quieto > 0) {
                if (e[j].quieto > 0)
                    e[j].quieto -= delta
                continue
            }

            let blanco = objetivoForzado >= 0 && g[objetivoForzado].vida > 0
                ? objetivoForzado : primerVivo(g)
            if (blanco < 0)
                break

            if (g[blanco].invulnerable > 0)
                continue

            // La armadura reduce un porcentaje, no resta una cantidad fija.
            // Restando, seis de armadura contra enemigos de tres dejaba las
            // primeras veinte oleadas en cero daño: sin tensión y con la
            // pantalla llena de "-0".
            const armadura = statsDe(g[blanco]).armadura + (g[blanco].provocando > 0 ? 12 : 0)
            const reduccion = 100 / (100 + armadura * 4)
            let recibido = e[j].daño * delta * reduccion

            // el escudo se lleva el golpe antes que la vida
            if (g[blanco].escudo > 0) {
                const absorbido = Math.min(g[blanco].escudo, recibido)
                g[blanco].escudo -= absorbido
                recibido -= absorbido
            }

            g[blanco].vida -= recibido
            heroeHerido(blanco, recibido)

            // represalia: parte del golpe vuelve a quien lo dio
            if (g[blanco].reflejando > 0) {
                const vuelta = recibido * 1.5
                e[j].vida -= vuelta
                impacto(j, vuelta)
                if (e[j].vida <= 0) {
                    enemigoMuerto(j)
                    aplicarExp(g, Math.ceil(8 * Math.pow(1.11, oleada - 1)))
                }
            }
        }

        grupo = g
        enemigos = e

        if (!enemigos.some(function (x) { return x.vida > 0 })) {
            const ganado = oroBase * Math.pow(oroCrec, oleada - 1) * enemigos.length
            oro += ganado
            oleadaSuperada(oleada)

            oleadasDesdeCofre += 1
            if (oleadasDesdeCofre >= oleadasPorCofre) {
                oleadasDesdeCofre = 0
                sumarCofre(0)
            }
            if (esJefe)
                sumarCofre(1)
            if (oleada % 50 === 0)
                sumarCofre(2)

            oleada += 1
            generarOleada()
            guardar()
        } else if (!grupo.some(function (h) { return h.vida > 0 })) {
            terminarPartida()
        }
    }

    // Copia con objetos nuevos, no solo el array.
    //
    // Con slice() el array cambia de identidad pero los objetos de dentro son
    // los mismos, y una vista que lea `lista[i]` recibe la misma referencia:
    // QML da la propiedad por no cambiada, no emite señal y las barras se
    // quedan congeladas. Clonando cada elemento, cualquier binding se entera.
    function clonar(lista) {
        const salida = []
        for (let i = 0; i < lista.length; ++i)
            salida.push(Object.assign({}, lista[i]))
        return salida
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
    function habilidadLista(i, id) {
        if (!viva || !grupo[i] || grupo[i].vida <= 0)
            return false
        return (grupo[i].recargas[id] || 0) <= 0
    }

    function lanzar(i, id) {
        if (!habilidadLista(i, id))
            return

        const g = clonar(grupo)
        const e = clonar(enemigos)
        lanzarInterno(g, e, i, id)
        grupo = g
        enemigos = e
    }

    function recargaDe(clase, id) {
        const c = claseDe(clase)
        for (let i = 0; i < c.habilidades.length; ++i) {
            if (c.habilidades[i].id === id)
                return c.habilidades[i].recarga
        }
        return 20
    }

    function lanzarInterno(g, e, i, id) {
        const st = statsDe(g[i])

        if (id === "provocar") {
            g[i].provocando = 6

        } else if (id === "muro") {
            // escudo para todo el grupo, proporcional a lo que aguanta quien lo pone
            for (let j = 0; j < g.length; ++j) {
                if (g[j].vida <= 0)
                    continue
                g[j].escudo = (g[j].escudo || 0) + vidaMaxDe(g[i]) * 0.22
                escudoPuesto(j)
            }

        } else if (id === "represalia") {
            g[i].reflejando = 8

        } else if (id === "bastion") {
            g[i].invulnerable = 5

        } else if (id === "llamarada") {
            for (let j = 0; j < e.length; ++j) {
                if (e[j].vida <= 0)
                    continue
                e[j].vida -= st.daño * 6
                impacto(j, st.daño * 6)
                if (e[j].vida <= 0) enemigoMuerto(j)
            }

        } else if (id === "cadena") {
            // rebota y crece: premia que haya oleada llena
            let golpe = st.daño * 3
            for (let j = 0; j < e.length; ++j) {
                if (e[j].vida <= 0)
                    continue
                e[j].vida -= golpe
                impacto(j, golpe)
                if (e[j].vida <= 0) enemigoMuerto(j)
                golpe *= 1.6
            }

        } else if (id === "meteoro") {
            let masSano = -1, mejor = -1
            for (let j = 0; j < e.length; ++j) {
                if (e[j].vida > mejor) { mejor = e[j].vida; masSano = j }
            }
            if (masSano >= 0) {
                e[masSano].vida -= st.daño * 16
                impacto(masSano, st.daño * 16)
                if (e[masSano].vida <= 0) enemigoMuerto(masSano)
            }

        } else if (id === "quietud") {
            for (let j = 0; j < e.length; ++j)
                e[j].quieto = 5

        } else if (id === "bendicion") {
            for (let j = 0; j < g.length; ++j) {
                if (g[j].vida <= 0)
                    continue
                const cura = vidaMaxDe(g[j]) * 0.35
                g[j].vida = Math.min(vidaMaxDe(g[j]), g[j].vida + cura)
                curado(j, cura)
            }

        } else if (id === "egida") {
            const herido = masHerido(g)
            const quien = herido >= 0 ? herido : i
            g[quien].escudo = (g[quien].escudo || 0) + vidaMaxDe(g[quien]) * 0.45
            escudoPuesto(quien)

        } else if (id === "renovar") {
            for (let j = 0; j < g.length; ++j) {
                if (g[j].vida > 0)
                    g[j].regenerando = 10
            }

        } else if (id === "volver") {
            for (let j = 0; j < g.length; ++j) {
                if (g[j].vida <= 0) {
                    g[j].vida = vidaMaxDe(g[j]) * 0.5
                    curado(j, g[j].vida)
                    break
                }
            }
        }

        g[i].recargas[id] = recargaDe(g[i].clase, id)
        habilidadLanzada(i)
    }

    Timer {
        interval: game.tickMs
        repeat: true
        running: game.cargado && game.viva && !game.pausada
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

    // Reloj del relevo: el del combate se detiene al morir el grupo, así que
    // hace falta uno aparte que no dependa de `viva`.
    Timer {
        interval: 1000
        repeat: true
        running: game.cargado && !game.viva && game.relevoEn > 0 && Settings.juegoContinuar
        onTriggered: {
            if (game.ahora() >= game.relevoEn)
                game.nuevaPartida()
        }
    }

    // ── con la barra cerrada ──────────────────────────────────────
    // La partida no avanza sin mirar —moriría sin que la vieras— pero sí caen
    // cofres con el tiempo: es lo que da sentido a volver.
    function recuperarOffline(desde) {
        const transcurrido = Math.min(topeOfflineSegundos, Math.max(0, ahora() - desde))
        if (transcurrido < segundosPorCofre)
            return null

        const ganados = Math.floor(transcurrido / segundosPorCofre)
        for (let i = 0; i < ganados; ++i)
            sumarCofre(0)

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
            oleada: oleada, oro: oro,
            grupo: grupo, enemigos: enemigos, viva: viva, comprados: comprados,
            finalizada: finalizada, relevoEn: relevoEn,
            cofresPorTipo: cofresPorTipo, reliquias: reliquias,
            equipo: equipo, bolsa: bolsa, meta: meta,
            heroes: heroes, inicioElegido: inicioElegido,
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
            grupo = s.grupo || []
            enemigos = s.enemigos || []
            viva = s.viva === true && grupo.length > 0
            cofresPorTipo = s.cofresPorTipo || [0, 0, 0]
            reliquias = s.reliquias || 0
            equipo = s.equipo || ({})
            bolsa = s.bolsa || []
            meta = s.meta || ({ vida: 0, daño: 0, fortuna: 0 })
            heroes = s.heroes || ({})
            inicioElegido = s.inicioElegido || 1
            mejorOleada = s.mejorOleada || 0
            partidas = s.partidas || 0
            oleadasDesdeCofre = s.oleadasDesdeCofre || 0
            comprados = s.comprados || [0, 0, 0]
            finalizada = s.finalizada || ""
            relevoEn = s.relevoEn || 0
        }

        // Una partida terminada tiene que decirlo. Sin esto el tablero se
        // queda congelado —héroes en gris, sin cartel y sin botón— porque el
        // cartel de fin solo sale si hay texto que enseñar.
        if (!viva && grupo.length > 0 && finalizada.length === 0)
            finalizada = "Has caído en la oleada " + oleada

        // Si murió mientras no mirabas —o viene de un guardado anterior al
        // relevo—, se encadena en cuanto te dé tiempo a leer el resumen.
        if (Settings.juegoContinuar && !viva && grupo.length > 0
            && (relevoEn === 0 || ahora() >= relevoEn))
            relevoEn = ahora() + 8

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
