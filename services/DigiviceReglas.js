//  Las reglas puras del Digivice: nada de estado, nada de QML.
//
//  Están fuera del servicio porque docs/GAMES.md pide justo esto —poder
//  probar la simulación sin arrancar Quickshell— y porque una regla que
//  solo se puede ejercitar abriendo la barra acaba sin probarse. El índice
//  y el azar entran por parámetro para que todo aquí sea determinista.
//
//  `services/Digivice.qml` lo importa como `Reglas`, y `tools/digivice_test.js`
//  lo carga con node. Un solo sitio, dos consumidores: no pueden divergir.

.pragma library

var ESCALERA = ["Baby I", "Baby II", "Child", "Adult", "Perfect", "Ultimate"]

function escalonSiguiente(etapa) {
    var i = ESCALERA.indexOf(etapa)
    return (i < 0 || i >= ESCALERA.length - 1) ? "" : ESCALERA[i + 1]
}

function escalonPrevio(etapa) {
    var i = ESCALERA.indexOf(etapa)
    return i <= 0 ? "" : ESCALERA[i - 1]
}

//  Crece rápido a propósito: en los aparatos un Perfect no gana por poco a
//  un Child, lo borra. Si la curva fuese suave, subir de etapa dejaría de
//  ser la recompensa que organiza todo el juego.
function poderDeEtapa(e) {
    switch (e) {
    case "Baby I":   return 1
    case "Baby II":  return 2
    case "Child":    return 5
    case "Adult":    return 11
    case "Perfect":  return 20
    case "Ultimate": return 32
    default:         return 4
    }
}

//  El triángulo clásico. Free y los que no traen atributo se quedan fuera
//  del piedra-papel-tijera en vez de inventarles uno.
function ventaja(a, b) {
    if (a === "Vaccine" && b === "Virus")   return 1.25
    if (a === "Virus"   && b === "Data")    return 1.25
    if (a === "Data"    && b === "Vaccine") return 1.25
    if (b === "Vaccine" && a === "Virus")   return 0.8
    if (b === "Virus"   && a === "Data")    return 0.8
    if (b === "Data"    && a === "Vaccine") return 0.8
    return 1
}

//  Arquetipo por el `type` de la API. Son 144 tipos distintos —"Holy Knight",
//  "Bewitching Beast", "Small Dragon"…— así que una tabla exhaustiva sería
//  absurda y frágil: se mira por palabra clave, en orden, y el primero que
//  encaja manda. El orden importa ("Demon Dragon" es dragón, no demonio a
//  secas) y por eso los compuestos van delante.
var ARQUETIPOS = [
    // [palabra, vida, atq, def, vel]
    ["Dragon",   1.05, 1.25, 1.00, 0.95],
    ["Dinosaur", 1.15, 1.20, 1.00, 0.80],
    ["Demon Lord", 1.10, 1.30, 1.00, 0.95],
    ["Cyborg",   1.00, 1.10, 1.25, 0.85],
    ["Machine",  1.05, 1.00, 1.35, 0.75],
    ["Mineral",  1.20, 0.90, 1.40, 0.65],
    ["Armor",    1.05, 1.00, 1.30, 0.80],
    ["Angel",    1.05, 1.05, 1.10, 1.05],
    ["Holy",     1.10, 1.05, 1.15, 0.95],
    ["God",      1.10, 1.15, 1.10, 1.00],
    ["Undead",   0.90, 1.20, 0.85, 1.05],
    ["Demon",    0.95, 1.25, 0.90, 1.05],
    ["Dark",     0.95, 1.20, 0.90, 1.05],
    ["Bird",     0.85, 1.05, 0.80, 1.40],
    ["Insect",   0.85, 1.10, 0.95, 1.20],
    ["Fairy",    0.85, 1.00, 0.85, 1.35],
    ["Plant",    1.20, 0.85, 1.15, 0.70],
    ["Slime",    1.25, 0.80, 1.10, 0.75],
    ["Aquatic",  1.15, 0.95, 1.05, 0.95],
    ["Amphibian", 1.10, 0.95, 1.05, 1.00],
    ["Mollusk",  1.20, 0.85, 1.20, 0.65],
    ["Beast",    1.00, 1.10, 0.95, 1.15],
    ["Mammal",   1.00, 1.05, 0.95, 1.10],
    ["Reptile",  1.05, 1.05, 1.05, 0.90],
    ["Warrior",  1.00, 1.15, 1.05, 0.95],
    ["Puppet",   0.95, 1.00, 1.00, 1.10]
]

function arquetipoDe(tipo) {
    var t = tipo || ""
    for (var i = 0; i < ARQUETIPOS.length; ++i) {
        if (t.indexOf(ARQUETIPOS[i][0]) >= 0) {
            var a = ARQUETIPOS[i]
            return { nombre: a[0], vida: a[1], atq: a[2], def: a[3], vel: a[4] }
        }
    }
    return { nombre: "", vida: 1, atq: 1, def: 1, vel: 1 }
}

//  Y el atributo, que ya decide el triángulo, también inclina el reparto:
//  Virus pega y aguanta poco, Data aguanta y pega poco, Vaccine es el
//  equilibrado, Free va suelto y rápido.
function repartoDeAtributo(attr) {
    switch (attr) {
    case "Virus":   return { vida: 0.95, atq: 1.15, def: 0.90, vel: 1.05 }
    case "Data":    return { vida: 1.15, atq: 0.90, def: 1.15, vel: 0.95 }
    case "Vaccine": return { vida: 1.05, atq: 1.05, def: 1.05, vel: 1.00 }
    case "Free":    return { vida: 1.00, atq: 1.00, def: 0.95, vel: 1.20 }
    default:        return { vida: 1, atq: 1, def: 1, vel: 1 }
    }
}

//  ── qué PINTA tiene el golpe de cada bicho ────────────────────────
//
//  Todos los golpes salían igual: un punto de color con una estela. Da igual
//  que pegue un dragón, una planta o una máquina, y eso tira por la borda lo
//  único que distingue a las 1488 especies aparte del sprite.
//
//  Va por ARQUETIPO y no por el `type` crudo: son 144 tipos distintos, pero
//  `arquetipoDe` ya los reduce a 26, y esos 26 caben en nueve dibujos. Un
//  tipo que no encaje en ninguno pega con la bola de siempre, que es el
//  respaldo honesto.
//
//  Y el ATRIBUTO no cambia la forma: la tiñe. Son dos ejes distintos —de qué
//  está hecho el bicho y de qué bando es— y mezclarlos en un solo dibujo
//  perdería los dos. Así se lee «una hoja morada» = planta virus.
var GOLPES = {
    Dragon:    { forma: "bola",   color: "#e8804a" },
    Dinosaur:  { forma: "bola",   color: "#e8804a" },
    "Demon Lord": { forma: "sombra", color: "#a05ac0" },
    Cyborg:    { forma: "rayo",   color: "#8ad0e8" },
    Machine:   { forma: "rayo",   color: "#8ad0e8" },
    Mineral:   { forma: "roca",   color: "#c8b070" },
    Armor:     { forma: "roca",   color: "#c8b070" },
    Angel:     { forma: "luz",    color: "#f0e8b0" },
    Holy:      { forma: "luz",    color: "#f0e8b0" },
    God:       { forma: "luz",    color: "#f0e8b0" },
    Undead:    { forma: "sombra", color: "#a05ac0" },
    Demon:     { forma: "sombra", color: "#a05ac0" },
    Dark:      { forma: "sombra", color: "#a05ac0" },
    Bird:      { forma: "pluma",  color: "#d8e8f0" },
    Fairy:     { forma: "pluma",  color: "#f0b0d8" },
    Insect:    { forma: "aguja",  color: "#d8e070" },
    Plant:     { forma: "hoja",   color: "#7de08a" },
    Slime:     { forma: "gota",   color: "#9fe07a" },
    Aquatic:   { forma: "gota",   color: "#70b8e8" },
    Amphibian: { forma: "gota",   color: "#70b8e8" },
    Mollusk:   { forma: "gota",   color: "#70b8e8" },
    Beast:     { forma: "garra",  color: "#e0a070" },
    Mammal:    { forma: "garra",  color: "#e0a070" },
    Reptile:   { forma: "garra",  color: "#e0a070" },
    Warrior:   { forma: "filo",   color: "#e8dcc8" },
    Puppet:    { forma: "filo",   color: "#e8dcc8" }
}

var FORMAS_GOLPE = ["bola", "rayo", "roca", "luz", "sombra",
                    "pluma", "aguja", "hoja", "gota", "garra", "filo",
                    "chispa"]

//  El halo del atributo. Es el mismo eje que ya decide el triángulo de
//  Vaccine/Virus/Data, así que teñir por él hace que se vea en la pelea lo
//  que ya pesaba en los números.
function auraDeAtributo(attr) {
    switch (attr) {
    case "Virus":   return "#c98ae0"
    case "Data":    return "#8ab4e0"
    case "Vaccine": return "#9fe8ac"
    case "Free":    return "#e8d05a"
    default:        return "#d8d8d8"
    }
}

//  Segunda pasada, SOLO para el dibujo.
//
//  `arquetipoDe` deja 455 fichas de 1488 sin encajar, y con eso el 41 %
//  pegaba con la bola de respaldo: o sea, cuatro de cada diez bichos volvían
//  a pegar todos igual, que era el problema que se venía a arreglar.
//
//  Lo que NO se puede hacer es meter estas palabras en `ARQUETIPOS`: esa
//  tabla también fija los multiplicadores de vida, ataque, defensa y
//  velocidad, así que ampliarla sería colar un cambio de balance por la
//  puerta de atrás mientras se tocaban los colores. Son dos ejes distintos y
//  van en dos tablas distintas.
//
//  Las 140 fichas que no traen `type` ninguno se quedan en la bola, y está
//  bien que así sea: no hay nada que leer ahí.
var VISTA_EXTRA = [
    ["Archangel", "luz"], ["Cherub", "luz"], ["Ophan", "luz"],
    ["Seraph", "luz"], ["Throne", "luz"],
    ["Small Devil", "sombra"], ["Oni", "sombra"], ["Ghost", "sombra"],
    ["Devil", "sombra"], ["Evil", "sombra"], ["Wicked", "sombra"],
    ["Ice", "roca"], ["Snow", "roca"], ["Ore", "roca"], ["Rock", "roca"],
    ["Crystal", "roca"], ["Metal", "roca"],
    ["Crustacean", "gota"], ["Plesiosaur", "gota"], ["Fish", "gota"],
    ["Shellfish", "gota"], ["Sea", "gota"],
    ["Pterosaur", "pluma"], ["Chick", "pluma"], ["Wing", "pluma"],
    ["Larva", "aguja"], ["Bee", "aguja"], ["Spider", "aguja"],
    ["Weapon", "filo"], ["Knight", "filo"], ["Blade", "filo"],
    ["Ankylosaur", "bola"], ["Ceratopsian", "bola"], ["Flame", "bola"],
    ["Fire", "bola"], ["Saurian", "bola"],
    ["Plant", "hoja"], ["Vegetation", "hoja"], ["Flower", "hoja"],
    ["Seed", "hoja"], ["Bulb", "hoja"], ["Stegosaur", "bola"],
    ["Parasite", "aguja"], ["Smoke", "sombra"],
    ["Android", "rayo"], ["Robot", "rayo"], ["Machine", "rayo"],
    ["Beast", "garra"], ["Animal", "garra"]
]

//  Color por forma, para que la segunda pasada no tenga que repetirlos.
var COLOR_FORMA = {
    bola: "#e8804a", rayo: "#8ad0e8", roca: "#c8b070", luz: "#f0e8b0",
    sombra: "#a05ac0", pluma: "#d8e8f0", aguja: "#d8e070", hoja: "#7de08a",
    gota: "#70b8e8", garra: "#e0a070", filo: "#e8dcc8"
}

function golpeVistaDe(indice, id) {
    var d = indice[String(id)]
    var arq = arquetipoDe(d ? d.t : "")
    var aura = auraDeAtributo(d ? d.a : "")
    var g = GOLPES[arq.nombre]
    if (g)
        return { forma: g.forma, color: g.color, aura: aura,
                 arquetipo: arq.nombre }

    var t = (d && d.t) || ""
    for (var i = 0; i < VISTA_EXTRA.length; ++i) {
        if (t.indexOf(VISTA_EXTRA[i][0]) >= 0) {
            var f = VISTA_EXTRA[i][1]
            return { forma: f, color: COLOR_FORMA[f], aura: aura,
                     arquetipo: VISTA_EXTRA[i][0] }
        }
    }
    //  El respaldo tiene dibujo PROPIO —la chispa— y no la bola del dragón.
    //  Compartiéndolos, el 35 % de las peleas enseñaba la misma bola naranja:
    //  la mitad porque el bicho es un dragón y la otra mitad porque su tipo
    //  es «Mutation» y no dice nada. Dos motivos opuestos con la misma cara
    //  es peor que no distinguir: hace creer que se parecen.
    return { forma: "chispa", color: "#e8dcc8", aura: aura, arquetipo: "" }
}

//  ── el entrenamiento ──────────────────────────────────────────────
//
//  Cuatro estadísticas entrenables por separado —PV, ATQ, DEF, VEL— en vez
//  de una «fuerza» que subía sola. La diferencia es que entrenar deja de ser
//  un número y pasa a ser DECIDIR en qué quieres que sea bueno: un tanque de
//  PV y DEF juega distinto a un veloz que esquiva todo.
//
//  Es lo que hace Digital Tamers con sus salas por estadística.
var ESTADISTICAS = ["pv", "atq", "def", "vel"]

//  Techo por etapa: sin él, un Child con mil sesiones superaría a un Adult
//  recién nacido y subir de etapa dejaría de importar. El tope crece con la
//  escalera, así que entrenar mucho acerca al siguiente escalón pero no lo
//  sustituye.
function topeEntreno(etapa) {
    var i = ESCALERA.indexOf(etapa)
    if (i < 0) i = 2
    return 6 + i * 6            // Baby I 6 · Child 18 · Adult 24 · Ultimate 36
}

function entrenoDe(entrenos, cual) {
    if (!entrenos) return 0
    return entrenos[cual] || 0
}

//  Cuánto suma cada punto de entreno, por estadística. La vida sube más por
//  punto porque su escala es diez veces mayor: sin esto, entrenar PV no se
//  notaría y nadie lo entrenaría.
//  Calibrado con una regla explícita: **un bicho entrenado a tope vale más o
//  menos lo que uno de la etapa siguiente sin entrenar**. Ni menos —entrenar
//  sería decorativo— ni más —subir de etapa dejaría de ser la recompensa que
//  organiza el juego—. Con los primeros números un Child a tope hacía 178 PV
//  y 34 ATQ contra los 118 y 15 de un Adult recién nacido: lo aplastaba.
var PESO_ENTRENO = { pv: 2.5, atq: 0.5, def: 0.4, vel: 0.35 }

//  La API no trae números de combate. Antes se fabricaban SOLO con el id, o
//  sea que dos Adult se diferenciaban por un hash invisible: el jugador no
//  podía leer por qué uno era mejor. Ahora salen de lo que sí trae la ficha
//  —etapa, atributo, tipo, cuántas técnicas conoce— y eso se puede mirar en
//  la enciclopedia y entender. El id solo queda como desempate pequeño.
//  `entrenos` es {pv, atq, def, vel}; se acepta un número por compatibilidad
//  con partidas viejas, donde había una sola «fuerza».
function statsDe(indice, id, entrenos, peso) {
    var d = indice[String(id)]
    if (!d)
        return { vida: 1, atq: 1, def: 1, vel: 1 }

    if (typeof entrenos === "number") {
        var f = entrenos
        entrenos = { pv: f / 4, atq: f / 4, def: f / 4, vel: f / 4 }
    }
    entrenos = entrenos || {}
    var tope = topeEntreno(d.l)
    function ent(k) {
        return Math.min(tope, Math.max(0, entrenos[k] || 0)) * PESO_ENTRENO[k]
    }

    var base = poderDeEtapa(d.l)
    var arq = arquetipoDe(d.t)
    var att = repartoDeAtributo(d.a)

    //  Conocer más técnicas pega más; estar en varios campos aguanta más.
    //  Son datos reales de la ficha, no adorno.
    var tec = 1 + 0.04 * Math.min(4, (d.sk || []).length)
    var camp = 1 + 0.03 * Math.min(4, (d.f || []).length)

    // Desempate estable y pequeño (±5 %), solo para que no haya clones.
    var n = parseInt(id, 10) || 0
    var j = 1 + (((n * 7919) % 11) - 5) / 100

    //  Gordo se mueve peor, y solo eso: la vida y el ataque no cambian. Un
    //  bicho pasado de peso no es más débil, es más lento —que en un combate
    //  donde la esquiva sale de la velocidad ya se nota bastante—. Con tope,
    //  para que engordar sea un lastre y no una sentencia.
    var exceso = peso === undefined ? 0 : excesoDePeso(d.l, peso)
    var lastre = 1 - Math.min(0.4, exceso * 0.02)

    return {
        vida: Math.max(1, Math.round(base * 9 * arq.vida * att.vida * camp * j
                                     + ent("pv"))),
        atq:  Math.max(1, Math.round(base * arq.atq * att.atq * tec * j
                                     + ent("atq"))),
        def:  Math.max(1, Math.round(base * 0.7 * arq.def * att.def * j
                                     + ent("def"))),
        vel:  Math.max(1, Math.round(base * 0.6 * arq.vel * att.vel * j * lastre
                                     + ent("vel")))
    }
}

//  ── lo que el aparato te cuenta ───────────────────────────────────
//
//  Un renglón discreto bajo el bicho. Existe porque el juego tiene muchas
//  reglas que solo se notan si alguien te las dice: que el sobrepeso quita
//  velocidad, que el carácter cambia lo que pide, que la carretera está
//  parada esperándote. Sin esto son reglas invisibles, y una regla invisible
//  es indistinguible de un fallo.
//
//  Tres cosas lo mantienen «disimulado» y no en un tutorial:
//
//   · **Solo aparece si hay algo que decir.** Con todo en orden, el renglón
//     no está. No hay un consejo de relleno.
//   · **Dice el porqué, no la orden.** «Le sobra peso: va más lento» y no
//     «entrena velocidad». El juego informa; decidir es cosa tuya.
//   · **Se apaga solo.** Como cada consejo cuelga de una condición, arreglar
//     la cosa lo hace desaparecer. Nada que marcar como leído.
//
//  `prio` ordena: primero lo que hace daño, luego lo que se está perdiendo, y
//  al final lo que es solo interesante saber.
var CONSEJOS = [
    { id: "enfermo", prio: 100,
      cuando: function (e) { return e.enfermo },
      texto: "Está enfermo: pega y aguanta bastante menos" },
    { id: "envenenado", prio: 95,
      cuando: function (e) { return e.envenenado },
      texto: "Envenenado: pierde el ánimo al doble y entra así a las peleas" },
    { id: "hambre", prio: 90,
      cuando: function (e) { return e.hambre === 0 },
      texto: "Con el estómago vacío se le acumulan los descuidos" },
    { id: "animo", prio: 85,
      cuando: function (e) { return e.animo === 0 },
      texto: "Aburrido también cuenta como descuido, no solo el hambre" },
    { id: "suciedad", prio: 80,
      cuando: function (e) { return e.suciedad >= e.maxSuciedad },
      texto: "Con el suelo lleno los descuidos llegan el doble de rápido" },
    { id: "peso", prio: 70,
      cuando: function (e) { return e.peso > e.pesoMinimo + 4 },
      texto: "Le sobra peso: eso le quita velocidad, y la velocidad esquiva" },
    { id: "caminoParado", prio: 65,
      cuando: function (e) { return e.encuentro || e.rastro },
      texto: "El camino está parado: te espera algo antes de seguir" },
    { id: "evoluciona", prio: 60,
      cuando: function (e) { return e.puedeEvolucionar },
      texto: "Ya puede evolucionar" },
    { id: "cobrar", prio: 55,
      cuando: function (e) { return e.objetivosCobrables > 0 },
      texto: "Tienes objetivos sin cobrar" },
    { id: "jefe", prio: 50,
      cuando: function (e) { return e.anteElJefe },
      texto: "El jefe de la zona te espera al final del camino" },
    { id: "zonaHecha", prio: 45,
      cuando: function (e) { return e.caminoAcabado },
      texto: "Camino terminado: puedes rehacerlo y sale distinto" },
    { id: "sinEntrenar", prio: 40,
      cuando: function (e) { return e.entrenoTotal === 0 && e.etapaIdx >= 2 },
      texto: "Sin entrenar nada: cada estadística tiene su minijuego" },
    { id: "vitrina", prio: 35,
      cuando: function (e) { return e.banco === 0 && e.criados >= 2 },
      texto: "La guardería está vacía: el que criaste sale a ayudar en combate" },
    //  Lo que está haciendo AHORA MISMO manda sobre lo que es en general. Si
    //  está dando botes con tu música y el renglón dice «se esconde y
    //  observa», el aparato se contradice a sí mismo delante de tus ojos.
    { id: "bailando", prio: 30,
      cuando: function (e) { return e.animo_ === "bailando" },
      texto: "" },       // se rellena con el `comoBaila` de su carácter
    { id: "resollando", prio: 29,
      cuando: function (e) { return e.animo_ === "resollando" },
      texto: "Toma aire un momento" },
    { id: "nervioso", prio: 28,
      cuando: function (e) { return e.animo_ === "nervioso" },
      texto: "Con tantas ventanas abiertas no para quieto" },
    { id: "tranquilo", prio: 26,
      cuando: function (e) { return e.animo_ === "tranquilo" },
      texto: "Está tranquilo mientras te concentras" },
    //  Y la nota del carácter, SOLO cuando no está haciendo nada especial:
    //  es lo que es en general, no lo que hace ahora.
    { id: "caracter", prio: 20,
      cuando: function (e) { return !e.animo_ || e.animo_ === "normal" },
      texto: "" }        // se rellena con la nota de su carácter
]

//  Los consejos que aplican ahora mismo, de más urgente a menos.
function consejosDe(e, notaCaracter, comoBaila) {
    e = e || {}
    var out = []
    for (var i = 0; i < CONSEJOS.length; ++i) {
        var c = CONSEJOS[i]
        if (!c.cuando(e))
            continue
        var t = c.id === "caracter" ? (notaCaracter || "")
              : c.id === "bailando" ? (comoBaila || "Le gusta lo que suena")
              : c.texto
        if (t)
            out.push({ id: c.id, prio: c.prio, texto: t })
    }
    out.sort(function (a, b) { return b.prio - a.prio })
    return out
}

//  ── el carácter ───────────────────────────────────────────────────
//
//  Cada bicho tiene el suyo, y sale de la MISMA semilla que su agenda y su
//  carretera: es suyo, no cambia al reiniciar la barra, y dos criados a la vez
//  no se parecen.
//
//  Es la respuesta barata a «que el juego sea único» sin red, sin clave y sin
//  llamadas a ningún sitio: determinista, gratis y probable, que es como está
//  hecho todo lo demás de aquí.
//
//  Toca dos cosas y ninguna es decorativa:
//
//    · **El tuyo** colorea el CUIDADO —cuántas veces pide comer o mimo al
//      día— y qué le sienta mejor. Un glotón te tiene dando de comer; un
//      juguetón aguanta el hambre y reclama que le hagas caso.
//    · **El del rival** colorea cómo juega el triángulo del combate, así que
//      dos enemigos de la misma etapa ya no pelean igual. Es lo que hace que
//      leer al rival tenga algo que leer.
//
//  Los números son pequeños a propósito: el combate a igualdad de etapa está
//  medido entre el 46 % y el 53 % de victorias y el carácter no puede
//  llevárselo por delante.
//  `baile` es cómo se mueve con tu música: cuánto salta, a qué ritmo, cuántos
//  segundos aguanta antes de descansar y cuánto descansa. Todos bailaban
//  igual y sin parar, que es lo que delata que no hay nadie ahí dentro: un
//  tímido dando botes tres horas seguidas no es tímido.
var CARACTERES = [
    { id: "valiente",  nombre: "Valiente",
      atacar: 1.6, defender: 0.7, cargar: 0.9,
      hambre: 0,  animo: 0,  comer: 0, mimo: 0,
      baile: { salto: 12, ritmo: 90,  aguante: 40, descanso: 12 },
      comoBaila: "Baila a lo grande",
      nota: "Se lanza de cabeza" },
    { id: "cauto",     nombre: "Cauto",
      atacar: 0.7, defender: 1.7, cargar: 1.0,
      hambre: 0,  animo: 0,  comer: 0, mimo: 0,
      baile: { salto: 5,  ritmo: 220, aguante: 25, descanso: 20 },
      comoBaila: "Se mueve con cuidado",
      nota: "Prefiere cubrirse" },
    { id: "tozudo",    nombre: "Tozudo",
      atacar: 0.9, defender: 0.8, cargar: 1.8,
      hambre: 0,  animo: -1, comer: 0, mimo: 0,
      baile: { salto: 8,  ritmo: 150, aguante: 120, descanso: 8 },
      comoBaila: "No piensa parar",
      nota: "Carga y aguanta" },
    { id: "gloton",    nombre: "Glotón",
      atacar: 1.2, defender: 0.9, cargar: 1.0,
      hambre: 3,  animo: -1, comer: 1, mimo: 0,
      baile: { salto: 9,  ritmo: 130, aguante: 18, descanso: 25 },
      comoBaila: "Se cansa enseguida",
      nota: "Siempre tiene hambre" },
    { id: "jugueton",  nombre: "Juguetón",
      atacar: 1.1, defender: 0.9, cargar: 1.1,
      hambre: -2, animo: 3,  comer: 0, mimo: 1,
      baile: { salto: 14, ritmo: 80,  aguante: 90, descanso: 6 },
      comoBaila: "Se vuelve loco con la música",
      nota: "Pide más mimo que comida" },
    { id: "timido",    nombre: "Tímido",
      atacar: 0.8, defender: 1.4, cargar: 1.2,
      hambre: -1, animo: 2,  comer: 0, mimo: 1,
      baile: { salto: 4,  ritmo: 260, aguante: 15, descanso: 30 },
      comoBaila: "Se mueve poco, pero se mueve",
      nota: "Se esconde y observa" }
]

function caracterDe(semilla) {
    var i = Math.abs(_mezcla(semilla, 4441, 91)) % CARACTERES.length
    return CARACTERES[i]
}

//  El del rival sale de su ESPECIE, no de tu semilla: dos Kunemon peleando
//  igual sería raro, pero un Kunemon que pelea distinto cada vez que te lo
//  cruzas sería peor — dejaría de poder aprenderse.
function caracterDeEspecie(id) {
    var n = parseInt(id, 10) || 0
    return CARACTERES[Math.abs(_mezcla(n, 7717, 13)) % CARACTERES.length]
}

//  ── la agenda del día ─────────────────────────────────────────────
//
//  El bicho no se vacía a ritmo de metrónomo: cada día tiene su AGENDA de
//  sucesos —cuándo pide comer, cuándo pide mimo— colocados a horas que
//  cambian de un día para otro.
//
//  Es el modelo del emulador de aparatos, que no lleva un goteo sino sucesos
//  contados por día: `hunger_events_left`, `next_hunger_zero`,
//  `poop_events_per_day`, `sleep_minutes_per_day`, y rangos por todas partes
//  (`care_mistakes_min/max`, `additional_poops`). Aquí había un goteo a ritmo
//  fijo, y de ese goteo salieron TRES defectos con la misma raíz:
//
//    1. La deuda crecía sin tope con el medidor a cero, así que tras unas
//       horas de abandono dar de comer no hacía nada visible. Un acumulador
//       puede crecer; una agenda no tiene nada que acumular.
//    2. Los dos medidores volvían a alinearse cada pocas horas —un tercio de
//       los avisos caían en el mismo minuto— justo lo contrario de lo que
//       promete el diseño. La agenda los separa al colocarlos.
//    3. El bicho pedía de comer a las 9:00, a las 10:00 y a las 11:00, en
//       punto. Se le podía poner el reloj en hora. Eso no es una criatura, es
//       un temporizador de cocina.
//
//  La agenda se GENERA, no se guarda: sale de una semilla estable y del día,
//  así que preguntar «cuántos sucesos hubo entre estas dos horas» funciona
//  igual estando delante que recuperando las ocho horas que estuviste fuera.
//  Sin estado que persistir y sin deuda que se dispare.

//  Azar determinista y barato. No se usa `Math.random` a propósito: la agenda
//  tiene que salir igual cada vez que se pregunte por el mismo día, o el
//  recálculo de lo que pasó fuera daría un resultado distinto al de estar
//  delante mirándolo.
function _mezcla(a, b, c) {
    var x = (a | 0) * 374761393 + (b | 0) * 668265263 + (c | 0) * 2246822519
    x = (x ^ (x >>> 13)) >>> 0
    x = (x * 1274126177) >>> 0
    return (x ^ (x >>> 16)) >>> 0
}

function _azarDe(semilla, dia, tipo, i) {
    return _mezcla(semilla + dia * 7919, tipo * 104729 + i * 31, dia ^ i) / 4294967296
}

//  Cuántos sucesos de cada clase tiene un día, y en qué ventana caben. La
//  ventana es la de vigilia: dormido no se pasa hambre, y colocar sucesos a
//  las cuatro de la mañana sería regalarlos.
var TIPOS = { hambre: 1, animo: 2, caca: 3 }

//  Sucesos por día de cada clase, con su margen. El margen es lo que hace que
//  un día no se parezca al siguiente, y sale del emulador, que tiene rangos
//  para todo en vez de constantes.
var AGENDA = {
    hambre: { min: 13, max: 17 },
    animo:  { min: 9,  max: 12 },
    caca:   { min: 5,  max: 8 }
}

//  Separación mínima entre un suceso de hambre y uno de ánimo. Es la regla
//  que el goteo no podía cumplir: si caen juntos, atender es un solo gesto y
//  no hay nada que administrar.
var SEPARACION = 25

//  Los minutos —desde el arranque de la vigilia— en que ocurre cada suceso de
//  ese día. Ordenados, separados y estables.
function agendaDelDia(semilla, dia, tipo, minutosVigilia, ajuste) {
    var cfg = AGENDA[tipo]
    if (!cfg)
        return []
    var t = TIPOS[tipo] || 1
    var cuantos = cfg.min + Math.floor(_azarDe(semilla, dia, t, 0)
                                       * (cfg.max - cfg.min + 1))
    //  El carácter suma o resta sucesos, con suelo: un glotón pide de comer
    //  más veces y un juguetón, menos. Nunca por debajo de tres, o habría
    //  bichos que no piden nada y el cuidado dejaría de existir para ellos.
    cuantos = Math.max(3, cuantos + (ajuste | 0))
    var out = []
    for (var i = 0; i < cuantos; ++i) {
        //  Repartidos por tramos y con desvío dentro del tramo: así no se
        //  amontonan al principio ni dejan la tarde entera vacía, pero
        //  tampoco caen a horas en punto.
        var tramo = minutosVigilia / cuantos
        var base = i * tramo
        var desvio = _azarDe(semilla, dia, t, i + 1) * tramo
        out.push(Math.floor(base + desvio))
    }
    out.sort(function (a, b) { return a - b })

    //  El ánimo se aparta de la comida. Se mueve el del ánimo y no el del
    //  hambre porque el hambre es el que marca el ritmo del juego.
    if (tipo === "animo") {
        var comidas = agendaDelDia(semilla, dia, "hambre", minutosVigilia)

        function libre(m) {
            if (m < 0 || m > minutosVigilia)
                return false
            for (var j = 0; j < comidas.length; ++j)
                if (Math.abs(m - comidas[j]) < SEPARACION)
                    return false
            return true
        }

        for (var k = 0; k < out.length; ++k) {
            if (libre(out[k]))
                continue
            //  Se busca el hueco más cercano en LAS DOS direcciones, no
            //  empujando hacia delante. Empujar solo hacia delante tenía dos
            //  fallos: apartarse de una comida podía meterte encima de la
            //  siguiente, y cerca del final del día te sacaba de la vigilia
            //  —70 sucesos de 6391 acababan fuera, agendados mientras el
            //  bicho dormía—.
            var puesto = false
            for (var paso = 1; paso <= minutosVigilia && !puesto; ++paso) {
                if (libre(out[k] + paso)) { out[k] += paso; puesto = true }
                else if (libre(out[k] - paso)) { out[k] -= paso; puesto = true }
            }
            //  Si el día está tan lleno que no cabe, se queda donde estaba:
            //  mejor un suceso pegado a una comida que uno fuera de la
            //  vigilia, que no ocurriría nunca.
            if (!puesto)
                out[k] = Math.max(0, Math.min(minutosVigilia, out[k]))
        }
        out.sort(function (a, b) { return a - b })
    }
    return out
}

//  Cuántos sucesos caen en (desde, hasta], en minutos desde el arranque de la
//  vigilia del día `dia`. Los dos extremos pueden cruzar días enteros, que es
//  lo que pasa al volver tras una noche.
function sucesosEntre(semilla, tipo, diaDesde, minDesde, diaHasta, minHasta,
                      minutosVigilia, ajuste) {
    if (diaHasta < diaDesde)
        return 0
    var n = 0
    //  Tope de días a repasar: sin él, una fecha corrupta en el guardado
    //  pondría a girar el bucle para siempre.
    var tope = Math.min(diaHasta, diaDesde + 30)
    for (var d = diaDesde; d <= tope; ++d) {
        var ag = agendaDelDia(semilla, d, tipo, minutosVigilia, ajuste)
        for (var i = 0; i < ag.length; ++i) {
            var m = ag[i]
            if (d === diaDesde && m <= minDesde) continue
            if (d === diaHasta && m > minHasta) continue
            n += 1
        }
    }
    return n
}

//  ── cómo se vacían los medidores ──────────────────────────────────
//
//  Esto vivía dentro del servicio, en QML, y por eso ninguna prueba llegaba a
//  mirarlo. Salió caro: la deuda de hambre se acumulaba SIN TOPE con el
//  medidor ya a cero, así que tras unas horas sin atenderlo había 148 minutos
//  guardados —casi cinco corazones— y dar de comer no hacía nada visible. El
//  corazón subía, el siguiente tick se lo llevaba, la comida se gastaba y el
//  peso subía igual. Desde fuera, el botón parecía roto.
//
//  Está aquí porque es una REGLA, no una animación: cuánto cae cada medidor
//  en un rato, y qué pasa con lo que sobra.
function drenar(hambre, animo, restoHambre, restoAnimo, minutos, opts) {
    opts = opts || {}
    var porHambre = opts.minutosPorHambre || 30
    var porAnimo = opts.minutosPorAnimo || 40

    var h = hambre, a = animo
    var rh = restoHambre + minutos
    //  Envenenado, el ánimo cae al doble: es lo que hace que comer algo en
    //  mal estado sea una equivocación con consecuencias.
    var ra = restoAnimo + (opts.envenenado ? minutos * 2 : minutos)

    while (rh >= porHambre && h > 0) { rh -= porHambre; h -= 1 }
    while (ra >= porAnimo && a > 0) { ra -= porAnimo; a -= 1 }

    //  Con el medidor a cero, la cuenta SE PARA. No se puede tener más hambre
    //  que vacío, y guardar la deuda mientras tanto es lo que hacía inútil dar
    //  de comer. Es la misma regla que ya seguía la suciedad.
    if (h === 0) rh = 0
    if (a === 0) ra = 0

    return { hambre: h, animo: a, restoHambre: rh, restoAnimo: ra }
}

//  ── el peso ───────────────────────────────────────────────────────
//
//  El emulador lo tiene (`min_weight`) y los aparatos de verdad también: cada
//  comida engorda, cada entrenamiento adelgaza, y por debajo del mínimo de su
//  etapa un bicho no puede bajar. Sin esto, dar de comer no tiene contrapartida
//  y cuidar se reduce a pulsar un botón cuando hay hambre.
function pesoBaseDe(etapa) {
    switch (etapa) {
    case "Baby I":   return 5
    case "Baby II":  return 10
    case "Child":    return 20
    case "Adult":    return 30
    case "Perfect":  return 40
    case "Ultimate": return 50
    default:         return 20
    }
}

//  Lo que sobra por encima del mínimo de su etapa. Es lo que pesa —nunca
//  mejor dicho— en las estadísticas y en la evolución.
function excesoDePeso(etapa, peso) {
    return Math.max(0, (peso || 0) - pesoBaseDe(etapa))
}

//  ── requisitos para evolucionar ───────────────────────────────────
//
//  Antes bastaba con esperar en la etapa: evolucionar era un temporizador y
//  el jugador se enteraba cuando ya había pasado. Digital Tamers lo hace en
//  tres ejes —nivel, experiencia y VICTORIAS (`evoLevelC/R/U`, `evoXpC/R/U`,
//  `evoVitoriaC/R/U`)— y los enseña.
//
//  Aquí son tres también: tiempo en la etapa, victorias y experiencia. Y se
//  enseñan siempre, porque un requisito que no se ve no es una meta.
var REQUISITOS = {
    "Baby I":  { minutos: 5,   victorias: 0,  xp: 10 },
    "Baby II": { minutos: 30,  victorias: 2,  xp: 40 },
    "Child":   { minutos: 180, victorias: 6,  xp: 150 },
    "Adult":   { minutos: 480, victorias: 15, xp: 400 },
    "Perfect": { minutos: 960, victorias: 30, xp: 900 }
}

function requisitosDe(etapa) {
    return REQUISITOS[etapa] || null
}

//  Qué falta, en las tres. Devuelve ceros cuando ya se cumple, para que la
//  vista pueda pintar «listo» sin volver a calcular nada.
function faltaPara(etapa, minutosEnEtapa, victorias, xp) {
    var r = requisitosDe(etapa)
    if (!r)
        return null
    return {
        minutos: Math.max(0, r.minutos - (minutosEnEtapa || 0)),
        victorias: Math.max(0, r.victorias - (victorias || 0)),
        xp: Math.max(0, r.xp - (xp || 0)),
        req: r
    }
}

function cumpleRequisitos(etapa, minutosEnEtapa, victorias, xp) {
    var f = faltaPara(etapa, minutosEnEtapa, victorias, xp)
    if (!f)
        return false
    return f.minutos === 0 && f.victorias === 0 && f.xp === 0
}

//  La experiencia que deja un rival: cuanto más arriba esté, más enseña.
//  Ganarle a un Baby I siendo Perfect no debería servir de nada.
function xpDe(indice, idEnemigo, esJefe) {
    var d = indice[String(idEnemigo)]
    if (!d)
        return 0
    var base = poderDeEtapa(d.l) * 3
    return Math.round(base * (esJefe ? 3 : 1))
}

//  ── jogress ───────────────────────────────────────────────────────
//
//  Un cuarto de todas las evoluciones de la API piden una pareja concreta
//  —3804 parejas sobre 620 especies— y es lo que le da propósito a la
//  guardería: fusionas dos que has criado para conseguir uno que no sale de
//  ninguna línea.
//
//  `jog` es el índice de `datos/jogress.json`.
function jogressDe(jog, id) {
    return (jog && jog[String(id)]) || []
}

//  Qué sale de fusionar estos dos, o "" si no son pareja.
function jogressCon(jog, idA, idB) {
    var lista = jogressDe(jog, idA)
    for (var i = 0; i < lista.length; ++i)
        if (String(lista[i].con) === String(idB))
            return String(lista[i].da)
    return ""
}

//  ── de una especie a su huevo ─────────────────────────────────────
//
//  Capturar los datos de un Adult no te da un Adult: te da el HUEVO de su
//  línea, y lo crías tú desde abajo. Para eso se baja peldaño a peldaño por
//  el MISMO grafo filtrado que usa la escalera —no por el `prior` crudo—,
//  porque el de la API es una red y no un árbol: bajando a lo bruto todo el
//  mundo acaba en el mismo nudo.
//
//  Y en cada bajada se elige con un hash de la especie CAPTURADA, no por
//  orden alfabético. Con el alfabético "Algomon (Baby I)" salía de huevo
//  para siete de cada ocho especies —gana la A— y todos los huevos eran el
//  mismo. Con el hash, cada especie tiene SU huevo y siempre el mismo.
function raizDe(indice, id) {
    var origen = String(id)
    if (!indice[origen])
        return ""

    //  Un entero estable a partir del id, para repartir las bajadas.
    var semilla = (parseInt(origen, 10) || 0) * 2654435761 % 4294967296

    var actual = origen
    var vueltas = 0
    while (vueltas < 10) {
        vueltas += 1
        var cands = candidatosRegresion(indice, actual)
        if (cands.length === 0)
            break
        actual = cands[(semilla + vueltas * 7) % cands.length]
    }

    //  Y si la bajada se atasca a medio camino —hay peldaños sin predecesor
    //  en los datos: Angewomon se quedaba en un Child— se cae a un huevo de
    //  verdad. Un huevo que no es Baby I no es un huevo, y el juego se
    //  encontraría criando un Child recién nacido.
    if (indice[actual] && indice[actual].l === "Baby I")
        return actual

    var semillas = []
    for (var k in indice) {
        if (indice[k].l === "Baby I" && _crudos(indice, k).length > 0)
            semillas.push(k)
    }
    if (semillas.length === 0)
        return actual
    semillas.sort()
    return semillas[semilla % semillas.length]
}

//  ── la carretera ──────────────────────────────────────────────────
//
//  La exploración era invisible: un contador que subía con cada cambio de
//  ventana y, cada seis, soltaba un combate de la nada. El original hace otra
//  cosa —`area_distance` y `boss_distance`: la distancia recorrida de la zona
//  y lo que falta para el jefe— y eso es un VIAJE, no un contador.
//
//  Aquí la distancia es un **cuentakilómetros**: permanente, no se gasta. Usar
//  el ordenador te lleva por el camino y los jefes están cada vez más lejos.
//  Lo ambiental deja de ser el combustible y pasa a ser el progreso.
//
//  Los eventos van COLOCADOS en la carretera —en el kilómetro 40, en el 120,
//  en el 350— y no sorteados en un momento cualquiera. Es la misma idea que la
//  agenda del cuidado, pero en distancia en vez de en tiempo, y trae la misma
//  ventaja: preguntar «qué hay entre estas dos distancias» da lo mismo de
//  golpe que a trocitos, así que recuperar lo que pasó mientras no mirabas es
//  exacto y no aproximado.

//  Cada gesto, una zancada distinta. Antes todo valía 1 y la cifra no
//  significaba nada; así abrir una aplicación es un tranco de verdad y
//  cambiar de ventana un paso corto.
//
//  Nada de esto lee NADA: solo se mira que hubo un cambio y cuántas ventanas
//  hay. Ni títulos, ni pids, ni nombres de aplicación.
var ZANCADAS = { ventana: 1, escritorio: 2, app: 5, reloj: 1 }

function zancadaDe(gesto) {
    return ZANCADAS[gesto] || 1
}

//  Cuánto mide la carretera de cada zona. Crece un 40 % por zona: la primera
//  se hace en un rato y la última es una campaña. El Área Oscura, que además
//  está cerrada hasta que caigan cuatro jefes, queda a casi 3700.
function distanciaJefe(indiceZona) {
    return Math.round(250 * Math.pow(1.4, Math.max(0, indiceZona)))
}

//  Cada cuánto hay un hito, más o menos. Con desvío, para que la carretera no
//  sea una regla graduada.
var PASO_HITO = 30

//  Los hitos de una zona: a qué distancia está cada uno. El último es SIEMPRE
//  el jefe, y va exacto al final de la carretera — un jefe sorteado no
//  cerraría nada.
function hitosDe(semilla, indiceZona) {
    var fin = distanciaJefe(indiceZona)
    var out = []
    var d = 0
    var i = 0
    while (true) {
        //  Entre el 60 % y el 140 % del paso: ni amontonados ni desiertos.
        var salto = Math.round(PASO_HITO * (0.6 + _azarDe(semilla, indiceZona, 9, i) * 0.8))
        d += Math.max(8, salto)
        if (d >= fin)
            break
        out.push({ en: d, jefe: false, i: i })
        i += 1
        //  Tope de seguridad: una zona con distancia absurda no puede poner a
        //  girar el bucle para siempre.
        if (out.length > 400)
            break
    }
    out.push({ en: fin, jefe: true, i: i })
    return out
}

//  Qué clase de evento hay en cada hito. Los pesos dependen de LA PROFUNDIDAD
//  —cuánto llevas de esa carretera— así que el principio es apacible y el
//  final está lleno de bichos. Eso es la «rareza» pedida: no es un sorteo
//  plano, es un sorteo que cambia según dónde estés.
var EVENTOS = [
    //  id          peso al empezar   peso al final
    { id: "nada",     ini: 26, fin: 10 },
    { id: "bicho",    ini: 28, fin: 46 },
    { id: "rastro",   ini: 18, fin: 14 },
    { id: "hallazgo", ini: 21, fin: 16 },
    { id: "datos",    ini: 7,  fin: 14 }
]

function _pesoEvento(e, prof) {
    return e.ini + (e.fin - e.ini) * Math.max(0, Math.min(1, prof))
}

function eventoDeHito(semilla, indiceZona, hito, fin) {
    if (hito.jefe)
        return "jefe"
    var prof = fin > 0 ? hito.en / fin : 0
    var total = 0
    var i
    for (i = 0; i < EVENTOS.length; ++i)
        total += _pesoEvento(EVENTOS[i], prof)
    var r = _azarDe(semilla, indiceZona, 10, hito.i) * total
    for (i = 0; i < EVENTOS.length; ++i) {
        r -= _pesoEvento(EVENTOS[i], prof)
        if (r <= 0)
            return EVENTOS[i].id
    }
    return "nada"
}

//  Los hitos que se cruzan al pasar de `desde` a `hasta`. Es la función que
//  sostiene todo: da igual preguntarla de golpe al volver de comer o a
//  trocitos mientras miras.
function hitosEntre(semilla, indiceZona, desde, hasta) {
    if (hasta <= desde)
        return []
    var todos = hitosDe(semilla, indiceZona)
    var fin = distanciaJefe(indiceZona)
    var out = []
    for (var i = 0; i < todos.length; ++i) {
        var h = todos[i]
        if (h.en > desde && h.en <= hasta)
            out.push({ en: h.en, jefe: h.jefe,
                       evento: eventoDeHito(semilla, indiceZona, h, fin) })
    }
    return out
}

//  Lo que viene después de donde estás, para poder enseñar la carretera.
function proximoHito(semilla, indiceZona, desde) {
    var todos = hitosDe(semilla, indiceZona)
    var fin = distanciaJefe(indiceZona)
    for (var i = 0; i < todos.length; ++i) {
        if (todos[i].en > desde)
            return { en: todos[i].en, jefe: todos[i].jefe,
                     evento: eventoDeHito(semilla, indiceZona, todos[i], fin) }
    }
    return null
}

//  En qué punto está una carretera. Existe como regla y no como caso suelto
//  dentro del servicio porque el estado «al final y con el jefe vivo» es el
//  que se me escapó: al perder contra el jefe la distancia se quedaba al
//  máximo, no quedaban hitos por delante y la zona moría para siempre, sin
//  manera de volver a retarlo.
//  `vueltaCerrada` es si el jefe DE ESTA VUELTA ya cayó, no si la zona está
//  conquistada. La estrella de conquistada es para siempre; el jefe vuelve a
//  plantarse cada vez que rehaces el camino.
function estadoCarretera(indiceZona, distancia, vueltaCerrada) {
    var fin = distanciaJefe(indiceZona)
    if (distancia < fin)
        return "andando"
    return vueltaCerrada ? "terminada" : "jefe"
}

//  La semilla de una vuelta. Rehacer una zona no puede darte la MISMA
//  carretera: sería releer un libro sabiéndote dónde está cada cosa.
function semillaDeVuelta(semilla, indiceZona, vuelta) {
    return _mezcla(semilla, indiceZona * 1013, (vuelta | 0) * 7717) % 1000000
}

//  ── los jefes ─────────────────────────────────────────────────────
//
//  Cada zona tiene el suyo, y aparece tras ganar unos cuantos encuentros
//  allí: es el `boss_distance` del emulador —el jefe está al final del
//  camino, no en una tirada de suerte—. Sin esto explorar no tiene meta y
//  las nueve zonas son la misma cosa nueve veces.
//
//  El jefe va UN PELDAÑO POR ENCIMA de ti y es el más grande de su campo, no
//  uno al azar: de los habitantes de ese escalón se elige el que más técnicas
//  y más campos tiene, que es lo que en esta base de datos separa a un bicho
//  cualquiera de uno importante. Determinista, para que la zona tenga SU
//  jefe y no uno distinto cada vez que miras.
function jefeDe(indice, zonaId, etapaJugador) {
    var i = ESCALERA.indexOf(etapaJugador)
    if (i < 0)
        return ""
    //  Un escalón arriba, y si ya estás en la cima, de tu propia altura.
    var objetivo = ESCALERA[Math.min(ESCALERA.length - 1, i + 1)]

    var mejor = "", punt = -1
    for (var k in indice) {
        var d = indice[k]
        if (d.l !== objetivo)
            continue
        if (!d.f || d.f.indexOf(zonaId) < 0)
            continue
        //  Muchas técnicas suma y estar en muchos campos RESTA. Lo segundo
        //  es la clave: premiando a los generalistas, Greymon —que está en
        //  media base de datos— salía de jefe en seis zonas de nueve. Con la
        //  resta gana el especialista, que es el que suena a esa zona:
        //  Bakemon en Pesadilla, Ballistamon en el Imperio de Metal, Devimon
        //  en el Área Oscura. Las nueve salen distintas.
        var p = (d.sk ? d.sk.length : 0) * 3 - (d.f ? d.f.length : 0) * 2
        //  El desempate por nombre es lo que lo hace estable: sin él, dos
        //  bichos con la misma puntuación se turnarían segun el orden en que
        //  el motor recorra el objeto.
        if (p > punt || (p === punt && mejor && d.n.localeCompare(indice[mejor].n) < 0)) {
            punt = p
            mejor = k
        }
    }
    return mejor
}

//  Pelear en tu propio campo favorece. Los `fields` de la API son afinidades
//  de especie y ya se usan como mapa, así que la ventaja de terreno sale de
//  algo que el jugador ya ve al elegir zona.
function bonusZona(indice, id, zonaId) {
    var d = indice[String(id)]
    if (!d || !d.f || !zonaId)
        return 1
    return d.f.indexOf(zonaId) >= 0 ? 1.15 : 1
}

//  Cuántos golpes sabe un bicho SALVAJE por haber llegado a su etapa. Los
//  rivales no entrenan, así que sin esto ninguno usaría jamás una ráfaga y el
//  sistema de formas solo existiría para el jugador.
//
//  Tope de 2 —simple y ráfaga— también a propósito: la columna es una
//  apuesta a que el otro no ataca, y eso es una lectura, no una tirada. La
//  máquina no lee. Se la queda el jugador, y ahí está la ventaja de estar
//  mirando la pantalla.
var ABIERTAS_POR_ETAPA = [1, 1, 2, 2, 2, 2]

//  Cuántas técnicas tiene DESBLOQUEADAS con el esfuerzo que lleva encima.
//
//  Una ficha trae hasta cuatro, y antes rotaban todas desde el primer día:
//  un Baby I recién nacido usaba su técnica definitiva. Ahora se ganan
//  entrenando —una cada ocho de fuerza— y eso le da sentido a entrenar más
//  allá de un número: entrenas para que aprenda a pegar de otra manera.
//  Se abren con el ATQ ENTRENADO, no con una fuerza genérica: aprender a
//  pegar de otra manera es consecuencia de haber entrenado el ataque.
function tecnicasAbiertas(indice, id, entrenos) {
    var d = indice[String(id)]
    var sk = d && d.sk ? d.sk : []
    if (sk.length === 0)
        return 0
    var atq = typeof entrenos === "number" ? entrenos / 4
            : entrenoDe(entrenos, "atq")
    //  Sin suelo por etapa, a propósito. Llegué a ponerlo para que un Adult
    //  sin entrenar no fuese con una mano atada contra un Adult salvaje, pero
    //  eso anulaba por la puerta de atrás la regla que sostiene el
    //  entrenamiento: **los golpes se ganan**. El desequilibrio que quería
    //  arreglar no venía de aquí, venía de que el modo sin manos elegía a
    //  cara o cruz; arreglado eso, el suelo sobra.
    return Math.max(1, Math.min(sk.length, 1 + Math.floor(atq / 6)))
}

function tecnicasDeRival(indice, id) {
    var d = indice[String(id)]
    var sk = d && d.sk ? d.sk : []
    if (sk.length === 0)
        return 0
    var i = ESCALERA.indexOf(d.l)
    if (i < 0) i = 2
    return Math.max(1, Math.min(sk.length, ABIERTAS_POR_ETAPA[i]))
}

//  La técnica que toca en este golpe. Rota entre las DESBLOQUEADAS para que
//  el combate se lea distinto según quién pegue y según cómo lo has criado;
//  sin técnicas, un golpe seco.
function tecnicaDe(indice, id, turno, fuerza) {
    var d = indice[String(id)]
    var sk = d && d.sk ? d.sk : []
    if (sk.length === 0)
        return ""
    var abiertas = tecnicasAbiertas(indice, id, fuerza)
    return sk[Math.floor(turno / 2) % abiertas]
}

//  ── las formas de ataque ──────────────────────────────────────────
//
//  Digital Tamers no tiene un solo daño: separa `AtkDmg`, `BarrageDmg` y
//  `PillarDmg`. Es lo que le faltaba a este combate — el triángulo estaba
//  bien pero todos los ataques eran el mismo número con otro nombre, así que
//  elegir «atacar» no era elegir nada.
//
//  Ahora cada técnica de la ficha lleva forma según su orden, y como las
//  técnicas se ganan entrenando el ataque, entrenar abre MANERAS de pegar y
//  no solo cifras:
//
//      simple   fiable, daño medio
//      ráfaga   tres golpes pequeños que se cuelan por la defensa
//      columna  el doble de daño, pero lenta y se falla el doble
//
//  **La columna es lenta, y esa es su verdadera pega.** Medido: con solo la
//  esquiva doblada de castigo hacía 38 de daño contra los 20 de la simple y
//  los 30 de la ráfaga, o sea que era la respuesta correcta siempre y las
//  otras dos sobraban. Ahora, si el rival ataca a la vez, no llegas a
//  soltarla: no haces nada y te comes su golpe **entero**, no a medias como
//  en una colisión normal.
//
//  Con eso las tres son respuestas a preguntas distintas:
//
//      simple   nunca es un error; aguanta la colisión
//      ráfaga   contra los duros, y casi nunca falla del todo (tres dados)
//      columna  una apuesta a que el rival NO ataca este intercambio
//
//  Y encima se lee: la columna es el golpe que castiga al que carga.
var FORMAS = ["simple", "rafaga", "columna"]

function formaDe(i) {
    return FORMAS[Math.min(2, Math.max(0, i | 0))]
}

//  Las técnicas que puedes usar, con su forma. Es lo que se enseña en el
//  selector del combate.
function tecnicasConForma(indice, id, entrenos) {
    var d = indice[String(id)]
    var sk = d && d.sk ? d.sk : []
    var n = tecnicasAbiertas(indice, id, entrenos)
    var out = []
    for (var i = 0; i < n && i < sk.length; ++i)
        out.push({ i: i, nombre: sk[i], forma: formaDe(i) })
    if (out.length === 0)
        out.push({ i: 0, nombre: "", forma: "simple" })
    return out
}

//  El golpe con su forma. Aquí vuelve a entrar la ESQUIVA, que se había
//  quedado sin usar cuando el combate pasó a decisiones: sin ella la
//  velocidad no valía para nada dentro de la pelea y entrenarla era un
//  adorno. La columna la duplica —por eso es una apuesta— y la ráfaga la
//  tira tres veces, una por golpe, así que falla a trozos en vez de del todo.
function golpeDe(atacante, defensor, atrA, atrD, forma, azar) {
    var r = azar || Math.random
    var esq = probEsquiva(defensor, atacante)

    if (forma === "rafaga") {
        //  Media defensa en vez de defensa entera: es lo que la hace la
        //  respuesta contra los duros. Tres golpes a un tercio largo, de
        //  manera que contra un rival blando rinde algo MENOS que la simple
        //  —si no, sería la simple con premio— y contra uno duro, más.
        var uno = Math.max(1, Math.round(
            atacante.atq * ventaja(atrA, atrD) - defensor.def * 0.25))
        var total = 0, tocados = 0
        for (var i = 0; i < 3; ++i) {
            if (r() < esq)
                continue
            total += Math.max(1, Math.round(uno * 0.30))
            tocados += 1
        }
        return { daño: total, impactos: tocados, de: 3, fallo: tocados === 0 }
    }

    if (forma === "columna") {
        if (r() < Math.min(0.6, esq * 2))
            return { daño: 0, impactos: 0, de: 1, fallo: true }
        return { daño: Math.round(dañoDe(atacante, defensor, atrA, atrD) * 1.9),
                 impactos: 1, de: 1, fallo: false }
    }

    if (r() < esq)
        return { daño: 0, impactos: 0, de: 1, fallo: true }
    return { daño: dañoDe(atacante, defensor, atrA, atrD),
             impactos: 1, de: 1, fallo: false }
}

//  ── estados alterados ─────────────────────────────────────────────
//
//  Qué estado deja cada bicho lo decide su ARQUETIPO, que es un dato que el
//  jugador puede mirar en la enciclopedia: una planta envenena, una máquina
//  paraliza, un demonio debilita. Así saber contra qué peleas se convierte en
//  información útil en vez de un adorno de la ficha.
//
//  Un tercio largo de los arquetipos no deja ninguno, a propósito: si todos
//  los combates tuvieran estado, el estado dejaría de ser una amenaza y
//  pasaría a ser el clima.
var ESTADO_POR_ARQUETIPO = {
    "Plant": "veneno", "Insect": "veneno", "Slime": "veneno",
    "Mollusk": "veneno", "Undead": "veneno", "Demon": "veneno",
    "Dark": "veneno",

    "Machine": "paralisis", "Cyborg": "paralisis", "Mineral": "paralisis",
    "Armor": "paralisis", "Puppet": "paralisis",

    "Demon Lord": "debilidad", "Angel": "debilidad", "Holy": "debilidad",
    "God": "debilidad", "Fairy": "debilidad"
}

function estadoQueInflige(indice, id) {
    var d = indice[String(id)]
    if (!d)
        return ""
    return ESTADO_POR_ARQUETIPO[arquetipoDe(d.t).nombre] || ""
}

//  La duración cuenta el intercambio en que se pone.
//
//  La parálisis dura DOS y no uno por una razón concreta: se aplica al final
//  del intercambio y el descuento pasa justo después, así que con uno se
//  apagaría antes de robarte nada. Con dos roba exactamente un intercambio,
//  que es lo que dice hacer.
var ESTADOS = {
    veneno:    { turnos: 3, texto: "Veneno",     glifo: "\u{F00A7}" },
    paralisis: { turnos: 2, texto: "Parálisis",  glifo: "\u{F0241}" },
    debilidad: { turnos: 4, texto: "Debilidad",  glifo: "\u{F0533}" }
}

//  Cuánto cuesta cada golpe con estado, por forma. La columna no deja
//  ninguno: es daño puro y ya tiene su premio. La ráfaga es la que más los
//  deja porque son tres oportunidades, no una.
//
//  Los números NO son los que puse a ojo. Con 0,15 y 0,30 solo uno de cada
//  cuatro combates veía un estado y la parálisis robaba 0,03 turnos por
//  combate: o sea, nunca. Un sistema que no se ve no está en el juego, por
//  mucho que esté en el código. La cuenta de por qué salían tan poco: solo
//  un tercio de los intercambios son de los que dejan estado —pillado y
//  colisión—, y solo el 42 % de las fichas dejan alguno, así que la
//  probabilidad del golpe se multiplica por 0,14 antes de llegar a la mesa.
var PROB_ESTADO = { simple: 0.30, rafaga: 0.55, columna: 0 }

function aplicarEstado(estados, tipo) {
    var out = (estados || []).slice()
    var d = ESTADOS[tipo]
    if (!d)
        return out
    for (var i = 0; i < out.length; ++i) {
        if (out[i].tipo === tipo) {
            //  Reaplicar renueva, no acumula: si no, dos ráfagas seguidas
            //  encadenarían un veneno eterno.
            out[i] = { tipo: tipo, turnos: d.turnos }
            return out
        }
    }
    out.push({ tipo: tipo, turnos: d.turnos })
    return out
}

function tieneEstado(estados, tipo) {
    for (var i = 0; i < (estados || []).length; ++i)
        if (estados[i].tipo === tipo)
            return true
    return false
}

//  Descuenta un intercambio a cada estado y dice lo que quema el veneno.
//  Devuelve una lista nueva: los estados se pasan entre QML y las reglas y
//  mutarlos por dentro rompe los enlaces de la vista.
function tickEstados(estados, vidaMax) {
    var quema = 0
    var vivos = []
    for (var i = 0; i < (estados || []).length; ++i) {
        var e = estados[i]
        if (e.tipo === "veneno")
            quema += Math.max(1, Math.round(vidaMax * 0.05))
        if (e.turnos > 1)
            vivos.push({ tipo: e.tipo, turnos: e.turnos - 1 })
    }
    return { estados: vivos, quema: quema }
}

//  La debilidad pega donde duele y nada más: −35 % de ataque. No toca la
//  vida ni la defensa porque entonces sería «te va peor en todo», que no se
//  puede jugar en contra — así al menos sabes que te toca cubrirte y esperar.
function conEstados(stats, estados) {
    var s = { vida: stats.vida, atq: stats.atq, def: stats.def, vel: stats.vel }
    if (tieneEstado(estados, "debilidad"))
        s.atq = Math.max(1, Math.round(s.atq * 0.65))
    return s
}

//  ── la comida ─────────────────────────────────────────────────────
//
//  Había un botón «comer» y ya está: +1 de hambre, +1 de peso, sin elección
//  ninguna. Un sistema de cuidado con un solo verbo no tiene decisiones
//  dentro, que es lo que le pasaba a casi todo este juego.
//
//  Cinco comidas, y cada una es un trato distinto:
//
//      ración        lo de siempre; nunca se acaba, y por eso es el suelo
//      ración grande llena el doble y engorda el triple
//      carne         da vigor para los próximos combates, pero pesa
//      fruta omni    no llena: CURA —enfermedad, veneno y estados—
//      en mal estado llena igual y te envenena
//
//  La de mal estado es la que hace que cazar sea una apuesta y no una cinta
//  transportadora: si fallas, te llevas algo que llena y te sienta mal.
//  Engancha con los estados de la fase 3 —el veneno ya existe— en vez de
//  inventarse un castigo nuevo.
var COMIDAS = [
    { id: "racion", nombre: "Ración", hambre: 1, peso: 1, animo: 0,
      vigor: 0, cura: false, veneno: false, infinita: true,
      glifo: "\u{F05F2}", nota: "Lo de siempre" },

    { id: "grande", nombre: "Ración grande", hambre: 2, peso: 3, animo: 0,
      vigor: 0, cura: false, veneno: false, infinita: false,
      glifo: "\u{F025A}", nota: "Llena el doble, engorda el triple" },

    { id: "carne", nombre: "Carne", hambre: 1, peso: 2, animo: 1,
      vigor: 3, cura: false, veneno: false, infinita: false,
      glifo: "\u{F141F}", nota: "Vigor para los próximos combates" },

    { id: "omni", nombre: "Fruta Omni", hambre: 0, peso: 0, animo: 2,
      vigor: 0, cura: true, veneno: false, infinita: false,
      glifo: "\u{F025B}", nota: "Cura la enfermedad y el veneno" },

    { id: "podrida", nombre: "En mal estado", hambre: 1, peso: 1, animo: -1,
      vigor: 0, cura: false, veneno: true, infinita: false,
      glifo: "\u{F068C}", nota: "Llena… y sienta fatal" }
]

function comidaDe(id) {
    for (var i = 0; i < COMIDAS.length; ++i)
        if (COMIDAS[i].id === id)
            return COMIDAS[i]
    return null
}

//  Cuánto ataque de más da el vigor de la carne. Se gasta por combate, no
//  por tiempo: si caducara con el reloj, comer antes de pelear sería un
//  trámite de cronómetro en vez de una decisión.
function bonusVigor(vigor) {
    return vigor > 0 ? 1 + Math.min(3, vigor) * 0.06 : 1
}

//  ── la caza ───────────────────────────────────────────────────────
//
//  `obj_Hunt_Food` del emulador: la comida se busca en el mapa. Aquí se paga
//  con lo único que este juego tiene de moneda honesta —los pasos, o sea,
//  haber estado usando el ordenador— y así comer deja de ser gratis y queda
//  atado a explorar, que era el objetivo.
//
//  Y no es una tirada: son TRES RASTROS y eliges uno. Detrás de cada uno hay
//  algo distinto, y la velocidad entrenada te deja descartar los malos antes
//  de elegir. Es una decisión con una estadística detrás, que es lo que le
//  faltaba a la mitad de este juego.
//
//  Cada zona da lo suyo: en la jungla hay fruta y en el Imperio de Metal casi
//  nada que se pueda comer. Sin esto, cambiar de zona no cambiaría nada para
//  quien viene a cazar.
//  Ninguna tabla trae `racion`, y eso NO es un descuido: la ración es
//  infinita, así que encontrarla no es encontrar nada. Con ella en las tablas,
//  uno de cada tres rastros era tirar doce pasos a la basura y el jugador no
//  tenía manera de saber por qué. Lo mínimo que se saca de cazar es una
//  ración grande.
var CAZA_POR_ZONA = {
    "Nature Spirits":     ["carne", "grande", "grande", "omni"],
    "Deep Savers":        ["carne", "carne", "grande", "omni"],
    "Wind Guardians":     ["grande", "grande", "carne", "omni"],
    "Jungle Troopers":    ["omni", "carne", "grande", "omni"],
    "Dragon's Roar":      ["carne", "carne", "carne", "grande"],
    //  El Imperio de Metal da de comer lo justo: es chatarra, no un bosque.
    "Metal Empire":       ["grande", "grande", "grande", "carne"],
    "Nightmare Soldiers": ["carne", "grande", "carne", "carne"],
    "Virus Busters":      ["grande", "omni", "grande", "grande"],
    "Dark Area":          ["omni", "carne", "carne", "omni"]
}

//  Cuántos rastros se ofrecen. CUATRO, y no tres, por aritmética: con tres y
//  la pista gratis de la velocidad ya solo quedaban dos sin marcar, y
//  olfatear —que descarta uno más— no cabía sin dejar la respuesta servida.
//  O sea que pagar por olfatear solo funcionaba con la velocidad baja, justo
//  al revés de lo que tiene sentido. Con cuatro: la pista deja tres, olfatear
//  deja dos, y sigue habiendo que elegir.
var RASTROS = 4

//  Cuántos rastros malos te marca la velocidad antes de elegir. Con la VEL a
//  tope de tu etapa te queda una elección entre dos, no entre tres — nunca
//  se regala la respuesta, porque entonces cazar dejaría de decidirse.
function pistasDeCaza(vel, etapa) {
    var tope = topeEntreno(etapa)
    if (tope <= 0)
        return 0
    return vel >= tope * 0.6 ? 1 : 0
}

//  Marcar un rastro malo MÁS, pagando. Es lo que le da uso al rastro que
//  acumulas andando: tu oficio siguiendo huellas, gastado en leer huellas.
//
//  Solo uno más, y nunca el bueno: con dos marcados de tres, la cacería se
//  resolvería sola y dejaría de ser una decisión — que es justo lo que la
//  hacía valer la pena.
function marcarOtro(rastros) {
    if (!rastros)
        return false
    var sinMarcar = 0
    for (var i = 0; i < rastros.length; ++i)
        if (!rastros[i].marcado)
            sinMarcar += 1
    //  Si ya solo quedan dos sin marcar, marcar otro deja uno solo: eso es
    //  regalar la respuesta.
    if (sinMarcar <= 2)
        return false
    for (var j = 0; j < rastros.length; ++j) {
        if (!rastros[j].marcado && rastros[j].malo) {
            rastros[j].marcado = true
            return true
        }
    }
    for (var k = 0; k < rastros.length; ++k) {
        if (!rastros[k].marcado && !rastros[k].bueno) {
            rastros[k].marcado = true
            return true
        }
    }
    return false
}

//  Monta una cacería: qué hay detrás de cada rastro.
//
//  Siempre hay exactamente UNO malo y uno bueno; el tercero es del montón.
//  Con eso el riesgo es legible —un tercio si eliges a ciegas— en vez de una
//  probabilidad escondida que el jugador nunca podría estimar.
function montarCaza(zonaId, vel, etapa, azar) {
    var r = azar || Math.random
    var tabla = CAZA_POR_ZONA[zonaId] || ["grande", "grande", "carne", "grande"]

    var bueno = tabla[Math.floor(r() * tabla.length) % tabla.length]
    //  El premio gordo de la zona nunca puede ser el que sienta mal: si no,
    //  «acertar» a veces sería peor que fallar.
    if (bueno === "podrida")
        bueno = "carne"

    //  El del montón es una ración GRANDE, no una ración a secas: la de
    //  siempre es infinita y «encontrar» algo que ya tenías infinito es
    //  volver de la cacería con las manos vacías sin que nadie te lo diga.
    //  `marcado` va SIEMPRE, y con un booleano de verdad. Dejarlo sin poner
    //  en los que no se marcan parecía inofensivo, pero en QML un
    //  `visible: undefined` no vale `false`: falla la conversión y la
    //  propiedad se queda en su valor por defecto, que es visible. Resultado:
    //  la cruz de «descartado» salía sobre TODOS los rastros y la pista no
    //  servía para nada.
    //
    //  Uno bueno, uno malo y dos del montón: el riesgo sigue siendo legible
    //  —uno de cada cuatro a ciegas— y hay sitio para olfatear.
    var rastros = [
        { comida: bueno, bueno: true, malo: false, marcado: false },
        { comida: "grande", bueno: false, malo: false, marcado: false },
        { comida: "grande", bueno: false, malo: false, marcado: false },
        { comida: "podrida", bueno: false, malo: true, marcado: false }
    ]

    //  Barajar con el azar que nos den, para que las pruebas puedan fijarlo.
    for (var i = rastros.length - 1; i > 0; --i) {
        var j = Math.floor(r() * (i + 1))
        var t = rastros[i]; rastros[i] = rastros[j]; rastros[j] = t
    }

    //  Las pistas marcan rastros MALOS, empezando por el que sienta mal: de
    //  qué sirve una pista que señala lo que ya te ibas a comer igual.
    var pistas = pistasDeCaza(vel, etapa)
    var marcados = 0
    for (var k = 0; k < rastros.length && marcados < pistas; ++k) {
        if (rastros[k].malo) { rastros[k].marcado = true; marcados += 1 }
    }
    for (var k2 = 0; k2 < rastros.length && marcados < pistas; ++k2) {
        if (!rastros[k2].bueno && !rastros[k2].marcado) {
            rastros[k2].marcado = true; marcados += 1
        }
    }

    return { rastros: rastros, pistas: pistas }
}

//  ── el meta-juego ─────────────────────────────────────────────────
//
//  Hasta aquí el juego pedía cosas y no daba ninguna: se criaba porque sí y
//  ganar un combate solo movía un contador. Faltaba la capa que ata todo lo
//  demás — objetivos que dicen a qué jugar, una moneda que se gana jugando y
//  un sitio donde gastarla.
//
//  Los **bits** salen de pelear, y escalados por la etapa del rival, así que
//  la moneda premia lo mismo que premia la experiencia: subir de nivel de
//  juego, no repetir el combate más fácil mil veces.
function bitsDe(indice, idEnemigo, esJefe) {
    var d = indice[String(idEnemigo)]
    if (!d)
        return 0
    var base = Math.round(poderDeEtapa(d.l) * 2)
    return esJefe ? base * 5 : base
}

//  ── los objetos ───────────────────────────────────────────────────
//
//  Cuatro clases, y ninguna es «un consumible más»: cada una desbloquea algo
//  que el juego ya tenía a medias.
//
//      vitamina    entrena de golpe, respetando el tope de la etapa
//      cinta       quita peso, que era un lastre sin remedio
//      digimental  abre la evolución ARMOR, y lo sueltan los jefes
//      antídoto    abre la evolución X, y es lo más caro del mercado
//
//  Los digimentales no se listan aquí uno a uno: son once y se generan del
//  índice de especiales, que es quien sabe cuáles existen de verdad.
var OBJETOS = [
    { id: "vitamina", nombre: "Vitamina", glifo: "\u{F1130}",
      nota: "+1 al entreno que elijas", precio: 60, vendible: true },
    { id: "cinta", nombre: "Cinta de correr", glifo: "\u{F0473}",
      nota: "Le quita 4 de peso", precio: 25, vendible: true },
    { id: "antidoto", nombre: "Anticuerpo X", glifo: "\u{F0391}",
      nota: "Abre la evolución X", precio: 400, vendible: false }
]

function objetoDe(id) {
    if (String(id).indexOf("dig:") === 0) {
        var n = String(id).slice(4)
        return { id: String(id), nombre: "Digimental de " + n, dig: n,
                 glifo: "\u{F113B}", nota: "Abre la evolución Armor",
                 precio: 0, vendible: false }
    }
    for (var i = 0; i < OBJETOS.length; ++i)
        if (OBJETOS[i].id === id)
            return OBJETOS[i]
    return null
}

//  Qué digimental suelta el jefe de cada zona. Uno por zona y distinto en
//  cada una: si dos zonas soltaran el mismo, conquistar la segunda no daría
//  nada nuevo. Los dos que sobran —Amistad y Amor— salen de los objetivos,
//  para que no todo dependa de pelear.
var DIGIMENTAL_POR_ZONA = {
    "Nature Spirits":     "Sincerity",
    "Deep Savers":        "Purity",
    "Wind Guardians":     "Hope",
    "Jungle Troopers":    "Kindness",
    "Dragon's Roar":      "Courage",
    "Metal Empire":       "Knowledge",
    "Nightmare Soldiers": "Fate",
    "Virus Busters":      "Light",
    "Dark Area":          "Miracles"
}

function digimentalDeZona(zonaId) {
    var n = DIGIMENTAL_POR_ZONA[zonaId]
    return n ? "dig:" + n : ""
}

//  Lo que se puede comprar. La comida entra aquí porque el mercado es lo que
//  convierte los bits en algo útil el primer día: sin comida a la venta, un
//  jugador nuevo mira una moneda que no sabe para qué sirve.
var PRECIOS = { grande: 10, carne: 25, omni: 90, vitamina: 60, cinta: 25,
                antidoto: 400 }

function precioDe(id) {
    return PRECIOS[id] || 0
}

//  Vender da la mitad, redondeando hacia abajo. Ni más —comprar y vender en
//  bucle sería una máquina de bits— ni cero, que haría inútil el excedente.
function precioVenta(id) {
    return Math.floor(precioDe(id) / 2)
}

function seVende(id) {
    if (String(id).indexOf("dig:") === 0)
        return false
    var o = objetoDe(id)
    if (o)
        return !!o.vendible
    var c = comidaDe(id)
    //  La ración no: es infinita, y venderla sería imprimir dinero.
    return !!c && !c.infinita && precioDe(id) > 0
}

//  ── los objetivos ─────────────────────────────────────────────────
//
//  Tres familias, y las tres tiran de algo distinto para que no haya una sola
//  manera de jugar: criar, coleccionar y pelear. Cada uno mira UN número del
//  resumen que le pasa el servicio, así que añadir objetivos no obliga a
//  tocar ninguna lógica.
//
//  La recompensa se COBRA a mano. Un premio que entra solo mientras miras
//  otra pantalla no se siente como un premio: se siente como un número que
//  cambió.
var OBJETIVOS = [
    // crianza
    { id: "child",   tipo: "crianza", texto: "Lleva uno a Child",
      campo: "etapaMax", meta: 2, bits: 30 },
    { id: "adult",   tipo: "crianza", texto: "Lleva uno a Adult",
      campo: "etapaMax", meta: 3, bits: 80 },
    { id: "perfect", tipo: "crianza", texto: "Lleva uno a Perfect",
      campo: "etapaMax", meta: 4, bits: 200, objeto: "vitamina" },
    { id: "ultimate", tipo: "crianza", texto: "Lleva uno a Ultimate",
      campo: "etapaMax", meta: 5, bits: 500, objeto: "antidoto" },
    { id: "evo10",   tipo: "crianza", texto: "Evoluciona 10 veces",
      campo: "evoluciones", meta: 10, bits: 100 },
    // colección
    { id: "ver25",   tipo: "coleccion", texto: "Encuentra 25 especies",
      campo: "vistos", meta: 25, bits: 40 },
    { id: "ver100",  tipo: "coleccion", texto: "Encuentra 100 especies",
      campo: "vistos", meta: 100, bits: 150 },
    { id: "criar5",  tipo: "coleccion", texto: "Cría 5 especies",
      campo: "criados", meta: 5, bits: 60 },
    { id: "criar20", tipo: "coleccion", texto: "Cría 20 especies",
      campo: "criados", meta: 20, bits: 250, objeto: "dig:Love" },
    { id: "fusion",  tipo: "coleccion", texto: "Haz un Jogress",
      campo: "fusiones", meta: 1, bits: 80 },
    // combate
    { id: "ganar10", tipo: "combate", texto: "Gana 10 combates",
      campo: "victorias", meta: 10, bits: 30 },
    { id: "ganar50", tipo: "combate", texto: "Gana 50 combates",
      campo: "victorias", meta: 50, bits: 120, objeto: "cinta" },
    { id: "jefes3",  tipo: "combate", texto: "Vence a 3 jefes",
      campo: "jefes", meta: 3, bits: 100 },
    { id: "jefes9",  tipo: "combate", texto: "Conquista las nueve zonas",
      campo: "jefes", meta: 9, bits: 400, objeto: "dig:Friendship" },
    { id: "cazar10", tipo: "combate", texto: "Sigue 10 rastros",
      campo: "cazas", meta: 10, bits: 50 },
    // exploración
    //
    //  La carretera era el sistema más grande del juego y no tenía ni una
    //  meta colgando: se andaba porque sí. Estos cuatro la atan al
    //  meta-juego, que es lo que hace que recorrerla signifique algo.
    { id: "andar500", tipo: "exploracion", texto: "Recorre 500 de camino",
      campo: "recorrido", meta: 500, bits: 40 },
    { id: "andar5000", tipo: "exploracion", texto: "Recorre 5000 de camino",
      campo: "recorrido", meta: 5000, bits: 180, objeto: "cinta" },
    { id: "zonas3", tipo: "exploracion", texto: "Conquista 3 zonas",
      campo: "jefes", meta: 3, bits: 90 },
    { id: "vuelta2", tipo: "exploracion", texto: "Recorre una zona dos veces",
      campo: "vueltas", meta: 1, bits: 70 }
]

function objetivoDe(id) {
    for (var i = 0; i < OBJETIVOS.length; ++i)
        if (OBJETIVOS[i].id === id)
            return OBJETIVOS[i]
    return null
}

//  El estado de cada objetivo contra el resumen de la partida. Devuelve la
//  lista entera y no solo los pendientes: ver los ya cobrados es la mitad de
//  la gracia de tener objetivos.
function estadoObjetivos(resumen, cobrados) {
    resumen = resumen || {}
    cobrados = cobrados || {}
    var out = []
    for (var i = 0; i < OBJETIVOS.length; ++i) {
        var o = OBJETIVOS[i]
        var hay = resumen[o.campo] || 0
        out.push({
            obj: o,
            hay: Math.min(hay, o.meta),
            meta: o.meta,
            hecho: hay >= o.meta,
            cobrado: !!cobrados[o.id],
            //  Cobrable = hecho y sin cobrar. Es lo que enciende el botón.
            cobrable: hay >= o.meta && !cobrados[o.id]
        })
    }
    return out
}

//  ── evoluciones especiales ────────────────────────────────────────
//
//  Son el 5 % de las aristas y por eso valen: son logros, no rutas. Cada una
//  pide algo distinto y ninguna se consigue solo esperando.
//
//      Armor  el digimental que suelta el jefe de una zona
//      X      el anticuerpo, lo más caro del mercado
//      Warp   crianza impecable: CERO descuidos, y salta una etapa entera
function armoresDe(esp, id) {
    if (!esp || !esp.armor)
        return []
    return esp.armor[String(id)] || []
}

//  Las que puedes hacer AHORA, según los digimentales que lleves encima.
function armorConLoQueTienes(esp, id, objetos) {
    var todas = armoresDe(esp, id)
    var out = []
    for (var i = 0; i < todas.length; ++i) {
        var clave = "dig:" + todas[i].dig
        if ((objetos || {})[clave] > 0)
            out.push({ dig: todas[i].dig, da: todas[i].da, objeto: clave })
    }
    return out
}

function xDe(esp, id) {
    if (!esp || !esp.x)
        return ""
    return esp.x[String(id)] || ""
}

function warpDe(esp, id) {
    if (!esp || !esp.warp)
        return []
    return esp.warp[String(id)] || []
}

//  El Warp no cuesta objeto: cuesta haber criado impecable. Cero descuidos y
//  el doble de todo lo que pide una evolución normal, porque salta una etapa
//  entera y saltarla barata rompería la escalera.
function puedeWarp(etapa, minutosEnEtapa, victorias, xp, errores) {
    if (errores > 0)
        return false
    var r = requisitosDe(etapa)
    if (!r)
        return false
    return minutosEnEtapa >= r.minutos * 2 && victorias >= r.victorias * 2
        && xp >= r.xp * 2
}

//  ── el código de equipo ───────────────────────────────────────────
//
//  Los aparatos peleaban entre sí por cable o por infrarrojos. Aquí no hay
//  cable ni servidor, así que el equipo se empaqueta en un CÓDIGO que se pasa
//  como se pasa cualquier cosa entre dos personas: copiando y pegando.
//
//  Y se lee del portapapeles con un campo de texto, no con la API de
//  portapapeles de k4: esa pide permiso a propósito —lleva contraseñas y
//  tokens— y gastarlo en un juego sería desproporcionado. Un `TextInput`
//  acepta Ctrl+V sin permiso ninguno.
//
//  Alfabeto **Crockford base32**: sin las letras que se confunden al copiar a
//  mano —ni O ni I ni L ni U— y con equivalencias canónicas al leer, así que
//  un cero escrito como «O» sigue valiendo. Un código que se lee mal y da un
//  equipo distinto sin avisar es peor que uno que no se lee.
var B32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

function _valorB32(c) {
    //  Las confusiones habituales, resueltas hacia el dígito.
    if (c === "O" || c === "o") return 0
    if (c === "I" || c === "i" || c === "L" || c === "l") return 1
    var i = B32.indexOf(c.toUpperCase())
    return i < 0 ? -1 : i
}

//  Cuántos bits ocupa cada cosa. La especie necesita 11 —hay 1488 fichas— y
//  cada entreno 6, que llega de sobra para el tope de 36 de Ultimate.
var BITS_ESPECIE = 11
var BITS_ENTRENO = 6
var MAX_EQUIPO = 3

function _aBits(n, cuantos, out) {
    for (var i = cuantos - 1; i >= 0; --i)
        out.push((n >> i) & 1)
}

function _deBits(bits, desde, cuantos) {
    var n = 0
    for (var i = 0; i < cuantos; ++i)
        n = (n << 1) | (bits[desde + i] || 0)
    return n
}

//  Suma de comprobación de 8 bits sobre lo que va dentro. Sin ella, cambiar
//  una letra al copiar daría un equipo distinto y perfectamente válido: el
//  jugador pelearía contra otra cosa sin enterarse jamás.
function _suma(bits) {
    var s = 0
    for (var i = 0; i < bits.length; ++i)
        s = (s * 2 + bits[i]) % 251        // primo: reparte mejor los cambios
    return s & 0xFF
}

var VERSION_CODIGO = 1

//  `equipo` es una lista de { especie, entrenos }.
function codificarEquipo(equipo) {
    if (!equipo || equipo.length === 0)
        return ""
    var n = Math.min(MAX_EQUIPO, equipo.length)
    var bits = []
    _aBits(VERSION_CODIGO, 4, bits)
    _aBits(n - 1, 2, bits)
    for (var i = 0; i < n; ++i) {
        var c = equipo[i]
        var id = parseInt(c.especie, 10) || 0
        _aBits(id & 0x7FF, BITS_ESPECIE, bits)
        for (var j = 0; j < ESTADISTICAS.length; ++j) {
            var v = Math.max(0, Math.min(63,
                Math.round(entrenoDe(c.entrenos, ESTADISTICAS[j]))))
            _aBits(v, BITS_ENTRENO, bits)
        }
    }
    _aBits(_suma(bits), 8, bits)

    //  A base32, rellenando con ceros el último grupo de cinco.
    var texto = ""
    for (var k = 0; k < bits.length; k += 5) {
        var v2 = 0
        for (var m = 0; m < 5; ++m)
            v2 = (v2 << 1) | (bits[k + m] || 0)
        texto += B32[v2]
    }
    //  En grupos de cuatro: un chorro de veinticuatro letras no se compara de
    //  un vistazo ni se dicta por teléfono.
    var out = ""
    for (var p = 0; p < texto.length; p += 4)
        out += (p > 0 ? "-" : "") + texto.slice(p, p + 4)
    return out
}

//  Devuelve { equipo } o { error }. Nunca lanza: un código mal pegado es lo
//  más normal del mundo y tiene que decir QUÉ pasa, no romperse.
function descodificarEquipo(indice, texto) {
    var limpio = String(texto || "").replace(/[^0-9A-Za-z]/g, "")
    if (limpio.length === 0)
        return { error: "vacio" }

    var bits = []
    for (var i = 0; i < limpio.length; ++i) {
        var v = _valorB32(limpio[i])
        if (v < 0)
            return { error: "letra", cual: limpio[i] }
        _aBits(v, 5, bits)
    }

    if (bits.length < 4 + 2 + 35 + 8)
        return { error: "corto" }

    var ver = _deBits(bits, 0, 4)
    if (ver !== VERSION_CODIGO)
        return { error: "version", cual: String(ver) }

    var n = _deBits(bits, 4, 2) + 1
    var necesarios = 6 + n * (BITS_ESPECIE + 4 * BITS_ENTRENO)
    if (bits.length < necesarios + 8)
        return { error: "corto" }

    //  La suma se calculó sobre TODO lo anterior a ella, así que se recorta
    //  ahí: los bits de relleno del último grupo no cuentan.
    var suma = _deBits(bits, necesarios, 8)
    if (_suma(bits.slice(0, necesarios)) !== suma)
        return { error: "suma" }

    //  Y el relleno del último grupo tiene que ser CERO. Sin esta línea, el
    //  último carácter podía cambiar sin que nada se quejara —solo tocaba
    //  bits de relleno— y dos códigos distintos daban el mismo equipo. No
    //  hacía daño, pero un código que no es el que te pasaron no puede
    //  aceptarse en silencio.
    for (var r = necesarios + 8; r < bits.length; ++r)
        if (bits[r] !== 0)
            return { error: "suma" }

    var equipo = []
    var p = 6
    for (var k = 0; k < n; ++k) {
        var id = String(_deBits(bits, p, BITS_ESPECIE))
        p += BITS_ESPECIE
        var ent = {}
        for (var j = 0; j < ESTADISTICAS.length; ++j) {
            ent[ESTADISTICAS[j]] = _deBits(bits, p, BITS_ENTRENO)
            p += BITS_ENTRENO
        }
        if (!indice[id])
            return { error: "especie", cual: id }
        //  Con el tope de su etapa: un código manipulado a mano no puede
        //  traer un Child con 63 de todo.
        var tope = topeEntreno(indice[id].l)
        for (var j2 = 0; j2 < ESTADISTICAS.length; ++j2)
            ent[ESTADISTICAS[j2]] = Math.min(tope, ent[ESTADISTICAS[j2]])
        equipo.push({ especie: id, entrenos: ent })
    }
    return { equipo: equipo }
}

//  El texto del error, que es lo que ve el jugador. Va aquí y no en la vista
//  porque es parte de la regla: si el código no vale, hay que poder decir por
//  qué sin adivinarlo.
function motivoDeCodigo(err) {
    switch (err) {
    case "vacio":   return "Pega un código"
    case "letra":   return "Ese código tiene letras que no van"
    case "corto":   return "El código está incompleto"
    case "version": return "Ese código es de otra versión"
    case "suma":    return "El código está mal copiado"
    case "especie": return "Ese código nombra un Digimon que no existe"
    default:        return "Código no válido"
    }
}

//  Quién gana el encuentro: se pelea por parejas, uno contra uno, y gana quien
//  se lleve más asaltos. Con equipos de distinto tamaño se juegan tantos
//  asaltos como tenga el más corto, para que traer más bichos no sea ganar.
function asaltosDe(mio, suyo) {
    return Math.min(mio ? mio.length : 0, suyo ? suyo.length : 0)
}

//  ── el aliado ─────────────────────────────────────────────────────
//
//  `obj_Player_Helper_SPAtk` del emulador: un segundo bicho entra, pega una
//  vez y se va. Aquí sale **el mejor criado de la guardería**, y esa regla es
//  a propósito: la guardería llevaba desde que existe sin hacer nada más que
//  guardar, y ahora criar a un segundo tiene una consecuencia en combate.
//
//  Reemplaza a la llamada de carga máxima —mismo botón, misma energía— porque
//  gastar tres de energía en multiplicar tu propio golpe era una cifra, y esto
//  es alguien. Si la guardería está vacía, la llamada vieja sigue ahí.
function aliadoDe(indice, banco) {
    if (!banco || banco.length === 0)
        return null
    var mejor = null, mejorP = -1
    for (var i = 0; i < banco.length; ++i) {
        var c = banco[i]
        var d = c && indice[String(c.especie)]
        if (!d)
            continue
        var e = c.entrenos
        var suma = e ? (e.pv || 0) + (e.atq || 0) + (e.def || 0) + (e.vel || 0)
                     : (c.fuerza || 0)
        //  La etapa manda sobre el entreno: un Adult a medias ayuda más que
        //  un Baby a tope, igual que en cualquier otra parte del juego.
        var p = poderDeEtapa(d.l) * 100 + suma
        if (p > mejorP) {
            mejorP = p
            mejor = { hueco: i, especie: String(c.especie),
                      entrenos: e || {}, nombre: d.n, etapa: d.l }
        }
    }
    return mejor
}

//  El golpe del aliado NO se esquiva: es una emboscada y cuesta energía, así
//  que tiene que valer siempre la pena. Usa su forma más alta desbloqueada,
//  que es el premio de haberlo entrenado.
function golpeAliado(indice, aliado, idSuyo) {
    if (!aliado || !indice[String(aliado.especie)] || !indice[String(idSuyo)])
        return null
    var dA = indice[String(aliado.especie)], dS = indice[String(idSuyo)]
    var st = statsDe(indice, aliado.especie, aliado.entrenos)
    var suyo = statsDe(indice, idSuyo, 0)
    var tec = tecnicasConForma(indice, aliado.especie, aliado.entrenos)
    var elegida = tec[tec.length - 1]
    var mult = elegida.forma === "columna" ? 1.9
             : elegida.forma === "rafaga" ? 1.35 : 1.3
    return {
        especie: String(aliado.especie),
        nombre: dA.n,
        tecnica: elegida.nombre,
        forma: elegida.forma,
        daño: Math.max(1, Math.round(
            dañoDe(st, suyo, dA.a, dS.a) * mult)),
        estado: estadoQueInflige(indice, aliado.especie)
    }
}

//  El suelo de 1 existe para que un combate desigual TERMINE, en vez de
//  quedarse en dos bichos que no se hacen nada.
function dañoDe(atacante, defensor, atrA, atrD) {
    var bruto = atacante.atq * ventaja(atrA, atrD) - defensor.def * 0.5
    return Math.max(1, Math.round(bruto))
}

var MAX_TURNOS = 40

//  Dos bichos muy defensivos —un Mineral contra un Slime, ambos Data— pegan
//  en el suelo de 1 y no se matan en cuarenta turnos: medido, 10 de 300 se
//  quedaban colgados. En vez de subir el tope, el combate SE CALIENTA a
//  partir del turno 16. Así siempre termina y, de paso, un combate largo se
//  vuelve dramático en vez de un empate aburrido.
function escalada(turno) {
    return 1 + Math.max(0, turno - 16) * 0.18
}

//  Con tope: sin él un Ultimate contra un Child no fallaría jamás y el
//  combate dejaría de tener azar.
function probEsquiva(defensor, atacante) {
    var d = (defensor.vel - atacante.vel) / Math.max(1, atacante.vel)
    return Math.max(0, Math.min(0.35, d * 0.4))
}

//  Los `next` que están en el peldaño siguiente, sin más filtro. Es la
//  versión cruda que usa `tieneSalida`: sin el filtro de viabilidad, que es
//  lo que evita que la comprobación se llame a sí misma sin fondo.
function _crudos(indice, id) {
    var d = indice[String(id)]
    if (!d)
        return []
    var sig = escalonSiguiente(d.l)
    if (!sig)
        return []
    var out = []
    for (var i = 0; i < d.nx.length; ++i) {
        var c = indice[String(d.nx[i])]
        if (c && c.ls.indexOf(sig) >= 0)
            out.push(String(d.nx[i]))
    }
    return out
}

//  Ultimate es la cima: allí no tener salida es haber llegado, no un atasco.
function tieneSalida(indice, id) {
    var d = indice[String(id)]
    if (!d)
        return false
    if (d.l === "Ultimate")
        return true
    return _crudos(indice, id).length > 0
}

function candidatosEvolucion(indice, id) {
    var out = _crudos(indice, id)

    //  Se descartan los que no tienen futuro. La API es una enciclopedia y
    //  tiene ramas que mueren a medio camino: dejarlas convierte una mala
    //  tirada en una partida sin techo, y el jugador no puede ni saberlo.
    //  Si TODOS mueren se dejan tal cual, que quedarse sin evolución es peor
    //  que evolucionar a un callejón.
    var vivos = []
    for (var i = 0; i < out.length; ++i) {
        if (tieneSalida(indice, out[i]))
            vivos.push(out[i])
    }
    if (vivos.length > 0)
        out = vivos

    //  Orden estable: la API no promete ninguno, y sin esto la misma crianza
    //  podría dar bichos distintos entre dos versiones de los datos.
    out.sort(function (a, b) {
        return indice[a].n.localeCompare(indice[b].n)
    })
    return out
}

function candidatosRegresion(indice, id) {
    var d = indice[String(id)]
    if (!d)
        return []
    var prev = escalonPrevio(d.l)
    if (!prev)
        return []
    var out = []
    for (var i = 0; i < d.pr.length; ++i) {
        var c = indice[String(d.pr[i])]
        if (c && c.ls.indexOf(prev) >= 0)
            out.push(String(d.pr[i]))
    }
    out.sort(function (a, b) {
        return indice[a].n.localeCompare(indice[b].n)
    })
    return out
}

//  De 0 (impecable) a 3 (desastre). Elige RAMA, no si evolucionas:
//  evolucionar evoluciona todo el mundo, como en los aparatos. Criar bien
//  te da el candidato de cabecera.
//  `exceso` es lo que le sobra de peso sobre el mínimo de su etapa: criar
//  bien incluye no cebarlo, que es de lo que va la mitad de un vpet.
function gradoCrianza(errores, fuerza, enfermo, exceso) {
    var g = 0
    if (errores >= 1) g += 1
    if (errores >= 4) g += 1
    if (fuerza < 8)   g += 1
    if (enfermo)      g += 1
    if ((exceso || 0) >= 10) g += 1
    return Math.min(3, g)
}

//  Los habitantes de una zona a tu altura: un peldaño arriba o abajo. El de
//  arriba es el que da miedo, y por eso explorar tiene sentido.
//  El radio se abre hasta encontrar a alguien. Con radio fijo hay zonas sin
//  vecinos a tu altura —la Jungla y el Área Oscura no tienen ningún Baby I—
//  y explorarlas de recién nacido no encontraba nada: no un combate difícil,
//  sino un mapa que no responde, que es mucho peor.
function habitantesDe(indice, zonaId, etapaRef) {
    var iRef = Math.max(0, ESCALERA.indexOf(etapaRef))
    for (var radio = 1; radio <= ESCALERA.length; ++radio) {
        var out = []
        for (var k in indice) {
            var d = indice[k]
            if (!d.f || d.f.indexOf(zonaId) < 0)
                continue
            var i = ESCALERA.indexOf(d.l)
            if (i < 0)
                continue
            if (Math.abs(i - iRef) <= radio)
                out.push(k)
        }
        if (out.length > 0)
            return out
    }
    return []
}

//  ── el choque: piedra, papel y tijera con esteroides ──────────────
//
//  El emulador resuelve el combate con cuatro fases —`obj_turn_attack`,
//  `obj_turn_prep_def`, `obj_turn_defense`, `obj_turn_collision`— y CERO
//  entrada del jugador: todo son Alarm y Step. Es fiel y es un vídeo.
//
//  Aporrear un botón tampoco valía: aporrear es esfuerzo, no decisión, y
//  aburre por lo mismo que aburre mirar. Así que las cuatro fases del
//  emulador pasan a ser tres cosas que ELIGES:
//
//      atacar  gana a  cargar     (le pillas a medio preparar)
//      defender gana a  atacar    (bloqueas y devuelves)
//      cargar  gana a  defender   (te preparas mientras él se cubre)
//
//  Y los empates no son nada: atacar contra atacar es la COLISIÓN del
//  emulador —los dos haces chocan y los dos se llevan lo suyo—, que es la
//  fase que le da nombre a `obj_turn_collision`.
var ACCIONES = ["atacar", "defender", "cargar"]

function chocar(mia, suya) {
    if (mia === suya) {
        if (mia === "atacar")  return { tipo: "colision", ganador: "" }
        if (mia === "defender") return { tipo: "nada", ganador: "" }
        return { tipo: "ambosCargan", ganador: "" }
    }
    if (mia === "atacar" && suya === "cargar")   return { tipo: "pillado", ganador: "mio" }
    if (mia === "defender" && suya === "atacar") return { tipo: "parada", ganador: "mio" }
    if (mia === "cargar" && suya === "defender") return { tipo: "cargado", ganador: "mio" }
    if (suya === "atacar" && mia === "cargar")   return { tipo: "pillado", ganador: "suyo" }
    if (suya === "defender" && mia === "atacar") return { tipo: "parada", ganador: "suyo" }
    return { tipo: "cargado", ganador: "suyo" }
}

//  Qué hace el rival. No es azar puro: los que pegan fuerte atacan más y los
//  duros se cubren más, así que su ficha se nota en cómo juega y aprendes a
//  leerlo. Con un poso de aleatoriedad para que no sea un puzle resuelto.
function eligeRival(indice, idSuyo, azar, stats) {
    var st = stats || statsDe(indice, idSuyo, 0)
    //  Y su CARÁCTER, que es lo que hace que dos rivales de la misma etapa no
    //  peleen igual. Sale de la especie, así que el mismo bicho siempre juega
    //  parecido y se puede aprender a leerlo.
    var c = caracterDeEspecie(idSuyo)
    var pesoAtacar = (3 + st.atq / Math.max(1, st.def)) * c.atacar
    var pesoDefender = (2 + st.def / Math.max(1, st.atq)) * c.defender
    var pesoCargar = 2 * c.cargar
    var total = pesoAtacar + pesoDefender + pesoCargar
    var r = (azar ? azar() : Math.random()) * total
    if (r < pesoAtacar) return "atacar"
    if (r < pesoAtacar + pesoDefender) return "defender"
    return "cargar"
}

//  Con qué forma pega el modo sin manos. La columna queda fuera a propósito:
//  es una apuesta a que el rival no ataca este intercambio, y eso es una
//  lectura que solo puede hacer alguien que esté mirando. Entre la simple y
//  la ráfaga elige por la defensa del rival, que es justo la decisión que
//  distingue a las dos.
function formaSinManos(indice, idMio, idSuyo, mio, suyo, formas) {
    var tiene = { simple: false, rafaga: false }
    for (var i = 0; i < formas.length; ++i)
        if (formas[i].forma in tiene)
            tiene[formas[i].forma] = true
    if (!tiene.rafaga)
        return "simple"
    if (!tiene.simple)
        return "rafaga"
    //  La ráfaga se cuela por media defensa; compensa cuando la defensa
    //  pesa de verdad frente a lo que pegas.
    return suyo.def >= mio.atq * 0.5 ? "rafaga" : "simple"
}

//  ── un intercambio ────────────────────────────────────────────────
//
//  El choque de haces del aparato: los dos disparan y el punto de encuentro
//  se va hacia uno u otro. Aquí vive la unidad del combate, y existe separada
//  porque ahora hay DOS maneras de jugarlo y no puede haber dos reglas: a
//  mano, con lo que el jugador empuje, y sin manos, para el IPC y las pruebas.
//
//  `empuje` va de 0 a 1: es lo que ha puesto el jugador de su parte. 0,5 es
//  "ni fu ni fa" y es lo que usa el modo sin manos, para que jugar a ciegas no
//  sea mejor ni peor que no jugar.
function intercambio(indice, idMio, idSuyo, opts) {
    opts = opts || {}
    var dMio = indice[String(idMio)], dSuyo = indice[String(idSuyo)]
    if (!dMio || !dSuyo)
        return null

    var mio = opts.statsMio || statsDe(indice, idMio, opts.fuerza || 0, opts.peso)
    var suyo = opts.statsSuyo || statsDe(indice, idSuyo, 0)

    //  Los estados pesan antes que nada: la debilidad tiene que morder sobre
    //  el ataque de este intercambio, no sobre el del siguiente.
    var estadosMios = opts.estadosMios || []
    var estadosSuyos = opts.estadosSuyos || []
    mio = conEstados(mio, estadosMios)
    suyo = conEstados(suyo, estadosSuyos)

    //  El estado del bicho pesa, y esto SE PERDIÓ al reescribir el choque:
    //  durante un rato un bicho enfermo y muerto de hambre peleaba igual que
    //  uno sano, que es tanto como decir que cuidarlo no servía para nada.
    //  Lo cazó la prueba de «descuidado se gana menos».
    if (opts.enfermo) {
        mio.atq = Math.max(1, Math.round(mio.atq * 0.6))
        mio.def = Math.max(1, Math.round(mio.def * 0.6))
    }
    var maxC = opts.maxCorazones || 4
    var hambre = opts.hambre === undefined ? maxC : opts.hambre
    var animo = opts.animo === undefined ? maxC : opts.animo
    var flojera = 1 - 0.25 * ((maxC - hambre) + (maxC - animo)) / (2 * maxC)
    //  Y el vigor de la carne tira para el otro lado: es lo que hace que
    //  comer bien antes de pelear sea una decisión y no un trámite.
    mio.atq = Math.max(1, Math.round(mio.atq * flojera * bonusVigor(opts.vigor || 0)))

    //  Lo que cada uno eligió. Paralizado no eliges: `nada` pierde contra
    //  todo, así que el intercambio se resuelve con el rival haciendo lo suyo
    //  sin oposición. Es el turno robado, y se ve.
    var paralizado = tieneEstado(estadosMios, "paralisis")
    var mia = paralizado ? "nada" : (opts.mia || "atacar")
    var suya = opts.suya || eligeRival(indice, idSuyo, opts.azar)
    var res = paralizado
            ? (suya === "atacar" ? { tipo: "pillado", ganador: "suyo" }
             : suya === "cargar" ? { tipo: "ambosCargan", ganador: "suyo" }
             : { tipo: "nada", ganador: "" })
            : chocar(mia, suya)

    //  La carga acumulada multiplica tu siguiente golpe. Es lo que hace que
    //  cargar sea una apuesta y no un turno perdido.
    var carga = 1 + 0.5 * Math.min(3, opts.carga || 0)

    //  Con qué forma pega cada uno. La tuya la eliges; la del rival sale de
    //  las que su etapa le abre, rotando por turno.
    var turno = opts.turno || 0
    var formaMia = opts.forma || "simple"
    var nSuyas = tecnicasDeRival(indice, idSuyo)
    var iSuya = nSuyas > 0 ? Math.floor(turno / 2) % nSuyas : 0
    var formaSuya = formaDe(iSuya)

    var azar = opts.azar || Math.random
    var golpeMio = golpeDe(mio, suyo, dMio.a, dSuyo.a, formaMia, azar)
    var golpeSuyo = golpeDe(suyo, mio, dSuyo.a, dMio.a, formaSuya, azar)

    var daño = 0, aQuien = "", cargaGanada = 0, fallo = false, impactos = 0
    switch (res.tipo) {
    case "pillado":
        //  Pillar cargando duele: es el castigo por avariciar.
        if (res.ganador === "mio") {
            daño = Math.round(golpeMio.daño * carga * 1.4); aQuien = "suyo"
            fallo = golpeMio.fallo; impactos = golpeMio.impactos
        } else {
            daño = Math.round(golpeSuyo.daño * 1.4); aQuien = "mio"
            fallo = golpeSuyo.fallo; impactos = golpeSuyo.impactos
        }
        break
    case "parada":
        //  Parar devuelve algo, pero poco: defender es sobrevivir, no ganar.
        //  El contragolpe no lleva forma —no es tu técnica, es el rebote— y
        //  por eso tampoco se esquiva ni deja estado.
        if (res.ganador === "mio") {
            daño = Math.max(1, Math.round(dañoDe(mio, suyo, dMio.a, dSuyo.a) * 0.4))
            aQuien = "suyo"
        } else {
            daño = Math.max(1, Math.round(dañoDe(suyo, mio, dSuyo.a, dMio.a) * 0.4))
            aQuien = "mio"
        }
        break
    case "cargado":
        //  Cargar contra una defensa no hace daño: da munición.
        cargaGanada = res.ganador === "mio" ? 1 : 0
        break
    case "colision":
        //  La columna es lenta: si el otro ataca a la vez, no llega a salir.
        //  Vale para los dos lados —el rival también se queda vendido si le
        //  toca columna— porque una regla que solo castiga al jugador no es
        //  una regla, es un impuesto.
        var lentoMio = formaMia === "columna"
        var lentoSuyo = formaSuya === "columna"
        if (lentoMio && !lentoSuyo) {
            daño = golpeSuyo.daño; aQuien = "mio"; fallo = true
        } else if (lentoSuyo && !lentoMio) {
            daño = Math.round(golpeMio.daño * carga); aQuien = "suyo"
            impactos = golpeMio.impactos; fallo = golpeMio.fallo
        } else if (lentoMio && lentoSuyo) {
            //  Los dos lentos: ninguno sale a tiempo y no pasa nada.
            fallo = true
        } else {
            //  Los dos haces chocan y los dos se llevan lo suyo, a la mitad.
            daño = Math.round(golpeMio.daño * carga * 0.5)
            aQuien = "ambos"
            fallo = golpeMio.fallo
            impactos = golpeMio.impactos
        }
        break
    case "ambosCargan":
        cargaGanada = paralizado ? 0 : 1
        break
    default:
        break     // los dos se cubren: no pasa nada, y se nota
    }

    //  Un golpe que no toca no deja estado: envenenar con un fallo sería
    //  regalar la mitad del sistema.
    var infligido = ""
    if (daño > 0 && (res.tipo === "pillado" || res.tipo === "colision")) {
        var atacaMio = aQuien === "suyo" || aQuien === "ambos"
        var forma = atacaMio ? formaMia : formaSuya
        var cual = estadoQueInflige(indice, atacaMio ? idMio : idSuyo)
        if (cual && azar() < (PROB_ESTADO[forma] || 0))
            infligido = cual
    }

    return {
        mia: mia,
        suya: suya,
        tipo: res.tipo,
        ganador: res.ganador,
        aQuien: aQuien,
        cargaGanada: cargaGanada,
        daño: Math.max(0, daño),
        dañoSuyo: aQuien === "ambos"
                ? Math.max(1, Math.round(golpeSuyo.daño * 0.5)) : 0,
        paralizado: paralizado,
        forma: aQuien === "mio" ? formaSuya : formaMia,
        fallo: fallo,
        impactos: impactos,
        //  A quién le cae el estado: al que recibió el golpe.
        estado: infligido,
        estadoA: infligido === "" ? ""
               : (aQuien === "mio" ? "mio" : "suyo"),
        //  La fuerza solo cuenta para el TUYO: los rivales no entrenan.
        tecnica: aQuien === "mio"
               ? tecnicaDeRival(indice, idSuyo, turno)
               : tecnicaDe(indice, idMio, turno, opts.fuerza || 0)
    }
}

//  La técnica del rival sale de las que su etapa le abre, no de un entreno
//  que no tiene.
function tecnicaDeRival(indice, id, turno) {
    var d = indice[String(id)]
    var sk = d && d.sk ? d.sk : []
    if (sk.length === 0)
        return ""
    var n = tecnicasDeRival(indice, id)
    return sk[Math.floor((turno || 0) / 2) % Math.max(1, n)]
}

//  El combate entero de una vez, para el IPC y las pruebas.
//
//  Encadena LOS MISMOS choques que la pelea jugada, eligiendo al azar por el
//  jugador. Antes tenía su propio bucle de esquivas y turnos —dos reglas
//  distintas para lo mismo— y eso es exactamente lo que acaba divergiendo:
//  el día que se toca el triángulo, el IPC sigue jugando a otra cosa.
function resolverCombate(indice, idMio, idSuyo, opts) {
    opts = opts || {}
    var azar = opts.azar || Math.random
    var dMio = indice[String(idMio)], dSuyo = indice[String(idSuyo)]
    if (!dMio || !dSuyo)
        return null

    var mio = statsDe(indice, idMio, opts.fuerza || 0, opts.peso)
    //  El rival puede venir ENTRENADO: en un duelo por código el otro equipo
    //  lo ha criado alguien. Sin esto la pelea sin manos peleaba siempre
    //  contra bichos recién nacidos y el código no habría servido de nada.
    var suyo = opts.statsSuyo || statsDe(indice, idSuyo, opts.entrenosSuyos || 0)
    var vMio = mio.vida, vSuyo = suyo.vida
    var carga = 0
    var turnos = []
    var n = 0
    //  Con lo que traigas puesto: si te has comido algo en mal estado, el
    //  veneno entra contigo. Un estado que se borrase al empezar la pelea no
    //  sería un castigo, sería un adorno de la pantalla de casa.
    var estadosMios = (opts.estadosMios || []).slice()
    var estadosSuyos = []
    var formas = tecnicasConForma(indice, idMio, opts.fuerza || 0)

    //  El aliado entra solo, y una vez: sin manos no hay a quién preguntar.
    //  Lo gasta al primer intercambio en que va perdiendo, que es cuando lo
    //  gastaría cualquiera.
    var aliado = opts.aliado || null
    var aliadoUsado = false

    while (vMio > 0 && vSuyo > 0 && n < MAX_TURNOS) {
        //  Sin manos se juega con el MISMO criterio que el rival, no a
        //  cara o cruz. Medido: eligiendo al azar contra un rival que elige
        //  con criterio se ganaba el 32 % de los combates a igualdad de
        //  etapa, y con los dos jugando igual, el 51 %. Aquel 32 % no decía
        //  nada del equilibrio del combate —decía que el modo automático
        //  jugaba mal—, y encima castigaba a quien pelea por IPC.
        var mia = eligeRival(indice, idMio, azar, mio)
        var forma = formaSinManos(indice, idMio, idSuyo, mio, suyo, formas)
        var r = intercambio(indice, idMio, idSuyo, {
            fuerza: opts.fuerza, enfermo: opts.enfermo, hambre: opts.hambre,
            animo: opts.animo, maxCorazones: opts.maxCorazones, zona: opts.zona,
            mia: mia, carga: carga, turno: n, azar: azar, forma: forma,
            vigor: opts.vigor, statsSuyo: suyo,
            estadosMios: estadosMios, estadosSuyos: estadosSuyos
        })
        if (!r)
            break

        if (r.aQuien === "ambos") {
            vSuyo -= r.daño
            vMio -= r.dañoSuyo
            carga = 0
        } else if (r.aQuien === "suyo") {
            vSuyo -= r.daño
            carga = 0
        } else if (r.aQuien === "mio") {
            vMio -= r.daño
            carga = 0
        } else {
            carga = Math.min(3, carga + r.cargaGanada)
        }

        if (r.estado) {
            if (r.estadoA === "mio") estadosMios = aplicarEstado(estadosMios, r.estado)
            else estadosSuyos = aplicarEstado(estadosSuyos, r.estado)
        }

        //  El aliado: una vez, cuando la cosa se tuerce. Con el 45 % de vida
        //  salía en uno de cada diez combates —esperaba a una situación tan
        //  apurada que casi nunca llegaba—, y un recurso de una vez por
        //  combate no se guarda: se usa en cuanto ayuda, que es lo que haría
        //  cualquiera con el botón delante.
        if (aliado && !aliadoUsado && vMio > 0 && vSuyo > 0
                && vMio < mio.vida * 0.7) {
            var ga = golpeAliado(indice, aliado, idSuyo)
            if (ga) {
                vSuyo -= ga.daño
                aliadoUsado = true
                if (ga.estado)
                    estadosSuyos = aplicarEstado(estadosSuyos, ga.estado)
            }
        }

        //  Y el veneno cobra al cerrar el intercambio, con lo que puede
        //  rematar: un combate ganado por envenenamiento es una victoria.
        var tm = tickEstados(estadosMios, mio.vida)
        var ts = tickEstados(estadosSuyos, suyo.vida)
        estadosMios = tm.estados
        estadosSuyos = ts.estados
        vMio -= tm.quema
        vSuyo -= ts.quema

        //  El calentón, y más fuerte que antes: con elecciones al azar salen
        //  muchos turnos sin daño —los dos se cubren, los dos cargan— y 20 de
        //  cada 300 combates no acababan en cuarenta turnos. Desde el 12 se
        //  pierde vida cada turno, y cada vez más.
        if (n >= 12) {
            var chispa = Math.ceil((n - 11) / 2)
            vMio -= chispa
            vSuyo -= chispa
        }

        turnos.push({
            mio: r.aQuien === "suyo" || r.aQuien === "ambos",
            esquiva: r.aQuien === "",
            daño: r.daño,
            tecnica: r.tecnica,
            mia: r.mia,
            suya: r.suya,
            forma: r.forma,
            fallo: r.fallo,
            estado: r.estado,
            paralizado: r.paralizado
        })
        n += 1
    }

    return {
        enemigo: String(idSuyo),
        turnos: turnos,
        //  Quien llame decide qué cobrar por él: sale gratis aquí y la
        //  energía la descuenta el servicio, igual que en la pelea a mano.
        aliadoUsado: aliadoUsado,
        gane: vSuyo <= 0 && vMio > 0,
        vidaMia: mio.vida,
        vidaSuya: suyo.vida,
        restanteMia: Math.max(0, vMio),
        restanteSuya: Math.max(0, vSuyo)
    }
}

//  Para node. QML no define `module`, así que la guarda lo deja pasar.
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        ESCALERA: ESCALERA,
        escalonSiguiente: escalonSiguiente,
        escalonPrevio: escalonPrevio,
        poderDeEtapa: poderDeEtapa,
        ventaja: ventaja,
        statsDe: statsDe,
        dañoDe: dañoDe,
        probEsquiva: probEsquiva,
        candidatosEvolucion: candidatosEvolucion,
        candidatosRegresion: candidatosRegresion,
        gradoCrianza: gradoCrianza,
        AGENDA: AGENDA,
        SEPARACION: SEPARACION,
        agendaDelDia: agendaDelDia,
        sucesosEntre: sucesosEntre,
        drenar: drenar,
        pesoBaseDe: pesoBaseDe,
        excesoDePeso: excesoDePeso,
        habitantesDe: habitantesDe,
        CONSEJOS: CONSEJOS,
        consejosDe: consejosDe,
        CARACTERES: CARACTERES,
        caracterDe: caracterDe,
        caracterDeEspecie: caracterDeEspecie,
        ZANCADAS: ZANCADAS,
        zancadaDe: zancadaDe,
        distanciaJefe: distanciaJefe,
        PASO_HITO: PASO_HITO,
        EVENTOS: EVENTOS,
        hitosDe: hitosDe,
        eventoDeHito: eventoDeHito,
        hitosEntre: hitosEntre,
        proximoHito: proximoHito,
        estadoCarretera: estadoCarretera,
        semillaDeVuelta: semillaDeVuelta,
        jefeDe: jefeDe,
        raizDe: raizDe,
        requisitosDe: requisitosDe,
        faltaPara: faltaPara,
        cumpleRequisitos: cumpleRequisitos,
        xpDe: xpDe,
        jogressDe: jogressDe,
        jogressCon: jogressCon,
        escalada: escalada,
        intercambio: intercambio,
        chocar: chocar,
        eligeRival: eligeRival,
        ACCIONES: ACCIONES,
        arquetipoDe: arquetipoDe,
        GOLPES: GOLPES,
        FORMAS_GOLPE: FORMAS_GOLPE,
        auraDeAtributo: auraDeAtributo,
        golpeVistaDe: golpeVistaDe,
        repartoDeAtributo: repartoDeAtributo,
        bonusZona: bonusZona,
        B32: B32,
        MAX_EQUIPO: MAX_EQUIPO,
        VERSION_CODIGO: VERSION_CODIGO,
        codificarEquipo: codificarEquipo,
        descodificarEquipo: descodificarEquipo,
        motivoDeCodigo: motivoDeCodigo,
        asaltosDe: asaltosDe,
        bitsDe: bitsDe,
        OBJETOS: OBJETOS,
        objetoDe: objetoDe,
        DIGIMENTAL_POR_ZONA: DIGIMENTAL_POR_ZONA,
        digimentalDeZona: digimentalDeZona,
        PRECIOS: PRECIOS,
        precioDe: precioDe,
        precioVenta: precioVenta,
        seVende: seVende,
        OBJETIVOS: OBJETIVOS,
        objetivoDe: objetivoDe,
        estadoObjetivos: estadoObjetivos,
        armoresDe: armoresDe,
        armorConLoQueTienes: armorConLoQueTienes,
        xDe: xDe,
        warpDe: warpDe,
        puedeWarp: puedeWarp,
        COMIDAS: COMIDAS,
        comidaDe: comidaDe,
        bonusVigor: bonusVigor,
        CAZA_POR_ZONA: CAZA_POR_ZONA,
        RASTROS: RASTROS,
        pistasDeCaza: pistasDeCaza,
        montarCaza: montarCaza,
        marcarOtro: marcarOtro,
        tecnicaDe: tecnicaDe,
        tecnicasAbiertas: tecnicasAbiertas,
        tecnicasDeRival: tecnicasDeRival,
        tecnicaDeRival: tecnicaDeRival,
        FORMAS: FORMAS,
        formaDe: formaDe,
        tecnicasConForma: tecnicasConForma,
        golpeDe: golpeDe,
        ESTADOS: ESTADOS,
        PROB_ESTADO: PROB_ESTADO,
        estadoQueInflige: estadoQueInflige,
        aplicarEstado: aplicarEstado,
        tieneEstado: tieneEstado,
        tickEstados: tickEstados,
        conEstados: conEstados,
        aliadoDe: aliadoDe,
        golpeAliado: golpeAliado,
        ESTADISTICAS: ESTADISTICAS,
        topeEntreno: topeEntreno,
        entrenoDe: entrenoDe,
        tieneSalida: tieneSalida,
        resolverCombate: resolverCombate
    }
}
