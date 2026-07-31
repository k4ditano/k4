pragma Singleton

// Registro y estado persistente de los plugins.
//
// `active` sigue siendo una decisión momentánea del host —quién ocupa la
// island—; `habilitado` es la decisión del usuario y sobrevive a los reinicios.
// Mantenerlas separadas evita que cerrar un plugin lo desactive para siempre.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: manager

    readonly property string rutaEstado:
        (Quickshell.env("HOME") || "") + "/.local/state/k4/plugins.json"
    readonly property string rutaCatalogo:
        Quickshell.shellPath("plugins/catalog.json")

    property bool cargado: false
    property var habilitados: ({})
    property var errores: ({})

    // El catálogo en JSON es la fuente que leen las herramientas externas. La
    // copia mínima evita que la barra se quede sin defaults si el fichero se
    // está actualizando o si se arranca con una versión antigua instalada.
    property var catalogo: [
        { id: "idle", title: "Píldora", version: "1.0.0", enabled: true, configurable: false },
        { id: "volume", title: "Volumen", version: "1.0.0", enabled: true },
        { id: "clock", title: "Reloj", version: "1.0.0", enabled: true },
        { id: "player", title: "Reproductor", version: "1.0.0", enabled: true },
        { id: "toast", title: "Notificación", version: "1.0.0", enabled: true },
        { id: "panel", title: "Centro de control", version: "1.0.0", enabled: true },
        { id: "launcher", title: "Lanzador", version: "1.0.0", enabled: true },
        { id: "ask", title: "Preguntar", version: "1.0.0", enabled: true },
        { id: "hyprtheme", title: "Tema de Hyprland", version: "1.0.0", enabled: true },
        { id: "weather", title: "El tiempo", version: "1.0.0", enabled: true },
        { id: "tray", title: "Bandeja", version: "1.0.0", enabled: true },
        { id: "game", title: "Mazmorra", version: "1.0.0", enabled: true },
        { id: "settings", title: "Ajustes", version: "1.0.0", enabled: true, configurable: false },
        { id: "clipboard", title: "Portapapeles", version: "1.0.0", enabled: true },
        { id: "system", title: "Sistema", version: "1.0.0", enabled: true },
        { id: "files", title: "Archivos", version: "1.0.0", enabled: true },
        { id: "keys", title: "Atajos", version: "1.0.0", enabled: true },
        { id: "windows", title: "Ventanas", version: "1.0.0", enabled: true },
        { id: "session", title: "Sesión", version: "1.0.0", enabled: true },
        { id: "captura", title: "Captura", version: "1.0.0", enabled: true }
    ]

    signal cambiado(string id, bool habilitado)

    function indice(id) {
        for (let i = 0; i < catalogo.length; ++i)
            if (catalogo[i].id === id)
                return i
        return -1
    }

    function metadata(id) {
        const i = indice(id)
        return i >= 0 ? catalogo[i] : null
    }

    function estaHabilitado(id) {
        const m = metadata(id)
        if (!m)
            return false
        return habilitados[id] !== undefined ? !!habilitados[id] : m.enabled !== false
    }

    function puedeConfigurar(id) {
        const m = metadata(id)
        return !!(m && m.configurable !== false)
    }

    function poner(id, valor) {
        if (indice(id) < 0 || !puedeConfigurar(id))
            return
        const d = Object.assign({}, habilitados)
        d[id] = !!valor
        habilitados = d
        if (!valor)
            Indicadores.quitarDe(id)
        guardar()
        cambiado(id, !!valor)
    }

    function alternar(id) { poner(id, !estaHabilitado(id)) }

    function habilitar(id) { poner(id, true) }
    function deshabilitar(id) { poner(id, false) }

    function registrarError(id, motivo) {
        const d = Object.assign({}, errores)
        d[id] = String(motivo || "error de carga")
        errores = d
    }

    function limpiarError(id) {
        const d = Object.assign({}, errores)
        delete d[id]
        errores = d
    }

    readonly property var opcionesAjustes: catalogo
        .filter(function (m) { return m.configurable !== false })
        .map(function (m) {
            return { id: "plugin_" + m.id,
                     pluginId: m.id,
                     nombre: m.title,
                     desc: "Activar o desactivar este plugin",
                     glifo: 0xF04E5 }
        })

    function valorAjuste(id) {
        return estaHabilitado(String(id).replace(/^plugin_/, ""))
    }

    function alternarAjuste(id) {
        alternar(String(id).replace(/^plugin_/, ""))
    }

    function cargar() {
        const bruto = estado.text()
        if (bruto.length > 0) {
            try {
                const d = JSON.parse(bruto)
                if (d.habilitados && typeof d.habilitados === "object")
                    habilitados = d.habilitados
            } catch (e) {
                // Un estado roto no impide arrancar: se usan los defaults.
            }
        }
        cargado = true
    }

    function cargarCatalogo() {
        const bruto = catalogoFile.text()
        if (!bruto || bruto.length === 0)
            return
        try {
            const d = JSON.parse(bruto)
            if (!d.plugins || !Array.isArray(d.plugins))
                return
            catalogo = d.plugins.map(function (m) {
                return Object.assign({}, m, {
                    enabled: m.enabledByDefault !== false
                })
            })
        } catch (e) {
            // Se conserva el catálogo de emergencia embebido.
        }
    }

    function guardar() {
        if (!cargado)
            return
        estado.setText(JSON.stringify({ habilitados: habilitados }, null, 1))
    }

    FileView {
        id: estado
        path: manager.rutaEstado
        blockLoading: true
    }

    FileView {
        id: catalogoFile
        path: manager.rutaCatalogo
        blockLoading: true
        onLoaded: manager.cargarCatalogo()
    }

    Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: manager.cargar()
    }
}
