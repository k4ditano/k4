//  Tematizar Hyprland desde la island: colores, ventanas, efectos y fondo.
//
//  Dos caminos, mismo lenguaje. En caliente va por `hyprctl eval`, que evalúa
//  Lua en el Hyprland vivo — `hyprctl keyword` no sirve aquí: con el parser
//  nuevo responde "keyword can't work with non-legacy parsers".
//
//  Para que sobreviva al reinicio, k4 es dueño de config/k4-theme.lua y lo
//  añade al final de hyprland.lua. Al ir el último, sus valores ganan sin
//  tocar ni una línea de la configuración de CachyOS: borras el archivo y la
//  línea `require`, y todo vuelve a estar como estaba.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "hyprtheme"
    title: "Tema de Hyprland"
    priority: 65
    active: open
    tecladoOpcional: open

    property bool open: false
    property string tab: "tema"        // "tema" | "ventanas" | "efectos" | "fondo"

    islandWidth: 880
    islandHeight: 470

    handlesBackgroundTap: true
    onBackgroundTapped: {}   // se traga el clic: cerrar es cosa del botón

    // Se abre con el ratón, así que se va al sacarlo. Con más margen que el
    // panel: aquí se arrastran deslizadores y es fácil pasarse del borde.
    closeOnHoverExit: true
    hoverExitDelay: 1000
    onHoverTimedOut: close()

    readonly property string hyprDir: Quickshell.env("HOME") + "/.config/hypr"
    readonly property string themeFile: hyprDir + "/config/k4-theme.lua"
    readonly property string entryFile: hyprDir + "/hyprland.lua"
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/k4/hyprtheme.json"

    // ── ajustes ───────────────────────────────────────────────────
    property string preset: "cachyos"
    property color accentFrom: "#82dccc"
    property color accentTo: "#007d6f"
    property color inactive: "#798bb2"
    property int angle: 45

    property int gapsIn: 3
    property int gapsOut: 8
    property int borderSize: 2
    property int rounding: 10

    property bool blur: true
    property int blurSize: 5
    property int blurPasses: 4
    property real activeOpacity: 0.95
    property real inactiveOpacity: 0.85
    property bool shadow: true

    property bool animEnabled: true
    property int animSpeed: 3

    property string wallpaper: ""

    // Marca de agua: los presets solo se ven "elegidos" mientras no toques nada.
    property bool dirty: false

    readonly property var presets: [
        { id: "cachyos", name: "CachyOS",  from: "#82dccc", to: "#007d6f", inactive: "#798bb2" },
        { id: "noche",   name: "Noche",    from: "#5e5ce6", to: "#1c1c3a", inactive: "#3a3a4c" },
        { id: "ambar",   name: "Ámbar",    from: "#ff9f0a", to: "#c1440e", inactive: "#5c4a3a" },
        { id: "malva",   name: "Malva",    from: "#bf5af2", to: "#5e2b8a", inactive: "#4a3a5c" },
        { id: "menta",   name: "Menta",    from: "#30d158", to: "#0a6b3d", inactive: "#3a5c48" },
        { id: "acero",   name: "Acero",    from: "#98a5b8", to: "#3a4654", inactive: "#4a5462" }
    ]

    function applyPreset(id) {
        for (let i = 0; i < presets.length; ++i) {
            if (presets[i].id !== id)
                continue

            preset = id
            accentFrom = presets[i].from
            accentTo = presets[i].to
            inactive = presets[i].inactive
            dirty = false
            apply()
            return
        }
    }

    // ── color → el formato que espera Hyprland ────────────────────
    // hl.config quiere "rgba(rrggbbaa)"; QML da "#rrggbb" o "#aarrggbb".
    function hypr(color) {
        const hex = String(color)
        if (hex.length === 9)                       // #aarrggbb
            return "rgba(" + hex.substring(3) + hex.substring(1, 3) + ")"
        return "rgba(" + hex.substring(1) + "ff)"   // #rrggbb
    }

    // ── el Lua que describe el tema ───────────────────────────────
    function luaBody() {
        return 'hl.config({\n'
            + '    general = {\n'
            + '        gaps_in = ' + gapsIn + ',\n'
            + '        gaps_out = ' + gapsOut + ',\n'
            + '        border_size = ' + borderSize + ',\n'
            + '        col = {\n'
            + '            active_border = { colors = { "' + hypr(accentFrom) + '", "'
                + hypr(accentTo) + '" }, angle = ' + angle + ' },\n'
            + '            inactive_border = "' + hypr(inactive) + '",\n'
            + '        },\n'
            + '    },\n'
            + '    decoration = {\n'
            + '        rounding = ' + rounding + ',\n'
            + '        active_opacity = ' + activeOpacity.toFixed(2) + ',\n'
            + '        inactive_opacity = ' + inactiveOpacity.toFixed(2) + ',\n'
            + '        blur = {\n'
            + '            enabled = ' + (blur ? "true" : "false") + ',\n'
            + '            size = ' + blurSize + ',\n'
            + '            passes = ' + blurPasses + ',\n'
            + '        },\n'
            + '        shadow = { enabled = ' + (shadow ? "true" : "false") + ' },\n'
            + '    },\n'
            + '})\n\n'
            + 'hl.animation({ leaf = "global", enabled = ' + (animEnabled ? "true" : "false")
                + ', speed = ' + animSpeed + ', bezier = "quick" })\n'
    }

    // ── aplicar en caliente ───────────────────────────────────────
    function apply() {
        evalProcess.command = ["hyprctl", "eval", luaBody()]
        evalProcess.running = true
        saveState()
    }

    // ── persistir ─────────────────────────────────────────────────
    function persist() {
        themeView.setText(
            '-- Generado por k4 · módulo HyprTheme.\n'
            + '-- No lo edites a mano: se reescribe cada vez que guardas desde la barra.\n'
            + '-- Para revertirlo: borra este archivo y su línea require de hyprland.lua.\n\n'
            + luaBody())

        ensureRequire()
        saveState()
    }

    // Añade el require al final de hyprland.lua si no está. Va el último a
    // propósito: lo que se aplica después es lo que manda.
    function ensureRequire() {
        const current = entryView.text()
        if (current.length === 0 || current.indexOf("config.k4-theme") !== -1)
            return

        entryView.setText(current.replace(/\s*$/, "")
            + '\n\n-- k4: tema gestionado desde la barra (debe ir el último)\n'
            + 'require("config.k4-theme")\n')
    }

    function isPersisted() {
        return entryView.text().indexOf("config.k4-theme") !== -1
    }

    // ── estado propio, para reabrir con los mismos valores ────────
    function saveState() {
        stateView.setText(JSON.stringify({
            preset: preset,
            accentFrom: String(accentFrom),
            accentTo: String(accentTo),
            inactive: String(inactive),
            angle: angle,
            gapsIn: gapsIn, gapsOut: gapsOut, borderSize: borderSize, rounding: rounding,
            blur: blur, blurSize: blurSize, blurPasses: blurPasses,
            activeOpacity: activeOpacity, inactiveOpacity: inactiveOpacity, shadow: shadow,
            animEnabled: animEnabled, animSpeed: animSpeed,
            wallpaper: wallpaper,
            dirty: dirty
        }, null, 2))
    }

    function loadState() {
        const raw = stateView.text()
        if (raw.length === 0)
            return

        let s
        try {
            s = JSON.parse(raw)
        } catch (e) {
            return
        }

        preset = s.preset !== undefined ? s.preset : preset
        accentFrom = s.accentFrom !== undefined ? s.accentFrom : accentFrom
        accentTo = s.accentTo !== undefined ? s.accentTo : accentTo
        inactive = s.inactive !== undefined ? s.inactive : inactive
        angle = s.angle !== undefined ? s.angle : angle
        gapsIn = s.gapsIn !== undefined ? s.gapsIn : gapsIn
        gapsOut = s.gapsOut !== undefined ? s.gapsOut : gapsOut
        borderSize = s.borderSize !== undefined ? s.borderSize : borderSize
        rounding = s.rounding !== undefined ? s.rounding : rounding
        blur = s.blur !== undefined ? s.blur : blur
        blurSize = s.blurSize !== undefined ? s.blurSize : blurSize
        blurPasses = s.blurPasses !== undefined ? s.blurPasses : blurPasses
        activeOpacity = s.activeOpacity !== undefined ? s.activeOpacity : activeOpacity
        inactiveOpacity = s.inactiveOpacity !== undefined ? s.inactiveOpacity : inactiveOpacity
        shadow = s.shadow !== undefined ? s.shadow : shadow
        animEnabled = s.animEnabled !== undefined ? s.animEnabled : animEnabled
        animSpeed = s.animSpeed !== undefined ? s.animSpeed : animSpeed
        wallpaper = s.wallpaper !== undefined ? s.wallpaper : wallpaper
        dirty = s.dirty === true
    }

    // ── fondo de pantalla ─────────────────────────────────────────
    // El proyecto swww se renombró a awww, así que se acepta cualquiera de los
    // dos; swaybg es el plan C: sin transiciones y hay que relanzarlo.
    property string wallTool: ""       // "awww" | "swww" | "swaybg" | ""
    property var wallpapers: []

    readonly property var wallDirs: [
        Quickshell.env("HOME") + "/Imágenes",
        Quickshell.env("HOME") + "/Pictures",
        Quickshell.env("HOME") + "/Descargas",
        "/usr/share/wallpapers",
        "/usr/share/backgrounds"
    ]

    function setWallpaper(path) {
        if (path.length === 0 || wallTool.length === 0)
            return

        wallpaper = path

        if (wallTool === "swaybg") {
            // no sabe recargar: se mata y se levanta otro
            Quickshell.execDetached(["sh", "-c",
                "pkill -x swaybg; swaybg -i " + JSON.stringify(path) + " -m fill >/dev/null 2>&1 &"])
        } else {
            Quickshell.execDetached(["sh", "-c",
                wallTool + " img " + JSON.stringify(path)
                + " --transition-type grow --transition-fps 60 >/dev/null 2>&1"
                + " || { " + wallTool + "-daemon >/dev/null 2>&1 & sleep 1; "
                + wallTool + " img " + JSON.stringify(path) + " >/dev/null 2>&1; }"])
        }

        saveState()
    }

    function refreshWallpapers() {
        const args = ["find"]
        for (let i = 0; i < wallDirs.length; ++i)
            args.push(wallDirs[i])
        wallScan.command = args.concat([
            "-maxdepth", "3", "-type", "f",
            "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o",
            "-iname", "*.png", "-o", "-iname", "*.webp", ")"
        ])
        wallScan.running = true
    }

    function toggle() {
        open = !open
        if (open) {
            if (panel) panel.close()
            Notifs.dismissToast()
        }
    }

    // El escaneo va atado al estado, no a una función de entrada: así vale
    // igual abriendo desde el panel, por IPC o saltando directo a la pestaña.
    onOpenChanged: if (open) refreshWallpapers()
    onTabChanged: if (tab === "fondo") refreshWallpapers()

    function close() { open = false }

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    // ── archivos ──────────────────────────────────────────────────
    FileView { id: themeView; path: self.themeFile }
    FileView { id: entryView; path: self.entryFile; blockLoading: true }
    FileView { id: stateView; path: self.stateFile; blockLoading: true }

    Process { id: evalProcess }

    Process {
        // el estado vive en ~/.local/state/k4, que puede no existir aún
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: self.loadState()
    }

    Process {
        id: toolScan
        command: ["sh", "-c",
            "command -v awww || command -v swww || command -v swaybg || true"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const found = this.text.trim().split("\n")[0]
                if (found.length === 0)
                    return
                self.wallTool = found.substring(found.lastIndexOf("/") + 1)
            }
        }
    }

    Process {
        id: wallScan

        stdout: StdioCollector {
            onStreamFinished: {
                const found = this.text.trim().split("\n").filter(function (p) { return p.length > 0 })
                found.sort()
                self.wallpapers = found.slice(0, 120)
            }
        }
    }

    IpcHandler {
        target: "k4.theme"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
        function apply(): void { self.apply() }
        function save(): void { self.persist() }
        function preset(id: string): void { self.applyPreset(id) }
        function tab(name: string): void {
            self.open = true
            self.tab = name
        }
        function wallpaper(path: string): void { self.setWallpaper(path) }
    }

    view: Component {
        HyprThemeView { plugin: self }
    }
}
