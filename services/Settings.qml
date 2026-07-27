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

    // ── idioma ────────────────────────────────────────────────────
    // "auto" sigue al del sistema. services/Idioma.qml lo lee.
    property string idioma: "auto"

    // ── juego ─────────────────────────────────────────────────────
    // El interruptor maestro. Apagado no es «ocultar»: se paran los relojes
    // del combate, el guardado y el vigía de tokens, que solo trabaja para
    // esto. Quien no quiera el juego no debe pagar nada por tenerlo instalado.
    property bool juegoActivo: true
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
            grupo: Idioma.t("Mazmorra"),
            opciones: [
                { id: Idioma.t("juegoActivo"), nombre: Idioma.t("Mazmorra activa"),
                  desc: Idioma.t("Apagada no corre, no guarda y no ocupa sitio"), glifo: 0xF04E5 },
                { requiere: Idioma.t("juegoActivo"), id: Idioma.t("juegoContinuar"), nombre: Idioma.t("Continuar sola al morir"),
                  desc: Idioma.t("Encadena la siguiente partida tras el resumen"), glifo: 0xF04E5 },
                { requiere: Idioma.t("juegoActivo"), id: Idioma.t("juegoEnPildora"), nombre: Idioma.t("Mostrar en la píldora"),
                  desc: Idioma.t("Oleada actual y aviso de cofres sin abrir"), glifo: 0xF0BC2 },
                { requiere: Idioma.t("juegoActivo"), id: Idioma.t("juegoPorTokens"), nombre: Idioma.t("Pelear con tokens"),
                  desc: Idioma.t("Avanza solo mientras gastas en Claude o Codex"), glifo: 0xF0241 }
            ]
        },
        {
            grupo: Idioma.t("Island"),
            opciones: [
                { id: Idioma.t("bandejaEnPildora"), nombre: Idioma.t("Bandeja en la píldora"),
                  desc: Idioma.t("Iconos de las aplicaciones en segundo plano"), glifo: 0xF0FB0 },
                { id: Idioma.t("notificacionesAlPasar"), nombre: Idioma.t("Notificaciones al pasar el ratón"),
                  desc: Idioma.t("Las recientes, bajo el reloj y el reproductor"), glifo: 0xF009A }
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
            idioma: idioma,
            juegoActivo: juegoActivo,
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
                if (s.idioma !== undefined) idioma = s.idioma
                if (s.juegoActivo !== undefined) juegoActivo = s.juegoActivo
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
