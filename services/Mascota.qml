pragma Singleton

//  La mascota de la barra: una criatura que no simula un mundo, siente el
//  tuyo. Sus sentidos son lecturas de los servicios que ya existen —CPU,
//  música, clima, tokens, notificaciones— y su colección se desbloquea por
//  cómo usas la máquina de verdad.
//
//  Toda la simulación vive aquí; plugins/Mascota es vista y poco más. Las
//  reglas de la casa: determinista, sin red, y deriva de necesidades LENTA —
//  esto es compañía, no chantaje.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: mascota

    // ── curvas y constantes, con nombre y unidad ──────────────────
    readonly property real hambrePorHora: 4        // puntos que baja la saciedad
    readonly property real animoPorHora: 3
    readonly property real energiaPorHora: 5       // se gasta despierta
    readonly property real descansoPorHora: 20     // se recupera dormida/ausente
    readonly property int topeOfflineHoras: 8      // como la mazmorra
    readonly property int comidaSube: 30
    readonly property int caricia: 18
    readonly property int juegoSube: 25
    readonly property int diasEtapa1: 7            // cría → adulta
    readonly property int diasEtapa2: 21           // adulta → forma final
    readonly property int tironCadaMin: 45         // cooldown del tirón de atención

    // ── el catálogo de especies ───────────────────────────────────
    //
    //  `umbral` está en la unidad del contador que lo vigila (minutos, veces,
    //  días o elementos de un conjunto). La pista sale en el terrario
    //  mientras la especie sigue en silueta.
    readonly property var especies: [
        { id: "pulpo", nombre: "Pulpi", contador: "", umbral: 0,
          pista: "" },
        { id: "buho", nombre: "Búho de lámpara", contador: "madrugadaMin", umbral: 300,
          pista: "le gusta oírte teclear de madrugada" },
        { id: "dragon", nombre: "Dragón de datos", contador: "chispaDias", umbral: 5,
          pista: "huele la chispa que gastas en la IA" },
        { id: "salamandra", nombre: "Salamandra de fragua", contador: "cpuAltaMin", umbral: 30,
          pista: "solo sale cuando la máquina arde" },
        { id: "sirena", nombre: "Sirena de altavoz", contador: "musicaMin", umbral: 3000,
          pista: "cuenta las horas que suena tu música" },
        { id: "bonsai", nombre: "Bonsái andante", contador: "diasTranquilos", umbral: 7,
          pista: "crece donde hay silencio y pocas interrupciones" },
        { id: "gato", nombre: "Gato del portapapeles", contador: "copias", umbral: 500,
          pista: "colecciona todo lo que copias" },
        { id: "paloma", nombre: "Paloma mensajera", contador: "notifsTotal", umbral: 1000,
          pista: "llega con el correo de cada día" },
        { id: "capibara", nombre: "Capibara del onsen", contador: "diasConPausa", umbral: 20,
          pista: "aprecia a quien sabe descansar" },
        { id: "zorro", nombre: "Zorro del wifi", contador: "redes", umbral: 10,
          pista: "te sigue de red en red" },
        { id: "golem", nombre: "Golem de silicio", contador: "uptimeMin", umbral: 12000,
          pista: "despierta tras muchas horas de barra encendida" },
        { id: "fantasma", nombre: "Fantasma del orden", contador: "limpiezas", umbral: 30,
          pista: "aparece donde se barre a menudo" },
        { id: "abeja", nombre: "Abeja obrera", contador: "diasEnjambre", umbral: 5,
          pista: "admira a quien trabaja en muchos escritorios" },
        { id: "camaleon", nombre: "Camaleón del tema", contador: "tintes", umbral: 10,
          pista: "se asoma cuando la barra cambia de color" },
        { id: "ballena", nombre: "Ballena lunar", contador: "diasRacha", umbral: 30,
          pista: "solo emerge ante treinta días seguidos de compañía" }
    ]

    function especieDe(id) {
        for (let i = 0; i < especies.length; ++i)
            if (especies[i].id === id)
                return especies[i]
        return null
    }

    // ── estado ────────────────────────────────────────────────────
    property bool cargado: false
    property string activa: "pulpo"
    //  { id: { dias: <días de convivencia> } }, solo desbloqueadas.
    property var coleccion: ({ pulpo: { dias: 0 } })
    //  Los sentidos acumulados. `redes` y `hoyEscritorios` son conjuntos.
    property var contadores: ({
        madrugadaMin: 0, chispaDias: 0, cpuAltaMin: 0, musicaMin: 0,
        diasTranquilos: 0, copias: 0, notifsTotal: 0, diasConPausa: 0,
        redes: [], uptimeMin: 0, limpiezas: 0, diasEnjambre: 0,
        tintes: 0, diasRacha: 0
    })
    property real hambre: 80       // saciedad: 0 hambrienta, 100 llena
    property real energia: 90
    property real animo: 80
    property real carino: 50
    property real ultimaVez: 0     // epoch segundos del último tick guardado

    //  Memoria de trabajo del día, no persiste entre días.
    property string hoyFecha: ""
    property int hoyNotifs: 0
    property real hoyChispaBase: -1
    property var hoyEscritorios: []
    property bool hoyPausa: false
    property string ultimoDiaVisto: ""

    //  Transitorios visuales.
    property real comiendoHasta: 0
    property real saludandoHasta: 0
    property real ultimoTiron: 0
    property real bloqueoDesde: 0
    property int notifsAntes: -1

    // ── lo que la vista pregunta ──────────────────────────────────

    readonly property var especieActiva: especieDe(activa)
    readonly property int etapa: etapaDe((coleccion[activa] || { dias: 0 }).dias)
    readonly property string nombre: Settings.mascotaNombre.length > 0
        ? Settings.mascotaNombre : (especieActiva ? especieActiva.nombre : "")

    function etapaDe(dias) {
        return dias >= diasEtapa2 ? 2 : (dias >= diasEtapa1 ? 1 : 0)
    }

    //  Poses de la hoja base (pulpo): 0 contento · 1 dormido · 2 bailando ·
    //  3 asustado · 4 comiendo · 5 saludando. Pura: la vista y la píldora
    //  preguntan y no deciden.
    function poseDe(ahora) {
        if (ahora < comiendoHasta) return 4
        if (ahora < saludandoHasta) return 5
        if (Sesion.bloqueado || energia < 20) return 1
        if (cpuCarga > 0.85) return 3
        if (Media.isPlaying && animo > 40) return 2
        return 0
    }

    readonly property string humor: {
        if (hambre < 25) return "hambrienta"
        if (energia < 20) return "agotada"
        if (animo > 70 && hambre > 50) return "radiante"
        if (animo < 30) return "mustia"
        return "tranquila"
    }

    // ── acciones ──────────────────────────────────────────────────

    function comer() {
        hambre = Math.min(100, hambre + comidaSube)
        comiendoHasta = Date.now() / 1000 + 6
        apuntar()
    }

    function acariciar() {
        carino = Math.min(100, carino + caricia)
        animo = Math.min(100, animo + 6)
        apuntar()
    }

    function jugar() {
        animo = Math.min(100, animo + juegoSube)
        energia = Math.max(0, energia - 8)
        apuntar()
    }

    function adoptar(id) {
        if (!coleccion[id])
            return
        activa = id
        saludandoHasta = Date.now() / 1000 + 5
        apuntar()
    }

    // ── el reloj ──────────────────────────────────────────────────

    property var _reloj: Timer {
        interval: 60000
        repeat: true
        running: mascota.cargado && Settings.mascotaActiva
        onTriggered: mascota.tick(1)
    }

    //  CPU sin encender el panel de Sistema: /proc/loadavg una vez por tick.
    property real cpuCarga: 0
    property int _nucleos: 1
    property var _sondaCpu: Process {
        command: ["cat", "/proc/loadavg"]
        stdout: StdioCollector {
            onStreamFinished: {
                const carga = parseFloat(String(this.text).split(" ")[0])
                if (isFinite(carga))
                    mascota.cpuCarga = carga / Math.max(1, mascota._nucleos)
            }
        }
    }
    property var _sondaNucleos: Process {
        command: ["nproc"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(String(this.text).trim(), 10)
                if (isFinite(n) && n > 0)
                    mascota._nucleos = n
            }
        }
    }

    function tick(minutos) {
        const ahora = Date.now() / 1000
        const fecha = new Date().toISOString().slice(0, 10)
        const hora = new Date().getHours()
        _sondaCpu.running = true

        //  Día nuevo: se cierran los contadores del día anterior.
        if (fecha !== hoyFecha) {
            _cerrarDia()
            hoyFecha = fecha
        }

        //  Necesidades: deriva lenta. Ausente (sesión bloqueada) descansa.
        const h = minutos / 60
        hambre = Math.max(0, hambre - hambrePorHora * h)
        if (Sesion.bloqueado) {
            energia = Math.min(100, energia + descansoPorHora * h)
        } else {
            energia = Math.max(0, energia - energiaPorHora * h)
            animo = Math.max(0, animo - animoPorHora * h)
        }
        carino = Math.max(0, carino - 1 * h)

        //  Sentidos.
        const c = Object.assign({}, contadores)
        c.uptimeMin += minutos
        if (!Sesion.bloqueado && hora >= 0 && hora < 5)
            c.madrugadaMin += minutos
        if (Media.isPlaying)
            c.musicaMin += minutos
        if (cpuCarga > 0.85)
            c.cpuAltaMin += minutos

        //  Notificaciones: deltas positivos suman; caer a cero desde varias
        //  es una limpieza.
        if (notifsAntes >= 0) {
            if (Notifs.count > notifsAntes) {
                const nuevas = Notifs.count - notifsAntes
                c.notifsTotal += nuevas
                hoyNotifs += nuevas
                if (nuevas >= 3)
                    animo = Math.max(0, animo - 3)   // el bombardeo asusta
            } else if (Notifs.count === 0 && notifsAntes >= 3) {
                c.limpiezas += 1
            }
        }
        notifsAntes = Notifs.count

        //  Copias del portapapeles, por delta del historial.
        if (Clipboard.cargado) {
            if (c._copiasAntes === undefined)
                c._copiasAntes = Clipboard.count
            if (Clipboard.count > c._copiasAntes)
                c.copias += Clipboard.count - c._copiasAntes
            c._copiasAntes = Clipboard.count
        }

        //  Redes y escritorios: conjuntos de nombres vistos.
        if (Wifi.name && c.redes.indexOf(Wifi.name) < 0)
            c.redes = c.redes.concat([Wifi.name])
        if (hoyEscritorios.indexOf(Workspaces.activo) < 0)
            hoyEscritorios = hoyEscritorios.concat([Workspaces.activo])

        //  Pausas: cinco minutos bloqueada cuentan como descanso del día.
        if (Sesion.bloqueado) {
            if (bloqueoDesde === 0)
                bloqueoDesde = ahora
            else if (ahora - bloqueoDesde > 300)
                hoyPausa = true
        } else {
            bloqueoDesde = 0
        }

        //  Chispa de IA: ¿ha crecido hoy?
        if (hoyChispaBase < 0)
            hoyChispaBase = Tokens.totalChispa

        contadores = c

        //  Convivencia: la activa suma días de calendario contigo.
        if (ultimoDiaVisto !== fecha) {
            ultimoDiaVisto = fecha
            const col = Object.assign({}, coleccion)
            col[activa] = { dias: (col[activa] ? col[activa].dias : 0) + 1 }
            const antes = etapaDe(col[activa].dias - 1)
            coleccion = col
            if (etapaDe(col[activa].dias) > antes)
                _celebrar(Idioma.f(Idioma.t("¡%1 ha evolucionado!"), nombre),
                          Idioma.t("Ábrela en la barra para verla"))
        }

        _comprobarDesbloqueos()
        _quejarse(ahora)
        _tinteDeHumor()

        ultimaVez = ahora
        apuntar()
    }

    //  El cierre de un día alimenta los contadores de días cualificados.
    function _cerrarDia() {
        if (hoyFecha === "")
            return
        const c = Object.assign({}, contadores)
        if (hoyNotifs < 20)
            c.diasTranquilos += 1
        if (hoyPausa)
            c.diasConPausa += 1
        if (hoyEscritorios.length >= 5)
            c.diasEnjambre += 1
        if (hoyChispaBase >= 0 && Tokens.totalChispa > hoyChispaBase)
            c.chispaDias += 1
        //  La racha: días consecutivos con la barra encendida.
        const ayer = new Date(Date.now() - 86400000).toISOString().slice(0, 10)
        c.diasRacha = (hoyFecha === ayer || c._ultimoDiaRacha === ayer)
            ? c.diasRacha + 1 : 1
        c._ultimoDiaRacha = hoyFecha
        contadores = c
        hoyNotifs = 0
        hoyPausa = false
        hoyEscritorios = []
        hoyChispaBase = Tokens.totalChispa
    }

    //  El camaleón cuenta tintes ajenos: los de la propia mascota no valen.
    property var _vigilaTintes: Connections {
        target: Theme
        function onTinteDuenoChanged() {
            if (Theme.tinteDueno !== "" && Theme.tinteDueno !== "mascota") {
                const c = Object.assign({}, mascota.contadores)
                c.tintes += 1
                mascota.contadores = c
            }
        }
    }

    function _valorContador(clave) {
        const v = contadores[clave]
        return (v && v.length !== undefined) ? v.length : (v || 0)
    }

    function _comprobarDesbloqueos() {
        for (let i = 0; i < especies.length; ++i) {
            const e = especies[i]
            if (coleccion[e.id] || e.umbral === 0)
                continue
            if (_valorContador(e.contador) >= e.umbral) {
                const col = Object.assign({}, coleccion)
                col[e.id] = { dias: 0 }
                coleccion = col
                _celebrar(Idioma.f(Idioma.t("¡Un huevo! %1 quiere vivir contigo"),
                                   e.nombre),
                          Idioma.t("Está esperando en el terrario"))
                return   // un desbloqueo por tick: que cada uno se celebre
            }
        }
    }

    function _celebrar(titulo, cuerpo) {
        Island.efecto("mascota", "tiron")
        Quickshell.execDetached(["notify-send", "-a", "k4",
                                 titulo, cuerpo])
    }

    //  Un tirón de atención con hambre crítica, con su propio cooldown muy
    //  por encima del freno del host: la mascota molesta lo justo.
    function _quejarse(ahora) {
        if (hambre >= 25 || ahora - ultimoTiron < tironCadaMin * 60)
            return
        ultimoTiron = ahora
        Island.efecto("mascota", "tiron", 0.5)
    }

    //  El ambiente de su humor, solo si el usuario lo pide (apagado de
    //  fábrica): tenue de verdad, y se destiñe solo al normalizarse.
    function _tinteDeHumor() {
        if (!Settings.mascotaTinte) {
            if (Theme.tinteDueno === "mascota")
                Theme.destintar("mascota")
            return
        }
        if (humor === "radiante")
            Theme.tintar("mascota", "#2e5c3a", 0.10, 0)
        else if (humor === "hambrienta" || humor === "mustia")
            Theme.tintar("mascota", "#5c2e2e", 0.10, 0)
        else if (Theme.tinteDueno === "mascota")
            Theme.destintar("mascota")
    }

    // ── persistencia ──────────────────────────────────────────────

    readonly property string ruta: Quickshell.env("HOME") + "/.local/state/k4/mascota.json"

    function apuntar() {
        if (!cargado)
            return
        vista.setText(JSON.stringify({
            activa: activa, coleccion: coleccion, contadores: contadores,
            hambre: hambre, energia: energia, animo: animo, carino: carino,
            ultimaVez: ultimaVez, hoyFecha: hoyFecha, hoyNotifs: hoyNotifs,
            hoyPausa: hoyPausa, ultimoDiaVisto: ultimoDiaVisto
        }, null, 1))
    }

    FileView { id: vista; path: mascota.ruta; blockLoading: true }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: mascota.cargar()
    }

    function cargar() {
        const bruto = vista.text()
        if (bruto.length > 0) {
            try {
                const d = JSON.parse(bruto)
                activa = d.activa || "pulpo"
                if (d.coleccion && d.coleccion.pulpo)
                    coleccion = d.coleccion
                if (d.contadores)
                    contadores = Object.assign({}, contadores, d.contadores)
                hambre = d.hambre !== undefined ? d.hambre : hambre
                energia = d.energia !== undefined ? d.energia : energia
                animo = d.animo !== undefined ? d.animo : animo
                carino = d.carino !== undefined ? d.carino : carino
                ultimaVez = d.ultimaVez || 0
                hoyFecha = d.hoyFecha || ""
                hoyNotifs = d.hoyNotifs || 0
                hoyPausa = d.hoyPausa === true
                ultimoDiaVisto = d.ultimoDiaVisto || ""
            } catch (e) {
                //  Estado ilegible: se empieza de cero, sin tirar la barra.
            }
        }

        //  El tiempo fuera, con tope: dormida recupera energía y gasta poco.
        const ahora = Date.now() / 1000
        if (ultimaVez > 0) {
            const horas = Math.min(topeOfflineHoras,
                                   Math.max(0, (ahora - ultimaVez) / 3600))
            hambre = Math.max(0, hambre - hambrePorHora * 0.5 * horas)
            energia = Math.min(100, energia + descansoPorHora * horas)
        }

        saludandoHasta = ahora + 6     // la bienvenida
        cargado = true
        apuntar()
    }
}
