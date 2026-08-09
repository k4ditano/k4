//  Auditoría de balance del Digivice.
//
//      node tools/digivice_balance.js
//
//  No comprueba que las reglas sean correctas —de eso va `digivice_test.js`—
//  sino que el JUEGO se pueda jugar: cuánto se tarda en llegar arriba, cuántos
//  combates hacen falta, si la economía cierra, y si el castigo por descuidar
//  al bicho es proporcionado.
//
//  Existe porque «está equilibrado» sin números es una opinión, y porque los
//  dos juegos originales que se analizaron dan referencias muy distintas: el
//  emulador de aparatos es un llavero de días, y Digital Tamers es un RPG que
//  pide **500 victorias** para una evolución tardía. Este juego vive en una
//  barra de escritorio y no puede pedir ninguna de las dos cosas.

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
    const caja = { module: { exports: {} }, Math: Math, console: console }
    caja.exports = caja.module.exports
    vm.createContext(caja)
    vm.runInContext(src, caja, { filename: 'DigiviceReglas.js' })
    return caja.module.exports
}

const R = cargarReglas()
const indice = JSON.parse(fs.readFileSync(
    path.join(raiz, 'plugins/Digivice/datos/digimon.json'), 'utf8')).digimon

function tit(t) {
    console.log('\n' + '─'.repeat(64) + '\n' + t + '\n' + '─'.repeat(64))
}

function horas(min) {
    if (min < 60) return min + ' min'
    const h = Math.floor(min / 60), m = Math.round(min % 60)
    return h + ' h' + (m ? ' ' + m : '')
}

// ── 1. el camino hasta la cima ────────────────────────────────────
tit('1 · Cuánto cuesta llegar a Ultimate')

let minTotal = 0, vicTotal = 0, xpTotal = 0
const filas = []
for (const etapa of R.ESCALERA) {
    const r = R.requisitosDe(etapa)
    if (!r) continue
    minTotal += r.minutos
    vicTotal += r.victorias
    xpTotal += r.xp
    filas.push([etapa, r.minutos, r.victorias, r.xp])
}
console.log('etapa'.padEnd(10) + 'tiempo'.padStart(8)
            + 'victorias'.padStart(11) + 'xp'.padStart(7))
for (const [e, m, v, x] of filas)
    console.log(e.padEnd(10) + horas(m).padStart(8)
                + String(v).padStart(11) + String(x).padStart(7))
console.log('TOTAL'.padEnd(10) + horas(minTotal).padStart(8)
            + String(vicTotal).padStart(11) + String(xpTotal).padStart(7))

//  ¿Cuántos combates hacen falta de verdad? La xp por combate depende de la
//  etapa del rival, y peleas contra los de tu altura.
let combates = 0, xpAcum = 0
for (const [etapa, , vic, xp] of filas) {
    const rivales = Object.keys(indice).filter(k => indice[k].l === etapa)
    const xpMedia = rivales.reduce(
        (s, k) => s + R.xpDe(indice, k, false), 0) / Math.max(1, rivales.length)
    const porXp = Math.ceil(xp / Math.max(1, xpMedia))
    const n = Math.max(vic, porXp)
    combates += n
    xpAcum += xpMedia * n
    console.log('   ' + etapa.padEnd(9) + String(vic).padStart(3)
                + ' victorias · la xp pide ' + String(porXp).padStart(3)
                + ' → ' + String(n).padStart(3) + ' combates')
}
console.log('\ncombates mínimos hasta Ultimate: %d', combates)
console.log('tiempo mínimo (si no duermes ni fallas): %s', horas(minTotal))
console.log('→ a ritmo humano, con sueño de 10 h al día: unos %d días',
            Math.ceil(minTotal / (14 * 60)))

// ── 2. la economía ────────────────────────────────────────────────
tit('2 · ¿Cierra la economía?')

const etapasReales = R.ESCALERA.filter(e => Object.keys(indice).some(k => indice[k].l === e))
let bitsCombates = 0
for (const [etapa, , vic] of filas) {
    const rivales = Object.keys(indice).filter(k => indice[k].l === etapa)
    const media = rivales.reduce(
        (s, k) => s + R.bitsDe(indice, k, false), 0) / Math.max(1, rivales.length)
    bitsCombates += media * vic
}
const bitsJefes = 9 * (Object.keys(indice).filter(k => indice[k].l === 'Adult')
    .reduce((s, k) => s + R.bitsDe(indice, k, true), 0)
    / Math.max(1, Object.keys(indice).filter(k => indice[k].l === 'Adult').length))
const bitsObjetivos = R.OBJETIVOS.reduce((s, o) => s + o.bits, 0)

console.log('ingresos hasta la cima (aprox):')
console.log('   combates normales ' + String(Math.round(bitsCombates)).padStart(6))
console.log('   los nueve jefes   ' + String(Math.round(bitsJefes)).padStart(6))
console.log('   los ' + R.OBJETIVOS.length + ' objetivos  '
            + String(bitsObjetivos).padStart(6))
console.log('   TOTAL             '
            + String(Math.round(bitsCombates + bitsJefes + bitsObjetivos)).padStart(6))
console.log('\nprecios:')
for (const id of Object.keys(R.PRECIOS))
    console.log('   ' + id.padEnd(10) + String(R.precioDe(id)).padStart(5)
                + '   (se vende por ' + R.precioVenta(id) + ')')
const total = bitsCombates + bitsJefes + bitsObjetivos
console.log('\nel Anticuerpo X cuesta %d = %s%% de todo lo que ganas',
            R.precioDe('antidoto'),
            (100 * R.precioDe('antidoto') / total).toFixed(1))
console.log('comidas que podrías comprar con todo: %d raciones grandes',
            Math.floor(total / R.precioDe('grande')))

// ── 3. el entrenamiento ───────────────────────────────────────────
tit('3 · El entrenamiento: ¿cuántas sesiones?')

//  Una sesión da `aciertos * factor` repartido; con tres rondas y dificultad
//  normal (×2), lo normal es +2 a +6 en la estadística elegida.
for (const etapa of ['Child', 'Adult', 'Perfect', 'Ultimate']) {
    const tope = R.topeEntreno(etapa)
    console.log(etapa.padEnd(9) + ': tope ' + String(tope).padStart(2)
                + ' por estadística → ' + Math.ceil(tope / 6)
                + ' sesiones por stat, ' + 4 * Math.ceil(tope / 6)
                + ' para las cuatro')
}

//  Y lo que se prometió en la fase 1: entrenado a tope ≈ la etapa siguiente
//  sin entrenar.
console.log('\ncalibración (lo que promete la fase 1):')
for (const [a, b] of [['Child', 'Adult'], ['Adult', 'Perfect'], ['Perfect', 'Ultimate']]) {
    const deA = Object.keys(indice).filter(k => indice[k].l === a).slice(0, 60)
    const deB = Object.keys(indice).filter(k => indice[k].l === b).slice(0, 60)
    const tope = R.topeEntreno(a)
    const ent = { pv: tope, atq: tope, def: tope, vel: tope }
    const mA = deA.reduce((s, k) => s + R.statsDe(indice, k, ent).vida, 0) / deA.length
    const mB = deB.reduce((s, k) => s + R.statsDe(indice, k, 0).vida, 0) / deB.length
    console.log('   ' + a.padEnd(8) + ' a tope ' + String(Math.round(mA)).padStart(4)
                + ' PV  vs  ' + b.padEnd(8) + ' crudo ' + String(Math.round(mB)).padStart(4)
                + ' PV   (' + Math.round(100 * mA / mB) + '%)')
}

// ── 4. el castigo por descuidar ───────────────────────────────────
tit('4 · El ritmo del cuidado y cuánto perdona')

const qml = fs.readFileSync(path.join(raiz, 'services/Digivice.qml'), 'utf8')
function cte(nombre, pordefecto) {
    const m = qml.match(new RegExp('property int ' + nombre + ':\\s*(\\d+)'))
    return m ? parseInt(m[1], 10) : pordefecto
}
const VIG = 14 * 60
const GRACIA = cte('minutosGraciaError', 90)
const ENF = cte('erroresParaEnfermar', 3)
const mReg = qml.match(/erroresParaRegresar:\s*erroresParaEnfermar \+ (\d+)/)
const REG = ENF + (mReg ? parseInt(mReg[1], 10) : 6)

console.log('el cuidado va por AGENDA, no por goteo: cada día tiene sus horas')
console.log('de hambre y de mimo, y cambian de un día para otro.\n')
console.log('sucesos por día:')
for (const t of ['hambre', 'animo', 'caca'])
    console.log('   ' + t.padEnd(8) + R.AGENDA[t].min + ' a ' + R.AGENDA[t].max)
console.log('   separación mínima entre comer y mimar: ' + R.SEPARACION + ' min')

//  Un día de ejemplo, para ver que no es un metrónomo.
const hm = m => String(8 + Math.floor(m / 60)).padStart(2, '0')
                + ':' + String(m % 60).padStart(2, '0')
console.log('\ntres días seguidos de un mismo bicho (horas de comer):')
for (let d = 0; d < 3; ++d)
    console.log('   día ' + d + ': '
                + R.agendaDelDia(4242, d, 'hambre', VIG).slice(0, 8).map(hm).join(' '))

//  Cuánto tarda en vaciarse: cuatro corazones son cuatro sucesos.
let sH = 0, sA = 0
for (let d = 1; d <= 200; ++d) {
    const h = R.agendaDelDia(d, 0, 'hambre', VIG)
    const a = R.agendaDelDia(d, 0, 'animo', VIG)
    sH += h.length >= 4 ? h[3] : VIG
    sA += a.length >= 4 ? a[3] : VIG
}
console.log('\nse vacía (media de 200 bichos):')
console.log('   hambre en ' + horas(Math.round(sH / 200)))
console.log('   ánimo  en ' + horas(Math.round(sA / 200)))

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
        if (dh && m - dh >= GRACIA) { dh = m; e += 1 }
        if (da && m - da >= GRACIA) { da = m; e += 1 }
        if (e >= errores) return m
    }
    return Infinity
}
let peorR = Infinity, peorE = Infinity, medR = 0
for (let d = 1; d <= 200; ++d) {
    const r = cuandoLlega(REG, d), e2 = cuandoLlega(ENF, d)
    peorR = Math.min(peorR, r); peorE = Math.min(peorE, e2); medR += r
}
console.log('\nsin tocarlo (peor día de 200):')
console.log('   enferma a las      ' + horas(peorE))
console.log('   REGRESA de etapa a las ' + horas(peorR)
            + '   (media ' + horas(Math.round(medR / 200)) + ')')
console.log('\ncontexto: el tope de progreso con la barra cerrada son 8 h,')
console.log('y duerme de 22:00 a 08:00 (dormido no hay agenda).')
if (peorR <= 8 * 60) {
    console.log('\n*** UNA JORNADA DE TRABAJO LO HACE REGRESAR ***')
} else {
    console.log('\n→ ni en el peor día una jornada de 8 h lo degrada.')
}

// ── 4b. la carretera ──────────────────────────────────────────────
tit('4b · Las expediciones: ¿cuánto se tarda en llegar al jefe?')

console.log('zancadas: ' + Object.keys(R.ZANCADAS).map(
    k => k + ' ' + R.ZANCADAS[k]).join(' · '))
console.log('\nlongitud de las nueve carreteras:')
let linea = '   '
for (let z = 0; z < 9; ++z) linea += String(R.distanciaJefe(z)).padStart(6)
console.log(linea)

//  Cuánta distancia hace un día según cómo uses el ordenador. El goteo del
//  reloj es el SUELO: tiene que quedar por debajo del uso activo, o daría
//  igual usar el ordenador y la idea entera se cae.
const RELOJ_SEG = cte('segundosPorPaso', 90)
const porRelojDia = Math.round(14 * 3600 / RELOJ_SEG) * R.ZANCADAS.reloj

const perfiles = [
    { n: 'apenas lo usa',   ventanas: 0,   escritorios: 0,  apps: 0 },
    { n: 'uso ligero',      ventanas: 60,  escritorios: 10, apps: 3 },
    { n: 'uso normal',      ventanas: 200, escritorios: 30, apps: 8 },
    { n: 'todo el día',     ventanas: 500, escritorios: 80, apps: 20 }
]
console.log('\ndistancia al día (el goteo del reloj aporta ' + porRelojDia + '):')
for (const p of perfiles) {
    const activa = p.ventanas * R.ZANCADAS.ventana
                 + p.escritorios * R.ZANCADAS.escritorio
                 + p.apps * R.ZANCADAS.app
    const tot = activa + porRelojDia
    const pct = Math.round(100 * activa / tot)
    console.log('   ' + p.n.padEnd(16) + String(tot).padStart(5)
                + '   (' + pct + '% viene de usarlo)'
                + (pct < 50 ? '   ← manda el reloj, no tú' : ''))
}

console.log('\ndías hasta el jefe de cada zona:')
console.log('   ' + 'perfil'.padEnd(16)
            + [1, 3, 5, 7, 9].map(z => ('z' + z).padStart(7)).join(''))
for (const p of perfiles) {
    const tot = p.ventanas * R.ZANCADAS.ventana
              + p.escritorios * R.ZANCADAS.escritorio
              + p.apps * R.ZANCADAS.app + porRelojDia
    let fila = '   ' + p.n.padEnd(16)
    for (const z of [1, 3, 5, 7, 9])
        fila += (R.distanciaJefe(z - 1) / tot).toFixed(1).padStart(7)
    console.log(fila)
}

//  Y qué te encuentras por el camino.
console.log('\nqué sale en la carretera (10 zonas × 40 semillas):')
const cuenta = {}
let hitos = 0
for (let sem = 0; sem < 40; ++sem)
    for (let z = 0; z < 9; ++z) {
        const fin = R.distanciaJefe(z)
        for (const h of R.hitosDe(sem, z)) {
            const e = R.eventoDeHito(sem, z, h, fin)
            cuenta[e] = (cuenta[e] || 0) + 1
            hitos += 1
        }
    }
for (const k of Object.keys(cuenta).sort((a, b) => cuenta[b] - cuenta[a]))
    console.log('   ' + k.padEnd(10) + String(Math.round(100 * cuenta[k] / hitos)).padStart(3) + '%')
console.log('   ' + String(Math.round(hitos / (40 * 9))).padStart(3)
            + ' hitos de media por carretera')

//  Que el principio sea apacible y el final tenga bichos.
let biPrimero = 0, biUltimo = 0, nPrim = 0, nUlt = 0
for (let sem = 0; sem < 60; ++sem) {
    const z = 4, fin = R.distanciaJefe(z)
    const hs = R.hitosDe(sem, z)
    for (const h of hs) {
        const e = R.eventoDeHito(sem, z, h, fin)
        if (h.en < fin * 0.25) { nPrim += 1; if (e === 'bicho') biPrimero += 1 }
        if (h.en > fin * 0.75 && !h.jefe) { nUlt += 1; if (e === 'bicho') biUltimo += 1 }
    }
}
console.log('\nbichos en el primer cuarto: ' + Math.round(100 * biPrimero / nPrim)
            + '%   ·   en el último: ' + Math.round(100 * biUltimo / nUlt) + '%')

// ── 4c. el huevo ──────────────────────────────────────────────────
tit('4c · El primer huevo: ¿cuánto se espera?')

const PARA_ROMPER = (function () {
    const m = qml.match(/property int pasosParaEclosionar:\s*(\d+)/)
    return m ? parseInt(m[1], 10) : 24
})()
console.log('rompe a las ' + PARA_ROMPER + ' de zancada acumulada')
console.log('(cuenta la MISMA zancada que la carretera: ventana 1, escritorio 2,')
console.log(' abrir una aplicación 5, y el goteo del reloj)\n')
console.log('   ' + 'perfil'.padEnd(16) + 'al día'.padStart(7) + 'tarda'.padStart(12))
for (const p of perfiles) {
    const tot = p.ventanas * R.ZANCADAS.ventana
              + p.escritorios * R.ZANCADAS.escritorio
              + p.apps * R.ZANCADAS.app + porRelojDia
    const horas14 = PARA_ROMPER / (tot / 14)
    console.log('   ' + p.n.padEnd(16) + String(tot).padStart(7)
                + (horas14 < 1
                   ? (Math.round(horas14 * 60) + ' min').padStart(12)
                   : (horas14.toFixed(1) + ' h').padStart(12)))
}
console.log('\nes lo PRIMERO que ve quien abre el plugin: tiene que sentirse')
console.log('una espera de verdad, pero no tanta como para cerrarlo y olvidarlo.')

// ── 5. el combate ─────────────────────────────────────────────────
tit('5 · El combate')

function azarFijo(s) {
    let x = s
    return () => { x = (x * 1103515245 + 12345) & 0x7fffffff; return x / 0x7fffffff }
}
for (const etapa of ['Child', 'Adult', 'Perfect']) {
    const pool = Object.keys(indice).filter(
        k => indice[k].l === etapa && (indice[k].sk || []).length >= 2)
    let gane = 0, turnos = 0, n = 300, colgados = 0
    for (let i = 0; i < n; ++i) {
        const x = pool[i % pool.length], y = pool[(i * 13 + 7) % pool.length]
        if (x === y) continue
        const r = R.resolverCombate(indice, x, y, { azar: azarFijo(i + 1) })
        if (r.gane) gane += 1
        turnos += r.turnos.length
        if (r.turnos.length >= 40) colgados += 1
    }
    console.log(etapa.padEnd(8) + ': ' + Math.round(100 * gane / n)
                + '% de victorias · ' + (turnos / n).toFixed(1)
                + ' turnos de media · ' + colgados + ' sin terminar')
}

//  Un combate a tu altura, ¿cuánto dura en tiempo real?
//
//  El combate ya no espera a que pulses: va solo y tú intervienes si quieres,
//  así que el ritmo lo marca ENTERO el reloj de la pantalla. El número estaba
//  a mano —1150 ms— y se quedó viejo en cuanto cambió el temporizador; ahora
//  se lee del propio QML para que esta cuenta no pueda mentir.
const comb = fs.readFileSync(
    path.join(raiz, 'plugins/Digivice/Combate.qml'), 'utf8')
function tempo(id, pordefecto) {
    const m = comb.match(new RegExp('id: ' + id + '[\\s\\S]{0,80}?interval:\\s*(\\d+)'))
    return m ? parseInt(m[1], 10) : pordefecto
}
const PASO = tempo('reloj', 1500) / 1000
const VS = tempo('arranque', 1600) / 1000
const mediaTurnos = 19
const duracion = VS + mediaTurnos * PASO
console.log('\nel combate va SOLO: %s s de pantalla VS y %s s por intercambio',
            VS.toFixed(1), PASO.toFixed(1))
console.log('un combate de %d intercambios son ~%d s sin tocar un botón',
            mediaTurnos, Math.round(duracion))
console.log('→ los %d combates hasta la cima son ~%s de pelea pura',
            combates, horas(Math.round(combates * duracion / 60)))
console.log('→ y hasta %d intervenciones por combate, todas opcionales',
            mediaTurnos)

// ── 6. la caza ────────────────────────────────────────────────────
tit('6 · La caza y la comida')

console.log('cazar cuesta 12 de rastro; cada cambio de ventana da 1')
console.log('→ una cacería cada 12 cambios de ventana')
console.log('un tercio de los rastros sienta mal, así que de cada 3 cacerías')
console.log('a ciegas sale 1 mala; con la velocidad al tope, 1 de cada 2')
const comidas = R.COMIDAS.map(c => c.id)
console.log('\ncomidas: %s', comidas.join(', '))
console.log('la ración es infinita: el hambre nunca puede matar por falta de comida')

// ── 7. veredicto ──────────────────────────────────────────────────
tit('7 · Contraste con los originales')

console.log('Digital Tamers ReBorn pide, literalmente:')
console.log('   «500 Wins required to proceed evolution.»')
console.log('   «250 Wins and 0 Losses required to proceed evolution.»')
console.log('Este juego pide %d victorias en TODA la escalera.', vicTotal)
console.log('→ ' + (500 / Math.max(1, vicTotal)).toFixed(1)
            + ' veces menos. Es deliberado: aquello es un RPG de móvil')
console.log('  con horas de grindeo; esto vive en una barra de escritorio.')
console.log('\nDel emulador de aparatos NO se han podido sacar constantes:')
console.log('las guarda en el bytecode de GameMaker, no en cadenas. De él se')
console.log('tiene el MODELO —los nombres de variable— y ahí sí hay una')
console.log('diferencia de fondo que conviene tener presente:')
console.log('   original:  poop_events_per_day · sleep_minutes_per_day')
console.log('              hunger_events_left · next_hunger_zero')
console.log('              → sucesos programados por DÍA')
console.log('   este:      un goteo continuo a ritmo fijo')
console.log('El modelo por día reparte mejor los avisos a lo largo de la')
console.log('jornada; el goteo es más simple y más fácil de explicar. Se')
console.log('queda el goteo, pero con los tiempos ya corregidos.')
