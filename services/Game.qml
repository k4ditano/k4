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

    //  ── por qué estos tres números y no los de antes ──────────────
    //
    //  Se llegaba a la oleada 30 sin hacer nada y en cuatro minutos. No era que
    //  fuese fácil —el muro estaba en la 25-32— sino que no había CUESTA: llano
    //  gratis y de pronto un ladrillo. Medido sobre el modelo de combate, con
    //  las tres palancas separadas, porque hacen cosas distintas:
    //
    //  · La VIDA BASE (48 → 130) alarga cada oleada, que es lo que mata el
    //    rusheo. Y no acerca el muro: se muere por daño recibido, no por
    //    tardar. Con 48, la primera oleada duraba 2 segundos; con 130 dura 6, y
    //    la décima pasa de 18 a 49.
    //
    //  · El CRECIMIENTO DEL DAÑO enemigo (1,095 → 1,072) aleja el muro. Crecía
    //    más rápido que la vida efectiva del grupo (~1,047), y de ahí el final
    //    de golpe en vez de una cuesta que se empina.
    //
    //  · Y la EXPERIENCIA por muerte, abajo, crecía a 1,11 contra el 1,075 de
    //    la vida enemiga. Esa era la causa raíz: cada oleada te hacía
    //    RELATIVAMENTE más fuerte que lo que te tocaba matar, así que el juego
    //    se aceleraba solo. Compuesto sobre treinta oleadas son ×2,6 de ventaja
    //    regalada.
    //
    //  Juntas dejan el muro donde estaba —la 32, o sea el mismo contenido a la
    //  vista— pero tardando 18,6 minutos en vez de 3,9, con la oleada 30 a 92
    //  segundos. La palanca fina para ajustar el ritmo es la vida base.
    readonly property real enemigoVidaBase: 130
    readonly property real enemigoVidaCrec: 1.075
    readonly property real enemigoDañoBase: 3.2
    readonly property real enemigoDañoCrec: 1.072
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
    //  Uno cada cuarto de hora, y AHORA a los dos lados: fuera por el tiempo
    //  que estuvo cerrada y dentro por `goteoPorReloj`. Antes dentro se pagaba
    //  por oleada —`oleadasPorCofre: 5`—, que a cuatro segundos la oleada era
    //  un cofre cada veinte segundos.
    readonly property int segundosPorCofre: 900

    // Segundos que espera una habilidad lista antes de lanzarse sola. Da margen
    // para usarla tú si estás mirando, sin castigarte si no.
    readonly property int autoHabilidad: 5
    // El escudo se apilaba sin freno: en la oleada 40 la clériga acumulaba
    // 38.000 contra bichos que pegaban 120, y no entraba un golpe en toda la
    // partida. Con tope es un colchón, no una armadura de dios.
    readonly property real topeEscudo: 0.6
    // Cuánto se puede llegar a recortar de las recargas con accesorios.
    readonly property real topeRecorte: 0.55

    readonly property var rasgos: GameDatos.rasgos

    // Deterministas a propósito: la misma oleada trae siempre los mismos
    // rasgos, así se puede medir el balance y no depende de la suerte.
    function rasgosPara(ol, indice, afinidad, extra) {
        const posibles = []
        for (let i = 0; i < rasgos.length; ++i) {
            if (ol >= rasgos[i].desde)
                posibles.push(rasgos[i].id)
        }
        if (!posibles.length)
            return []

        const salida = []
        // el suyo por naturaleza va primero, si ya está desbloqueado
        if (afinidad && posibles.indexOf(afinidad) !== -1)
            salida.push(afinidad)

        const cuantos = Math.min(posibles.length,
            1 + Math.floor(ol / 60) + (extra ? 1 : 0))
        for (let i = 0; salida.length < cuantos && i < posibles.length * 2; ++i) {
            const cual = posibles[(ol + indice * 2 + i * 3) % posibles.length]
            if (salida.indexOf(cual) === -1)
                salida.push(cual)
        }
        return salida
    }

    function rasgoDe(id) {
        for (let i = 0; i < rasgos.length; ++i) {
            if (rasgos[i].id === id)
                return rasgos[i]
        }
        return null
    }

    readonly property var defensaDe: GameDatos.defensaDe

    // Lo que de verdad recibe un enemigo: su carne, y encima la coraza si la
    // trae como rasgo.
    function mermar(enemigo, fis, mag) {
        const d = defensaDe[enemigo.defensa || "equilibrada"] || defensaDe.equilibrada
        let total = (fis || 0) * d.fis + (mag || 0) * d.mag
        if (enemigo.rasgos && enemigo.rasgos.indexOf("coraza") !== -1)
            total *= 0.62
        return total
    }

    // Reparte una cantidad con la misma mezcla que tenga el héroe, para que
    // una habilidad de un mago pegue como magia sin declararlo una por una.
    function comoPega(st, cantidad) {
        const total = (st.daño || 0) + (st.dañoMag || 0)
        if (total <= 0)
            return { fis: cantidad, mag: 0 }
        const f = st.dañoMag / total
        return { fis: cantidad * (1 - f), mag: cantidad * f }
    }

    // Atajo para los sitios que solo quieren pegar una cantidad.
    function pegarA(enemigo, st, cantidad) {
        const r = comoPega(st, cantidad)
        return mermar(enemigo, r.fis, r.mag)
    }



    readonly property var habilidadesEnemigo: GameDatos.habilidadesEnemigo

    // Una por bicho, la más alta que tenga desbloqueada la oleada. Los jefes
    // van una escalón por delante, como con los rasgos.
    function habilidadEnemigaDe(ol, indice) {
        const posibles = []
        for (let i = 0; i < habilidadesEnemigo.length; ++i) {
            if (ol >= habilidadesEnemigo[i].desde)
                posibles.push(habilidadesEnemigo[i])
        }
        if (!posibles.length)
            return null
        return posibles[(ol + indice) % posibles.length]
    }

    function habEnemigaDe(id) {
        for (let i = 0; i < habilidadesEnemigo.length; ++i) {
            if (habilidadesEnemigo[i].id === id)
                return habilidadesEnemigo[i]
        }
        return null
    }

    readonly property var especies: GameDatos.especies

    readonly property var titulosJefe: GameDatos.titulosJefe
    readonly property var deBioma: GameDatos.deBioma

    // Uno de cada siete sale élite: más duro, con un rasgo de más y con oro
    // extra. Son los que rompen el piloto automático de una oleada.
    function esElite(ol, indice) {
        return ol >= 18 && (ol + indice * 3) % 7 === 0
    }

    readonly property var clases: GameDatos.clases

    readonly property var tiendaDef: GameDatos.tiendaDef

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

    // ── plantilla ─────────────────────────────────────────────────
    // Tres en el campo de entre los desbloqueados. Cambiarla reinicia la
    // partida en curso: no se puede meter a alguien a mitad de una pelea.
    property var plantilla: ["tanque", "mago", "clerigo"]
    property var desbloqueados: ["tanque", "mago", "clerigo"]
    readonly property int huecosPlantilla: 3

    function estaDesbloqueado(clase) { return desbloqueados.indexOf(clase) !== -1 }
    function enPlantilla(clase) { return plantilla.indexOf(clase) !== -1 }

    function alternarEnPlantilla(clase) {
        if (!estaDesbloqueado(clase))
            return

        const lista = plantilla.slice()
        const i = lista.indexOf(clase)

        if (i !== -1) {
            if (lista.length <= 1)
                return              // no se puede salir al campo sin nadie
            lista.splice(i, 1)
        } else {
            if (lista.length >= huecosPlantilla)
                return
            lista.push(clase)
        }

        plantilla = lista
        nuevaPartida()
        guardar()
    }

    function desbloquear(clase) {
        if (estaDesbloqueado(clase))
            return false
        desbloqueados = desbloqueados.concat([clase])
        guardar()
        return true
    }

    // ── cuentas de toda la vida del jugador ───────────────────────
    // Las llevan los logros y los retos de desbloqueo.
    property var cuentas: ({
        muertes: 0, jefes: 0, cofres: 0, oleadas: 0,
        partidas: 0, desguaces: 0, habilidades: 0, oroTotal: 0,
        combinaciones: 0, megajefes: 0
    })

    function contar(clave, cuanto) {
        const c = Object.assign({}, cuentas)
        c[clave] = (c[clave] || 0) + (cuanto === undefined ? 1 : cuanto)
        cuentas = c
    }

    readonly property int nivelMaximo: {
        let alto = 1
        for (const clase in heroes) {
            if (heroes[clase].nivel > alto)
                alto = heroes[clase].nivel
        }
        return alto
    }

    // progreso de un reto de desbloqueo, para pintarlo
    function progresoReto(reto) {
        if (!reto)
            return 1
        if (reto.tipo === "oleada")   return Math.min(1, mejorOleada / reto.meta)
        if (reto.tipo === "muertes")  return Math.min(1, cuentas.muertes / reto.meta)
        if (reto.tipo === "jefes")    return Math.min(1, cuentas.jefes / reto.meta)
        if (reto.tipo === "cofres")   return Math.min(1, cuentas.cofres / reto.meta)
        if (reto.tipo === "nivel")    return Math.min(1, nivelMaximo / reto.meta)
        return 0
    }

    function textoReto(reto) {
        if (!reto)
            return ""
        const cuanto = reto.tipo === "oleada" ? mejorOleada
            : reto.tipo === "nivel" ? nivelMaximo : (cuentas[reto.tipo] || 0)
        const como = { oleada: "llega a la oleada", muertes: "derrota a",
                       jefes: "derrota a", cofres: "abre", nivel: "alcanza el nivel" }
        const que = { muertes: " monstruos", jefes: " jefes", cofres: " cofres" }
        return (como[reto.tipo] || "") + " " + reto.meta + (que[reto.tipo] || "")
            + "  (" + Math.min(cuanto, reto.meta) + "/" + reto.meta + ")"
    }

    // Revisa si algún reto ya está cumplido y desbloquea a quien toque.
    property var logrosHechos: []

    //  ── no se cobra lo que ya estaba hecho antes de empezar ───────
    //
    //  Hay logros que no miden lo que haces en la mazmorra sino lo que ya
    //  habías hecho fuera: los Vibecoder van por los tokens de IA de todo tu
    //  historial y los Constante por tu racha de días. Al empezar un perfil
    //  esos están cumplidos DE ANTES, así que `revisarLogros` los daba todos de
    //  golpe en la oleada 1.
    //
    //  Lo que costaba, medido sobre la partida de este equipo: 2.609 millones
    //  de tokens completan Vibecoder I a IV y Constante I y II, o sea 8.800
    //  reliquias y cuatro cofres antes del primer golpe. Con el altar a 40 de
    //  base y ×1,6 por nivel, eso son DIEZ niveles de una mejora comprables en
    //  la oleada 1: ×2,16 de daño gratis. La partida arrancaba rota y el
    //  jugador no llegaba a tocar el bucle —cero cofres abiertos en toda la
    //  vida de la partida, con treinta y ocho esperando—.
    //
    //  La regla se aplica a TODOS y no solo a esos dos, que es lo que la hace
    //  una regla: un logro que ya se cumple en el momento de estrenar perfil se
    //  marca como hecho y no paga. Los de la mazmorra parten de cero, así que a
    //  ellos no les afecta; lo único que caza son los que miden algo de fuera,
    //  que es exactamente lo que se quería.
    //
    //  Se marcan como hechos y no se esconden a propósito: los tienes, salen en
    //  su panel y cuentan para la colección. Lo que no hacen es financiar una
    //  economía que no se ganaron.
    function sellarLogrosPrevios() {
        const ya = logrosHechos.slice()
        for (let i = 0; i < Logros.definicion.length; ++i) {
            const l = Logros.definicion[i]
            if (ya.indexOf(l.id) === -1 && Logros.progresoDe(l, game) >= 1)
                ya.push(l.id)
        }
        logrosHechos = ya
    }

    // Se revisa tras cada oleada: barato y así la recompensa llega en caliente.
    function revisarLogros() {
        for (let i = 0; i < Logros.definicion.length; ++i) {
            const l = Logros.definicion[i]
            if (logrosHechos.indexOf(l.id) !== -1)
                continue
            if (Logros.progresoDe(l, game) < 1)
                continue

            logrosHechos = logrosHechos.concat([l.id])
            reliquias += l.reliquias
            if (l.cofre >= 0)
                sumarCofre(l.cofre)
            logroConseguido(l.id)
        }
    }

    function revisarDesbloqueos() {
        for (let i = 0; i < clases.length; ++i) {
            const c = clases[i]
            if (!c.reto || estaDesbloqueado(c.id))
                continue
            if (progresoReto(c.reto) >= 1) {
                desbloquear(c.id)
                heroeDesbloqueado(c.id)
            }
        }
    }

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

    readonly property var metaDef: GameDatos.metaDef

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
    //  Lo que suelta un bicho al morir. Crece al MISMO ritmo que su vida
    //  (`enemigoVidaCrec`) y no más rápido, que es lo que hacía a 1,11: con la
    //  exp por delante, cada oleada te dejaba relativamente más fuerte que la
    //  siguiente y la partida se aceleraba sola hasta rushearse. Igualadas, tu
    //  potencia sigue subiendo pero ya no se dispara.
    //
    //  Estaba escrito a pelo en los dos sitios que reparten experiencia —el
    //  golpe y el veneno—, así que se podían separar sin que nadie lo notara.
    readonly property real expPorMuerteBase: 8

    function expPorMuerte() {
        return Math.ceil(expPorMuerteBase * Math.pow(enemigoVidaCrec, oleada - 1))
    }

    readonly property real expBase: 46
    // Sube más rápido a propósito: con los niveles ya permanentes, cada partida
    // empieza donde acabó la anterior y una curva suave dejaba el juego sin
    // muro. Medido: llegaba a la oleada 70 sin despeinarse.
    readonly property real expCrec: 1.27

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

    // ── el megajefe ───────────────────────────────────────────────
    //
    //  Cada 80 oleadas cambia el bioma, y ese salto no estaba marcado con
    //  nada: era una oleada más. Es el sitio natural para un examen de
    //  verdad, porque separa dos tramos del juego.
    //
    //  No es un jefe con más vida. Tiene FASES: al bajar de dos tercios y de
    //  un tercio de vida se recompone, cambia de color y trae refuerzos. Lo
    //  que se mide no es cuánto pegas, es si aguantas tres asaltos.
    readonly property bool esMegajefe: oleada % oleadasPorBioma === 0

    readonly property var megajefes: [
        { nombre: Idioma.t("Ent milenario"),  sprite: "M00", tono: "#7ac74f" },
        { nombre: Idioma.t("Reina de quitina"), sprite: "M01", tono: "#b06cd6" },
        { nombre: Idioma.t("Señor de la fragua"), sprite: "M02", tono: "#ff6b35" },
        { nombre: Idioma.t("Devorador de estrellas"), sprite: "M03", tono: "#6ccce4" }
    ]

    readonly property var megajefeActual: megajefes[
        Math.floor((oleada - 1) / oleadasPorBioma) % megajefes.length]

    // Fase en la que está: 0, 1 o 2. Cada una añade un rasgo y refuerzos.
    property int faseMega: 0
    signal megaFase(int fase)
    signal megaEntra(string nombre)
    signal crisolSoltado()

    // Mucha vida y tres fases; pegar, lo justo. Medido en la oleada 80, con 3,4
    // hacía 14.000 por segundo contra un tanque de 16.000: te fulminaba antes
    // de que llegaras a ver la segunda fase, y un jefe al que no ves las
    // mecánicas es solo una pared.
    // 100 y no 26: medido, el grupo hacía más de 35.000 por segundo y se
    // comía las 378.000 del primer intento en menos de once segundos, sin
    // llegar a ver una sola fase. Un jefe de fases necesita durar.
    readonly property real megaVida: 100     // veces la vida de una oleada normal
    readonly property real megaDaño: 1.9

    // Lo que suelta, aparte del cofre: la ampliación del crisol, y solo a
    // partir del segundo. El primero ya tiene bastante con ser el primero.
    readonly property real probCrisol: 0.35
    readonly property bool grupoVivo: grupo.some(function (h) { return h.vida > 0 })

    // Estadísticas finales de un héroe: su clase, más lo que lleve puesto,
    // más las mejoras permanentes, más las de esta partida.
    function statsDe(heroe) {
        const c = claseDe(heroe.clase)
        const eq = equipo[heroe.clase] || ({})

        // lo que da el nivel: compuesto, distinto para cada clase
        const nivel = (heroe.nivel || 1) - 1
        const p = c.porNivel

        // El daño de la clase se reparte entre físico y mágico según su
        // mezcla; el total no cambia, así que el equilibrio medido sigue
        // valiendo y lo que se añade es contra qué defensa choca cada parte.
        const bruto = c.daño * Math.pow(1 + p.daño, nivel)
        let daño = bruto * (1 - (c.magia || 0))
        let dañoMag = bruto * (c.magia || 0)

        let vida = c.vida * Math.pow(1 + p.vida, nivel)
        let armadura = c.armadura + p.armadura * nivel
        let resistencia = (c.resistencia || 0) + (p.resistencia || 0) * nivel
        let cura = (c.id === "clerigo" ? 5 : 0) * Math.pow(1 + p.vida, nivel)
        let recorte = 0

        const huecos = ["arma", "escudo", "armadura", "amuleto"]
        for (let i = 0; i < huecos.length; ++i) {
            const it = eq[huecos[i]]
            if (!it)
                continue
            daño += it.stats.daño || 0
            dañoMag += it.stats.dañoMag || 0
            vida += it.stats.vida || 0
            armadura += it.stats.armadura || 0
            resistencia += it.stats.resistencia || 0
            cura += it.stats.cura || 0
            recorte += it.stats.recorte || 0
        }

        return {
            daño: daño * metaMultDaño,
            dañoMag: dañoMag * metaMultDaño,
            // lo que pega en total, para las fichas y las habilidades
            total: (daño + dañoMag) * metaMultDaño,
            vida: Math.round(vida * metaMultVida),
            armadura: armadura,
            resistencia: resistencia,
            cura: cura,
            // Con tope: sin él, cuatro accesorios buenos dejarían las
            // habilidades sin recarga y el combate sería un fuego artificial
            // continuo.
            recorte: Math.min(topeRecorte, recorte / 100)
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
    // Reordenar agrupado: el orden de los grupos sale del orden de la bolsa
    // —manda la primera aparición—, así que mover un grupo es sacar todas sus
    // piezas y volver a meterlas donde empieza el grupo de destino.
    function moverGrupo(claveDesde, indiceDestino) {
        const lista = grupos
        if (indiceDestino < 0 || indiceDestino >= lista.length)
            return

        const destino = lista[indiceDestino]
        if (!destino || destino.clave === claveDesde)
            return

        const mueve = bolsa.filter(function (o) { return claveDe(o) === claveDesde })
        if (mueve.length === 0)
            return

        const resto = bolsa.filter(function (o) { return claveDe(o) !== claveDesde })
        // dónde empieza el grupo de destino dentro de lo que queda
        let corte = resto.length
        for (let i = 0; i < resto.length; ++i) {
            if (claveDe(resto[i]) === destino.clave) {
                corte = i
                break
            }
        }

        bolsa = resto.slice(0, corte).concat(mueve).concat(resto.slice(corte))
        guardar()
    }

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
        contar("desguaces")
        reliquias += Items.valorDesguace(objeto)
        bolsa = bolsa.filter(function (x) { return x.id !== objeto.id })
        guardar()
    }

    // Desguaza de golpe todo lo que no supere a lo equipado. Con la bolsa
    // llena de piezas comunes, ir una a una es insufrible.
    // Quita la marca de recién llegado. Reasigna la bolsa entera a propósito:
    // tocar un objeto dentro del array no emite señal y la casilla seguiría
    // enseñando el badge hasta el siguiente cambio.
    function vistoObjeto(id) {
        let tocado = false
        const nueva = bolsa.map(function (o) {
            if (o && o.id === id && o.nuevo) {
                tocado = true
                const copia = Object.assign({}, o)
                delete copia.nuevo
                return copia
            }
            return o
        })
        if (!tocado)
            return
        bolsa = nueva
        guardar()
    }

    readonly property int sinVer: bolsa.filter(function (o) { return o && o.nuevo }).length

    // ── grupos de la bolsa ────────────────────────────────────────
    //
    //  Dos piezas son «la misma» si comparten tipo, grado y nivel, aunque sus
    //  cifras varíen algo por la tirada. Agrupar así hace legible una bolsa de
    //  sesenta y es lo que da sentido a combinar.

    function claveDe(objeto) {
        if (!objeto)
            return ""
        return objeto.tipo + "|" + objeto.rareza + "|" + Items.nivelDe(objeto)
            + "|" + (objeto.escuela || "acero")
    }

    readonly property var grupos: {
        const mapa = ({})
        const orden = []
        for (let i = 0; i < bolsa.length; ++i) {
            const o = bolsa[i]
            if (!o) continue
            const k = claveDe(o)
            if (!mapa[k]) {
                mapa[k] = { clave: k, piezas: [], mejor: o, nuevo: false }
                orden.push(k)
            }
            mapa[k].piezas.push(o)
            if (o.nuevo) mapa[k].nuevo = true
            if (Items.puntuacion(o) > Items.puntuacion(mapa[k].mejor))
                mapa[k].mejor = o
        }
        return orden.map(function (k) { return mapa[k] })
    }

    readonly property int combinables: grupos.filter(function (g) {
        return g.piezas.length >= 3
    }).length

    signal combinado(string cambio, var objeto)

    // Se van las tres peores del grupo y vuelve una. Nunca se toca lo
    // equipado, que vive fuera de la bolsa.
    function combinarGrupo(clave) {
        const grupo = grupos.filter(function (g) { return g.clave === clave })[0]
        if (!grupo || grupo.piezas.length < 3)
            return

        const ordenadas = grupo.piezas.slice().sort(function (a, b) {
            return Items.puntuacion(a) - Items.puntuacion(b)
        })
        const gastadas = ordenadas.slice(0, 3)
        const r = Items.combinar(gastadas)
        if (!r)
            return

        const fuera = gastadas.map(function (o) { return o.id })
        bolsa = bolsa.filter(function (o) {
            return o && fuera.indexOf(o.id) === -1
        }).concat([r.objeto])

        contar("combinaciones")
        guardar()
        combinado(r.cambio, r.objeto)
    }

    // ── el crisol ─────────────────────────────────────────────────
    //
    //  Tres huecos de salida. El quinto y el cuarto los suelta el segundo
    //  megajefe: es una mejora que cambia cómo juegas —fundir cinco da mejores
    //  probabilidades— y por eso merece estar detrás de algo, no comprarse.
    property bool crisolAmpliado: false
    readonly property int huecosCrisol: crisolAmpliado ? 5 : 3

    // Fundir de verdad: se van las piezas puestas y vuelve una.
    function fundirPiezas(piezas) {
        if (!piezas || piezas.length < 3)
            return null

        const r = Items.combinar(piezas)
        if (!r)
            return null

        const fuera = piezas.map(function (o) { return o.id })
        bolsa = bolsa.filter(function (o) {
            return o && fuera.indexOf(o.id) === -1
        })

        contar("combinaciones")
        guardar()
        return r
    }

    // Lo que sale del crisol no está en ningún sitio hasta que decides.
    function guardarFundido(objeto) {
        if (!objeto)
            return
        if (bolsa.length >= topeBolsa) {
            reliquias += Items.valorDesguace(objeto)
        } else {
            objeto.nuevo = true
            bolsa = bolsa.concat([objeto])
        }
        guardar()
    }

    function tirarFundido(objeto) {
        if (!objeto)
            return
        reliquias += Items.valorDesguace(objeto)
        contar("desguaces")
        guardar()
    }

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

        contar("cofres")
        const objeto = Items.generar(tipo, Math.max(oleada, mejorOleada), fortuna)

        if (bolsa.length >= topeBolsa) {
            // Bolsa llena: se desguaza solo, mejor eso que perderlo sin más.
            // Pero se marca, porque la ceremonia estaba enseñando una pieza
            // que en realidad nunca llegaba a la bolsa.
            const vale = Items.valorDesguace(objeto)
            reliquias += vale
            objeto.desguazado = vale
        } else {
            // Recién salido del cofre: se marca para poder encontrarlo entre
            // sesenta casillas. La marca se quita al pasar el ratón, que es
            // justo cuando ya lo has visto.
            objeto.nuevo = true
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
    // El impacto dice cuánto y a quién; este dice quién lo dio, que es lo que
    // hace falta para dibujar el ataque de cada clase a su manera.
    signal golpea(int indiceHeroe, int indiceEnemigo)
    // Con `habilidadLanzada` la vista sabía que alguien había lanzado algo,
    // pero no qué: todas se veían igual. Este lleva el efecto, que es lo que
    // decide cómo se dibuja.
    signal efectoHabilidad(int indiceHeroe, string efecto)
    signal habilidadEnemiga(int indiceEnemigo, string forma, string nombre)
    // Los rasgos son pasivos y por eso eran invisibles: actuaban cada segundo
    // sin que se viera nada. Solo se avisa de los que cambian algo de verdad,
    // no de los que reducen un número.
    signal rasgoActuo(int indiceEnemigo, int indiceHeroe, string rasgo)
    signal heroeHerido(int indiceHeroe, real daño)
    signal enemigoMuerto(int indiceEnemigo)
    signal curado(int indiceHeroe, real cantidad)
    signal habilidadLanzada(int indiceHeroe)
    signal oleadaSuperada(int numero)
    signal partidaTerminada(int oleadaAlcanzada, int cofresGanados, real reliquiasGanadas)
    signal subioNivel(int indiceHeroe, int nivel)
    signal escudoPuesto(int indiceHeroe)
    signal heroeDesbloqueado(string clase)
    signal logroConseguido(string id)

    // ── ciclo de partida ──────────────────────────────────────────
    // Empezar de cero de verdad: no una partida nueva, sino como recién
    // instalado. Se toca todo lo que sobrevive a morir —niveles, héroes
    // desbloqueados, logros, equipo, reliquias y las cuentas de por vida—,
    // que es justo lo que `nuevaPartida` conserva a propósito.
    function borrarTodo() {
        heroes = ({})
        plantilla = ["tanque", "mago", "clerigo"]
        desbloqueados = ["tanque", "mago", "clerigo"]
        logrosHechos = []
        cuentas = ({
            muertes: 0, jefes: 0, cofres: 0, oleadas: 0,
            partidas: 0, desguaces: 0, habilidades: 0, oroTotal: 0,
        combinaciones: 0, megajefes: 0
        })

        equipo = ({})
        bolsa = []
        cofresPorTipo = [0, 0, 0]
        meta = ({ vida: 0, daño: 0, fortuna: 0 })
        reliquias = 0

        mejorOleada = 0
        partidas = 0
        inicioElegido = 1

        // y a jugar, que dejarlo sin grupo montado sería un tablero muerto
        nuevaPartida()
        //  Antes de que corra un solo tic: empezar de cero no puede volver a
        //  cobrar los logros que ya estaban cumplidos de fuera.
        sellarLogrosPrevios()
        guardar()
        borradoTodo()
    }

    signal borradoTodo()

    function nuevaPartida() {
        relevoEn = 0
        oleada = Math.max(1, Math.min(inicioElegido,
            iniciosDisponibles[iniciosDisponibles.length - 1]))
        oro = 0
        comprados = [0, 0, 0]
        finalizada = ""

        const g = []
        for (let i = 0; i < plantilla.length; ++i) {
            const c = claseDe(plantilla[i])
            const recargas = ({})
            const recorta = 1 - statsDe({ clase: c.id, nivel: datosHeroe(c.id).nivel }).recorte
            for (let h = 0; h < c.habilidades.length; ++h)
                recargas[c.habilidades[h].id] = c.habilidades[h].recarga * recorta

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
            const cual = faunaPorBioma[bioma][(oleada * 3 + i) % faunaPorBioma[bioma].length]
            const esp = especies[cual] || ({ nombre: Idioma.t("Bicho"), afinidad: null, vida: 1, daño: 1 })
            const elite = !esJefe && esElite(oleada, i)

            // Los jefes no heredan la mezcla de la especie: son otra cosa.
            const multVida = (esJefe ? jefeVida : esp.vida) * (elite ? 2.2 : 1)
            const multDaño = (esJefe ? jefeDaño : esp.daño) * (elite ? 1.4 : 1)

            const vida = enemigoVidaBase * Math.pow(enemigoVidaCrec, oleada - 1)
                * (esMegajefe ? megaVida : multVida)
            lista.push({
                vida: vida,
                vidaMax: vida,
                daño: enemigoDañoBase * Math.pow(enemigoDañoCrec, oleada - 1)
                    * (esMegajefe ? megaDaño : multDaño),
                sprite: esMegajefe ? megajefeActual.sprite
                    : esJefe
                    ? "b" + String((Math.floor(oleada / oleadasPorJefe) * 3) % 20).padStart(2, "0")
                    : "m" + String(cual).padStart(2, "0"),
                nombre: esMegajefe ? megajefeActual.nombre
                    : esJefe
                    ? titulosJefe[Math.floor(oleada / oleadasPorJefe) % titulosJefe.length]
                        + " " + deBioma[bioma]
                    : (elite ? "★ " : "") + esp.nombre,
                jefe: esJefe,
                mega: esMegajefe,
                secuaz: false,
                elite: elite,
                // De qué está hecho y con qué pega. Los jefes van equilibrados
                // a propósito: son el examen, no un puzle de resistencias.
                defensa: esJefe ? "equilibrada" : (esp.defensa || "equilibrada"),
                ataque: esJefe ? "fisico" : (esp.ataque || "fisico"),
                quieto: 0,
                veneno: 0,
                envalentonado: 0,       // lo que le ha subido un aullido
                hab: (function () {
                    const h = habilidadEnemigaDe(oleada + (esJefe ? 20 : 0), i)
                    return h ? h.id : ""
                })(),
                // arranca a media carga: la primera no cae nada más empezar
                recargaHab: (function () {
                    const h = habilidadEnemigaDe(oleada + (esJefe ? 20 : 0), i)
                    return h ? h.recarga * 0.55 : 0
                })(),
                // los jefes llevan uno más: son el examen de las diez oleadas
                rasgos: esMegajefe
                    ? rasgosPara(oleada + 60, i, null, true)
                    : rasgosPara(oleada + (esJefe ? 30 : 0), i,
                                 esJefe ? null : esp.afinidad, elite || esJefe)
            })
        }
        enemigos = lista
        if (esMegajefe) {
            faseMega = 0
            megaEntra(megajefeActual.nombre)
        }
    }

    // Segundos que se queda el resumen antes de arrancar sola la siguiente.
    readonly property int segundosRelevo: 20
    property real relevoEn: 0
    readonly property int relevoRestante: relevoEn > 0 ? Math.max(0, Math.ceil(relevoEn - ahora())) : 0

    function terminarPartida() {
        viva = false
        partidas += 1

        //  ── morir paga lo que has AVANZADO ────────────────────────
        //
        //  Pagaba `oleada^1.45` reliquias y `oleada/12` cofres cada vez, y con
        //  «continuar» encendido la partida se reencadena sola: la forma más
        //  rentable de farmear era morirse mucho, que es lo contrario de
        //  progresar. Medido: un día seguido daban 8.300 cofres y 141.000
        //  reliquias sin haber avanzado una sola oleada de récord.
        //
        //  En el género, morir CUESTA —en TBH te resetea la protección de mala
        //  suerte acumulada—. Aquí no hace falta castigar: basta con pagar por
        //  lo que se ha ganado. Solo cuenta lo que pasa de tu récord, y por
        //  cuánto lo pasas; caer otra vez donde ya caíste no paga nada.
        const avance = Math.max(0, oleada - mejorOleada)
        const ganadosCofres = avance > 0 ? Math.max(1, Math.floor(avance / 12)) : 0
        const ganadasReliquias = avance > 0
            ? Math.floor(Math.pow(oleada, 1.45) * Math.min(1, avance / 20)) : 0

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

    //  ── el goteo por reloj ────────────────────────────────────────
    //
    //  Fuera ya caía un cofre cada cuarto de hora (`segundosPorCofre`) y
    //  dentro no: dentro se pagaba por oleada. Eso premia correr, y correr es
    //  lo que se quería quitar — una oleada dura cuatro segundos, así que
    //  pagar por oleada es pagar por segundo.
    //
    //  Ahora es la misma regla a los dos lados: el tiempo paga igual mires o
    //  no. Es lo que hace que un idle acompañe en vez de rushearse — dejarlo
    //  correr paga, correr más rápido no paga más— y de paso quita la razón
    //  para tener la barra abierta a propósito.
    property real creditoCofre: 0

    function goteoPorReloj(delta) {
        creditoCofre += delta
        while (creditoCofre >= segundosPorCofre) {
            creditoCofre -= segundosPorCofre
            sumarCofre(0)
        }
    }

    // ── combate ───────────────────────────────────────────────────
    // Un tic por segundo: suficiente para que se vea vivo y ridículo en coste.
    function tic(delta) {
        if (!viva || !cargado || pausada)
            return

        goteoPorReloj(delta)

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

            // la ponzoña de los monstruos va royendo al héroe
            if (g[i].veneno > 0 && g[i].vida > 0) {
                const roe = g[i].veneno * delta
                g[i].vida -= roe
                g[i].veneno = Math.max(0, g[i].veneno - g[i].veneno * 0.12 * delta)
                heroeHerido(i, roe)
            }
        }

        // ── golpean los héroes
        for (let i = 0; i < g.length; ++i) {
            if (g[i].vida <= 0)
                continue

            const c = claseDe(g[i].clase)
            const st = statsDe(g[i])
            const blanco = primerVivo(e)

            if (blanco >= 0) {
                const pega = mermar(e[blanco], st.daño * delta, st.dañoMag * delta)
                e[blanco].vida -= pega
                impacto(blanco, pega)
                golpea(i, blanco)
                if (e[blanco].vida <= 0) {
                    enemigoMuerto(blanco)
                    aplicarExp(g, expPorMuerte())
                    contar(e[blanco].jefe ? "jefes" : "muertes")
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

        // ── el megajefe cambia de fase
        if (esMegajefe && e.length > 0 && e[0].mega && e[0].vida > 0) {
            const parte = e[0].vida / e[0].vidaMax
            const toca = parte <= 0.33 ? 2 : (parte <= 0.66 ? 1 : 0)

            if (toca > faseMega) {
                faseMega = toca

                // se recompone un poco y se envalentona
                e[0].vida = Math.min(e[0].vidaMax, e[0].vida + e[0].vidaMax * 0.08)
                e[0].envalentonado = (e[0].envalentonado || 0) + 0.25

                // y estrena un rasgo que antes no tenía
                const nuevos = ["ruptura", "drenaje", "eco"]
                const r = (e[0].rasgos || []).slice()
                if (r.indexOf(nuevos[toca]) === -1)
                    r.push(nuevos[toca])
                e[0].rasgos = r

                // refuerzos: dos secuaces del bioma, con vida de oleada normal
                const base = enemigoVidaBase * Math.pow(enemigoVidaCrec, oleada - 1)
                for (let k = 0; k < 2; ++k) {
                    const cual = faunaPorBioma[bioma][(oleada + k) % faunaPorBioma[bioma].length]
                    const esp = especies[cual] || ({ nombre: "Bicho", vida: 1, daño: 1 })
                    e.push({
                        vida: base * 0.8, vidaMax: base * 0.8,
                        daño: enemigoDañoBase * Math.pow(enemigoDañoCrec, oleada - 1) * 0.7,
                        sprite: "m" + String(cual).padStart(2, "0"),
                        nombre: esp.nombre,
                        jefe: false, mega: false, secuaz: true, elite: false,
                        defensa: esp.defensa || "equilibrada",
                        ataque: esp.ataque || "fisico",
                        quieto: 0, veneno: 0, envalentonado: 0,
                        hab: "", recargaHab: 0,
                        rasgos: rasgosPara(oleada, k, esp.afinidad, false)
                    })
                }

                megaFase(toca)
            }
        }

        // el veneno va royendo aunque nadie golpee
        for (let j = 0; j < e.length; ++j) {
            if (e[j].vida > 0 && e[j].veneno > 0) {
                e[j].vida -= e[j].veneno * delta
                if (e[j].vida <= 0) {
                    enemigoMuerto(j)
                    aplicarExp(g, expPorMuerte())
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
            const marcas = e[j].rasgos || []

            // ── su habilidad, si le toca
            if (e[j].hab) {
                e[j].recargaHab = (e[j].recargaHab || 0) - delta
                if (e[j].recargaHab <= 0) {
                    const h = habEnemigaDe(e[j].hab)
                    if (h) {
                        e[j].recargaHab = h.recarga
                        lanzarEnemiga(g, e, j, h)
                    }
                }
            }

            let pega = e[j].daño * delta * (1 + (e[j].envalentonado || 0))
            // furia: el bicho herido se crece, así que rematar corre prisa
            if (marcas.indexOf("furia") !== -1)
                pega *= 1 + (1 - e[j].vida / e[j].vidaMax) * 0.9

            // Contra magia vale la resistencia, no la armadura: un tanque
            // enlatado deja de ser la respuesta a todo, que era el problema de
            // tener una sola defensa.
            const stB = statsDe(g[blanco])
            const guardia = (e[j].ataque === "magico" ? stB.resistencia : stB.armadura)
                + (g[blanco].provocando > 0 ? 12 : 0)
            const reduccion = 100 / (100 + guardia * 4)
            let recibido = pega * reduccion

            // el escudo se lleva el golpe antes que la vida, salvo contra
            // quien sabe romperlo
            if (g[blanco].escudo > 0) {
                if (marcas.indexOf("ruptura") === -1) {
                    const absorbido = Math.min(g[blanco].escudo, recibido)
                    g[blanco].escudo -= absorbido
                    recibido -= absorbido
                } else {
                    // el escudo estaba ahí y no ha servido de nada: eso sí hay
                    // que verlo, o parece que el golpe ha salido de la nada
                    rasgoActuo(j, blanco, "ruptura")
                }
            }

            g[blanco].vida -= recibido
            // Sin este filtro la pantalla se llenaba de "-0": el escudo se
            // comía el golpe entero y aun así se anunciaba el impacto.
            if (recibido > 0.5)
                heroeHerido(blanco, recibido)

            // ponzoña: deja veneno que sigue royendo después
            if (marcas.indexOf("ponzona") !== -1) {
                // solo al prender, no cada segundo que dure
                if (!(g[blanco].veneno > 0))
                    rasgoActuo(j, blanco, "ponzona")
                g[blanco].veneno = Math.max(g[blanco].veneno || 0, e[j].daño * 0.3)
            }

            // drenaje: lo que te quita, se lo queda
            if (marcas.indexOf("drenaje") !== -1 && recibido > 0) {
                e[j].vida = Math.min(e[j].vidaMax, e[j].vida + recibido * 0.55)
                rasgoActuo(j, blanco, "drenaje")
            }

            // eco: el golpe salpica a los de detrás, que era donde uno se
            // escondía dejando al tanque delante
            if (marcas.indexOf("eco") !== -1) {
                for (let k = 0; k < g.length; ++k) {
                    if (k === blanco || g[k].vida <= 0)
                        continue
                    const salpica = recibido * 0.4
                    g[k].vida -= salpica
                    if (salpica > 0.5) {
                        heroeHerido(k, salpica)
                        rasgoActuo(j, k, "eco")
                    }
                }
            }

            // represalia: parte del golpe vuelve a quien lo dio
            if (g[blanco].reflejando > 0) {
                const vuelta = recibido * 1.5
                e[j].vida -= vuelta
                impacto(j, vuelta)
                if (e[j].vida <= 0) {
                    enemigoMuerto(j)
                    aplicarExp(g, expPorMuerte())
                }
            }
        }

        grupo = g
        enemigos = e

        if (!enemigos.some(function (x) { return x.vida > 0 })) {
            let bono = 0
            for (let i = 0; i < enemigos.length; ++i)
                bono += enemigos[i].elite ? 0.8 : 0
            const ganado = oroBase * Math.pow(oroCrec, oleada - 1)
                * (enemigos.length + bono)
            oro += ganado
            oleadaSuperada(oleada)

            //  ── el botín paga terreno NUEVO ───────────────────────
            //
            //  El goteo de un cofre cada cinco oleadas era el grifo principal y
            //  no miraba nada: ni la oleada, ni si ibas apurado, ni si eso ya lo
            //  habías hecho veinte veces. Con una oleada durando cuatro
            //  segundos son veinte segundos por cofre, y de ahí salían treinta
            //  y ocho cofres sin abrir en media hora — tantos que ninguno
            //  importaba y no se abría ninguno.
            //
            //  Estirar los hitos en número de oleadas no vale: el muro está
            //  sobre la 30-60, así que un jefe cada cien no lo verías nunca.
            //  Lo que se estira es lo que CUENTA como hito — la primera vez que
            //  pisas cada sitio—. Repetir terreno conocido no paga, así que el
            //  grifo queda atado a cuánto avanzas de verdad, que es justo lo
            //  que sube despacio. Es lo que el género llama puertas de
            //  progresión, y de paso mata el farmeo por repetición.
            //
            //  Con la barra abierta o cerrada sigue cayendo por reloj —ver
            //  `creditoCofre`—, que es lo que hace que un idle acompañe: dejarlo
            //  correr paga, correr más rápido no.
            const nuevo = oleada > mejorOleada

            if (nuevo && esJefe)
                sumarCofre(1)

            // El megajefe paga como lo que es: tres cofres de acto, un buen
            // pellizco de reliquias, y a partir del segundo la ampliación del
            // crisol. El primero ya tiene bastante con ser el primero.
            if (esMegajefe && nuevo) {
                sumarCofre(2)
                sumarCofre(2)
                sumarCofre(2)
                reliquias += Math.floor(Math.pow(oleada, 1.6))
                contar("megajefes")

                const cual = Math.floor(oleada / oleadasPorBioma)
                if (cual >= 2 && !crisolAmpliado && Math.random() < probCrisol) {
                    crisolAmpliado = true
                    crisolSoltado()
                }
            }
            if (nuevo && oleada % 50 === 0)
                sumarCofre(2)

            contar("oleadas")
            oleada += 1
            generarOleada()
            revisarDesbloqueos()
            revisarLogros()
            guardar()
        } else if (!grupo.some(function (h) { return h.vida > 0 })) {
            terminarPartida()
        }
    }

    // Las habilidades de los enemigos, resueltas por efecto igual que las de
    // los héroes. Todas miden su potencia en golpes normales suyos, así que
    // escalan solas con la oleada.
    function lanzarEnemiga(g, e, j, h) {
        const base = e[j].daño * (1 + (e[j].envalentonado || 0))
        const blanco = primerVivo(g)

        if (h.efecto === "granGolpe") {
            if (blanco < 0) return
            const golpe = pegarAHeroe(g, blanco, base * h.potencia, e[j].ataque)
            if (golpe > 0) heroeHerido(blanco, golpe)

        } else if (h.efecto === "salpicar") {
            for (let k = 0; k < g.length; ++k) {
                if (g[k].vida <= 0) continue
                const golpe = pegarAHeroe(g, k, base * h.potencia, e[j].ataque)
                if (golpe > 0) heroeHerido(k, golpe)
            }

        } else if (h.efecto === "enfurecer") {
            // se envalentona toda la oleada, con tope para que no se dispare
            for (let k = 0; k < e.length; ++k) {
                if (e[k].vida > 0) {
                    e[k].envalentonado =
                        Math.min(1.2, (e[k].envalentonado || 0) + h.potencia)
                }
            }

        } else if (h.efecto === "drenar") {
            if (blanco < 0) return
            const golpe = pegarAHeroe(g, blanco, base * h.potencia, e[j].ataque)
            if (golpe > 0) heroeHerido(blanco, golpe)
            e[j].vida = Math.min(e[j].vidaMax, e[j].vida + golpe)

        } else if (h.efecto === "sanar") {
            e[j].vida = Math.min(e[j].vidaMax, e[j].vida + e[j].vidaMax * h.potencia)
        }

        habilidadEnemiga(j, h.forma, h.nombre)
    }

    // Aplica un golpe a un héroe contando armadura y escudo, y devuelve lo que
    // de verdad le ha entrado en la vida.
    function pegarAHeroe(g, k, cantidad, tipo) {
        if (g[k].invulnerable > 0)
            return 0

        const st = statsDe(g[k])
        const guardia = (tipo === "magico" ? st.resistencia : st.armadura)
            + (g[k].provocando > 0 ? 12 : 0)
        let recibido = cantidad * (100 / (100 + guardia * 4))

        if (g[k].escudo > 0) {
            const absorbido = Math.min(g[k].escudo, recibido)
            g[k].escudo -= absorbido
            recibido -= absorbido
        }

        g[k].vida -= recibido
        return recibido
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

    function habilidadDe(clase, id) {
        const c = claseDe(clase)
        for (let i = 0; i < c.habilidades.length; ++i) {
            if (c.habilidades[i].id === id)
                return c.habilidades[i]
        }
        return null
    }

    // Resuelve por EFECTO y no por identificador: así ocho clases con cuatro
    // habilidades cada una no son treinta y dos casos escritos a mano, sino
    // trece efectos con distinta potencia.
    function lanzarInterno(g, e, i, id) {
        const hab = habilidadDe(g[i].clase, id)
        if (!hab)
            return

        const st = statsDe(g[i])
        const p = hab.potencia

        if (hab.efecto === "provocar") {
            g[i].provocando = p

        } else if (hab.efecto === "invulnerable") {
            g[i].invulnerable = p

        } else if (hab.efecto === "reflejo") {
            g[i].reflejando = p

        } else if (hab.efecto === "escudoGrupo") {
            for (let j = 0; j < g.length; ++j) {
                if (g[j].vida <= 0) continue
                g[j].escudo = Math.min(vidaMaxDe(g[j]) * topeEscudo,
                    (g[j].escudo || 0) + vidaMaxDe(g[i]) * p)
                escudoPuesto(j)
            }

        } else if (hab.efecto === "escudoUno") {
            const herido = masHerido(g)
            const quien = herido >= 0 ? herido : i
            g[quien].escudo = (g[quien].escudo || 0) + vidaMaxDe(g[quien]) * p
            escudoPuesto(quien)

        } else if (hab.efecto === "curaGrupo") {
            for (let j = 0; j < g.length; ++j) {
                if (g[j].vida <= 0) continue
                const cura = vidaMaxDe(g[j]) * p
                g[j].vida = Math.min(vidaMaxDe(g[j]), g[j].vida + cura)
                curado(j, cura)
            }

        } else if (hab.efecto === "regenerar") {
            for (let j = 0; j < g.length; ++j) {
                if (g[j].vida > 0) g[j].regenerando = p
            }

        } else if (hab.efecto === "revivir") {
            for (let j = 0; j < g.length; ++j) {
                if (g[j].vida <= 0) {
                    g[j].vida = vidaMaxDe(g[j]) * p
                    curado(j, g[j].vida)
                    break
                }
            }

        } else if (hab.efecto === "area") {
            for (let j = 0; j < e.length; ++j) {
                if (e[j].vida <= 0) continue
                const enArea = pegarA(e[j], st, st.total * p)
                e[j].vida -= enArea
                impacto(j, enArea)
                if (e[j].vida <= 0) enemigoMuerto(j)
            }

        } else if (hab.efecto === "cadena") {
            // El multiplicador va aparte del golpe: así cada eslabón pasa por
            // la carne del enemigo al que le toca, que es lo suyo cuando uno
            // aguanta el acero y el siguiente la magia.
            let factor = 1
            for (let j = 0; j < e.length; ++j) {
                if (e[j].vida <= 0) continue
                const golpe = pegarA(e[j], st, st.total * p * factor)
                e[j].vida -= golpe
                impacto(j, golpe)
                if (e[j].vida <= 0) enemigoMuerto(j)
                factor *= 1.6
            }

        } else if (hab.efecto === "golpeUnico" || hab.efecto === "remate") {
            // golpeUnico busca al más sano; remate, al más tocado
            let elegido = -1, mejor = hab.efecto === "remate" ? Infinity : -1
            for (let j = 0; j < e.length; ++j) {
                if (e[j].vida <= 0) continue
                if (hab.efecto === "remate" ? e[j].vida < mejor : e[j].vida > mejor) {
                    mejor = e[j].vida
                    elegido = j
                }
            }
            if (elegido >= 0) {
                const remate = pegarA(e[elegido], st, st.total * p)
                e[elegido].vida -= remate
                impacto(elegido, remate)
                if (e[elegido].vida <= 0) enemigoMuerto(elegido)
            }

        } else if (hab.efecto === "veneno") {
            for (let j = 0; j < e.length; ++j) {
                if (e[j].vida > 0) e[j].veneno = st.total * p / 10
            }

        } else if (hab.efecto === "robarVida") {
            // pega y se queda con la mitad: da a las clases oscuras una forma
            // de aguantar que no es ni escudo ni cura del clérigo
            const quien = primerVivo(e)
            if (quien >= 0) {
                const golpe = pegarA(e[quien], st, st.total * p)
                e[quien].vida -= golpe
                impacto(quien, golpe)
                const roba = golpe * 0.5
                g[i].vida = Math.min(vidaMaxDe(g[i]), g[i].vida + roba)
                curado(i, roba)
                if (e[quien].vida <= 0) {
                    enemigoMuerto(quien)
                    aplicarExp(g, expPorMuerte())
                }
            }

        } else if (hab.efecto === "sangrar") {
            // como el veneno, pero concentrado en uno y mucho más fuerte
            const quien = primerVivo(e)
            if (quien >= 0)
                e[quien].veneno = Math.max(e[quien].veneno || 0, st.total * p / 4)

        } else if (hab.efecto === "aturdir") {
            for (let j = 0; j < e.length; ++j)
                e[j].quieto = p
        }

        g[i].recargas[id] = hab.recarga * (1 - statsDe(g[i]).recorte)
        contar("habilidades")
        habilidadLanzada(i)
        efectoHabilidad(i, hab.efecto)
    }

    Timer {
        interval: game.tickMs
        repeat: true
        // En modo vibecoding hace falta chispa en el depósito: sin gasto de
        // tokens el grupo se queda quieto, que es toda la gracia.
        running: Settings.juegoActivo && game.cargado && game.viva && !game.pausada
            && (!Settings.juegoPorTokens || Tokens.hay)
        onTriggered: {
            const t = game.ahora()
            let delta = Math.max(0, Math.min(5, t - game.ultimoTick))
            game.ultimoTick = t

            if (Settings.juegoPorTokens)
                delta = Tokens.gastar(delta)

            if (delta > 0)
                game.tic(delta)
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: Settings.juegoActivo && game.cargado
        onTriggered: game.guardar()
    }

    // Los logros de vibecoding se ganan trabajando, no peleando: si solo se
    // revisaran en el tic del combate, con el deposito vacio se quedarian sin
    // cobrar justo cuando te los acabas de ganar.
    Connections {
        target: Tokens
        function onIngreso() {
            if (game.cargado)
                game.revisarLogros()
        }
    }

    // Reloj del relevo: el del combate se detiene al morir el grupo, así que
    // hace falta uno aparte que no dependa de `viva`.
    Timer {
        interval: 1000
        repeat: true
        running: Settings.juegoActivo && game.cargado && !game.viva
            && game.relevoEn > 0 && Settings.juegoContinuar
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
            plantilla: plantilla, desbloqueados: desbloqueados, cuentas: cuentas,
            crisolAmpliado: crisolAmpliado,
            logrosHechos: logrosHechos,
            mejorOleada: mejorOleada, partidas: partidas,
            creditoCofre: creditoCofre,
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
        //  Con la mazmorra apagada ni se lee la partida: al encenderla en
        //  Ajustes este binding se enciende solo y la carga llega entonces.
        running: Settings.juegoActivo
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
            plantilla = s.plantilla || ["tanque", "mago", "clerigo"]
            desbloqueados = s.desbloqueados || ["tanque", "mago", "clerigo"]
            cuentas = s.cuentas || cuentas
            logrosHechos = s.logrosHechos || []
            mejorOleada = s.mejorOleada || 0
            partidas = s.partidas || 0
            creditoCofre = s.creditoCofre || 0
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

        //  Perfil estrenado —no había guardado que leer—: se sellan los que ya
        //  vinieran cumplidos antes de que el jugador empiece. Con guardado no
        //  se toca nada, que ahí los logros ya se ganaron jugando.
        if (!s)
            sellarLogrosPrevios()

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
}
