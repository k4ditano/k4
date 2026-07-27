pragma Singleton

//  Preferencias de la barra.
//
//  Solo vive aquí lo que de verdad cambia algo: un interruptor que no está
//  conectado a nada es peor que no tenerlo. Cada opción dice qué módulo la
//  lee, para que no queden huérfanas al refactorizar.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: ajustes

    readonly property string ruta: Quickshell.env("HOME") + "/.local/state/k4/ajustes.json"

    // ── juego ─────────────────────────────────────────────────────
    // services/Game.qml: al caer el grupo, ¿arranca sola la siguiente?
    property bool juegoContinuar: true
    // widgets/JuegoPildora.qml: oleada y aviso de cofres en la píldora
    property bool juegoEnPildora: true
    // services/Game.qml: el combate solo avanza con tokens de IA gastados
    property bool juegoPorTokens: false

    // ── barra ─────────────────────────────────────────────────────
    // widgets/TrayRow.qml: iconos de bandeja en la píldora
    property bool bandejaEnPildora: true
    // widgets/NotifStrip.qml: notificaciones recientes al pasar el ratón
    property bool notificacionesAlPasar: true

    readonly property var definicion: [
        {
            grupo: "Mazmorra",
            opciones: [
                { id: "juegoContinuar", nombre: "Continuar sola al morir",
                  desc: "Encadena la siguiente partida tras el resumen", glifo: 0xF04E5 },
                { id: "juegoEnPildora", nombre: "Mostrar en la píldora",
                  desc: "Oleada actual y aviso de cofres sin abrir", glifo: 0xF0BC2 },
                { id: "juegoPorTokens", nombre: "Pelear con tokens",
                  desc: "Avanza solo mientras gastas en Claude o Codex", glifo: 0xF0241 }
            ]
        },
        {
            grupo: "Island",
            opciones: [
                { id: "bandejaEnPildora", nombre: "Bandeja en la píldora",
                  desc: "Iconos de las aplicaciones en segundo plano", glifo: 0xF0FB0 },
                { id: "notificacionesAlPasar", nombre: "Notificaciones al pasar el ratón",
                  desc: "Las recientes, bajo el reloj y el reproductor", glifo: 0xF009A }
            ]
        }
    ]

    function alternar(id) {
        ajustes[id] = !ajustes[id]
        guardar()
    }

    function valor(id) { return ajustes[id] }

    // ── persistencia ──────────────────────────────────────────────
    function guardar() {
        if (!cargado)
            return

        vista.setText(JSON.stringify({
            juegoContinuar: juegoContinuar,
            juegoEnPildora: juegoEnPildora,
            juegoPorTokens: juegoPorTokens,
            bandejaEnPildora: bandejaEnPildora,
            notificacionesAlPasar: notificacionesAlPasar
        }, null, 1))
    }

    property bool cargado: false

    FileView { id: vista; path: ajustes.ruta; blockLoading: true }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: ajustes.cargar()
    }

    function cargar() {
        const bruto = vista.text()

        if (bruto.length > 0) {
            try {
                const s = JSON.parse(bruto)
                if (s.juegoContinuar !== undefined) juegoContinuar = s.juegoContinuar
                if (s.juegoEnPildora !== undefined) juegoEnPildora = s.juegoEnPildora
                if (s.juegoPorTokens !== undefined) juegoPorTokens = s.juegoPorTokens
                if (s.bandejaEnPildora !== undefined) bandejaEnPildora = s.bandejaEnPildora
                if (s.notificacionesAlPasar !== undefined)
                    notificacionesAlPasar = s.notificacionesAlPasar
            } catch (e) {
                // preferencias ilegibles: se quedan las de fábrica
            }
        }

        cargado = true
    }
}
