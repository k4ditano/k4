pragma Singleton

//  Gasto en agentes de IA, convertido en combustible para la mazmorra.
//
//  La idea: que el juego de la island no pelee solo, sino al ritmo al que tú
//  picas código con la IA. Cada token que gastas en Claude o Codex entra aquí
//  como «chispa»; el combate la quema. Si dejas de trabajar, tu grupo para.
//
//  El cambio no es arbitrario. Midiendo el historial real de este equipo salen
//  unas 92.000 chispas por minuto de trabajo de verdad, así que a 1.500 por
//  segundo la partida avanza más o menos en tiempo real mientras estás dentro
//  de una sesión, y se detiene cuando te levantas. Esa es toda la regla.
//
//  Se llevan dos cuentas distintas y no hay que confundirlas:
//
//    · el depósito, en chispa ponderada, que es lo que mueve el combate y solo
//      se llena con lo que gastes a partir de instalar esto;
//    · el histórico, en tokens crudos, que sí arranca con todo lo que ya
//      habías gastado. Es el número que se enseña.
//
//  Quien vigila los ficheros es tools/vigia-tokens.py, que solo lee lo que se
//  ha añadido desde la última vuelta. Añadir una herramienta nueva se hace
//  allí, no aquí.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: tokens

    // ── conversión ────────────────────────────────────────────────
    // Midiendo bloques de trabajo reales salen 75.000 chispas por minuto de
    // reloj, no por minuto activo: entre rafaga y rafaga se lee, se piensa y
    // se espera a que corra una herramienta. A 1.500/s el deposito se quedaba
    // seco el 16% del tiempo y aparecia el cartel de espera trabajando; a
    // 1.000 sobra margen y el combate no se corta.
    readonly property int chispaPorSegundo: 1000
    // Un depósito con fondo: media hora guardada cubre de sobra los ratos de
    // lectura entre turnos, y evita que una noche de tareas largas deje la
    // mazmorra corriendo sola hasta mañana.
    readonly property int topeDeposito: chispaPorSegundo * 60 * 30
    // Tres meses de detalle diario bastan para la gráfica; el total no caduca.
    readonly property int diasGuardados: 92

    // ── combustible ───────────────────────────────────────────────
    property real deposito: 0

    readonly property bool hay: deposito >= chispaPorSegundo * 0.2
    readonly property real segundos: deposito / chispaPorSegundo
    readonly property real llenado: Math.min(1, deposito / topeDeposito)

    // ── histórico ─────────────────────────────────────────────────
    property real totalTokens: 0
    property real totalChispa: 0
    property var porFuente: ({})            // { claude: { chispa, tokens } }
    property var historial: ({})            // { "2026-07-27": { chispa, tokens } }

    property string ultimaFuente: ""
    property real ultimoIngreso: 0
    property real ultimaCantidad: 0

    // ¿estás gastando ahora mismo? sirve para que la interfaz distinga
    // «trabajando» de «tirando de lo ahorrado»
    property bool activo: false

    signal ingreso(real chispa, string fuente)

    function ahora() { return Date.now() / 1000 }
    function dia(d) { return Qt.formatDate(d || new Date(), "yyyy-MM-dd") }

    property string hoy: dia()

    // Se recalculan al tocar el historial, que es lo único que los mueve.
    property real tokensHoy: 0
    property int racha: 0

    // Descuenta el combate consumido y devuelve los segundos que de verdad se
    // pueden jugar, que es lo que el juego debe simular.
    function gastar(segs) {
        const posibles = Math.min(segs, deposito / chispaPorSegundo)
        if (posibles <= 0)
            return 0

        deposito = Math.max(0, deposito - posibles * chispaPorSegundo)
        // sin esto lo gastado no se guardaba: solo se escribía el fichero al
        // entrar tokens nuevos, y al reiniciar volvía el depósito de antes
        sucio = true
        return posibles
    }

    // Días seguidos gastando algo. Se cuenta hacia atrás desde hoy, y si hoy
    // aún no has tocado nada se empieza en ayer: la racha no se rompe hasta
    // que te saltas un día entero.
    function calcularRacha() {
        const d = new Date()
        if (!historial[dia(d)])
            d.setDate(d.getDate() - 1)

        let n = 0
        while (historial[dia(d)] && historial[dia(d)].tokens > 0) {
            ++n
            d.setDate(d.getDate() - 1)
        }
        return n
    }

    // Los últimos `cuantos` días en orden, incluidos los vacíos: una gráfica
    // sin huecos miente sobre la constancia.
    function ultimosDias(cuantos) {
        const salida = []
        const d = new Date()
        d.setDate(d.getDate() - (cuantos - 1))

        for (let i = 0; i < cuantos; ++i) {
            const clave = dia(d)
            const e = historial[clave]
            salida.push({ dia: clave, tokens: e ? e.tokens : 0 })
            d.setDate(d.getDate() + 1)
        }
        return salida
    }

    function recalcular() {
        const h = historial[hoy]
        tokensHoy = h ? h.tokens : 0
        racha = calcularRacha()
    }

    // ── entrada de datos ──────────────────────────────────────────
    function anotar(d) {
        const fuentes = d.fuentes || ({})
        const dias = d.dias || ({})
        let chispaNueva = 0
        let cual = ""

        const pf = porFuente
        for (const nombre in fuentes) {
            const e = fuentes[nombre]
            const acc = pf[nombre] || ({ chispa: 0, tokens: 0 })
            acc.chispa += e.chispa
            acc.tokens += e.tokens
            pf[nombre] = acc

            totalChispa += e.chispa
            totalTokens += e.tokens

            if (e.chispa > chispaNueva) {
                chispaNueva = e.chispa
                cual = nombre
            }
        }
        porFuente = pf

        const hist = historial
        for (const clave in dias) {
            const e = dias[clave]
            const acc = hist[clave] || ({ chispa: 0, tokens: 0 })
            acc.chispa += e.chispa
            acc.tokens += e.tokens
            hist[clave] = acc
        }
        historial = podar(hist)
        recalcular()

        sucio = true

        // El repaso inicial cuenta para la estadística pero no llena el
        // depósito: si no, estrenar el modo regalaría meses de combate.
        if (d.historico)
            return

        let total = 0
        for (const nombre in fuentes)
            total += fuentes[nombre].chispa

        deposito = Math.min(topeDeposito, deposito + total)
        ultimaFuente = cual
        ultimaCantidad = total
        ultimoIngreso = ahora()
        activo = true

        ingreso(total, cual)
    }

    function podar(hist) {
        const claves = Object.keys(hist).sort()
        if (claves.length <= diasGuardados)
            return hist

        const salida = ({})
        for (let i = claves.length - diasGuardados; i < claves.length; ++i)
            salida[claves[i]] = hist[claves[i]]
        return salida
    }

    // ── texto para la interfaz ────────────────────────────────────
    function resto() {
        const s = Math.floor(segundos)
        if (s <= 0) return "sin chispa"
        if (s < 60) return s + " s"
        const m = Math.floor(s / 60)
        return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60) + " min"
    }

    function cifra(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(n >= 1e10 ? 0 : 1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "K"
        return String(Math.round(n))
    }

    // ── el vigía ──────────────────────────────────────────────────
    Process {
        id: vigia
        command: ["python3", Quickshell.shellPath("tools/vigia-tokens.py")]
        // Su único consumidor es la mazmorra: apagada, no hay por qué estar
        // leyendo ficheros de sesión cada tres segundos.
        running: Settings.juegoActivo

        stdout: SplitParser {
            onRead: function (linea) {
                let d = null
                try {
                    d = JSON.parse(linea)
                } catch (e) {
                    return
                }
                if (d && d.fuentes)
                    tokens.anotar(d)
            }
        }

        // Si el vigía se cae —python actualizado, fichero movido— el modo
        // dejaría de dar combustible en silencio. Se reintenta con calma.
        onExited: reintento.restart()
    }

    Timer {
        id: reintento
        interval: 15000
        onTriggered: if (Settings.juegoActivo) vigia.running = true
    }

    // «Activo» caduca: sin ingresos durante un minuto, dejas de estar picando.
    //
    //  Con la mazmorra apagada nadie consume «activo», así que el latido
    //  baja a uno por minuto — lo justo para el cambio de día. Era el único
    //  timer sin condición del fichero, y despertar el bucle de eventos cada
    //  cinco segundos de por vida no se lo gana nadie gratis.
    Timer {
        interval: Settings.juegoActivo ? 5000 : 60000
        repeat: true
        running: true
        onTriggered: {
            tokens.activo = tokens.ahora() - tokens.ultimoIngreso < 60

            // A medianoche cambia el dia: sin esto, «hoy» se quedaria clavado
            // en la fecha de cuando arranco la barra.
            const d = tokens.dia()
            if (d !== tokens.hoy) {
                tokens.hoy = d
                tokens.recalcular()
            }
        }
    }

    // ── persistencia ──────────────────────────────────────────────
    //  El depósito sobrevive a reiniciar la barra: lo gastaste, es tuyo.
    readonly property string ruta: Quickshell.env("HOME") + "/.local/state/k4/tokens.json"
    property bool cargado: false
    property bool sucio: false

    FileView { id: vista; path: tokens.ruta; blockLoading: true }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: tokens.cargar()
    }

    Timer {
        interval: 20000
        repeat: true
        running: tokens.cargado
        onTriggered: {
            if (!tokens.sucio)
                return
            tokens.sucio = false
            vista.setText(JSON.stringify({
                deposito: Math.round(tokens.deposito),
                totalChispa: Math.round(tokens.totalChispa),
                totalTokens: Math.round(tokens.totalTokens),
                porFuente: tokens.porFuente,
                historial: tokens.historial
            }, null, 1))
        }
    }

    function cargar() {
        const bruto = vista.text()

        if (bruto.length > 0) {
            try {
                const s = JSON.parse(bruto)
                deposito = Math.min(topeDeposito, s.deposito || 0)
                totalChispa = s.totalChispa || 0
                totalTokens = s.totalTokens || 0
                porFuente = s.porFuente || ({})
                historial = s.historial || ({})
                recalcular()
            } catch (e) {
                // depósito ilegible: se empieza en seco
            }
        }

        cargado = true
    }
}
