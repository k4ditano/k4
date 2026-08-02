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

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    islandWidth: 560

    //  El alto lo mandan los datos: cada agente es una tarjeta y cada límite
    //  una fila. Las cuentas son las del delegado de la vista —10 de margen,
    //  18 de cabecera, 6 de hueco y 20+4 por fila—; si allí cambian, aquí
    //  también, porque una tarjeta más alta que su hueco se ve cortada.
    islandHeight: {
        if (!cargado || !agentes.length)
            return 132

        let alto = 51                       // márgenes, cabecera y su hueco
        for (let i = 0; i < agentes.length; i++) {
            const filas = Math.max(1, (agentes[i].limites || []).length)
            alto += 40 + 24 * filas
        }
        return alto + 8 * (agentes.length - 1)
    }

    closeOnHoverExit: true
    hoverExitDelay: 1000
    onHoverTimedOut: close()

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

    K4.Process {
        id: lector
        command: ["python3", K4.Paths.guion("agentes.py")]

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
