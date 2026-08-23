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
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "hyprtheme"
    title: Idioma.t("Tema de Hyprland")
    priority: 65
    active: habilitado && open
    //  El teclado entero mientras está abierto: «opcional» es OnDemand y
    //  el compositor solo lo da si PINCHAS la superficie, así que abierto
    //  desde el centro de aplicaciones o por atajo no llegaba ni el ESC.
    //  Ver `tecladoOpcional` en api/K4/Plugin.qml.
    grabKeyboard: open

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

    readonly property string hyprDir: K4.Sistema.entorno("HOME") + "/.config/hypr"
    readonly property string themeFile: hyprDir + "/config/k4-theme.lua"
    readonly property string entryFile: hyprDir + "/hyprland.lua"
    readonly property string stateFile: K4.Sistema.entorno("HOME") + "/.local/state/k4/hyprtheme.json"

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

    //  ── el fondo, ahora por pantalla ─────────────────────────────
    //
    //  `{ "DP-3": "/ruta/a.mp4", "HDMI-A-1": "/ruta/b.png" }`. Con dos
    //  monitores, uno solo para los dos era una limitación que no tenía por qué
    //  existir: la superficie ya es una por pantalla.
    //
    //  `wallpaper` no se retira y no es por compatibilidad de adorno: es lo que
    //  tiene guardado quien ya usaba esto, y quien no haya elegido nada para una
    //  pantalla concreta debe seguir viendo lo que veía.
    property var fondos: ({})

    //  Cómo se pasa de un fondo al siguiente.
    //
    //   · "fundido"  — el honesto: uno se va mientras el otro llega. Vale para
    //     cualquier par de fondos y no cuenta nada que no sea verdad.
    //   · "iris"     — un círculo que crece DESDE LA ISLAND, que es quien acaba
    //     de cambiar el fondo: el cambio sale de donde lo has pedido.
    //   · "marea"    — el nuevo sube desde el canto de abajo con el frente
    //     ondulado, que es la gramática líquida de la casa.
    //   · "ninguna"  — corte seco, para quien cambia de fondo veinte veces al
    //     día y no quiere una película cada vez.
    readonly property var transiciones: ["fundido", "iris", "marea", "ninguna"]
    property string transicion: "fundido"

    function fondoDe(pantalla) {
        const propio = fondos[pantalla]
        return propio && propio.length > 0 ? propio : wallpaper
    }

    //  Contenedor NUEVO y no mutar el que hay: QML solo propaga cuando cambia
    //  la IDENTIDAD de la property, así que tocando la de dentro el lienzo no
    //  se entera de nada.
    function ponerFondoEn(pantalla, ruta) {
        if (!pantalla || pantalla.length === 0)
            return
        const d = ({})
        for (const k in fondos)
            d[k] = fondos[k]
        //  Vacío es QUITAR la elección de esa pantalla, no guardar una cadena
        //  vacía: `fondoDe` ya sabe volver al fondo común cuando no hay clave, y
        //  una clave con "" dentro es un estado que no significa nada y que hay
        //  que recordar filtrar en cada sitio que lea el mapa.
        if (String(ruta || "").length === 0)
            delete d[pantalla]
        else
            d[pantalla] = String(ruta)
        fondos = d
        saveState()
        ponerSuelo()
    }

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
            fondos: fondos,
            transicion: transicion,
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
        fondos = (s.fondos && typeof s.fondos === "object") ? s.fondos : ({})
        //  Comprobado contra la lista: un fichero a mano con cualquier otra cosa
        //  dejaría un efecto que no pinta nadie, o sea un cambio de fondo que se
        //  queda a medias sin decir por qué.
        if (s.transicion && transiciones.indexOf(s.transicion) >= 0)
            transicion = s.transicion
        dirty = s.dirty === true

        //  El suelo se repone al cargar: swaybg no sobrevive a un reinicio de
        //  sesión y lo que hay debajo tiene que ser lo que se eligió.
        ponerSuelo()

        // Si el detector del daemon terminó antes de leer el estado, no
        // habrá cambio de wallTool que dispare la aplicación; cubrimos ese
        // orden de inicialización también.
        if (wallTool.length > 0 && wallpaper.length > 0)
            applyWallpaper(wallpaper)
    }

    // ── fondo de pantalla ─────────────────────────────────────────
    // El proyecto swww se renombró a awww, así que se acepta cualquiera de los
    // dos; swaybg es el plan C: sin transiciones y hay que relanzarlo.
    property string wallTool: ""       // "awww" | "swww" | "swaybg" | ""
    property var wallpapers: []

    readonly property var wallDirs: [
        K4.Sistema.entorno("HOME") + "/Imágenes",
        K4.Sistema.entorno("HOME") + "/Pictures",
        K4.Sistema.entorno("HOME") + "/Descargas",
        "/usr/share/wallpapers",
        "/usr/share/backgrounds"
    ]

    //  ── el suelo ─────────────────────────────────────────────────
    //
    //  swaybg se queda debajo con el fotograma quieto de cada pantalla. Lo que
    //  dibuja la barra vive mientras vive la barra, y entre entrar a la sesión y
    //  que arranque quickshell hay un rato sin nadie; si ahí el fondo es negro,
    //  hemos empeorado algo que funcionaba. Para un vídeo o un GIF, el suelo es
    //  su póster (ver `posterDe`).
    //
    //  Una sola llamada con todas las pantallas: swaybg admite repetir `-o/-i`,
    //  y matarlo y levantarlo dos veces —una por monitor— deja al segundo sin la
    //  primera imagen, porque el nuevo proceso se queda los dos salidas.
    //  Las pantallas que hay, preguntadas al lienzo y no a `fondos`.
    //
    //  Recorriendo las claves de `fondos` solo salen las que tienen elección
    //  PROPIA, y a las demás se les quedaba sin poner el suelo: con dos
    //  monitores y un fondo elegido en uno, swaybg arrancaba con `-o HDMI-A-1`
    //  a secas y el otro se quedaba sin fondo en cuanto la barra no estuviera.
    //  Quien sabe cuántas pantallas hay es el lienzo, que es una por cada una.
    function pantallasConocidas() {
        const l = []
        for (let i = 0; i < lienzo.instances.length; ++i) {
            const t = lienzo.instances[i]
            if (t && t.cual && t.cual.length > 0)
                l.push(t.cual)
        }
        return l
    }

    //  El suelo no corre prisa —es para cuando la barra NO esté— así que se
    //  amortigua. Sin esto, dos cambios de fondo seguidos dejaban DOS swaybg
    //  vivos: el `pkill` del segundo salía antes de que el primero llegara a
    //  existir, y el escritorio acababa con dos demonios peleándose por la
    //  misma capa. Medido: `pgrep -c -x swaybg` daba 2.
    property Timer esperaSuelo: Timer {
        interval: 300
        onTriggered: self.ponerSueloYa()
    }

    function ponerSuelo() { esperaSuelo.restart() }

    function ponerSueloYa() {
        const trozos = []
        const pantallas = pantallasConocidas()
        for (let i = 0; i < pantallas.length; ++i) {
            const suelo = sueloDe(fondoDe(pantallas[i]))
            if (suelo.length > 0)
                trozos.push("-o " + JSON.stringify(pantallas[i])
                            + " -i " + JSON.stringify(suelo) + " -m fill")
        }
        //  Y si el lienzo todavía no existe —al arrancar—, el de siempre para
        //  todas, que es exactamente lo que hacía esto antes.
        if (trozos.length === 0 && wallpaper.length > 0)
            trozos.push("-i " + JSON.stringify(sueloDe(wallpaper)) + " -m fill")
        if (trozos.length === 0)
            return

        //  `pkill -x`, nunca `-f`: con `-f` el patrón casa también con la línea
        //  de esta misma orden y se mata a sí misma antes de llegar a swaybg.
        //
        //  Y con una espera corta antes de levantar el nuevo: matar no es
        //  instantáneo, y arrancar mientras el viejo agoniza deja los dos.
        K4.Sistema.lanzar(["sh", "-c",
            "pkill -x swaybg 2>/dev/null; sleep 0.2; swaybg " + trozos.join(" ")
            + " >/dev/null 2>&1 &"])
    }

    //  Qué imagen quieta representa a un fondo. Para una foto, ella misma; para
    //  lo que se mueve, su póster cacheado — y si todavía no existe se manda
    //  hacer y de momento no se pone suelo, que es mejor que poner uno vacío.
    readonly property string cachePosters:
        K4.Sistema.entorno("HOME") + "/.cache/k4/fondos"

    function esQuieto(ruta) {
        return !/\.(mp4|webm|mkv|mov|m4v|avi|gif|webp|apng)$/i.test(String(ruta))
    }

    function posterDe(ruta) {
        return cachePosters + "/" + Qt.md5(String(ruta)) + ".png"
    }

    property var postersPedidos: ({})

    function sueloDe(ruta) {
        if (!ruta || ruta.length === 0)
            return ""
        if (esQuieto(ruta))
            return ruta

        const destino = posterDe(ruta)
        if (postersPedidos[destino] === true)
            return destino
        postersPedidos[destino] = true

        //  Al segundo y no al primer fotograma: muchos vídeos empiezan en negro,
        //  y un póster negro es lo mismo que no tener póster.
        K4.Sistema.lanzar(["sh", "-c",
            "mkdir -p " + JSON.stringify(cachePosters)
            + "; [ -f " + JSON.stringify(destino) + " ] || ffmpeg -v error -y"
            + " -ss 1 -i " + JSON.stringify(ruta) + " -frames:v 1 "
            + JSON.stringify(destino) + " >/dev/null 2>&1"])
        return destino
    }

    function applyWallpaper(path) {
        if (path.length === 0 || wallTool.length === 0)
            return false

        if (wallTool === "swaybg") {
            // swaybg no sabe recargar: se mata y se levanta otro.
            K4.Sistema.lanzar(["sh", "-c",
                "pkill -x swaybg 2>/dev/null || true; swaybg -i "
                + JSON.stringify(path) + " -m fill >/dev/null 2>&1 &"])
        } else {
            // awww y swww aceptan la misma orden. Si el daemon aún no está
            // levantado, se arranca y se reintenta la imagen.
            K4.Sistema.lanzar(["sh", "-c",
                wallTool + " img " + JSON.stringify(path)
                + " --transition-type grow --transition-fps 60 >/dev/null 2>&1"
                + " || { " + wallTool + "-daemon >/dev/null 2>&1 & sleep 1; "
                + wallTool + " img " + JSON.stringify(path) + " >/dev/null 2>&1; }"])
        }
        return true
    }

    function setWallpaper(path) {
        if (path.length === 0)
            return

        // El clic es la acción completa: se actualiza la sesión y se escribe
        // solo el estado del fondo inmediatamente, sin guardar de rebote otros
        // retoques del tema. onWallToolChanged lo aplicará cuando esté listo.
        wallpaper = path
        saveState()
        applyWallpaper(path)
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
    onWallToolChanged: if (wallTool.length > 0 && wallpaper.length > 0)
        applyWallpaper(wallpaper)

    function close() { open = false }

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    // ── archivos ──────────────────────────────────────────────────
    K4.Fichero { id: themeView; path: self.themeFile }
    K4.Fichero { id: entryView; path: self.entryFile; blockLoading: true }
    K4.Fichero { id: stateView; path: self.stateFile; blockLoading: true }

    K4.Process { id: evalProcess }

    K4.Process {
        // el estado vive en ~/.local/state/k4, que puede no existir aún
        command: ["mkdir", "-p", K4.Paths.estado]
        running: true
        onTerminado: self.loadState()
    }

    K4.Process {
        id: toolScan
        command: ["sh", "-c",
            "command -v awww || command -v swww || command -v swaybg || true"]
        running: true

        onSalida: function (texto) {
            const found = texto.trim().split("\n")[0]
            if (found.length === 0)
                return
            self.wallTool = found.substring(found.lastIndexOf("/") + 1)
        }
    }

    K4.Process {
        id: wallScan

        onSalida: function (texto) {
            const found = texto.trim().split("\n").filter(function (p) { return p.length > 0 })
            found.sort()
            self.wallpapers = found.slice(0, 120)
        }
    }

    //  Quien dibuja. Va en el plugin y no en `view` porque una vista solo
    //  existe mientras se tiene la island, y el fondo tiene que estar puesto
    //  esté abierto el módulo o no.
    Lienzo { id: lienzo; plugin: self }

    K4.Ipc {
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

        //  ── el lienzo, mientras no tiene pantalla propia ──────────
        //
        //  Se conduce por aquí a propósito: así la parte que dibuja se puede
        //  probar entera —vídeo, GIF, foto, dos monitores— antes de que exista
        //  un solo botón, y sin que la interfaz condicione lo que hace.
        function fondo(pantalla: string, ruta: string): void {
            self.ponerFondoEn(pantalla, ruta)
        }

        function fondos(): string { return self.fondosEstado() }

        //  Cambiar la transición sin pantalla todavía. Devuelve lo que ha
        //  quedado puesto, para no tener que preguntarlo aparte.
        function transicion(cual: string): string {
            if (self.transiciones.indexOf(cual) >= 0) {
                self.transicion = cual
                self.saveState()
            }
            return self.transicion
        }
    }

    //  El estado del lienzo, en una función del plugin y no solo dentro del
    //  IpcHandler: así lo puede pedir también quien lo cargue por su cuenta —un
    //  banco de pruebas— sin pelearse por el nombre de IPC con la barra viva.
    function fondosEstado() {
        const salida = []
        for (let i = 0; i < lienzo.instances.length; ++i) {
            const t = lienzo.instances[i]
            if (t && typeof t.estado === "function")
                salida.push(t.estado())
        }
        return JSON.stringify({ telas: salida, guardado: self.fondos,
                                global: self.wallpaper })
    }

    view: Component {
        HyprThemeView { plugin: self }
    }
}
