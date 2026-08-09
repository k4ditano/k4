//  Pruebas de las reglas del Digivice, sin Quickshell.
//
//      node tools/digivice_test.js
//
//  Carga services/DigiviceReglas.js quitándole las directivas de QML (.pragma
//  y .import, que no son JS válido) y lo ejercita contra el índice real. Lo
//  que se comprueba no es que las funciones devuelvan algo, sino que el juego
//  SE PUEDA JUGAR: que la escalera se recorra entera, que un combate a tu
//  altura no esté decidido de antemano y que criar bien importe.

const fs = require('fs')
const path = require('path')
const vm = require('vm')

const raiz = path.join(__dirname, '..')

function cargarReglas() {
    const src = fs.readFileSync(
        path.join(raiz, 'services/DigiviceReglas.js'), 'utf8')
        .split('\n')
        .filter(l => !/^\s*\.(pragma|import)\b/.test(l))
        .join('\n')
    const sandbox = { module: { exports: {} }, Math: Math, console: console }
    sandbox.exports = sandbox.module.exports
    vm.createContext(sandbox)
    vm.runInContext(src, sandbox, { filename: 'DigiviceReglas.js' })
    return sandbox.module.exports
}

const R = cargarReglas()
const indice = JSON.parse(fs.readFileSync(
    path.join(raiz, 'plugins/Digivice/datos/digimon.json'), 'utf8')).digimon

let fallos = 0
function ok(cond, que, detalle) {
    if (cond) {
        console.log('  ok   ' + que)
    } else {
        fallos += 1
        console.log('  FALLA ' + que + (detalle ? '  → ' + detalle : ''))
    }
}

//  Azar fijo: las pruebas no pueden depender de la suerte.
function azarFijo(semilla) {
    let s = semilla
    return function () {
        s = (s * 1103515245 + 12345) & 0x7fffffff
        return s / 0x7fffffff
    }
}

console.log('\nindice: ' + Object.keys(indice).length + ' fichas\n')

// ── 1. el triángulo de atributos ──────────────────────────────────
console.log('atributos')
ok(R.ventaja('Vaccine', 'Virus') > 1, 'Vaccine gana a Virus')
ok(R.ventaja('Virus', 'Data') > 1, 'Virus gana a Data')
ok(R.ventaja('Data', 'Vaccine') > 1, 'Data gana a Vaccine')
ok(R.ventaja('Vaccine', 'Vaccine') === 1, 'el espejo no da ventaja')
ok(R.ventaja('Free', 'Virus') === 1, 'Free queda fuera del triángulo')

// ── 2. la escalera se recorre entera ──────────────────────────────
console.log('\nescalera')
const semillas = Object.keys(indice).filter(
    k => indice[k].l === 'Baby I' && R.candidatosEvolucion(indice, k).length > 0)
ok(semillas.length > 0, 'hay huevos con salida', semillas.length + ' semillas')

let completos = 0, atascos = {}
for (const s of semillas) {
    let k = s, pasos = 0
    while (pasos < 10) {
        const c = R.candidatosEvolucion(indice, k)
        if (c.length === 0) break
        k = c[0]
        pasos += 1
    }
    if (indice[k].l === 'Ultimate') completos += 1
    else atascos[indice[k].l] = (atascos[indice[k].l] || 0) + 1
}
ok(completos === semillas.length,
   'toda semilla llega a Ultimate criando bien',
   completos + '/' + semillas.length + ' — atascos: ' + JSON.stringify(atascos))

//  Y criando MAL, que es lo que de verdad importa: el grado de crianza manda
//  al jugador por candidatos que la prueba de arriba nunca pisa. Se recorre
//  todo lo alcanzable desde cualquier huevo, no solo la rama de cabecera.
const vistos = new Set(), atascados = []
const cola = semillas.slice()
while (cola.length) {
    const k = cola.pop()
    if (vistos.has(k)) continue
    vistos.add(k)
    if (indice[k].l === 'Ultimate') continue
    const c = R.candidatosEvolucion(indice, k)
    if (c.length === 0) { atascados.push(indice[k].n + ' (' + indice[k].l + ')'); continue }
    for (const x of c) if (!vistos.has(x)) cola.push(x)
}
ok(atascados.length === 0,
   'ninguna rama alcanzable muere a media escalera',
   vistos.size + ' especies alcanzables' +
   (atascados.length ? ' — atascan: ' + atascados.slice(0, 5).join(', ') : ''))

// ── 3. criar bien importa ─────────────────────────────────────────
console.log('\ncrianza')
ok(R.gradoCrianza(0, 10, false) === 0, 'impecable = grado 0')
ok(R.gradoCrianza(5, 0, true) === 3, 'desastre = grado 3')
const conRamas = Object.keys(indice).filter(
    k => R.candidatosEvolucion(indice, k).length >= 4)
ok(conRamas.length > 100,
   'hay ramas de sobra para que el grado elija', conRamas.length + ' especies')
//  Y que elegir distinto dé bicho distinto, que es el sentido del grado.
const ej = conRamas[0]
const cands = R.candidatosEvolucion(indice, ej)
ok(cands[0] !== cands[3], 'grados distintos dan especies distintas',
   indice[ej].n + ' → ' + indice[cands[0]].n + ' / ' + indice[cands[3]].n)

// ── 4. el orden es estable ────────────────────────────────────────
console.log('\ndeterminismo')
const a1 = R.candidatosEvolucion(indice, ej).join(',')
const a2 = R.candidatosEvolucion(indice, ej).join(',')
ok(a1 === a2, 'los candidatos no cambian entre llamadas')
const st1 = JSON.stringify(R.statsDe(indice, ej, 0))
const st2 = JSON.stringify(R.statsDe(indice, ej, 0))
ok(st1 === st2, 'las stats son deterministas', st1)

// ── 5. el combate termina y no está decidido ──────────────────────
console.log('\ncombate')
const child = Object.keys(indice).filter(k => indice[k].l === 'Child')
let sinTerminar = 0
for (let i = 0; i < 300; ++i) {
    const a = child[i % child.length], b = child[(i * 7 + 3) % child.length]
    const r = R.resolverCombate(indice, a, b, { azar: azarFijo(i + 1) })
    if (!r) continue
    if (r.restanteMia > 0 && r.restanteSuya > 0) sinTerminar += 1
}
ok(sinTerminar === 0, 'ningún combate a la par se queda sin resolver',
   sinTerminar + ' colgados')

//  Que a igualdad de etapa gane a veces cada uno. Si un lado ganase siempre,
//  explorar no tendría emoción ninguna.
let gane = 0, total = 0
for (let i = 0; i < 400; ++i) {
    const a = child[i % child.length], b = child[(i * 13 + 5) % child.length]
    if (a === b) continue
    const r = R.resolverCombate(indice, a, b, { azar: azarFijo(i + 100) })
    if (!r) continue
    total += 1
    if (r.gane) gane += 1
}
const pct = Math.round(100 * gane / total)
ok(pct > 25 && pct < 75, 'a igual etapa el combate está repartido', pct + '% de victorias')

//  Y que subir de etapa se note de verdad.
const unChild = child[0]
const adult = Object.keys(indice).filter(k => indice[k].l === 'Adult')[0]
let gana = 0
for (let i = 0; i < 100; ++i) {
    const r = R.resolverCombate(indice, unChild, adult, { azar: azarFijo(i + 7) })
    if (r && r.gane) gana += 1
}
ok(gana <= 5, 'un Child no le gana a un Adult', gana + '/100')

//  El estado del bicho pesa: enfermo y con hambre se pega peor.
let sano = 0, malo = 0
for (let i = 0; i < 200; ++i) {
    const b = child[(i * 11 + 2) % child.length]
    const s = R.resolverCombate(indice, unChild, b, { azar: azarFijo(i + 1) })
    const m = R.resolverCombate(indice, unChild, b,
        { azar: azarFijo(i + 1), enfermo: true, hambre: 0, animo: 0 })
    if (s && s.gane) sano += 1
    if (m && m.gane) malo += 1
}
ok(malo < sano, 'descuidado se gana menos', sano + ' sano vs ' + malo + ' descuidado')

// ── 5b. las stats salen de la ficha, no de un hash ────────────────
console.log('\nestadísticas legibles')
function unoCon(pred) { return Object.keys(indice).find(pred) }
const dragon = unoCon(k => indice[k].l === 'Adult' && /Dragon/.test(indice[k].t))
const maquina = unoCon(k => indice[k].l === 'Adult' && /Machine/.test(indice[k].t))
ok(dragon && maquina, 'hay un dragón y una máquina de la misma etapa')
if (dragon && maquina) {
    const sd = R.statsDe(indice, dragon, 0), sm = R.statsDe(indice, maquina, 0)
    ok(sd.atq > sm.atq, 'el dragón pega más que la máquina',
       `${indice[dragon].n} ${sd.atq} vs ${indice[maquina].n} ${sm.atq}`)
    ok(sm.def > sd.def, 'la máquina aguanta más que el dragón',
       `${sm.def} vs ${sd.def}`)
}
//  Y que el atributo incline el reparto, no solo el triángulo.
const virus = unoCon(k => indice[k].l === 'Adult' && indice[k].a === 'Virus' && !indice[k].t)
ok(R.repartoDeAtributo('Virus').atq > R.repartoDeAtributo('Data').atq,
   'Virus pega más que Data')
ok(R.repartoDeAtributo('Data').vida > R.repartoDeAtributo('Virus').vida,
   'Data aguanta más que Virus')
//  Lo importante de todo esto: que la variedad sea REAL y no ruido del id.
const adultos = Object.keys(indice).filter(k => indice[k].l === 'Adult')
const atqs = adultos.map(k => R.statsDe(indice, k, 0).atq)
const min = Math.min(...atqs), max = Math.max(...atqs)
ok(max / min >= 1.5, 'entre Adults hay diferencias que se notan',
   `ATQ de ${min} a ${max}`)

// ── 5a-bis. el triángulo del choque ───────────────────────────────
console.log('\nchoque')
ok(R.chocar('atacar', 'cargar').ganador === 'mio', 'atacar pilla al que carga')
ok(R.chocar('defender', 'atacar').ganador === 'mio', 'defender para el ataque')
ok(R.chocar('cargar', 'defender').ganador === 'mio', 'cargar gana al que se cubre')
ok(R.chocar('atacar', 'defender').ganador === 'suyo', 'y al revés también')
ok(R.chocar('atacar', 'atacar').tipo === 'colision', 'ataque contra ataque: colisión')
ok(R.chocar('defender', 'defender').tipo === 'nada', 'cubrirse los dos no hace nada')
ok(R.chocar('cargar', 'cargar').tipo === 'ambosCargan', 'cargar los dos acumula')

//  Lo que hace que el sistema sea una DECISIÓN y no una tirada: cargar tiene
//  que compensar el riesgo. Pillado cargando duele; cargar y acertar pega
//  mucho más.
const kA = child[1], kB = child[4]
const sinCarga = R.intercambio(indice, kA, kB, { mia: 'atacar', suya: 'cargar', carga: 0 })
const conCarga = R.intercambio(indice, kA, kB, { mia: 'atacar', suya: 'cargar', carga: 3 })
ok(conCarga.daño > sinCarga.daño * 1.9,
   'la carga multiplica el golpe', sinCarga.daño + ' → ' + conCarga.daño)
const pillado = R.intercambio(indice, kA, kB, { mia: 'cargar', suya: 'atacar', carga: 0 })
ok(pillado.aQuien === 'mio' && pillado.daño > 0,
   'te pillan cargando y lo pagas', '−' + pillado.daño)
const cubierto = R.intercambio(indice, kA, kB, { mia: 'defender', suya: 'defender' })
ok(cubierto.daño === 0, 'cubrirse los dos no hace daño a nadie')

// ── 5a-ter. entrenamiento por estadística ─────────────────────────
console.log('\nentrenamiento')
ok(R.ESTADISTICAS.length === 4, 'cuatro estadísticas entrenables',
   R.ESTADISTICAS.join(', '))
ok(R.topeEntreno('Baby I') < R.topeEntreno('Ultimate'),
   'el tope de entreno crece con la etapa',
   R.topeEntreno('Baby I') + ' → ' + R.topeEntreno('Ultimate'))

const kEnt = child[7]
const crudo = R.statsDe(indice, kEnt, {})
const soloPV = R.statsDe(indice, kEnt, { pv: 18 })
const soloATQ = R.statsDe(indice, kEnt, { atq: 18 })
ok(soloPV.vida > crudo.vida && soloPV.atq === crudo.atq,
   'entrenar PV sube SOLO la vida', crudo.vida + ' → ' + soloPV.vida)
ok(soloATQ.atq > crudo.atq && soloATQ.vida === crudo.vida,
   'entrenar ATQ sube SOLO el ataque', crudo.atq + ' → ' + soloATQ.atq)

//  El tope existe para que entrenar no sustituya a evolucionar.
const tope = R.topeEntreno('Child')
const aTope = R.statsDe(indice, kEnt, { pv: tope, atq: tope, def: tope, vel: tope })
const pasado = R.statsDe(indice, kEnt, { pv: 999, atq: 999, def: 999, vel: 999 })
ok(JSON.stringify(aTope) === JSON.stringify(pasado),
   'pasado el tope ya no suma nada')

//  LA REGLA DE ORO DEL BALANCE, y por eso tiene prueba: un bicho entrenado a
//  tope vale MÁS O MENOS lo que uno de la etapa siguiente sin entrenar. Con
//  los primeros números un Child a tope hacía 178 PV contra los 118 de un
//  Adult recién nacido: lo aplastaba, y subir de etapa dejaba de importar.
const adultosCrudos = Object.keys(indice).filter(k => indice[k].l === 'Adult')
    .slice(0, 40).map(k => R.statsDe(indice, k, {}))
const mediaAdulto = adultosCrudos.reduce((a, s) => a + s.vida, 0) / adultosCrudos.length
const childesTope = child.slice(0, 40)
    .map(k => R.statsDe(indice, k, { pv: tope, atq: tope, def: tope, vel: tope }))
const mediaChildTope = childesTope.reduce((a, s) => a + s.vida, 0) / childesTope.length
ok(mediaChildTope < mediaAdulto,
   'un Child a tope NO supera en vida a un Adult sin entrenar',
   Math.round(mediaChildTope) + ' vs ' + Math.round(mediaAdulto))
ok(mediaChildTope > mediaAdulto * 0.6,
   'pero se le acerca: entrenar vale casi una etapa',
   Math.round(100 * mediaChildTope / mediaAdulto) + '%')

//  Y las técnicas salen del ATQ entrenado, no de un total genérico.
const kSk = Object.keys(indice).find(k => (indice[k].sk || []).length >= 3)
ok(R.tecnicasAbiertas(indice, kSk, { atq: 0 }) === 1, 'sin entrenar ATQ, una técnica')
ok(R.tecnicasAbiertas(indice, kSk, { atq: 12 }) > 1, 'entrenando ATQ se abren más')
ok(R.tecnicasAbiertas(indice, kSk, { pv: 40, atq: 0 }) === 1,
   'entrenar PV no enseña técnicas nuevas')

// ── 5b-bis. el peso ───────────────────────────────────────────────
console.log('\npeso')
ok(R.pesoBaseDe('Baby I') < R.pesoBaseDe('Ultimate'),
   'un bicho grande pesa más de base',
   R.pesoBaseDe('Baby I') + ' → ' + R.pesoBaseDe('Ultimate'))
ok(R.excesoDePeso('Child', 20) === 0, 'en su mínimo no sobra nada')
ok(R.excesoDePeso('Child', 35) === 15, 'lo que pasa del mínimo es exceso')
ok(R.excesoDePeso('Child', 5) === 0, 'por debajo del mínimo no hay exceso negativo')

//  Lo que importa: que engordar SE NOTE, y solo en la velocidad.
const unChild2 = child[3]
const flaco = R.statsDe(indice, unChild2, 0, R.pesoBaseDe('Child'))
const gordo = R.statsDe(indice, unChild2, 0, R.pesoBaseDe('Child') + 30)
ok(gordo.vel < flaco.vel, 'gordo se mueve menos',
   flaco.vel + ' → ' + gordo.vel)
ok(gordo.vida === flaco.vida && gordo.atq === flaco.atq,
   'pero pega y aguanta igual: es lastre, no debilidad')
//  Con tope, para que cebarlo sea un lastre y no una sentencia.
const obeso = R.statsDe(indice, unChild2, 0, R.pesoBaseDe('Child') + 500)
ok(obeso.vel >= Math.round(flaco.vel * 0.55),
   'el lastre tiene tope', flaco.vel + ' → ' + obeso.vel)

//  Y que cebarlo empeore la rama de evolución, que es de lo que va un vpet.
ok(R.gradoCrianza(0, 10, false, 0) === 0, 'impecable y en su peso = grado 0')
ok(R.gradoCrianza(0, 10, false, 12) > R.gradoCrianza(0, 10, false, 0),
   'impecable pero cebado evoluciona peor')

// ── 5c. terreno y técnicas ────────────────────────────────────────
console.log('\nterreno y técnicas')
const conCampo = unoCon(k => (indice[k].f || []).indexOf('Dark Area') >= 0)
ok(R.bonusZona(indice, conCampo, 'Dark Area') > 1, 'pelear en tu campo favorece')
ok(R.bonusZona(indice, conCampo, 'Metal Empire') === 1, 'fuera de tu campo, nada')
const conTec = unoCon(k => (indice[k].sk || []).length >= 2)
//  Con fuerza suficiente para tenerlas desbloqueadas: sin entrenar solo sabe
//  una, y eso es lo que se quiere.
ok(R.tecnicaDe(indice, conTec, 0, { atq: 18 }) !== R.tecnicaDe(indice, conTec, 2, { atq: 18 }),
   'las técnicas rotan entre golpes (entrenado)',
   R.tecnicaDe(indice, conTec, 0, { atq: 18 }) + ' / ' + R.tecnicaDe(indice, conTec, 2, { atq: 18 }))
ok(R.tecnicaDe(indice, conTec, 0, { atq: 0 }) === R.tecnicaDe(indice, conTec, 2, { atq: 0 }),
   'sin entrenar, siempre la misma')
const sinTec = unoCon(k => (indice[k].sk || []).length === 0)
ok(!sinTec || R.tecnicaDe(indice, sinTec, 0) === '',
   'sin técnicas, golpe seco sin nombre')

//  Y que la técnica llegue DENTRO de cada turno, que es de donde la lee la
//  vista. Tenerla en `tecnicaDe` y que no viajase en el turno dejaría el
//  combate como una ristra de números, que es justo lo que se quería quitar.
const conAmbas = child.filter(k => (indice[k].sk || []).length > 0)
if (conAmbas.length >= 2) {
    const r = R.resolverCombate(indice, conAmbas[0], conAmbas[1],
                                { azar: azarFijo(42) })
    const conNombre = r.turnos.filter(t => t.tecnica).length
    ok(conNombre === r.turnos.length,
       'cada turno viaja con el nombre de su técnica',
       `${conNombre}/${r.turnos.length} — p.ej. "${r.turnos[0].tecnica}"`)
    //  Y que no sea siempre la misma cuando conoce varias.
    const variado = child.find(k => (indice[k].sk || []).length >= 2)
    if (variado) {
        const r2 = R.resolverCombate(indice, variado, conAmbas[0],
                                     { azar: azarFijo(9), fuerza: { atq: 18 } })
        const mias = new Set(r2.turnos.filter(t => t.mio).map(t => t.tecnica))
        ok(mias.size >= 2 || r2.turnos.filter(t => t.mio).length < 3,
           'quien conoce varias las alterna (entrenado)', [...mias].join(' / '))
    }
}
//  El terreno debe cambiar resultados, no solo un número en un objeto.
let enCasa = 0, fuera = 0
for (let i = 0; i < 200; ++i) {
    const a = child[i % child.length], b = child[(i * 17 + 3) % child.length]
    if (a === b) continue
    const z = (indice[a].f || [])[0]
    if (!z) continue
    const c1 = R.resolverCombate(indice, a, b, { azar: azarFijo(i + 5), zona: z })
    const c2 = R.resolverCombate(indice, a, b, { azar: azarFijo(i + 5), zona: 'ninguna' })
    if (c1 && c1.gane) enCasa++
    if (c2 && c2.gane) fuera++
}
ok(enCasa >= fuera, 'en tu campo se gana al menos igual',
   `${enCasa} en casa vs ${fuera} fuera`)

// ── 6. las zonas tienen habitantes ────────────────────────────────
console.log('\nzonas')
const ZONAS = ["Nature Spirits", "Deep Savers", "Wind Guardians",
               "Jungle Troopers", "Dragon's Roar", "Metal Empire",
               "Nightmare Soldiers", "Virus Busters", "Dark Area"]
let vacias = []
for (const z of ZONAS) {
    for (const e of R.ESCALERA) {
        if (R.habitantesDe(indice, z, e).length === 0)
            vacias.push(z + '/' + e)
    }
}
ok(vacias.length === 0, 'toda zona tiene habitantes en toda etapa',
   vacias.length ? vacias.join(', ') : '')

// ── 5d. las técnicas se ganan entrenando ──────────────────────────
console.log('\ntécnicas por esfuerzo')
const conCuatro = Object.keys(indice).find(k => (indice[k].sk || []).length >= 4)
if (conCuatro) {
    ok(R.tecnicasAbiertas(indice, conCuatro, { atq: 0 }) === 1,
       'recién nacido solo sabe una')
    ok(R.tecnicasAbiertas(indice, conCuatro, { atq: 6 }) === 2, 'con 6 de ATQ, dos')
    ok(R.tecnicasAbiertas(indice, conCuatro, { atq: 18 }) === 4, 'con 18, las cuatro')
    ok(R.tecnicasAbiertas(indice, conCuatro, { atq: 999 }) === 4,
       'no se inventa técnicas que no tiene')
    //  Y la compatibilidad con partidas viejas, que guardaban un número.
    ok(R.tecnicasAbiertas(indice, conCuatro, 24) >= 2,
       'un guardado antiguo con fuerza 24 sigue teniendo técnicas')
    //  Lo que importa: que entrenar CAMBIE lo que se ve en combate.
    const flojo = R.tecnicaDe(indice, conCuatro, 2, { atq: 0 })
    const duro = R.tecnicaDe(indice, conCuatro, 2, { atq: 18 })
    ok(flojo !== duro, 'entrenado pega con otra técnica',
       '"' + flojo + '" → "' + duro + '"')
}
const conUna = Object.keys(indice).find(k => (indice[k].sk || []).length === 1)
ok(!conUna || R.tecnicasAbiertas(indice, conUna, 999) === 1,
   'quien solo tiene una, solo tiene una')

// ── 6a-bis. requisitos de evolución ───────────────────────────────
console.log('\nrequisitos de evolución')
ok(R.requisitosDe('Baby I').minutos < R.requisitosDe('Perfect').minutos,
   'cada etapa pide más tiempo que la anterior')
ok(R.requisitosDe('Baby I').victorias < R.requisitosDe('Perfect').victorias,
   'y más victorias')
ok(R.requisitosDe('Ultimate') === null, 'en la cima no hay requisitos')

const f0 = R.faltaPara('Child', 0, 0, 0)
ok(f0.minutos > 0 && f0.victorias > 0 && f0.xp > 0,
   'recién llegado a Child le falta de todo')
ok(!R.cumpleRequisitos('Child', 0, 0, 0), 'y no puede evolucionar')
const req = R.requisitosDe('Child')
ok(R.cumpleRequisitos('Child', req.minutos, req.victorias, req.xp),
   'cumpliendo los tres, sí puede')
//  Los tres son NECESARIOS: con dos basta para que no evolucione, que es lo
//  que hace que las tres cosas importen y no solo esperar.
ok(!R.cumpleRequisitos('Child', req.minutos, req.victorias, req.xp - 1),
   'faltando solo experiencia, no evoluciona')
ok(!R.cumpleRequisitos('Child', req.minutos, req.victorias - 1, req.xp),
   'faltando solo una victoria, tampoco')

//  La experiencia que deja un rival crece con su etapa: machacar bebés no
//  puede ser la forma rápida de subir.
const unBaby = Object.keys(indice).find(k => indice[k].l === 'Baby I')
const unPerf = Object.keys(indice).find(k => indice[k].l === 'Perfect')
ok(R.xpDe(indice, unPerf, false) > R.xpDe(indice, unBaby, false) * 3,
   'un rival de etapa alta enseña mucho más',
   R.xpDe(indice, unBaby, false) + ' → ' + R.xpDe(indice, unPerf, false))
ok(R.xpDe(indice, unPerf, true) === R.xpDe(indice, unPerf, false) * 3,
   'el jefe da el triple')

// ── 6a-ter. jogress ───────────────────────────────────────────────
console.log('\njogress')
const jog = JSON.parse(fs.readFileSync(
    path.join(raiz, 'plugins/Digivice/datos/jogress.json'), 'utf8')).jogress
const conJog = Object.keys(jog)
ok(conJog.length > 400, 'hay fusiones de sobra', conJog.length + ' especies')

//  Simétrico: si A+B da C, B+A tiene que dar C. Sin esto, la fusión
//  dependería de a quién lleves encima, que no tiene ningún sentido.
let asimetricas = 0, comprobadas = 0
for (const a of conJog.slice(0, 200)) {
    for (const par of jog[a]) {
        comprobadas += 1
        if (R.jogressCon(jog, par.con, a) !== String(par.da)) asimetricas += 1
    }
}
ok(asimetricas === 0, 'la fusión es simétrica',
   asimetricas + ' asimétricas de ' + comprobadas)

//  Y todo lo que sale de una fusión tiene que existir en el índice, o la
//  pantalla enseñaría un hueco.
let huerfanos = 0
for (const a of conJog) for (const par of jog[a])
    if (!indice[String(par.da)] || !indice[String(par.con)]) huerfanos += 1
ok(huerfanos === 0, 'ninguna fusión apunta a una especie que no existe',
   huerfanos + ' huérfanas')

ok(R.jogressCon(jog, conJog[0], 'no-existe') === '',
   'dos que no son pareja no fusionan')

// ── 6b. los jefes ─────────────────────────────────────────────────
console.log('\njefes')
const jefes = ZONAS.map(z => R.jefeDe(indice, z, 'Child'))
ok(jefes.every(j => j), 'toda zona tiene jefe',
   jefes.filter(j => !j).length + ' sin jefe')
//  Lo que de verdad importa: que no sea el mismo en todas. Con la primera
//  puntuación —que premiaba estar en muchos campos— Greymon era el jefe de
//  seis zonas de nueve, y nueve zonas con el mismo jefe es una zona.
ok(new Set(jefes).size === ZONAS.length,
   'cada zona tiene un jefe DISTINTO',
   new Set(jefes).size + '/' + ZONAS.length + ': '
   + jefes.map(j => indice[j] ? indice[j].n : '—').join(', '))
//  Y que esté un peldaño por encima, que es lo que lo hace un jefe.
ok(jefes.every(j => indice[j] && indice[j].l === 'Adult'),
   'el jefe va un escalón por encima del jugador')
//  En la cima no hay escalón siguiente: el jefe es de tu propia altura.
const jefeCima = R.jefeDe(indice, 'Dark Area', 'Ultimate')
ok(jefeCima && indice[jefeCima].l === 'Ultimate',
   'en Ultimate el jefe es de tu altura, no inexistente',
   jefeCima ? indice[jefeCima].n : '—')
//  Estable entre llamadas, o la zona cambiaría de jefe al mirarla.
ok(R.jefeDe(indice, 'Dark Area', 'Child') === R.jefeDe(indice, 'Dark Area', 'Child'),
   'el jefe de una zona no cambia entre llamadas')

// ── 6c. los huevos ────────────────────────────────────────────────
console.log('\nhuevos')
//  Lo innegociable: capturar CUALQUIER especie tiene que dar un huevo, y un
//  huevo es un Baby I. Bajando por el grafo hay peldaños sin predecesor
//  —Angewomon se quedaba en un Child— y eso pondría al jugador a criar algo
//  que no ha nacido.
const todas = Object.keys(indice)
let sinHuevo = [], noBebe = []
for (const k of todas) {
    const h = R.raizDe(indice, k)
    if (!h) { sinHuevo.push(indice[k].n); continue }
    if (indice[h].l !== 'Baby I') noBebe.push(indice[k].n + '→' + indice[h].l)
}
ok(sinHuevo.length === 0, 'toda especie tiene huevo',
   sinHuevo.length + ' sin huevo')
ok(noBebe.length === 0, 'todo huevo es un Baby I',
   noBebe.length + ' no lo son: ' + noBebe.slice(0, 3).join(', '))

//  Estable: la misma especie da siempre el mismo huevo, o coleccionar sería
//  una tómbola.
const unAdulto = Object.keys(indice).find(k => indice[k].l === 'Adult')
ok(R.raizDe(indice, unAdulto) === R.raizDe(indice, unAdulto),
   'el huevo de una especie no cambia entre llamadas')

//  Y variado: si todas dieran el mismo huevo, capturar no significaría nada.
//  Con el desempate alfabético, "Algomon (Baby I)" salía para 7 de cada 8.
const adultos2 = Object.keys(indice).filter(k => indice[k].l === 'Adult')
const distintos = new Set(adultos2.map(k => R.raizDe(indice, k)))
ok(distintos.size > 40, 'especies distintas dan huevos distintos',
   distintos.size + ' huevos para ' + adultos2.length + ' Adult')

// ── 7. regresión ──────────────────────────────────────────────────
console.log('\nregresión')
const unAdult = Object.keys(indice).filter(
    k => indice[k].l === 'Adult' && R.candidatosRegresion(indice, k).length > 0)
ok(unAdult.length > 0, 'un Adult puede regresar', unAdult.length + ' especies')
if (unAdult.length) {
    const r = R.candidatosRegresion(indice, unAdult[0])
    ok(indice[r[0]].ls.indexOf('Child') >= 0, 'regresa justo un peldaño',
       indice[unAdult[0]].n + ' → ' + indice[r[0]].n)
}
const babyI = Object.keys(indice).filter(k => indice[k].l === 'Baby I')[0]
ok(R.candidatosRegresion(indice, babyI).length === 0,
   'un Baby I no puede regresar más')


{   //  ámbito propio: las pruebas de arriba ya usan varios de
    //  estos nombres, y renombrarlos uno a uno solo camufla el choque.
    // ── 9. formas de ataque ───────────────────────────────────────────
    //
    //  Lo que se vigila aquí NO es que las funciones devuelvan un número: es que
    //  ninguna de las tres formas sea la respuesta correcta siempre. El día que
    //  una domine, elegir con qué pegar deja de ser una decisión y el sistema
    //  entero sobra. Ya pasó una vez: la columna hacía 38 contra los 20 de la
    //  simple sin más pega que fallar un poco más.
    console.log('\nformas de ataque')

    ok(R.formaDe(0) === 'simple' && R.formaDe(1) === 'rafaga'
       && R.formaDe(2) === 'columna' && R.formaDe(3) === 'columna',
       'la forma sale del orden de la técnica')

    const conCuatroT = Object.keys(indice).find(k => (indice[k].sk || []).length >= 4)
    ok(R.tecnicasConForma(indice, conCuatroT, { atq: 0 }).length === 1,
       'sin entrenar solo tienes una forma')
    const cuatroFormas = R.tecnicasConForma(indice, conCuatroT, { atq: 999 })
    ok(cuatroFormas.length === 4 && cuatroFormas.map(t => t.forma).join(',')
         === 'simple,rafaga,columna,columna',
       'entrenado a tope se abren las tres formas')
    ok(R.tecnicasConForma(indice, 'no-existe', { atq: 0 }).length === 1,
       'una especie desconocida no revienta el selector')

    //  La inversión que justifica que la ráfaga exista: gana contra los duros y
    //  pierde contra los blandos. Si no se invirtiera, sería la simple con premio.
    function medio(a, b, forma, n) {
        const st = R.statsDe(indice, a, { atq: 12 }), sr = R.statsDe(indice, b, 0)
        let t = 0
        const az = azarFijo(7)
        for (let i = 0; i < (n || 4000); ++i)
            t += R.golpeDe(st, sr, indice[a].a, indice[b].a, forma, az).daño
        return t / (n || 4000)
    }
    const adultos = Object.keys(indice).filter(k => indice[k].l === 'Adult')
    const duro = adultos.find(k => /Machine|Mineral|Mollusk/.test(indice[k].t || ''))
    const blando = adultos.find(k => /Bird|Fairy/.test(indice[k].t || ''))
    const pegador = adultos.find(k => /Dragon/.test(indice[k].t || ''))
    ok(medio(pegador, duro, 'rafaga') > medio(pegador, duro, 'simple'),
       'la ráfaga gana a la simple contra un duro',
       medio(pegador, duro, 'rafaga').toFixed(1) + ' vs '
         + medio(pegador, duro, 'simple').toFixed(1))
    ok(medio(pegador, blando, 'rafaga') < medio(pegador, blando, 'simple'),
       'y la pierde contra uno blando',
       medio(pegador, blando, 'rafaga').toFixed(1) + ' vs '
         + medio(pegador, blando, 'simple').toFixed(1))

    //  La columna pega más cuando entra —para eso es la apuesta— pero se falla
    //  más contra los rápidos.
    let falloCol = 0, falloSim = 0
    const azF = azarFijo(11)
    const stP = R.statsDe(indice, pegador, { atq: 12 })
    const stB = R.statsDe(indice, blando, 0)
    for (let i = 0; i < 3000; ++i) {
        if (R.golpeDe(stP, stB, indice[pegador].a, indice[blando].a, 'columna', azF).fallo) falloCol++
        if (R.golpeDe(stP, stB, indice[pegador].a, indice[blando].a, 'simple', azF).fallo) falloSim++
    }
    ok(falloCol > falloSim * 1.5, 'la columna falla bastante más que la simple',
       falloCol + ' vs ' + falloSim + ' de 3000')

    //  Y la pega que la mantiene a raya: es lenta. Si el rival ataca a la vez,
    //  no sale y te comes el suyo ENTERO, no a medias.
    const dosC = Object.keys(indice).filter(k => indice[k].l === 'Child'
                                              && (indice[k].sk || []).length >= 3)
    const colision = R.intercambio(indice, dosC[0], dosC[1], {
        mia: 'atacar', suya: 'atacar', forma: 'columna', azar: azarFijo(3)
    })
    ok(colision.aQuien === 'mio' && colision.fallo,
       'una columna pillada en colisión no sale y te comes el golpe',
       colision.aQuien + ' · daño ' + colision.daño)
    const colisionSimple = R.intercambio(indice, dosC[0], dosC[1], {
        mia: 'atacar', suya: 'atacar', forma: 'simple', azar: azarFijo(3)
    })
    ok(colisionSimple.aQuien === 'ambos',
       'con la simple, la colisión reparte como siempre')

    //  Ninguna forma domina: contra un abanico de rivales, cada una gana alguna.
    let ganaSimple = 0, ganaRafaga = 0
    for (let i = 0; i < 60; ++i) {
        const r = adultos[(i * 37 + 5) % adultos.length]
        if (medio(pegador, r, 'simple', 400) >= medio(pegador, r, 'rafaga', 400)) ganaSimple++
        else ganaRafaga++
    }
    ok(ganaSimple > 5 && ganaRafaga > 5,
       'ni la simple ni la ráfaga ganan siempre',
       ganaSimple + ' simple / ' + ganaRafaga + ' ráfaga de 60 rivales')

    // ── 10. estados alterados ─────────────────────────────────────────
    console.log('\nestados')

    const unaPlanta = Object.keys(indice).find(k => /Plant/.test(indice[k].t || ''))
    const unaMaquina = Object.keys(indice).find(k => /Machine/.test(indice[k].t || ''))
    const unDragon = Object.keys(indice).find(k => /Dragon/.test(indice[k].t || ''))
    ok(R.estadoQueInflige(indice, unaPlanta) === 'veneno', 'una planta envenena')
    ok(R.estadoQueInflige(indice, unaMaquina) === 'paralisis', 'una máquina paraliza')
    ok(R.estadoQueInflige(indice, unDragon) === '', 'un dragón no deja estado')

    //  Que no TODOS dejen estado: si el estado fuera universal dejaría de ser una
    //  amenaza y sería el clima.
    const conEstado = Object.keys(indice).filter(k => R.estadoQueInflige(indice, k))
    const pctEstado = Math.round(100 * conEstado.length / Object.keys(indice).length)
    ok(pctEstado > 20 && pctEstado < 60, 'los estados son de algunos, no de todos',
       pctEstado + '% de las fichas')

    let e = R.aplicarEstado([], 'veneno')
    ok(e.length === 1 && e[0].turnos === R.ESTADOS.veneno.turnos, 'el veneno se pega')
    e = R.aplicarEstado(e, 'veneno')
    ok(e.length === 1, 'reaplicar renueva, no acumula')
    e = R.aplicarEstado(e, 'debilidad')
    ok(e.length === 2, 'pero dos estados distintos conviven')

    //  El veneno quema y se gasta.
    const t1 = R.tickEstados([{ tipo: 'veneno', turnos: 3 }], 100)
    ok(t1.quema === 5 && t1.estados[0].turnos === 2,
       'el veneno quema el 5 % y le queda un turno menos', t1.quema + ' de 100')
    const t2 = R.tickEstados([{ tipo: 'veneno', turnos: 1 }], 100)
    ok(t2.estados.length === 0, 'y al final se va')
    ok(R.tickEstados([{ tipo: 'debilidad', turnos: 2 }], 100).quema === 0,
       'la debilidad no quema vida')

    //  La debilidad toca el ataque y NADA más: «te va peor en todo» no se puede
    //  jugar en contra.
    const stSano = R.statsDe(indice, unDragon, 0)
    const stFlojo = R.conEstados(stSano, [{ tipo: 'debilidad', turnos: 3 }])
    ok(stFlojo.atq < stSano.atq, 'la debilidad baja el ataque')
    ok(stFlojo.vida === stSano.vida && stFlojo.def === stSano.def
       && stFlojo.vel === stSano.vel, 'y no toca vida, defensa ni velocidad')

    //  La parálisis roba EXACTAMENTE un intercambio. Dura dos porque se pone al
    //  final de uno y el descuento va justo detrás: con uno se apagaría antes de
    //  robar nada.
    let par = R.aplicarEstado([], 'paralisis')
    par = R.tickEstados(par, 100).estados
    ok(R.tieneEstado(par, 'paralisis'), 'la parálisis sigue viva al turno siguiente')
    const robado = R.intercambio(indice, dosC[0], dosC[1], {
        mia: 'atacar', suya: 'atacar', forma: 'simple',
        estadosMios: par, azar: azarFijo(5)
    })
    ok(robado.paralizado && robado.mia === 'nada',
       'paralizado no eliges: el turno se pierde')
    ok(robado.aQuien === 'mio', 'y el rival pega sin oposición')
    par = R.tickEstados(par, 100).estados
    ok(!R.tieneEstado(par, 'paralisis'), 'y se va tras robar uno solo')

    //  Un golpe que no toca no deja estado.
    const seco = R.intercambio(indice, unaPlanta, dosC[1], {
        mia: 'defender', suya: 'defender', forma: 'simple', azar: azarFijo(9)
    })
    ok(seco.estado === '', 'cubrirse los dos no envenena a nadie')
    ok((R.PROB_ESTADO.columna || 0) === 0, 'la columna nunca deja estado')
    ok(R.PROB_ESTADO.rafaga > R.PROB_ESTADO.simple,
       'la ráfaga deja más estados que la simple: son tres golpes')

    // ── 11. el aliado ─────────────────────────────────────────────────
    console.log('\naliado')

    ok(R.aliadoDe(indice, []) === null, 'sin guardería no hay aliado')
    ok(R.aliadoDe(indice, null) === null, 'ni con la guardería sin cargar')

    const unBaby = Object.keys(indice).find(k => indice[k].l === 'Baby I')
    const unAdultoA = adultos[0]
    const banco = [
        { especie: unBaby, entrenos: { pv: 6, atq: 6, def: 6, vel: 6 } },
        { especie: unAdultoA, entrenos: { pv: 0, atq: 0, def: 0, vel: 0 } }
    ]
    ok(R.aliadoDe(indice, banco).especie === String(unAdultoA),
       'sale el de etapa más alta aunque el otro esté más entrenado',
       R.aliadoDe(indice, banco).nombre)

    const dosIguales = [
        { especie: unAdultoA, entrenos: { atq: 0 } },
        { especie: unAdultoA, entrenos: { pv: 5, atq: 5, def: 5, vel: 5 } }
    ]
    ok(R.aliadoDe(indice, dosIguales).hueco === 1,
       'a igualdad de etapa sale el mejor criado')
    ok(R.aliadoDe(indice, [{ especie: 'no-existe' }]) === null,
       'una especie que no está en el índice no se ofrece como aliado')

    const ga = R.golpeAliado(indice, R.aliadoDe(indice, banco), dosC[1])
    ok(ga && ga.daño > 0, 'el aliado pega', ga ? ga.daño + ' de daño' : 'nada')
    ok(R.golpeAliado(indice, null, dosC[1]) === null, 'sin aliado no hay golpe')

    //  Y lo que de verdad importa: que tener guardería se NOTE. Es la respuesta a
    //  «¿para qué colecciono?».
    let sinA = 0, conA = 0
    const rivalDuro = adultos[3]
    for (let i = 0; i < 200; ++i) {
        const mio = adultos[(i * 7 + 1) % adultos.length]
        if (mio === rivalDuro) continue
        const ali = R.aliadoDe(indice, [{ especie: adultos[(i * 5 + 2) % adultos.length],
                                          entrenos: { atq: 8 } }])
        if (R.resolverCombate(indice, mio, rivalDuro, { azar: azarFijo(i + 3) }).gane) sinA++
        if (R.resolverCombate(indice, mio, rivalDuro,
                              { azar: azarFijo(i + 3), aliado: ali }).gane) conA++
    }
    ok(conA >= sinA, 'con aliado se gana igual o más',
       sinA + ' sin aliado vs ' + conA + ' con aliado')


}

{   //  ámbito propio, por lo mismo que el bloque de arriba.

// ── 12. la comida ─────────────────────────────────────────────────
//
//  Lo que se vigila: que las cinco comidas sean tratos DISTINTOS. El día que
//  dos hagan lo mismo, elegir qué darle deja de ser una decisión y volvemos
//  al botón único que había antes.
console.log('\ncomida')

ok(R.COMIDAS.length === 5, 'hay cinco comidas', R.COMIDAS.length + '')
ok(R.COMIDAS.filter(c => c.infinita).length === 1,
   'solo la ración es infinita: quedarse sin nada que comer no puede pasar')
ok(R.comidaDe('racion').infinita, 'y es la ración')
ok(R.comidaDe('no-existe') === null, 'una comida que no existe devuelve null')

//  Ninguna repite el mismo trato: llenar, engordar, vigor, curar, envenenar.
const huellas = R.COMIDAS.map(c => [c.hambre, c.peso, c.animo, c.vigor,
                                    c.cura, c.veneno].join('|'))
ok(new Set(huellas).size === R.COMIDAS.length,
   'ninguna comida hace lo mismo que otra')

ok(R.comidaDe('grande').hambre > R.comidaDe('racion').hambre
   && R.comidaDe('grande').peso > R.comidaDe('racion').peso,
   'la ración grande llena más y engorda más')
ok(R.comidaDe('omni').hambre === 0 && R.comidaDe('omni').cura,
   'la fruta omni no llena: cura')
ok(R.comidaDe('omni').peso === 0, 'y no engorda, que es lo que la hace valiosa')
ok(R.comidaDe('podrida').veneno && R.comidaDe('podrida').hambre > 0,
   'la que sienta mal llena igual: por eso es una trampa y no basura')
ok(R.comidaDe('carne').vigor > 0, 'la carne da vigor')

//  El vigor tiene que NOTARSE y tener techo.
ok(R.bonusVigor(0) === 1, 'sin vigor no hay bonificación')
ok(R.bonusVigor(3) > R.bonusVigor(1), 'más vigor pega más')
ok(R.bonusVigor(99) === R.bonusVigor(3), 'con techo: acumular carne no rompe nada')
ok(R.bonusVigor(3) < 1.3, 'y el techo es modesto: no sustituye a entrenar',
   'x' + R.bonusVigor(3).toFixed(2))

//  Y que llegue de verdad al combate.
const unosChild = Object.keys(indice).filter(k => indice[k].l === 'Child'
                                              && (indice[k].sk || []).length >= 2)
let sinVigor = 0, conVigor = 0
for (let i = 0; i < 300; ++i) {
    const a = unosChild[i % unosChild.length]
    const b = unosChild[(i * 17 + 3) % unosChild.length]
    if (a === b) continue
    const s = R.intercambio(indice, a, b, { mia: 'atacar', suya: 'cargar',
                                            forma: 'simple', azar: azarFijo(i + 1) })
    const v = R.intercambio(indice, a, b, { mia: 'atacar', suya: 'cargar',
                                            forma: 'simple', vigor: 3,
                                            azar: azarFijo(i + 1) })
    sinVigor += s.daño
    conVigor += v.daño
}
ok(conVigor > sinVigor, 'con vigor se pega más en combate',
   sinVigor + ' vs ' + conVigor)

// ── 13. la caza ───────────────────────────────────────────────────
console.log('\ncaza')

ok(Object.keys(R.CAZA_POR_ZONA).length === 9, 'las nueve zonas tienen tabla',
   Object.keys(R.CAZA_POR_ZONA).length + '')
//  Y que no sean todas la misma: si dieran lo mismo, cambiar de zona para
//  cazar no significaría nada.
const tablas = Object.values(R.CAZA_POR_ZONA).map(t => t.join(','))
ok(new Set(tablas).size >= 6, 'y dan cosas distintas',
   new Set(tablas).size + ' tablas distintas de 9')
//  Toda entrada de toda tabla tiene que ser una comida real.
const idsComida = R.COMIDAS.map(c => c.id)
const rotas = []
for (const [z, t] of Object.entries(R.CAZA_POR_ZONA))
    for (const c of t) if (idsComida.indexOf(c) < 0) rotas.push(z + ':' + c)
ok(rotas.length === 0, 'ninguna zona ofrece una comida que no existe',
   rotas.join(' '))

const caza = R.montarCaza('Nature Spirits', 0, 'Child', azarFijo(5))
ok(caza.rastros.length === R.RASTROS, 'se ofrecen cuatro rastros',
   R.RASTROS + '')
ok(caza.rastros.filter(r => r.malo).length === 1,
   'siempre hay exactamente uno malo: el riesgo es legible')
ok(caza.rastros.filter(r => r.bueno).length === 1, 'y exactamente uno bueno')
ok(caza.rastros.every(r => R.comidaDe(r.comida) !== null),
   'detrás de cada rastro hay una comida real')

//  Y ninguno puede dar algo que ya tienes infinito: encontrar una ración
//  cuando las raciones no se acaban es volver con las manos vacías sin que
//  nadie te lo diga. Pasó, y por eso está esta comprobación.
const inutiles = []
for (let i = 0; i < 300; ++i) {
    const z = Object.keys(R.CAZA_POR_ZONA)[i % 9]
    const c = R.montarCaza(z, 0, 'Adult', azarFijo(i + 31))
    for (const r of c.rastros)
        if (R.comidaDe(r.comida).infinita) inutiles.push(z + ':' + r.comida)
}
ok(inutiles.length === 0, 'ningún rastro da algo que ya tienes infinito',
   inutiles.slice(0, 3).join(' '))

//  El premio de la zona nunca puede ser la que sienta mal: acertar no puede
//  salir peor que fallar.
let premioMalo = 0
for (let i = 0; i < 400; ++i) {
    const z = Object.keys(R.CAZA_POR_ZONA)[i % 9]
    const c = R.montarCaza(z, 0, 'Adult', azarFijo(i + 11))
    const bueno = c.rastros.find(r => r.bueno)
    if (bueno.comida === 'podrida') premioMalo += 1
}
ok(premioMalo === 0, 'acertar el rastro nunca da comida en mal estado')

//  La velocidad se nota, y no lo resuelve.
ok(R.pistasDeCaza(0, 'Child') === 0, 'sin velocidad no hay pistas')
ok(R.pistasDeCaza(R.topeEntreno('Child'), 'Child') === 1,
   'con la velocidad al tope, una pista')
ok(R.pistasDeCaza(999, 'Child') < R.RASTROS - 1,
   'nunca se marcan tantos que la elección desaparezca')

const conPista = R.montarCaza('Jungle Troopers', R.topeEntreno('Adult'),
                              'Adult', azarFijo(3))
const marcados = conPista.rastros.filter(r => r.marcado)
ok(marcados.length === 1, 'la pista marca un rastro')
//  Y que `marcado` exista SIEMPRE y sea booleano. Dejarlo sin poner en los no
//  marcados hacía que QML enseñara la cruz de «descartado» sobre los tres:
//  `visible: undefined` no vale false, deja la propiedad en su valor por
//  defecto. Se vio en pantalla, no en ningún registro.
ok(conPista.rastros.every(r => typeof r.marcado === 'boolean'),
   'todo rastro dice si está marcado, con un booleano de verdad')
ok(marcados.every(r => !r.bueno),
   'y marca uno MALO: señalar el premio sería resolver la cacería')
ok(marcados[0].malo,
   'empezando por el que sienta mal, que es del que sirve avisar')

//  Olfatear: el rastro que acumulas andando se gasta en leer huellas. Al
//  absorber la caza dentro de la carretera le quité su único precio y se
//  quedó en un contador que solo subía y no hacía NADA.
//  CON la pista de la velocidad puesta, que es el caso que importa: con tres
//  rastros la pista ya dejaba solo dos y olfatear no cabía, así que pagar por
//  olfatear solo servía con la velocidad baja — justo al revés.
const conOlfato = R.montarCaza('Nature Spirits', R.topeEntreno('Child'),
                               'Child', azarFijo(21))
ok(conOlfato.rastros.filter(r => r.marcado).length === 1,
   'la velocidad ya descartó uno')
const antesM = conOlfato.rastros.filter(r => r.marcado).length
ok(R.marcarOtro(conOlfato.rastros), 'olfatear descarta una huella más')
ok(conOlfato.rastros.filter(r => r.marcado).length === antesM + 1,
   'exactamente una más')
ok(conOlfato.rastros.every(r => !r.bueno || !r.marcado),
   'y NUNCA descarta la buena')
//  Y no se puede olfatear hasta dejar una sola opción: eso sería regalar la
//  respuesta y la cacería dejaría de ser una decisión.
ok(!R.marcarOtro(conOlfato.rastros),
   'no se puede olfatear dos veces: dejaría la respuesta servida')
ok(conOlfato.rastros.filter(r => !r.marcado).length >= 2,
   'siempre quedan al menos dos por elegir')
ok(R.marcarOtro(null) === false, 'olfatear sin cacería no revienta')

//  Que el reparto sea de verdad aleatorio y no salga siempre en el mismo
//  sitio: un rastro malo que estuviera siempre el tercero se aprendería en
//  dos partidas y la caza dejaría de ser una decisión para siempre.
const posiciones = new Array(R.RASTROS).fill(0)
for (let i = 0; i < 800; ++i) {
    const c = R.montarCaza('Nature Spirits', 0, 'Child', azarFijo(i * 7 + 1))
    posiciones[c.rastros.findIndex(r => r.malo)] += 1
}
ok(posiciones.every(n => n > 800 / R.RASTROS / 2),
   'el rastro malo cae en todas las posiciones',
   posiciones.join('/'))

// ── 14. el veneno de la comida llega al combate ───────────────────
console.log('\nveneno de la comida')

//  Un estado que se borrase al empezar la pelea no sería un castigo, sería
//  un adorno de la pantalla de casa.
const veneno = [{ tipo: 'veneno', turnos: R.ESTADOS.veneno.turnos }]
let sano2 = 0, tocado = 0
for (let i = 0; i < 250; ++i) {
    const a = unosChild[i % unosChild.length]
    const b = unosChild[(i * 13 + 7) % unosChild.length]
    if (a === b) continue
    if (R.resolverCombate(indice, a, b, { azar: azarFijo(i + 21) }).gane) sano2 += 1
    if (R.resolverCombate(indice, a, b, { azar: azarFijo(i + 21),
                                          estadosMios: veneno }).gane) tocado += 1
}
ok(tocado < sano2, 'entrar envenenado a la pelea se paga',
   sano2 + ' sano vs ' + tocado + ' envenenado')

//  Y que no se le pegue al rival por error.
const conEntrada = R.resolverCombate(indice, unosChild[0], unosChild[1],
                                     { azar: azarFijo(4), estadosMios: veneno })
ok(conEntrada !== null, 'el combate con veneno de entrada se resuelve')

}

{   //  ámbito propio, por lo mismo que los bloques de arriba.

const especiales = JSON.parse(fs.readFileSync(
    path.join(raiz, 'plugins/Digivice/datos/especiales.json'), 'utf8'))

// ── 15. el meta-juego ─────────────────────────────────────────────
//
//  Lo que se vigila: que la economía no se pueda romper y que los objetivos
//  se puedan cumplir de verdad. Un objetivo inalcanzable no es una meta, es
//  una burla; y un mercado donde comprar y vender da beneficio no es una
//  economía, es una impresora de dinero.
console.log('\nmeta-juego')

const unChildM = Object.keys(indice).find(k => indice[k].l === 'Child')
const unAdultM = Object.keys(indice).find(k => indice[k].l === 'Adult')
const unUltM = Object.keys(indice).find(k => indice[k].l === 'Ultimate')

ok(R.bitsDe(indice, unAdultM, false) > R.bitsDe(indice, unChildM, false),
   'un rival de etapa alta da más bits',
   R.bitsDe(indice, unChildM, false) + ' vs ' + R.bitsDe(indice, unAdultM, false))
ok(R.bitsDe(indice, unAdultM, true) === R.bitsDe(indice, unAdultM, false) * 5,
   'el jefe da cinco veces más')
ok(R.bitsDe(indice, 'no-existe', false) === 0, 'un rival que no existe no da bits')

//  Vender NUNCA puede dar más de lo que cuesta comprar: con eso el mercado
//  sería un bucle infinito de bits y todo lo demás dejaría de importar.
const rotos = Object.keys(R.PRECIOS).filter(
    id => R.precioVenta(id) >= R.precioDe(id))
ok(rotos.length === 0, 'vender siempre da menos que comprar', rotos.join(' '))
ok(R.precioVenta('carne') > 0, 'pero vender da algo: el excedente vale')
ok(!R.seVende('racion'), 'la ración no se vende: es infinita e imprimiría bits')
ok(!R.seVende('dig:Courage'), 'un digimental no se vende: es la llave de una rama')

//  Los objetivos: alcanzables, sin repetidos y con premio.
ok(R.OBJETIVOS.length >= 12, 'hay objetivos de sobra', R.OBJETIVOS.length + '')
const ids = R.OBJETIVOS.map(o => o.id)
ok(new Set(ids).size === ids.length, 'ningún objetivo repite id')
ok(R.OBJETIVOS.every(o => o.bits > 0), 'todos dan bits')
const familias = new Set(R.OBJETIVOS.map(o => o.tipo))
ok(familias.size === 4,
   'cuatro familias: criar, coleccionar, pelear y explorar',
   [...familias].join(', '))
//  La carretera era el sistema más grande del juego y no tenía ni una meta
//  colgando: se andaba porque sí.
ok(R.OBJETIVOS.some(o => o.tipo === 'exploracion' && o.campo === 'recorrido'),
   'hay objetivos que miden lo ANDADO, no solo lo peleado')

//  Los topes tienen que ser posibles con lo que el juego ofrece de verdad.
//  Lo que el juego ofrece de verdad, para que ningún objetivo pida más.
let caminoTotal = 0
for (let z = 0; z < 9; ++z) caminoTotal += R.distanciaJefe(z)
const topes = { etapaMax: R.ESCALERA.length - 1, jefes: 9,
                vistos: Object.keys(indice).length,
                criados: Object.keys(indice).length,
                //  El recorrido no tiene techo —las zonas se rehacen— pero
                //  pedir más de una pasada entera ya sería pasarse.
                recorrido: caminoTotal }
const imposibles = R.OBJETIVOS.filter(
    o => topes[o.campo] !== undefined && o.meta > topes[o.campo])
ok(imposibles.length === 0, 'ningún objetivo pide más de lo que existe',
   imposibles.map(o => o.id).join(' '))

//  Y que el objeto que regala un objetivo sea un objeto real.
const premiosRotos = R.OBJETIVOS.filter(o => o.objeto && !R.objetoDe(o.objeto))
ok(premiosRotos.length === 0, 'todo premio es un objeto que existe',
   premiosRotos.map(o => o.objeto).join(' '))

//  El estado: nada cobrable sin cumplir, nada cobrable dos veces.
const cero = R.estadoObjetivos({}, {})
ok(cero.every(e => !e.cobrable), 'con la partida a cero no hay nada que cobrar')
const todo = R.estadoObjetivos(
    { victorias: 999, jefes: 9, criados: 999, vistos: 999, etapaMax: 5,
      evoluciones: 999, fusiones: 9, cazas: 99, recorrido: 99999, vueltas: 9 }, {})
ok(todo.every(e => e.cobrable), 'cumpliéndolo todo, todo es cobrable')
const yaCobrado = R.estadoObjetivos({ victorias: 999 }, { ganar10: true })
ok(!yaCobrado.find(e => e.obj.id === 'ganar10').cobrable,
   'lo cobrado no se vuelve a cobrar')
ok(yaCobrado.find(e => e.obj.id === 'ganar10').hecho,
   'pero sigue constando como hecho')
ok(cero.every(e => e.hay <= e.meta), 'el progreso no pasa de la meta')

// ── 16. evoluciones especiales ────────────────────────────────────
console.log('\nespeciales')

ok(Object.keys(especiales.armor).length > 20, 'hay evoluciones Armor',
   Object.keys(especiales.armor).length + ' especies')
ok(Object.keys(especiales.x).length > 50, 'y formas X',
   Object.keys(especiales.x).length + ' parejas')
ok(Object.keys(especiales.warp).length > 20, 'y saltos Warp',
   Object.keys(especiales.warp).length + ' especies')

//  Nada puede apuntar a una especie que no está en el índice.
const fantasmas = []
for (const [k, l] of Object.entries(especiales.armor))
    for (const e of l) if (!indice[e.da]) fantasmas.push(e.da)
for (const [k, v] of Object.entries(especiales.x)) if (!indice[v]) fantasmas.push(v)
for (const [k, l] of Object.entries(especiales.warp))
    for (const v of l) if (!indice[v]) fantasmas.push(v)
ok(fantasmas.length === 0, 'ninguna especial lleva a una especie inexistente',
   fantasmas.slice(0, 3).join(' '))

//  Todo digimental que se nombra tiene que existir como objeto, y todo
//  objeto-digimental tiene que servir para algo: uno que se suelte y no abra
//  ninguna evolución sería basura que ocupa sitio en la bolsa.
const digsUsados = new Set()
for (const l of Object.values(especiales.armor))
    for (const e of l) digsUsados.add(e.dig)
ok([...digsUsados].every(d => especiales.digimentales.indexOf(d) >= 0),
   'todo digimental que aparece está en la lista')
ok(especiales.digimentales.every(d => digsUsados.has(d)),
   'y todos los de la lista abren alguna evolución',
   especiales.digimentales.filter(d => !digsUsados.has(d)).join(' '))

//  Cada zona suelta un digimental, y distinto en cada una.
const porZona = Object.values(R.DIGIMENTAL_POR_ZONA)
ok(porZona.length === 9, 'las nueve zonas sueltan digimental')
ok(new Set(porZona).size === 9, 'y ninguno se repite entre zonas')
ok(porZona.every(d => especiales.digimentales.indexOf(d) >= 0),
   'todos los de zona existen de verdad')
ok(R.digimentalDeZona('Dragon\'s Roar') === 'dig:Courage',
   'la zona devuelve la clave de su objeto')
ok(R.digimentalDeZona('no-existe') === '', 'una zona inventada no suelta nada')

//  El armor solo se ofrece si TIENES el digimental.
const conArmor = Object.keys(especiales.armor)[0]
ok(R.armorConLoQueTienes(especiales, conArmor, {}).length === 0,
   'sin digimentales no hay Armor a la vista')
const suDig = 'dig:' + especiales.armor[conArmor][0].dig
const ofrecidas = R.armorConLoQueTienes(especiales, conArmor, { [suDig]: 1 })
ok(ofrecidas.length > 0, 'con el suyo, sí')
ok(ofrecidas.every(a => 'dig:' + a.dig === suDig),
   'y solo las de ESE digimental, no todas')

//  Una X no vuelve a aplicarse el anticuerpo.
const dobles = Object.keys(especiales.x).filter(
    k => (indice[k].n || '').indexOf('(X-Antibody)') >= 0)
ok(dobles.length === 0, 'un X no puede volver a hacerse X')

//  El Warp salta de verdad: si no saltara, sería la evolución normal con
//  otro nombre y regalaría un atajo que no lo es.
const noSalta = []
for (const [k, l] of Object.entries(especiales.warp))
    for (const v of l) {
        const a = R.ESCALERA.indexOf(indice[k].l)
        const b = R.ESCALERA.indexOf(indice[v].l)
        if (a < 0 || b < 0 || b - a !== 2) noSalta.push(indice[k].n + '->' + indice[v].n)
    }
//  EXACTAMENTE una etapa saltada, ni más. Con «al menos» la API ofrecía
//  saltos de Child a Ultimate —tres etapas de golpe— y eso no es un logro:
//  es saltarse el juego entero y dejar sin sentido la escalera que organiza
//  toda la crianza. Se vio jugando, no en ninguna prueba.
ok(noSalta.length === 0, 'todo Warp salta UNA etapa exacta, ni más',
   noSalta.slice(0, 3).join(' '))

//  Y lo que lo hace un logro: cero descuidos y el doble de todo.
ok(!R.puedeWarp('Child', 99999, 99, 9999, 1),
   'con un solo descuido no hay Warp')
ok(!R.puedeWarp('Child', 180, 6, 150, 0),
   'cumpliendo lo normal tampoco: el Warp pide el doble')
ok(R.puedeWarp('Child', 360, 12, 300, 0), 'con el doble y sin descuidos, sí')
ok(!R.puedeWarp('Ultimate', 99999, 999, 99999, 0),
   'desde la cima no hay adónde saltar')

// ── 17. los objetos ───────────────────────────────────────────────
console.log('\nobjetos')

ok(R.objetoDe('vitamina') !== null, 'la vitamina existe')
ok(R.objetoDe('no-existe') === null, 'un objeto inventado no')
const dg = R.objetoDe('dig:Courage')
ok(dg !== null && dg.dig === 'Courage',
   'los digimentales se resuelven por su clave', dg ? dg.nombre : '')
ok(R.objetoDe('dig:Courage').precio === 0,
   'y no tienen precio: no se compran, se ganan')
ok(R.OBJETOS.every(o => o.glifo && o.nombre && o.nota),
   'todo objeto tiene icono, nombre y explicación')
//  Todo lo que está a la venta tiene que tener precio, o el mercado
//  regalaría cosas.
const sinPrecio = ['grande', 'carne', 'omni', 'vitamina', 'cinta', 'antidoto']
    .filter(id => R.precioDe(id) <= 0)
ok(sinPrecio.length === 0, 'todo lo que se vende tiene precio', sinPrecio.join(' '))
ok(R.precioDe('antidoto') > R.precioDe('omni') * 3,
   'el anticuerpo X es con diferencia lo más caro: es LA meta del mercado')

}

{   //  ámbito propio, por lo mismo que los bloques de arriba.

// ── 18. el código de equipo ───────────────────────────────────────
//
//  Lo que se vigila: que un código mal copiado NO produzca un equipo válido
//  distinto. Ese es el fallo que no se ve: pelearías contra otra cosa y no te
//  enterarías jamás. Y que la ida y vuelta sea exacta, porque un código que
//  pierde entrenamiento por el camino convierte el duelo en otra cosa.
console.log('\ncódigo de equipo')

const idsC = Object.keys(indice).filter(k => indice[k].l)
function equipoDe(n, semilla) {
    const eq = []
    for (let i = 0; i < n; ++i) {
        const k = idsC[(semilla * 37 + i * 211) % idsC.length]
        const tope = R.topeEntreno(indice[k].l)
        eq.push({ especie: k, entrenos: {
            pv: (semilla + i) % (tope + 1), atq: (semilla * 3 + i) % (tope + 1),
            def: (semilla * 5 + i) % (tope + 1), vel: (semilla * 7 + i) % (tope + 1)
        } })
    }
    return eq
}

const eq3 = equipoDe(3, 11)
const cod3 = R.codificarEquipo(eq3)
ok(cod3.length > 0 && cod3.length < 40, 'un equipo de tres cabe en un código corto',
   cod3 + ' (' + cod3.length + ')')
ok(/^[0-9A-Z-]+$/.test(cod3), 'y solo lleva letras que se pueden dictar')
ok(cod3.indexOf('-') > 0, 'va en grupos, para poder compararlo de un vistazo')

//  Ida y vuelta EXACTA, sobre muchos equipos distintos.
let malos = 0
for (let s2 = 1; s2 < 200; ++s2) {
    for (const n of [1, 2, 3]) {
        const eq = equipoDe(n, s2)
        const d = R.descodificarEquipo(indice, R.codificarEquipo(eq))
        if (d.error || d.equipo.length !== n) { malos += 1; continue }
        for (let i = 0; i < n; ++i) {
            if (d.equipo[i].especie !== String(eq[i].especie)) malos += 1
            for (const k of R.ESTADISTICAS)
                if (d.equipo[i].entrenos[k] !== eq[i].entrenos[k]) malos += 1
        }
    }
}
ok(malos === 0, 'la ida y vuelta es exacta en 597 equipos', malos + ' fallos')

//  Un carácter cambiado tiene que CAZARSE, no dar otro equipo.
let colados = 0, cazados = 0
const base = R.codificarEquipo(equipoDe(3, 42)).replace(/-/g, '')
for (let i = 0; i < base.length; ++i) {
    for (const c of R.B32) {
        if (c === base[i]) continue
        const roto = base.slice(0, i) + c + base.slice(i + 1)
        const d = R.descodificarEquipo(indice, roto)
        if (d.error) cazados += 1
        else colados += 1
    }
}
//  TODOS, no «casi todos»: al principio se colaba uno —el que solo tocaba
//  el bit de relleno del último grupo—. No hacía daño, pero un código que no
//  es el que te pasaron no puede aceptarse en silencio.
ok(colados === 0, 'cualquier cambio de una letra se caza antes de pelear',
   cazados + ' cazados / ' + colados + ' colados')

//  Los errores tienen que ser DISTINTOS y explicables.
ok(R.descodificarEquipo(indice, '').error === 'vacio', 'un código vacío se dice')
ok(R.descodificarEquipo(indice, 'AB').error === 'corto', 'uno corto también')
ok(R.descodificarEquipo(indice, '!!!!').error === 'vacio',
   'la puntuación se ignora, no revienta')
const motivos = ['vacio', 'letra', 'corto', 'version', 'suma', 'especie']
ok(motivos.every(m => R.motivoDeCodigo(m).length > 0),
   'todo error tiene su explicación para el jugador')
ok(new Set(motivos.map(m => R.motivoDeCodigo(m))).size === motivos.length,
   'y ninguna se repite: decir siempre lo mismo es no decir nada')

//  Las confusiones de copiar a mano, resueltas: O es 0, I y L son 1.
const conOI = base.replace(/0/g, 'O').replace(/1/g, 'I')
ok(!R.descodificarEquipo(indice, conOI).error,
   'un código con O por 0 y con I por 1 sigue valiendo')
ok(!R.descodificarEquipo(indice, base.toLowerCase()).error,
   'y en minúsculas también')
//  Los grupos son cosmética: sin guiones tiene que dar lo mismo.
ok(JSON.stringify(R.descodificarEquipo(indice, cod3))
   === JSON.stringify(R.descodificarEquipo(indice, cod3.replace(/-/g, ''))),
   'los guiones son adorno: con y sin dan el mismo equipo')

//  Un código manipulado a mano no puede traer un Child con todo a 63.
const tramposo = R.codificarEquipo([{ especie: idsC.find(k => indice[k].l === 'Child'),
                                      entrenos: { pv: 63, atq: 63, def: 63, vel: 63 } }])
const leido = R.descodificarEquipo(indice, tramposo)
const topeChild = R.topeEntreno('Child')
ok(!leido.error && R.ESTADISTICAS.every(
       k => leido.equipo[0].entrenos[k] <= topeChild),
   'el entrenamiento se recorta al tope de su etapa: no se puede hacer trampa',
   JSON.stringify(leido.equipo && leido.equipo[0].entrenos))

//  Una especie que no está en el índice se rechaza, no se cuela.
ok(R.descodificarEquipo(indice,
     R.codificarEquipo([{ especie: '2047', entrenos: {} }])).error === 'especie',
   'un código que nombra un Digimon inexistente se rechaza')

// ── 19. el duelo ──────────────────────────────────────────────────
console.log('\nduelo')

ok(R.asaltosDe(equipoDe(3, 1), equipoDe(3, 2)) === 3, 'tres contra tres, tres asaltos')
ok(R.asaltosDe(equipoDe(3, 1), equipoDe(1, 2)) === 1,
   'con equipos desiguales manda el más corto: traer más bichos no es ganar')
ok(R.asaltosDe([], equipoDe(3, 2)) === 0, 'sin equipo no hay duelo')

//  Y lo que de verdad decide un duelo: haber criado. Si el entrenamiento del
//  rival no llegara al combate, el código no serviría para nada.
const adD = Object.keys(indice).filter(k => indice[k].l === 'Adult'
                                         && (indice[k].sk || []).length >= 3)
let contraCrudo = 0, contraCriado = 0
const tope = R.topeEntreno('Adult')
for (let i = 0; i < 200; ++i) {
    const a = adD[i % adD.length], b = adD[(i * 7 + 3) % adD.length]
    if (a === b) continue
    const az = () => 0.5
    if (R.resolverCombate(indice, a, b,
            { fuerza: { atq: 12 }, azar: azarFijo(i + 5) }).gane) contraCrudo += 1
    if (R.resolverCombate(indice, a, b, {
            fuerza: { atq: 12 }, azar: azarFijo(i + 5),
            statsSuyo: R.statsDe(indice, b,
                { pv: tope, atq: tope, def: tope, vel: tope })
        }).gane) contraCriado += 1
}
ok(contraCriado < contraCrudo / 2,
   'contra un equipo bien criado se gana mucho menos',
   contraCrudo + ' vs ' + contraCriado + ' de 200')

}

{   //  ámbito propio, por lo mismo que los bloques de arriba.

// ── 20. la agenda del día ─────────────────────────────────────────
//
//  El cuidado ya no es un goteo a ritmo fijo sino una AGENDA: cada día tiene
//  sus horas de hambre y de mimo, y cambian de un día para otro. Es el modelo
//  del emulador de aparatos (`hunger_events_left`, `poop_events_per_day`,
//  `sleep_minutes_per_day`) y sustituye al goteo porque del goteo salieron
//  tres defectos con la misma raíz:
//
//    1. la deuda crecía sin tope y dar de comer dejaba de hacer nada,
//    2. los dos medidores se realineaban y pedían a la vez un tercio de las
//       veces, justo lo contrario de lo que promete el diseño,
//    3. pedía de comer a las 9:00, a las 10:00 y a las 11:00, en punto.
console.log('\nagenda del día')

const VIG = 14 * 60

ok(R.agendaDelDia(1, 0, 'hambre', VIG).length > 0, 'un día tiene comidas')
ok(R.agendaDelDia(1, 0, 'inventado', VIG).length === 0,
   'una clase que no existe no inventa sucesos')

//  Determinista: el mismo día tiene que salir igual cada vez que se pregunte,
//  o recuperar las horas que estuviste fuera daría un resultado distinto al
//  de haber estado delante mirándolo.
ok(R.agendaDelDia(7, 3, 'hambre', VIG).join() === R.agendaDelDia(7, 3, 'hambre', VIG).join(),
   'el mismo día sale siempre igual')
ok(R.agendaDelDia(7, 3, 'hambre', VIG).join() !== R.agendaDelDia(7, 4, 'hambre', VIG).join(),
   'pero dos días seguidos son distintos: no es un metrónomo')
ok(R.agendaDelDia(7, 3, 'hambre', VIG).join() !== R.agendaDelDia(8, 3, 'hambre', VIG).join(),
   'y dos bichos distintos tienen su propio ritmo')

//  Dentro de la vigilia: colocar sucesos mientras duerme sería regalarlos.
let fuera = 0, totalS = 0
for (let d = 0; d < 200; ++d)
    for (const t of ['hambre', 'animo', 'caca'])
        for (const m of R.agendaDelDia(5, d, t, VIG)) {
            totalS += 1
            if (m < 0 || m > VIG) fuera += 1
        }
ok(fuera === 0, 'ningún suceso cae fuera de la vigilia', fuera + ' de ' + totalS)

//  LA regla que el goteo no podía cumplir: hambre y ánimo no piden a la vez.
let choques = 0, pares = 0, minima = 1e9
for (let d = 0; d < 300; ++d) {
    const h = R.agendaDelDia(11, d, 'hambre', VIG)
    const a = R.agendaDelDia(11, d, 'animo', VIG)
    for (const x of a) for (const y of h) {
        pares += 1
        const dif = Math.abs(x - y)
        if (dif < minima) minima = dif
        if (dif < R.SEPARACION) choques += 1
    }
}
ok(choques === 0, 'hambre y ánimo NUNCA piden a la vez',
   choques + ' choques en 300 días · separación mínima ' + minima + ' min')
ok(minima >= R.SEPARACION, 'y se respeta la separación pedida',
   minima + ' >= ' + R.SEPARACION)

//  Carga acotada por día: es la promesa que el goteo no podía hacer.
for (const t of ['hambre', 'animo', 'caca']) {
    let mn = 1e9, mx = 0
    for (let d = 0; d < 300; ++d) {
        const n = R.agendaDelDia(3, d, t, VIG).length
        if (n < mn) mn = n
        if (n > mx) mx = n
    }
    ok(mn >= R.AGENDA[t].min && mx <= R.AGENDA[t].max,
       'los sucesos de ' + t + ' se quedan en su rango',
       mn + '-' + mx + ' (pedido ' + R.AGENDA[t].min + '-' + R.AGENDA[t].max + ')')
}
ok(R.AGENDA.hambre.min > R.AGENDA.animo.max,
   'se pide de comer más veces que mimo: el hambre marca el ritmo')

// ── 21. contar sucesos entre dos instantes ────────────────────────
console.log('\nsucesos entre dos horas')

ok(R.sucesosEntre(4, 'hambre', 0, 0, 0, VIG, VIG)
   === R.agendaDelDia(4, 0, 'hambre', VIG).length,
   'un día entero cuenta todos los sucesos de ese día')
ok(R.sucesosEntre(4, 'hambre', 0, VIG, 0, VIG, VIG) === 0,
   'un intervalo vacío no cuenta ninguno')
ok(R.sucesosEntre(4, 'hambre', 5, 0, 4, VIG, VIG) === 0,
   'un intervalo al revés no cuenta ninguno')

//  Y lo que sostiene todo el modelo: preguntar de golpe da lo mismo que
//  preguntar a trocitos. Sin esto, recuperar las horas que estuviste fuera
//  daría un número distinto al de haber estado delante.
let porTrozos = 0
for (let m = 0; m < VIG; m += 37)
    porTrozos += R.sucesosEntre(9, 'hambre', 0, m, 0, Math.min(VIG, m + 37), VIG)
ok(porTrozos === R.sucesosEntre(9, 'hambre', 0, 0, 0, VIG, VIG),
   'contar a trocitos da lo mismo que contar de golpe',
   porTrozos + ' vs ' + R.sucesosEntre(9, 'hambre', 0, 0, 0, VIG, VIG))

//  Cruzar días enteros, que es lo que pasa al volver tras una noche.
const tresDias = R.sucesosEntre(2, 'hambre', 0, 0, 2, VIG, VIG)
const suma = [0, 1, 2].reduce(
    (s, d) => s + R.agendaDelDia(2, d, 'hambre', VIG).length, 0)
ok(tresDias === suma, 'cruzar tres días cuenta los tres', tresDias + ' vs ' + suma)

//  Y con un tope, para que una fecha corrupta no ponga a girar el bucle.
ok(R.sucesosEntre(2, 'hambre', 0, 0, 100000, VIG, VIG) < 1000,
   'una fecha absurda no cuelga el conteo')

// ── 22. el ritmo que sale de la agenda ────────────────────────────
console.log('\nritmo del cuidado')

//  Cuánto tarda en vaciarse: los cuatro corazones son cuatro sucesos.
function minutosParaVaciar(semilla, tipo) {
    const ag = R.agendaDelDia(semilla, 0, tipo, VIG)
    return ag.length >= 4 ? ag[3] : Infinity
}
let sumaH = 0, sumaA = 0, n = 0
for (let d = 1; d <= 100; ++d) {
    sumaH += minutosParaVaciar(d, 'hambre')
    sumaA += minutosParaVaciar(d, 'animo')
    n += 1
}
const medH = sumaH / n, medA = sumaA / n
ok(medH > 2 * 60 && medH < 5 * 60,
   'el hambre tarda entre 2 y 5 h en vaciarse: ni agobia ni se olvida',
   (medH / 60).toFixed(1) + ' h de media')
ok(medA > medH, 'y el ánimo aguanta más que el hambre',
   (medA / 60).toFixed(1) + ' h')

//  El fondo del pozo: con un descuido por cada tramo de gracia con el
//  medidor a cero, ¿cuánto tarda en regresar de etapa? Tiene que quedar por
//  encima de una jornada de trabajo. Con el modelo anterior eran 3 h 20 y le
//  pasó al usuario dos veces en una tarde.
const qmlSrv = fs.readFileSync(path.join(raiz, 'services/Digivice.qml'), 'utf8')
function cteQml(k, pordefecto) {
    const m = qmlSrv.match(new RegExp('property int ' + k + ':\\s*(\\d+)'))
    return m ? parseInt(m[1], 10) : pordefecto
}
const gracia = cteQml('minutosGraciaError', 60)
const paraEnf = cteQml('erroresParaEnfermar', 3)
const mR = qmlSrv.match(/erroresParaRegresar:\s*erroresParaEnfermar \+ (\d+)/)
const paraReg = paraEnf + (mR ? parseInt(mR[1], 10) : 3)

function cuandoLlega(errores, semilla) {
    const agH = [], agA = []
    for (let d = 0; d < 4; ++d) {
        for (const m of R.agendaDelDia(semilla, d, 'hambre', VIG)) agH.push(d * VIG + m)
        for (const m of R.agendaDelDia(semilla, d, 'animo', VIG)) agA.push(d * VIG + m)
    }
    let h = 4, a = 4, dh = 0, da = 0, e = 0, ih = 0, ia = 0
    for (let m = 1; m <= 4 * VIG; ++m) {
        while (ih < agH.length && agH[ih] <= m) { h = Math.max(0, h - 1); ih += 1 }
        while (ia < agA.length && agA[ia] <= m) { a = Math.max(0, a - 1); ia += 1 }
        if (h === 0 && !dh) dh = m
        if (a === 0 && !da) da = m
        if (dh && m - dh >= gracia) { dh = m; e += 1 }
        if (da && m - da >= gracia) { da = m; e += 1 }
        if (e >= errores) return m
    }
    return Infinity
}
let peorRegreso = Infinity
for (let d = 1; d <= 60; ++d)
    peorRegreso = Math.min(peorRegreso, cuandoLlega(paraReg, d))
ok(peorRegreso > 8 * 60,
   'ni en el peor día una jornada de trabajo lo hace regresar',
   'lo antes que regresa: ' + (peorRegreso / 60).toFixed(1) + ' h')
let peorEnferma = Infinity
for (let d = 1; d <= 60; ++d)
    peorEnferma = Math.min(peorEnferma, cuandoLlega(paraEnf, d))
ok(peorEnferma < peorRegreso,
   'pero enfermar llega antes: el aviso va delante del castigo',
   'enferma a las ' + (peorEnferma / 60).toFixed(1) + ' h')

}

{   //  ámbito propio, por lo mismo que los bloques de arriba.

// ── 23. la carretera ──────────────────────────────────────────────
//
//  La exploración era un contador invisible que cada seis pasos soltaba un
//  combate de la nada. Ahora es un VIAJE: la distancia es un cuentakilómetros
//  permanente, los jefes están cada vez más lejos y los eventos van COLOCADOS
//  en la carretera, no sorteados en un momento cualquiera.
//
//  Es la misma idea que la agenda del cuidado pero en distancia, y se vigila
//  igual: lo que importa es que preguntar «qué hay entre estas dos» dé lo
//  mismo de golpe que a trocitos.
console.log('\ncarretera')

ok(R.zancadaDe('app') > R.zancadaDe('escritorio')
   && R.zancadaDe('escritorio') > R.zancadaDe('ventana'),
   'cada gesto tiene su zancada: abrir una app es un tranco',
   Object.keys(R.ZANCADAS).map(k => k + ' ' + R.ZANCADAS[k]).join(' '))
ok(R.zancadaDe('inventado') === 1, 'un gesto desconocido vale un paso, no cero')

//  Las carreteras crecen: la primera es un rato y la última una campaña.
let crecen = true
for (let z = 1; z < 9; ++z)
    if (R.distanciaJefe(z) <= R.distanciaJefe(z - 1)) crecen = false
ok(crecen, 'cada zona está más lejos que la anterior',
   R.distanciaJefe(0) + ' → ' + R.distanciaJefe(8))
ok(R.distanciaJefe(8) > R.distanciaJefe(0) * 10,
   'y la última está muy lejos: es el final de la campaña',
   'x' + Math.round(R.distanciaJefe(8) / R.distanciaJefe(0)))

//  El jefe SIEMPRE al final, y solo uno.
for (let z = 0; z < 9; ++z) {
    const hs = R.hitosDe(5, z)
    const jefes = hs.filter(h => h.jefe)
    if (jefes.length !== 1 || jefes[0].en !== R.distanciaJefe(z)) {
        ok(false, 'el jefe cierra la carretera de la zona ' + z)
        break
    }
    if (z === 8) ok(true, 'el jefe cierra la carretera, y solo hay uno por zona')
}

//  Determinista, como la agenda del cuidado.
ok(JSON.stringify(R.hitosDe(3, 2)) === JSON.stringify(R.hitosDe(3, 2)),
   'la misma carretera sale siempre igual')
ok(JSON.stringify(R.hitosDe(3, 2)) !== JSON.stringify(R.hitosDe(4, 2)),
   'y dos bichos tienen carreteras distintas')

//  Los hitos avanzan y no se amontonan.
let malos = 0, minSalto = 1e9
for (let sem = 0; sem < 40; ++sem)
    for (let z = 0; z < 9; ++z) {
        const hs = R.hitosDe(sem, z)
        for (let i = 1; i < hs.length; ++i) {
            const salto = hs[i].en - hs[i - 1].en
            if (salto <= 0) malos += 1
            if (salto < minSalto && i < hs.length - 1) minSalto = salto
        }
    }
ok(malos === 0, 'los hitos siempre van hacia delante', malos + ' al revés')
ok(minSalto >= 8, 'y nunca se amontonan', 'salto mínimo ' + minSalto)

//  LO QUE SOSTIENE EL MODELO: de golpe o a trocitos, lo mismo.
const finZ = R.distanciaJefe(3)
let aTrozos = 0
for (let d = 0; d < finZ; d += 17)
    aTrozos += R.hitosEntre(8, 3, d, Math.min(finZ, d + 17)).length
ok(aTrozos === R.hitosEntre(8, 3, 0, finZ).length,
   'cruzar la carretera a trocitos cruza los mismos hitos que de golpe',
   aTrozos + ' vs ' + R.hitosEntre(8, 3, 0, finZ).length)
ok(R.hitosEntre(8, 3, 100, 100).length === 0, 'no avanzar no cruza nada')
ok(R.hitosEntre(8, 3, 200, 100).length === 0, 'ni retroceder')

//  El próximo hito es el siguiente de verdad.
const prox = R.proximoHito(8, 3, 0)
const primero = R.hitosEntre(8, 3, 0, finZ)[0]
ok(prox && prox.en === primero.en, 'el próximo hito es el primero que viene')
ok(R.proximoHito(8, 3, finZ) === null, 'pasado el jefe no queda camino')

//  Y por eso hace falta saber en QUÉ PUNTO está la carretera. Este es el
//  estado que se me escapó: al perder contra el jefe la distancia se quedaba
//  al máximo, no quedaban hitos por delante y la zona moría para siempre.
ok(R.estadoCarretera(3, 0, false) === 'andando', 'al empezar se anda')
ok(R.estadoCarretera(3, finZ - 1, false) === 'andando', 'y hasta el último palmo')
ok(R.estadoCarretera(3, finZ, false) === 'jefe',
   'al final con el jefe vivo, el jefe TE ESPERA — no se acaba el camino')
ok(R.estadoCarretera(3, finZ + 99, false) === 'jefe',
   'y sigue esperando por mucho que andes')
ok(R.estadoCarretera(3, finZ, true) === 'terminada',
   'solo vencerlo cierra la vuelta')

//  Y la zona se puede REHACER: cada una tiene su comida, sus especies y su
//  Digimental, y dejarlas muertas al vencer al jefe te quedaría sin sitio
//  donde andar al final de la partida.
ok(R.semillaDeVuelta(100, 3, 0) !== R.semillaDeVuelta(100, 3, 1),
   'rehacer una zona da una carretera DISTINTA, no la misma otra vez')
ok(R.semillaDeVuelta(100, 3, 1) === R.semillaDeVuelta(100, 3, 1),
   'pero la misma vuelta es siempre la misma')
ok(R.semillaDeVuelta(100, 3, 0) !== R.semillaDeVuelta(100, 4, 0),
   'y dos zonas no comparten carretera')
const v0 = R.hitosDe(R.semillaDeVuelta(100, 3, 0), 3)
const v1 = R.hitosDe(R.semillaDeVuelta(100, 3, 1), 3)
ok(JSON.stringify(v0) !== JSON.stringify(v1),
   'los hitos de la segunda vuelta caen en otros sitios')
ok(v0[v0.length - 1].en === v1[v1.length - 1].en,
   'pero el jefe sigue al final, a la misma distancia')

// ── 24. los eventos del camino ────────────────────────────────────
console.log('\neventos del camino')

const tiposVistos = {}
let totalHitos = 0
for (let sem = 0; sem < 40; ++sem)
    for (let z = 0; z < 9; ++z) {
        const fin = R.distanciaJefe(z)
        for (const h of R.hitosDe(sem, z)) {
            const e = R.eventoDeHito(sem, z, h, fin)
            tiposVistos[e] = (tiposVistos[e] || 0) + 1
            totalHitos += 1
        }
    }
ok(R.EVENTOS.every(e => tiposVistos[e.id] > 0),
   'todos los tipos de evento aparecen de verdad',
   Object.keys(tiposVistos).join(' '))
ok(tiposVistos['jefe'] > 0, 'y el jefe también')
//  Ninguno puede comerse la carretera entero.
const domina = Object.keys(tiposVistos).find(
    k => k !== 'jefe' && tiposVistos[k] / totalHitos > 0.55)
ok(!domina, 'ningún evento se come la carretera', domina || '')

//  La profundidad manda: el principio apacible, el final con bichos. Es lo
//  que pidió Abel como «rarezas y prioridades» — no un sorteo plano.
let biPrim = 0, nPrim = 0, biUlt = 0, nUlt = 0
for (let sem = 0; sem < 80; ++sem) {
    const z = 4, fin = R.distanciaJefe(z)
    for (const h of R.hitosDe(sem, z)) {
        if (h.jefe) continue
        const e = R.eventoDeHito(sem, z, h, fin)
        if (h.en < fin * 0.25) { nPrim += 1; if (e === 'bicho') biPrim += 1 }
        if (h.en > fin * 0.75) { nUlt += 1; if (e === 'bicho') biUlt += 1 }
    }
}
ok(biUlt / nUlt > biPrim / nPrim * 1.2,
   'hay bastantes más bichos al final que al principio',
   Math.round(100 * biPrim / nPrim) + '% vs ' + Math.round(100 * biUlt / nUlt) + '%')

//  Y que el mismo hito dé siempre el mismo evento: si cambiara, volver a
//  mirar la carretera enseñaría otra cosa.
const hs2 = R.hitosDe(6, 2), fin2 = R.distanciaJefe(2)
ok(hs2.every(h => R.eventoDeHito(6, 2, h, fin2) === R.eventoDeHito(6, 2, h, fin2)),
   'un hito da siempre el mismo evento')

}

{   //  ámbito propio, por lo mismo que los bloques de arriba.

// ── 25. el carácter ───────────────────────────────────────────────
//
//  Es la respuesta barata a «que el juego sea único» sin red, sin clave y sin
//  llamar a ningún sitio: sale de la misma semilla que la agenda y la
//  carretera, así que es determinista, gratis y probable.
console.log('\ncarácter')

ok(R.CARACTERES.length >= 5, 'hay caracteres de sobra', R.CARACTERES.length + '')
ok(new Set(R.CARACTERES.map(c => c.id)).size === R.CARACTERES.length,
   'ninguno repite id')
ok(R.CARACTERES.every(c => c.nombre && c.nota),
   'todos tienen nombre y una nota que explica en qué se nota')

//  Determinista: el mismo bicho tiene siempre el mismo carácter, o no sería
//  suyo — cambiaría al reiniciar la barra.
ok(R.caracterDe(1234).id === R.caracterDe(1234).id, 'la misma semilla, el mismo carácter')
const salen = new Set()
for (let i = 0; i < 400; ++i) salen.add(R.caracterDe(i).id)
ok(salen.size === R.CARACTERES.length,
   'y con muchas semillas salen todos', [...salen].join(' '))

//  El del rival sale de la ESPECIE: el mismo bicho pelea siempre parecido y
//  se puede aprender a leer.
ok(R.caracterDeEspecie('42').id === R.caracterDeEspecie('42').id,
   'la misma especie, el mismo carácter')
const porEsp = new Set()
for (const k of Object.keys(indice).slice(0, 400)) porEsp.add(R.caracterDeEspecie(k).id)
ok(porEsp.size === R.CARACTERES.length,
   'y las especies reparten todos los caracteres')

//  Que se NOTE en el combate: un valiente ataca más que un cauto.
function reparto(car) {
    //  Se busca una especie con ese carácter y se cuenta qué elige.
    const k = Object.keys(indice).find(x => R.caracterDeEspecie(x).id === car
                                         && indice[x].l === 'Adult')
    if (!k) return null
    const c = { atacar: 0, defender: 0, cargar: 0 }
    const az = azarFijo(3)
    for (let i = 0; i < 4000; ++i) c[R.eligeRival(indice, k, az)] += 1
    return c
}
const val = reparto('valiente'), cau = reparto('cauto')
ok(val && cau && val.atacar / 4000 > cau.atacar / 4000,
   'un valiente ataca más que un cauto',
   val && cau ? Math.round(100 * val.atacar / 4000) + '% vs '
              + Math.round(100 * cau.atacar / 4000) + '%' : '')
ok(cau && val && cau.defender > val.defender,
   'y el cauto se cubre más')
const toz = reparto('tozudo')
ok(toz && toz.cargar > val.cargar, 'y el tozudo carga más que nadie')

//  Y en el cuidado: el glotón pide de comer más veces al día.
const VIG2 = 14 * 60
const gl = R.CARACTERES.find(c => c.id === 'gloton')
const ju = R.CARACTERES.find(c => c.id === 'jugueton')
let comeGl = 0, comeJu = 0, mimoGl = 0, mimoJu = 0
for (let d = 0; d < 60; ++d) {
    comeGl += R.agendaDelDia(9, d, 'hambre', VIG2, gl.hambre).length
    comeJu += R.agendaDelDia(9, d, 'hambre', VIG2, ju.hambre).length
    mimoGl += R.agendaDelDia(9, d, 'animo', VIG2, gl.animo).length
    mimoJu += R.agendaDelDia(9, d, 'animo', VIG2, ju.animo).length
}
ok(comeGl > comeJu, 'el glotón pide de comer más veces que el juguetón',
   (comeGl / 60).toFixed(1) + ' vs ' + (comeJu / 60).toFixed(1) + ' al día')
ok(mimoJu > mimoGl, 'y el juguetón pide más mimo',
   (mimoJu / 60).toFixed(1) + ' vs ' + (mimoGl / 60).toFixed(1) + ' al día')

//  Y el suelo: ningún carácter puede dejar a un bicho sin pedir nada, o el
//  cuidado dejaría de existir para él.
let minimo = 999
for (const c of R.CARACTERES)
    for (let d = 0; d < 40; ++d) {
        minimo = Math.min(minimo, R.agendaDelDia(4, d, 'hambre', VIG2, c.hambre).length)
        minimo = Math.min(minimo, R.agendaDelDia(4, d, 'animo', VIG2, c.animo).length)
    }
ok(minimo >= 3, 'ningún carácter deja al bicho sin pedir nada', 'mínimo ' + minimo)

}

{   //  ámbito propio, por lo mismo que los bloques de arriba.

// ── 26. lo que el aparato te cuenta ───────────────────────────────
//
//  El juego tiene muchas reglas que solo se notan si alguien te las dice —que
//  el sobrepeso quita velocidad, que el carácter cambia lo que pide, que la
//  carretera está parada— y una regla invisible es indistinguible de un fallo.
console.log('\nconsejos')

const sano = { enfermo: false, envenenado: false, hambre: 4, animo: 4,
               suciedad: 0, maxSuciedad: 4, peso: 20, pesoMinimo: 20,
               encuentro: '', rastro: false, puedeEvolucionar: false,
               objetivosCobrables: 0, anteElJefe: false, caminoAcabado: false,
               entrenoTotal: 10, etapaIdx: 2, banco: 2, criados: 3 }

ok(R.consejosDe(sano, '').length === 0,
   'con todo en orden no hay consejo de relleno')
ok(R.consejosDe(sano, 'Se esconde y observa').length === 1,
   'salvo la nota de su carácter, que siempre se puede contar')

//  Y el aparato NO puede contradecir lo que estás viendo: si está dando
//  botes con tu música, decir «se esconde y observa» es desmentirse solo.
const bailando = Object.assign({}, sano, { animo_: 'bailando' })
const cb = R.consejosDe(bailando, 'Se esconde y observa', 'Se mueve poco, pero se mueve')
ok(cb[0].id === 'bailando', 'bailando, el renglón habla del baile',
   cb.map(c => c.id).join(' '))
ok(!cb.some(c => c.id === 'caracter'),
   'y la nota general se calla mientras pasa algo a la vista')
const nerv = R.consejosDe(Object.assign({}, sano, { animo_: 'nervioso' }), 'x', 'y')
ok(nerv[0].id === 'nervioso', 'y lo mismo estando nervioso')
ok(R.consejosDe(Object.assign({}, sano, { animo_: 'normal' }), 'nota', 'y')
     .some(c => c.id === 'caracter'),
   'sin nada especial, sí sale la nota del carácter')

//  Cada carácter baila a lo suyo: todos igual delataba que no hay nadie
//  dentro, y un tímido dando botes tres horas seguidas no es tímido.
ok(R.CARACTERES.every(c => c.baile && c.baile.salto > 0 && c.baile.ritmo > 0
                        && c.baile.aguante > 0 && c.baile.descanso > 0),
   'todos los caracteres tienen su manera de bailar')
ok(new Set(R.CARACTERES.map(c => c.baile.salto)).size >= 4,
   'y no saltan todos lo mismo')
const jug = R.CARACTERES.find(c => c.id === 'jugueton')
const tim = R.CARACTERES.find(c => c.id === 'timido')
ok(jug.baile.salto > tim.baile.salto && jug.baile.aguante > tim.baile.aguante,
   'el juguetón salta más y aguanta más que el tímido',
   jug.baile.salto + '/' + jug.baile.aguante + ' vs '
     + tim.baile.salto + '/' + tim.baile.aguante)
ok(R.CARACTERES.every(c => c.comoBaila),
   'y cada uno tiene su frase para contarlo')

//  Lo que hace daño manda sobre lo que es solo interesante.
const malito = Object.assign({}, sano, { enfermo: true, peso: 40,
                                         objetivosCobrables: 3 })
const l = R.consejosDe(malito, 'x')
ok(l[0].id === 'enfermo', 'lo que hace daño va primero', l.map(c => c.id).join(' '))
ok(l.length > 1, 'pero los demás siguen ahí para poder rotarlos')
let ordenado = true
for (let i = 1; i < l.length; ++i) if (l[i].prio > l[i - 1].prio) ordenado = false
ok(ordenado, 'y salen ordenados de más urgente a menos')

//  Cada consejo cuelga de una condición: arreglar la cosa lo apaga. Es lo
//  que lo mantiene «disimulado» y no en un tutorial con cosas que marcar.
const gordo = Object.assign({}, sano, { peso: 40 })
ok(R.consejosDe(gordo, '').some(c => c.id === 'peso'), 'con sobrepeso lo dice')
ok(!R.consejosDe(sano, '').some(c => c.id === 'peso'), 'y al adelgazar se calla')

//  Y ninguno da órdenes: informan del porqué y la decisión es del jugador.
const mandones = R.CONSEJOS.filter(
    c => /^(entrena|dale|ve a|pulsa|compra)\b/i.test(c.texto))
ok(mandones.length === 0, 'ningún consejo da órdenes: cuentan el porqué',
   mandones.map(c => c.id).join(' '))
//  Los dos que se rellenan al vuelo —el carácter y cómo baila— salen con el
//  texto vacío en la tabla a propósito.
const alVuelo = ['caracter', 'bailando']
ok(R.CONSEJOS.every(c => alVuelo.indexOf(c.id) >= 0 || c.texto.length > 0),
   'todos tienen texto salvo los que se rellenan del carácter')
ok(new Set(R.CONSEJOS.map(c => c.id)).size === R.CONSEJOS.length,
   'ninguno repite id')

}

// ── la firma del golpe ────────────────────────────────────────────
console.log('\nfirma del golpe')
{
//  Todos los golpes salían iguales: un punto de color. Ahora la forma sale
//  del arquetipo y el tinte del atributo, y eso tiene que valer para las
//  1488 especies, no para las cuatro que uno mire.
let sinFirma = []
let formasMal = []
const cuenta = {}
for (const id in indice) {
    const v = R.golpeVistaDe(indice, id)
    if (!v || !v.forma || !v.color || !v.aura) { sinFirma.push(id); continue }
    if (R.FORMAS_GOLPE.indexOf(v.forma) < 0) formasMal.push(id + ':' + v.forma)
    cuenta[v.forma] = (cuenta[v.forma] || 0) + 1
}
ok(sinFirma.length === 0, 'ninguna especie se queda sin firma de golpe',
   sinFirma.slice(0, 5).join(' '))
ok(formasMal.length === 0, 'y ninguna inventa una forma que no se sabe dibujar',
   formasMal.slice(0, 5).join(' '))

//  Que exista una firma no basta: si el 90 % cayera en el respaldo, seguirían
//  pegando todos igual y la regla no serviría de nada.
const total = Object.keys(indice).length
const bolas = cuenta['bola'] || 0
//  Contar bolas NO mide el respaldo: dragones, dinosaurios y llamas pegan
//  bolas porque les toca. Lo que hay que mirar es cuántas caen en el
//  respaldo de verdad, que es `arquetipo` vacío. La primera versión de la
//  medida las mezclaba y daba 384 falsos.
const conTipo = Object.keys(indice).filter(k => indice[k].t)
const respaldo = conTipo.filter(k => R.golpeVistaDe(indice, k).arquetipo === '')
ok(respaldo.length / conTipo.length < 0.2,
   'con tipo conocido, casi nadie cae en el respaldo',
   respaldo.length + ' de ' + conTipo.length)

//  Y las que quedan son tipos que NO dicen nada de cómo pega: «Mutation»,
//  «Lesser», «Unknown», «Card». Esas van a la chispa, que es dibujo propio
//  del respaldo: compartir la bola con los dragones hacía que el 35 % de las
//  peleas enseñara lo mismo por dos motivos opuestos.
ok(bolas < total * 0.15, 'la bola es solo de los que pegan bolas',
   'bola ' + bolas + ' de ' + total)
const mayor = Math.max.apply(null, Object.values(cuenta))
ok(mayor < total * 0.3, 'y ningún dibujo se come el reparto',
   Object.entries(cuenta).sort((a, b) => b[1] - a[1]).slice(0, 3)
     .map(e => e[0] + ' ' + e[1]).join(' · '))
ok(Object.keys(cuenta).length >= 8, 'se usan casi todos los dibujos',
   Object.keys(cuenta).join(' '))

//  Los dos ejes son independientes: el tipo da la forma y el atributo el
//  halo. Mezclarlos habría perdido uno de los dos.
const planta = { 1: { n: 'X', t: 'Plant', a: 'Virus' } }
const plantaV = { 1: { n: 'X', t: 'Plant', a: 'Vaccine' } }
ok(R.golpeVistaDe(planta, 1).forma === R.golpeVistaDe(plantaV, 1).forma,
   'el atributo no cambia la forma')
ok(R.golpeVistaDe(planta, 1).aura !== R.golpeVistaDe(plantaV, 1).aura,
   'pero sí el halo')
const maquina = { 1: { n: 'X', t: 'Machine', a: 'Virus' } }
ok(R.golpeVistaDe(maquina, 1).forma !== R.golpeVistaDe(planta, 1).forma,
   'y dos tipos distintos pegan distinto')

//  Una especie sin tipo no puede reventar la pantalla de combate.
const pelado = { 1: { n: 'X' } }
ok(R.golpeVistaDe(pelado, 1).forma === 'chispa',
   'sin tipo, cae en la chispa del respaldo')
ok(R.golpeVistaDe({}, 9).aura.length > 0, 'y sin ficha tampoco se rompe')
}


console.log('\n' + (fallos === 0 ? 'todo en orden' : fallos + ' fallos') + '\n')
process.exit(fallos === 0 ? 0 : 1)
