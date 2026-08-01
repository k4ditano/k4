pragma Singleton

//  K4MON — la simulación de crianza. La island es el digivice; esto es lo
//  que vive dentro: huevo, eclosión, cría y la primera digievolución, con
//  hambre, peso, disciplina y errores de cuidado que deciden la rama.
//
//  Reglas de la casa: determinista, sin red, todo en funciones puras donde
//  se pueda. El plugin es vista e IPC; aquí no se pinta nada.
//
//  Fase 1: huevo → Bit (bebé) → uno de los tres niños. Las etapas adultas,
//  el entrenamiento y el combate llegan en fases posteriores del plan.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: kmon

    // ── curvas y constantes, con nombre y unidad ──────────────────
    readonly property int eclosionSegundos: 600        // 10 min de incubación…
    readonly property int toqueAcelera: 120            // …y cada toque resta 2 min
    readonly property int bebeHoras: 24                // Bit tarda un día en decidirse
    readonly property real hambrePorMin: 0.5           // 100 → 0 en ~3,3 h despierto
    readonly property int llamadaConHambre: 30         // por debajo, el digivice llama
    readonly property int llamadaPlazoMin: 30          // desatender la llamada = error
    readonly property real energiaPorMin: 0.12
    readonly property real descansoPorMin: 0.5
    readonly property int duermeDesde: 23              // horario de sueño de la cría
    readonly property int despiertaA: 7
    readonly property int pesoSano: 10                 // ± lo que se considera bien
    readonly property int topeOfflineHoras: 8

    //  El catálogo de formas de esta fase. `color` tiñe la barra en su
    //  digievolución y el cristal del digivice.
    readonly property var formas: ({
        huevo: { nombre: "Huevo", color: "#8e8e93", sprite: "base/huevo.png" },
        bit: { nombre: "Bit", color: "#5ac8fa", sprite: "base/bit-normal.png" },
        chispin: { nombre: "Chispín", color: "#ffd60a", sprite: "formas/chispin.png",
                   lema: "criado con puntualidad y mano firme" },
        bytezno: { nombre: "Bytezno", color: "#30d158", sprite: "formas/bytezno.png",
                   lema: "curioso, algo desatendido, listo como él solo" },
        flamillo: { nombre: "Flamillo", color: "#ff453a", sprite: "formas/flamillo.png",
                    lema: "bien cebado: pura caldera" }
    })

    function formaDe(id) { return formas[id] || formas.bit }

    // ── estado ────────────────────────────────────────────────────
    property bool cargado: false
    property string etapa: "huevo"      // huevo · bebe · nino
    property string forma: "huevo"
    property real puesta: 0             // epoch: cuándo empezó a incubar
    property real nacimiento: 0         // epoch: cuándo eclosionó
    property int toques: 0
    property real hambre: 100           // 100 lleno · 0 vacío
    property real energia: 100
    property real peso: 5               // el Bit nace ligero
    property int disciplina: 50
    property int errores: 0
    property int comidas: 0             // total de esta vida
    property real llamadaDesde: 0       // epoch: hay llamada de hambre en curso
    property real ultimaVez: 0

    //  El acelerador de pruebas: segundos que el reloj del juego va por
    //  delante del real. Solo lo toca el IPC de depuración.
    property real desfase: 0

    function ahora() { return Date.now() / 1000 + desfase }

    signal digievolucion(string desde, string hacia)
    signal eclosion()

    // ── lo que la vista pregunta ──────────────────────────────────

    readonly property var formaActual: formaDe(forma)
    readonly property real edadHoras: nacimiento > 0
        ? Math.max(0, (ahora() - nacimiento) / 3600) : 0

    readonly property bool dormido: {
        if (etapa === "huevo")
            return false
        const h = new Date((ahora()) * 1000).getHours()
        return h >= duermeDesde || h < despiertaA
    }

    readonly property bool llamando: llamadaDesde > 0

    //  Progreso de incubación 0..1, con los toques descontando.
    readonly property real incubacion: etapa !== "huevo" ? 1
        : Math.min(1, ((ahora() - puesta) + toques * toqueAcelera)
                      / eclosionSegundos)

    //  Los sprites LCD (1-bit, estilo v-pet): por forma, sus frames
    //  [de pie, andando, celebrando, durmiendo?]. Una forma sin demake
    //  cae a su carta a color hasta que su hoja LCD aterrice.
    readonly property var lcds: ({
        //  [de pie, andando/salto, celebración, dormido?]
        bit: ["lcd/bit-0.png", "lcd/bit-1.png", "lcd/bit-1.png", "lcd/bit-2.png"],
        chispin: ["lcd/chispin-0.png", "lcd/chispin-1.png", "lcd/chispin-2.png"]
    })

    //  El sprite de la pantalla: 1-bit con ciclo de andar. `alterno` lo
    //  lleva el reloj de cada vista — el vaivén de frames ES la vida en
    //  una pantalla de fósforo.
    function spriteLcd(alterno) {
        if (etapa === "huevo")
            return incubacion > 0.85 ? "lcd/huevo-2.png"
                : incubacion > 0.5 ? "lcd/huevo-1.png" : "lcd/huevo-0.png"
        const l = lcds[forma]
        if (!l)
            return sprite()
        if (ahora() < _saltoHasta && l[2])
            return l[2]
        if (dormido && l[3])
            return l[3]
        return l[alterno ? 1 : 0]
    }

    //  Qué sprite toca: la vista y la píldora preguntan, nunca deciden.
    function sprite() {
        if (etapa === "huevo")
            return incubacion > 0.85 ? "base/eclosion.png" : "base/huevo.png"
        if (etapa === "bebe") {
            if (dormido) return "base/bit-dormido.png"
            if (llamando) return "base/bit-susto.png"
            if (ahora() < _saltoHasta) return "base/bit-salto.png"
            return "base/bit-normal.png"
        }
        return formaActual.sprite
    }

    property real _saltoHasta: 0

    readonly property string estadoTexto: {
        if (etapa === "huevo")
            return Idioma.t("incubando…")
        if (dormido)
            return Idioma.t("durmiendo")
        if (llamando)
            return Idioma.t("¡tiene hambre!")
        if (hambre < 50)
            return Idioma.t("le suenan las tripas")
        return energia < 30 ? Idioma.t("cansado") : Idioma.t("en plena forma")
    }

    // ── acciones del domador ──────────────────────────────────────

    //  Tocar el huevo lo anima a salir. Después de nacer, tocar es jugar:
    //  un saltito y nada más — el cariño de esta fase.
    function tocar() {
        if (etapa === "huevo") {
            toques += 1
            _tic()   // reevaluar ya: el último toque puede eclosionar
        } else if (!dormido) {
            _saltoHasta = ahora() + 4
        }
        apuntar()
    }

    function comer() {
        if (etapa === "huevo" || dormido)
            return
        //  Comer con el estómago aún lleno es sobrealimentar: engorda doble.
        peso += hambre > 70 ? 2 : 1
        hambre = 100
        comidas += 1
        llamadaDesde = 0
        _saltoHasta = ahora() + 4
        apuntar()
    }

    // ── la rama: la decisión de crianza de esta fase ──────────────
    //
    //  Pura y con las reglas a la vista (provisional hasta que el
    //  entrenamiento de la fase 2 aporte los stats):
    //    · cuidado limpio y peso sano  → CHISPÍN (la rama disciplinada)
    //    · sobrealimentado             → FLAMILLO (la caldera)
    //    · errores o peso descuidado   → BYTEZNO (el listillo asilvestrado)
    function ramaNino(err, kg) {
        if (kg > pesoSano + 5)
            return "flamillo"
        if (err <= 1 && Math.abs(kg - pesoSano) <= 5)
            return "chispin"
        return "bytezno"
    }

    // ── el reloj ──────────────────────────────────────────────────

    property var _reloj: Timer {
        interval: 30000
        repeat: true
        running: kmon.cargado && Settings.kmonActivo
        onTriggered: kmon._tic()
    }

    function _tic() {
        const t = ahora()

        if (etapa === "huevo") {
            if (incubacion >= 1)
                _eclosionar()
            ultimaVez = t
            apuntar()
            return
        }

        const min = 0.5   // el reloj late cada 30 s
        if (dormido) {
            energia = Math.min(100, energia + descansoPorMin * min)
            //  De noche no hay llamadas: se aguanta el hambre soñando.
            llamadaDesde = 0
        } else {
            hambre = Math.max(0, hambre - hambrePorMin * min)
            energia = Math.max(0, energia - energiaPorMin * min)

            if (hambre < llamadaConHambre && llamadaDesde === 0) {
                llamadaDesde = t
                Island.efecto("kmon", "tiron", 0.5)
            }

            //  Llamada desatendida: error de cuidado, y adelgaza.
            if (llamadaDesde > 0 && t - llamadaDesde > llamadaPlazoMin * 60) {
                errores += 1
                peso = Math.max(1, peso - 1)
                llamadaDesde = 0
            }
        }

        if (etapa === "bebe" && edadHoras >= bebeHoras)
            _digievolucionar(ramaNino(errores, peso))

        ultimaVez = t
        apuntar()
    }

    function _eclosionar() {
        etapa = "bebe"
        forma = "bit"
        nacimiento = ahora()
        hambre = 80
        energia = 100
        peso = 5
        eclosion()
        _cine("#5ac8fa")
        Quickshell.execDetached(["notify-send", "-a", "k4",
            Idioma.t("¡El huevo ha eclosionado!"),
            Idioma.t("Bit te está esperando en el digivice")])
    }

    function _digievolucionar(nueva) {
        const vieja = formaDe(forma).nombre
        forma = nueva
        etapa = "nino"
        digievolucion(vieja, formaDe(nueva).nombre)
        _cine(formaDe(nueva).color)
        Quickshell.execDetached(["notify-send", "-a", "k4",
            Idioma.f(Idioma.t("¡%1 ha digievolucionado en %2!"),
                     vieja, formaDe(nueva).nombre),
            formaDe(nueva).lema || ""])
    }

    //  El momento grande gasta el arsenal de la barra, si el usuario quiere.
    function _cine(color) {
        if (!Settings.kmonCine)
            return
        Theme.tintar("kmon", color, 0.35, 4200)
        Island.efecto("kmon", "sacudida", 1)
    }

    //  Empezar de cero (la despedida de las fases futuras pasará por aquí).
    function nuevaPartida() {
        //  El desfase de depuración se anula ANTES de fechar nada: fechar la
        //  puesta con el reloj adelantado dejaba el huevo en el futuro.
        desfase = 0
        etapa = "huevo"
        forma = "huevo"
        puesta = ahora()
        nacimiento = 0
        toques = 0
        hambre = 100
        energia = 100
        peso = 5
        disciplina = 50
        errores = 0
        comidas = 0
        llamadaDesde = 0
        desfase = 0
        apuntar()
    }

    // ── persistencia ──────────────────────────────────────────────

    readonly property string ruta: Quickshell.env("HOME") + "/.local/state/k4/kmon.json"

    function apuntar() {
        if (!cargado)
            return
        vista.setText(JSON.stringify({
            etapa: etapa, forma: forma, puesta: puesta,
            nacimiento: nacimiento, toques: toques, hambre: hambre,
            energia: energia, peso: peso, disciplina: disciplina,
            errores: errores, comidas: comidas,
            llamadaDesde: llamadaDesde, ultimaVez: ultimaVez,
            desfase: desfase
        }, null, 1))
    }

    FileView { id: vista; path: kmon.ruta; blockLoading: true }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: kmon.cargar()
    }

    function cargar() {
        const bruto = vista.text()
        let habia = false
        if (bruto.length > 0) {
            try {
                const d = JSON.parse(bruto)
                etapa = d.etapa || "huevo"
                forma = d.forma || "huevo"
                puesta = d.puesta || 0
                nacimiento = d.nacimiento || 0
                toques = d.toques || 0
                hambre = d.hambre !== undefined ? d.hambre : 100
                energia = d.energia !== undefined ? d.energia : 100
                peso = d.peso !== undefined ? d.peso : 5
                disciplina = d.disciplina !== undefined ? d.disciplina : 50
                errores = d.errores || 0
                comidas = d.comidas || 0
                llamadaDesde = d.llamadaDesde || 0
                ultimaVez = d.ultimaVez || 0
                desfase = d.desfase || 0
                habia = true
            } catch (e) {
                //  Estado ilegible: huevo nuevo, sin tirar la barra.
            }
        }

        //  El tiempo fuera, con tope: dormido no envejece más de una noche,
        //  y nunca acumula errores por hambre mientras la barra no corría.
        if (habia && ultimaVez > 0 && etapa !== "huevo") {
            const horas = Math.min(topeOfflineHoras,
                                   Math.max(0, (ahora() - ultimaVez) / 3600))
            hambre = Math.max(10, hambre - hambrePorMin * 30 * horas)
            energia = Math.min(100, energia + descansoPorMin * 30 * horas)
            llamadaDesde = 0
        }

        cargado = true
        if (!habia)
            nuevaPartida()
        else
            apuntar()
    }
}
