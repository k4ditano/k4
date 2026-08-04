//  Cómo van los límites de los CLI de agentes.
//
//  Claude Code y Codex cortan por ventanas —las cinco horas, la semana, y en
//  Claude además un cupo aparte para Fable— y averiguar por dónde vas obliga
//  a abrir cada herramienta y preguntárselo. Esto lo enseña de un vistazo.
//
//  El dato no se le pide a nadie: los dos programas ya guardan en disco lo que
//  el servidor les contestó la última vez, y `tools/agentes.py` lo lee y lo
//  deja en la misma forma para los dos. La contrapartida es que el dato es de
//  la última vez que corrió la herramienta, así que cada tarjeta dice de
//  cuándo es el suyo. Un porcentaje viejo enseñado como si fuera de ahora
//  engaña más que no enseñar nada.
//
//  Sondear solo mientras está abierto es a propósito: sin píldora que
//  alimentar, nadie mira estos números con la island plegada, y un proceso
//  cada medio minuto toda la sesión para eso no se paga.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "agentes"
    title: Idioma.t("Agentes")
    priority: 63
    active: habilitado && abierto

    property bool abierto: false

    //  Lo que devolvió el lector: una entrada por CLI instalado.
    property var agentes: []
    property bool cargado: false

    // ── el aviso ──────────────────────────────────────────────────
    //
    //  La píldora no está para llevar la cuenta —para eso se abre el módulo—
    //  sino para el momento en que la cuenta importa: cuando queda poco y
    //  todavía puedes decidir a qué lo gastas. Por eso aparece pasado un
    //  umbral y desaparece sola, y por eso se puede apagar entera.
    property bool avisar: true
    property int umbral: 85

    //  El límite más apurado de todos, sea de quien sea.
    readonly property var apurado: {
        let peor = null
        for (let i = 0; i < agentes.length; ++i) {
            const a = agentes[i]
            const ls = a.limites || []
            for (let j = 0; j < ls.length; ++j)
                if (!peor || (ls[j].pct || 0) > peor.pct)
                    peor = { pct: ls[j].pct || 0, nombre: ls[j].nombre || "",
                             agente: a.nombre || "" }
        }
        return peor
    }

    readonly property bool aprieta: avisar && apurado !== null
                                    && apurado.pct >= umbral

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    islandWidth: 560

    //  El alto lo mandan los datos: cada agente es una tarjeta y cada límite
    //  una fila. Las cuentas son las del delegado de la vista —10 de margen,
    //  18 de cabecera, 6 de hueco y 24+4 por fila—; si allí cambian, aquí
    //  también, porque una tarjeta más alta que su hueco se ve cortada.
    islandHeight: {
        if (!cargado || !agentes.length)
            return 132

        let alto = 51                       // márgenes, cabecera y su hueco
        for (let i = 0; i < agentes.length; i++) {
            const filas = Math.max(1, (agentes[i].limites || []).length)
            alto += 40 + 28 * filas
        }
        return alto + 8 * (agentes.length - 1)
    }

    //  El teclado entero mientras está abierto, y no `tecladoOpcional`.
    //
    //  Parece de más para un módulo que solo se mira, y lo probé así primero.
    //  Pero «opcional» es OnDemand, y OnDemand significa que el compositor da
    //  el teclado SOLO si pinchas la superficie: abriéndolo desde el centro de
    //  aplicaciones, desde el lanzador o por atajo no la pinchas nunca, así
    //  que el ESC que el host ya trae no llegaba jamás. Cerraba con ESC solo
    //  si antes le habías puesto el ratón encima, que es la clase de arreglo
    //  que parece que funciona hasta que lo usas.
    //
    //  Se paga tenerlo: mientras esté abierto, ninguna ventana recibe teclas.
    //  Se paga a gusto porque esto se abre, se mira y se cierra —el centro de
    //  aplicaciones hace lo mismo por la misma razón— y porque la tecla con
    //  la que se cierra tiene que funcionar siempre, no casi siempre.
    grabKeyboard: abierto

    //  NO se cierra al salir el ratón.
    //
    //  Esto se abre a propósito —desde el lanzador o por su píldora— y se
    //  QUEDA MIRANDO: son cinco cifras que hay que leer, y para leerlas uno
    //  aparta el ratón. Con el cierre por salida, apartarlo lo cerraba al
    //  segundo. Peor todavía abriéndolo desde el lanzador: el puntero estaba
    //  dentro de la island —era el lanzador— y al cambiar de plugin quedaba
    //  fuera, así que se cerraba solo sin que nadie hubiera movido nada.
    //
    //  Cerrar sigue siendo fácil y de tres maneras: ESC (que este plugin se
    //  queda el teclado para que funcione siempre), el aspa de la cabecera, y
    //  volver a abrirlo.
    closeOnHoverExit: false

    handlesBackgroundTap: true
    onBackgroundTapped: {}   // se traga el clic: cerrar es cosa del botón

    function toggle() {
        abierto = !abierto
        if (abierto) {
            if (panel)
                panel.close()
            Notifs.dismissToast()
            refrescar()
        }
    }

    function close() {
        abierto = false
    }

    function refrescar() {
        if (!lector.running)
            lector.running = true
    }

    //  Preguntarle al servidor por TU uso, con el token que Claude Code ya
    //  tiene en disco. Es lectura de tu propia cuenta y no gasta cupo. Se
    //  puede apagar, y entonces se lee la caché de disco de la herramienta —
    //  que es correcta pero va con horas de retraso.
    property bool enVivo: true

    K4.Process {
        id: lector
        command: self.enVivo
            ? ["python3", K4.Paths.guion("agentes.py")]
            : ["python3", K4.Paths.guion("agentes.py"), "--sin-red"]

        onSalida: function (texto) {
            try {
                const datos = JSON.parse(texto)
                self.agentes = datos.agentes || []
            } catch (e) {
                console.warn("agentes: respuesta ilegible —", e)
                self.agentes = []
            }
            self.cargado = true
        }

        onLineaError: function (linea) { console.warn("agentes:", linea) }
    }

    //  Mientras está a la vista se vuelve a mirar de vez en cuando: si estás
    //  trabajando con el agente en otra ventana, el porcentaje se mueve solo.
    Timer {
        interval: 20000
        repeat: true
        running: self.abierto
        onTriggered: self.refrescar()
    }

    //  Y de fondo, solo si hay aviso que dar y solo cada cinco minutos. Es la
    //  única razón para leer con la island plegada, así que se apaga con el
    //  aviso: quien no lo quiera no paga ni un proceso.
    Timer {
        interval: 300000
        repeat: true
        running: self.habilitado && self.avisar && !self.abierto
        triggeredOnStart: true
        onTriggered: self.refrescar()
    }

    // ── la píldora ────────────────────────────────────────────────

    //  Se lleva la cuenta de si está puesta en vez de llamar a `quitar` cada
    //  vuelta: el servicio reconstruye la lista entera en cada llamada, y
    //  quitar lo que ya no estaba redibujaba la píldora de todo el mundo cada
    //  cinco minutos para nada.
    property bool _avisoPuesto: false

    function pintarAviso() {
        if (!aprieta) {
            if (_avisoPuesto) {
                K4.Pildora.quitar("agentes.limite")
                _avisoPuesto = false
            }
            return
        }
        K4.Pildora.registrar("agentes.limite", Math.round(apurado.pct) + "%",
                             0xF06A9,
                             apurado.pct >= 95 ? Theme.red : Theme.yellow,
                             75, true)
        _avisoPuesto = true
    }

    onAprietaChanged: pintarAviso()
    onApuradoChanged: pintarAviso()

    Connections {
        target: K4.Pildora
        function onInvocado(id) {
            if (id === "agentes.limite" && !self.abierto)
                self.toggle()
        }
    }

    // ── lo que el usuario decide ──────────────────────────────────

    property var guardado: K4.Guardado {
        plugin: "agentes"
        onCargado: function (d) {
            if (d.avisar !== undefined) self.avisar = d.avisar === true
            if (d.umbral !== undefined) self.umbral = Number(d.umbral) || 85
            if (d.enVivo !== undefined) self.enVivo = d.enVivo === true
        }
    }

    function apuntar() {
        guardado.guardar({ avisar: avisar, umbral: umbral, enVivo: enVivo })
    }

    K4.Ajustes {
        plugin: "agentes"
        grupo: Idioma.t("Agentes")
        opciones: [
            { id: "enVivo", nombre: Idioma.t("Preguntar al servidor"),
              desc: Idioma.t("Tu uso real, al momento. Apagado se lee la caché de la herramienta, que va con horas de retraso"),
              glifo: 0xF06F2 },
            { id: "avisar", nombre: Idioma.t("Avisar cuando aprieta"),
              desc: Idioma.t("Un porcentaje en la píldora cuando el límite más apurado pasa del umbral"),
              glifo: 0xF0026 },
            { id: "umbral", tipo: "eleccion", nombre: Idioma.t("Umbral del aviso"),
              desc: Idioma.t("A partir de cuánto gastado merece la pena enterarse"),
              glifo: 0xF029A,
              alternativas: [{ codigo: "70", nombre: "70%" },
                             { codigo: "85", nombre: "85%" },
                             { codigo: "95", nombre: "95%" }] }
        ]
        valores: ({ enVivo: self.enVivo, avisar: self.avisar,
                    umbral: String(self.umbral) })
        onCambiado: function (id, valor) {
            if (id === "enVivo") {
                self.enVivo = valor === true
                self.refrescar()
            } else if (id === "avisar") {
                self.avisar = valor === true
            } else if (id === "umbral") {
                self.umbral = Number(valor) || 85
            }
            self.apuntar()
        }
    }

    K4.Ipc {
        target: "k4.agentes"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
        function refrescar(): void { self.refrescar() }
    }

    //  Buscar «claude» o «límites» en el lanzador tiene que traer esto: es lo
    //  que uno escribe cuando la pregunta es «¿cuánto me queda?».
    K4.Lanzador {
        plugin: "agentes"
        onBuscando: function (texto) {
            const t = texto.toLowerCase()
            const pega = t.length >= 2
                && ["agentes", "claude", "codex", "limites", "límites", "cupo",
                    "gasto", "ia"].some(p => p.indexOf(t) === 0)
            resultados = pega
                ? [{ id: "abrir", titulo: Idioma.t("Agentes"),
                     desc: Idioma.t("Los límites de Claude y Codex") }]
                : []
        }
        onElegido: function (id) {
            if (!self.abierto)
                self.toggle()
        }
    }

    view: Component {
        AgentesView { plugin: self }
    }
}
