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
    //  Sin `active`, sin `view` y sin teclado: este plugin ya NO se dibuja.
    //
    //  Tenía su propia pantalla con cuatro pestañas —color, ventanas, efectos y
    //  fondo— y era un sitio más donde configurar cosas. Todo eso vive ahora en
    //  la ventana de Ajustes, en sus secciones, con los mismos widgets. Aquí se
    //  queda lo que nadie más sabe hacer: escribir el Lua de Hyprland, hablar
    //  con awww/swww/swaybg y pintar el suelo.
    //
    //  Es el mismo camino que hicieron la tienda de plugins y los propios
    //  ajustes: lo que se abre y se usa es una aplicación, y lo que sabe hacer
    //  algo es un motor. Aquí solo queda el motor.

    //  Grande a propósito, y sobre todo ALTO.
    //
    //  Con 470 la rejilla de fondos enseñaba dos filas y media de cincuenta:
    //  para encontrar uno había que recorrerla a ciegas, que es justo lo que
    //  una rejilla de miniaturas viene a evitar. Con 780 caben cuatro filas
    //  largas y se elige mirando, que es como se elige un fondo.
    //
    //  780 y no más: el techo de la superficie son 880 (`Theme.maxIslandHeight`)
    //  y conviene dejar aire, que por debajo de la island todavía tiene que
    //  caber algo de escritorio para no parecer una ventana a pantalla completa
    //  que no lo es.

    // Se abre con el ratón, así que se va al sacarlo. Con más margen que el
    // panel: aquí se arrastran deslizadores y es fácil pasarse del borde.
    closeOnHoverExit: true
    hoverExitDelay: 1000
    //  Salvo con el selector de ficheros abierto: para elegir hay que sacar el
    //  ratón de aquí, y cerrarse entonces es cerrarse justo cuando el usuario
    //  está haciendo lo que le hemos pedido.
    onHoverTimedOut: if (!eligiendo) close()

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
        sacarPaleta()
    }

    // Marca de agua: los presets solo se ven "elegidos" mientras no toques nada.
    property bool dirty: false

    //  ── la paleta, sacada del fondo ──────────────────────────────
    //
    //  Encendido —lo de fábrica—, los colores salen del fondo que pongas y se
    //  reparten a los dos sitios donde se ven: el tinte de la barra y los bordes
    //  de Hyprland. Cambias de fondo y el ambiente entero se recoloca.
    //
    //  Y hay un tercer sitio de regalo: `services/Ambiente.qml` ya publica el
    //  tema TEÑIDO en `tema.json` para quien vive fuera de la barra, así que
    //  k4term se tiñe con el fondo sin escribir una línea de más.
    //
    //  Se apaga solo al tocar un preset: quien elige un color a mano no quiere
    //  que el siguiente fondo se lo pise, y apagarlo por su cuenta evita el
    //  ajuste que nadie encuentra.
    property bool paletaAuto: true

    //  De qué fondo sale. Con dos monitores y dos fondos distintos alguno tiene
    //  que mandar, y manda el de la pantalla donde vive la island: es el que
    //  estás mirando cuando la barra se tiñe.
    function fondoDeReferencia() {
        const p = K4.Isla.pantalla
        const propio = p && p.length > 0 ? fondoDe(p) : ""
        return propio.length > 0 ? propio : wallpaper
    }

    property var paletaSacada: []

    K4.Process {
        id: sacaColores
        environment: ({ "LC_ALL": "C" })

        onSalida: function (texto) {
            const lineas = String(texto).split("\n")
            const cols = []
            for (let i = 0; i < lineas.length; ++i) {
                //  «   8392: (39,39,113) #272771 srgb(39,39,113)»
                const m = lineas[i].match(/^\s*(\d+):\s*\(\s*(\d+),\s*(\d+),\s*(\d+)/)
                if (!m)
                    continue
                cols.push({ peso: parseInt(m[1], 10), r: +m[2], g: +m[3], b: +m[4] })
            }
            if (cols.length === 0)
                return
            self.paletaSacada = cols
            self.repartirPaleta(cols)
        }
    }

    function sacarPaleta() {
        if (!paletaAuto)
            return
        const fondo = fondoDeReferencia()
        if (fondo.length === 0)
            return
        //  De un vídeo o un GIF, su póster: magick abriría el vídeo entero para
        //  sacar un fotograma, y el póster ya está hecho.
        const fuente = esQuieto(fondo) ? fondo : posterDe(fondo)
        sacaColores.running = false
        //  Recortado al centro y a 200×200 antes de contar: es mucho más rápido
        //  y el resultado no cambia — lo que manda en un fondo son las masas de
        //  color, no los píxeles sueltos de las esquinas.
        sacaColores.command = ["sh", "-c",
            "[ -f \"$1\" ] || exit 0; magick \"$1\" -resize 200x200^"
            + " -gravity center -extent 200x200 -colors 8 -depth 8"
            + " -format %c histogram:info:-", "sh", fuente]
        sacaColores.running = true
    }

    //  ── de una lista de colores a un ambiente ────────────────────
    //
    //  No vale el más frecuente: en la mayoría de los fondos es un gris o un
    //  casi-negro, y un acento gris no es un acento. Se busca el que más COLOR
    //  tiene con peso suficiente, y se descartan los extremos — lo casi negro no
    //  se ve sobre la barra y lo casi blanco se come el texto.
    function _hsv(c) {
        const r = c.r / 255, g = c.g / 255, b = c.b / 255
        const mx = Math.max(r, g, b), mn = Math.min(r, g, b)
        return { v: mx, s: mx <= 0 ? 0 : (mx - mn) / mx }
    }

    function repartirPaleta(cols) {
        let total = 0
        for (let i = 0; i < cols.length; ++i)
            total += cols[i].peso

        let mejor = null, mejorNota = -1
        for (let i = 0; i < cols.length; ++i) {
            const c = cols[i]
            const h = _hsv(c)
            if (h.v < 0.18 || h.v > 0.94 || h.s < 0.12)
                continue
            //  La nota premia el color y castiga poco el peso: un acento que
            //  ocupa el 5 % del fondo sigue siendo el acento de ese fondo, y
            //  premiando el peso salía siempre el cielo o la pared.
            const nota = h.s * (0.55 + 0.45 * Math.min(1, c.peso / total * 4))
            if (nota > mejorNota) {
                mejorNota = nota
                mejor = c
            }
        }
        //  Sin ningún color aprovechable —un fondo en blanco y negro— se deja lo
        //  que hubiera: inventarse un acento es peor que no tener uno.
        if (!mejor)
            return

        const base = Qt.rgba(mejor.r / 255, mejor.g / 255, mejor.b / 255, 1)
        accentFrom = Qt.lighter(base, 1.25)
        accentTo = Qt.darker(base, 1.9)
        //  El inactivo tiene que LEERSE como apagado al lado del activo, así que
        //  se le quita color además de luz: oscurecer a secas deja dos bordes del
        //  mismo tono y no se distingue cuál tiene el foco.
        const gris = (mejor.r + mejor.g + mejor.b) / 3 / 255
        inactive = Qt.rgba((mejor.r / 255 * 0.35 + gris * 0.65) * 0.75,
                           (mejor.g / 255 * 0.35 + gris * 0.65) * 0.75,
                           (mejor.b / 255 * 0.35 + gris * 0.65) * 0.75, 1)
        dirty = false
        preset = "fondo"
        apply()
        saveState()

        //  Y la barra. La fuerza va baja a propósito: la island es negra y tiene
        //  que seguir siéndolo — esto es un ambiente, no una capa de pintura. El
        //  tope de la casa es 0,45 y aquí sobra con la mitad.
        K4.Tema.tintar("hyprtheme", base, 0.22, 0)
    }

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

            //  Elegir un preset es elegir a mano: quien lo hace no quiere que
            //  el siguiente fondo se lo pise.
            paletaAuto = false
            K4.Tema.destintar("hyprtheme")
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
            extras: extras,
            transicion: transicion,
            paletaAuto: paletaAuto,
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
        extras = (s.extras && s.extras.length !== undefined) ? s.extras : []
        if (s.transicion && transiciones.indexOf(s.transicion) >= 0)
            transicion = s.transicion
        if (s.paletaAuto !== undefined)
            paletaAuto = !!s.paletaAuto
        //  Y al cargar se rehace, que el tinte vive en memoria y no sobrevive a
        //  un reinicio de la barra.
        if (paletaAuto)
            sacarPaleta()
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

    //  Lo que ha encontrado el rastreo, y lo que has traído tú.
    //
    //  Se guardan por RUTA y no copiando el fichero. Copiar sería más robusto
    //  —un fondo en un USB deja de existir al sacarlo— pero también sería
    //  duplicar en silencio un vídeo de trescientos megas porque lo arrastraste
    //  a una rejilla. Si la ruta deja de existir, se cae sola del rastreo
    //  siguiente y ya está.
    property var encontrados: []
    property var extras: []

    //  Los tuyos primero: si te has molestado en traerlo, no lo busques luego
    //  entre cuarenta y cinco.
    readonly property var wallpapers: {
        const fuera = []
        for (let i = 0; i < extras.length; ++i)
            fuera.push(extras[i])
        for (let j = 0; j < encontrados.length; ++j)
            if (extras.indexOf(encontrados[j]) < 0)
                fuera.push(encontrados[j])
        return fuera
    }

    function admitido(ruta) {
        const r = String(ruta || "").toLowerCase()
        for (let i = 0; i < extensionesFondo.length; ++i)
            if (r.endsWith("." + extensionesFondo[i]))
                return true
        return false
    }

    //  ── traer uno de fuera ───────────────────────────────────────
    //
    //  Por el diálogo del sistema y no arrastrando, y no es la primera opción
    //  que probé: la de arrastrar estaba escrita y no puede funcionar AQUÍ. Este
    //  módulo se cierra al salir el ratón (`closeOnHoverExit`), así que para ir
    //  a por el fichero tienes que salir, y al salir ya no hay dónde soltarlo.
    //  Una superficie que se cierra al perder el puntero no puede ser destino de
    //  un arrastre, por bien escrito que esté el `DropArea`.
    //
    //  Zenity además trae vista previa, que para elegir un fondo es justo lo que
    //  hace falta: un fondo se reconoce mirándolo.
    property bool eligiendo: false

    K4.Process {
        id: selectorFondo
        //  Mientras el diálogo esté abierto la island se aparta: va en una capa
        //  por encima de todo y el selector le saldría por debajo, donde no se
        //  ve ni se puede pulsar.
        onArrancado: { self.eligiendo = true; Island.abrirDialogo() }
        onTerminado: { self.eligiendo = false; Island.cerrarDialogo() }
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n",
                  "--title=" + Idioma.t("Elegir fondo"),
                  "--file-filter=" + Idioma.t("Fondos")
                  + " | *.jpg *.jpeg *.png *.webp *.avif *.gif *.apng"
                  + " *.mp4 *.webm *.mkv *.mov *.m4v"]

        onSalida: function (texto) {
            const rutas = String(texto).trim().split("\n")
                .filter(function (r) { return r.length > 0 })
            //  Vacío es que le has dado a cancelar, que no es un fallo.
            if (rutas.length === 0)
                return
            if (self.sumarFondos(rutas) > 0)
                self.ponerEnElegida(self.extras[0])
        }
    }

    function elegirFondo() {
        if (!selectorFondo.running)
            selectorFondo.running = true
    }

    //  Y quitarlo. Poder añadir sin poder quitar es una calle sin salida: una
    //  ruta que ya no existe se queda enseñando una miniatura rota para siempre.
    //  Solo se quita de la lista; el fichero no se toca, que no es nuestro.
    function quitarFondo(ruta) {
        const l = extras.filter(function (x) { return x !== ruta })
        if (l.length === extras.length)
            return false
        extras = l
        saveState()
        return true
    }

    //  Añadir lo que se ha soltado. Devuelve cuántos han entrado, que es lo que
    //  la pantalla necesita para decir algo con sentido cuando no entra ninguno.
    function sumarFondos(rutas) {
        const nuevos = []
        for (let i = 0; i < rutas.length; ++i) {
            const r = String(rutas[i])
            if (!admitido(r) || extras.indexOf(r) >= 0)
                continue
            nuevos.push(r)
        }
        if (nuevos.length === 0)
            return 0
        //  Contenedor NUEVO: mutar el array no repinta la rejilla.
        extras = nuevos.concat(extras)
        saveState()
        prepararPosters()
        return nuevos.length
    }

    readonly property var wallDirs: [
        K4.Sistema.entorno("HOME") + "/Imágenes",
        K4.Sistema.entorno("HOME") + "/Pictures",
        K4.Sistema.entorno("HOME") + "/Vídeos",
        K4.Sistema.entorno("HOME") + "/Videos",
        K4.Sistema.entorno("HOME") + "/Descargas",
        "/usr/share/wallpapers",
        "/usr/share/backgrounds"
    ]

    //  Y lo que NO cuenta como fondo aunque esté en esas carpetas.
    //
    //  «Capturas» es donde el propio k4 guarda las fotos y las grabaciones de
    //  pantalla, así que la rejilla se llenaba de capturas de la barra: en esta
    //  máquina, de 120 imágenes encontradas la inmensa mayoría eran pantallazos
    //  de terminales. Un selector de fondos que enseña tus capturas es un
    //  selector que no has mirado nunca.
    readonly property var carpetasFuera: ["Capturas", "Screenshots", ".thumbnails"]

    //  Qué se admite. Los de siempre más lo que se mueve, que es de lo que iba
    //  todo esto.
    readonly property var extensionesFondo: [
        "jpg", "jpeg", "png", "webp", "avif",
        "gif", "apng",
        "mp4", "webm", "mkv", "mov", "m4v"
    ]

    //  La miniatura de un fondo: la propia imagen si está quieta, y el póster ya
    //  cacheado si se mueve. `posterSello` está en la cuenta a propósito: una
    //  ruta de fichero no cambia cuando el fichero aparece, así que sin algo que
    //  mueva el enlace la miniatura de un vídeo se quedaría rota hasta que
    //  cerraras y volvieras a abrir.
    property int posterSello: 0
    function miniaturaDe(ruta) {
        if (esQuieto(ruta))
            return ruta
        return posterSello >= 0 ? posterDe(ruta) : ""
    }

    //  Los pósters, todos de una tacada y en UN proceso.
    //
    //  Uno por fichero serían treinta ffmpeg compitiendo por la CPU justo cuando
    //  acabas de abrir la pantalla y quieres verla. En fila, y el que ya existe
    //  ni se toca.
    K4.Process {
        id: cocinaPosters
        onTerminado: self.posterSello += 1
    }

    function prepararPosters() {
        const ordenes = []
        for (let i = 0; i < wallpapers.length; ++i) {
            const r = wallpapers[i]
            if (esQuieto(r))
                continue
            const d = posterDe(r)
            ordenes.push("[ -f " + JSON.stringify(d) + " ] || ffmpeg -v error -y"
                         + " -ss 1 -i " + JSON.stringify(r)
                         + " -frames:v 1 -vf scale=480:-1 " + JSON.stringify(d)
                         + " >/dev/null 2>&1")
        }
        if (ordenes.length === 0)
            return
        cocinaPosters.running = false
        cocinaPosters.command = ["sh", "-c",
            "mkdir -p " + JSON.stringify(cachePosters) + "; " + ordenes.join("; ")]
        cocinaPosters.running = true
    }

    //  En qué pantalla se está trabajando en la pantalla de Ajustes. Vacío es
    //  «todas»: se pone el fondo común y se olvidan las elecciones sueltas.
    property string pantallaElegida: ""

    function ponerEnElegida(ruta) {
        if (pantallaElegida.length > 0) {
            ponerFondoEn(pantallaElegida, ruta)
            return
        }
        //  Todas: el fondo común manda y las elecciones por pantalla estorban,
        //  porque `fondoDe` las prefiere y el cambio no se vería en los
        //  monitores que tuvieran una.
        wallpaper = ruta
        fondos = ({})
        saveState()
        ponerSuelo()
        sacarPaleta()
    }

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

    //  ── el vídeo, a la medida de la pantalla ─────────────────────
    //
    //  Un vídeo 4K en un monitor de 1920 se descodifica y se sube entero para
    //  enseñar EXACTAMENTE lo mismo: cuatro veces los píxeles que caben. Es la
    //  misma cuenta que la foto ya hacía con `sourceSize` en Capa.qml —«una foto
    //  de 6000 px en un monitor de 1920 son 140 MB de textura»— y al vídeo le
    //  faltaba esa mitad.
    //
    //  Medido sobre el propio proceso, con un clip de 3840×2160 a 47 Mbps y la
    //  barra plegada:
    //
    //      el original    27 % de un núcleo  ·  1 GB de memoria
    //      la copia 1920  15 %               ·  553 MB
    //
    //  Y no es la descodificación: los hilos de ffmpeg suman un 2 % en los dos
    //  casos. Lo que cuesta es presentar ese cuadro.
    //
    //  La copia se hace UNA vez y vive en la caché. Mientras no está se sigue
    //  enseñando el original: un fondo tarde es peor que un fondo caro.
    property var escalados: ({})        // "ruta|ancho" -> la copia, ya hecha
    property var escaladosPedidos: ({})

    //  Lo de `gif|webp|apng` que admite `esQuieto` NO entra aquí: eso lo pinta
    //  un AnimatedImage, no el reproductor, y convertirlo a mp4 sería cambiarle
    //  el tipo por la espalda.
    function esVideo(ruta) {
        return /\.(mp4|webm|mkv|mov|m4v|avi)$/i.test(String(ruta))
    }

    function escaladoDe(ruta, ancho) {
        return cachePosters + "/" + Qt.md5(String(ruta)) + "-" + ancho + ".mp4"
    }

    //  Qué hay que reproducir de verdad. Lectura PURA —el mapa lo llena la
    //  cocina de abajo— para poder preguntarlo desde un binding sin que
    //  preguntar tenga efectos.
    function videoAMedida(ruta, ancho) {
        const hecho = escalados[String(ruta) + "|" + ancho]
        return hecho ? hecho : String(ruta)
    }

    //  Y esto sí tiene efecto, así que se llama desde un manejador y nunca
    //  desde un binding: lo hace Capa.qml al cambiar de ruta o de pantalla.
    function pedirEscalado(ruta, ancho) {
        if (!esVideo(ruta) || !(ancho > 0))
            return
        const clave = String(ruta) + "|" + ancho
        if (escalados[clave] !== undefined || escaladosPedidos[clave])
            return
        escaladosPedidos[clave] = true
        juntarEscalados.restart()
    }

    //  Se juntan las peticiones antes de cocinar: con dos monitores y una
    //  transición, esto llega cuatro veces seguidas para lo mismo.
    Timer {
        id: juntarEscalados
        interval: 400
        onTriggered: self.cocinarEscalados()
    }

    K4.Process {
        id: cocinaEscalados
        onSalida: function (texto) {
            const d = Object.assign({}, self.escalados)
            const lineas = String(texto).split("\n")
            for (let i = 0; i < lineas.length; ++i) {
                const partes = lineas[i].split("\t")
                if (partes.length === 2 && partes[1].length > 0)
                    d[partes[0]] = partes[1]
            }
            self.escalados = d
        }
    }

    function cocinarEscalados() {
        const claves = Object.keys(escaladosPedidos)
        if (claves.length === 0 || cocinaEscalados.running)
            return

        const ordenes = []
        for (let i = 0; i < claves.length; ++i) {
            const corte = claves[i].lastIndexOf("|")
            const ruta = claves[i].substring(0, corte)
            const ancho = claves[i].substring(corte + 1)
            ordenes.push([
                's=' + JSON.stringify(ruta),
                'd=' + JSON.stringify(escaladoDe(ruta, ancho)),
                'a=' + JSON.stringify(ancho),
                'k=' + JSON.stringify(claves[i]),
                //  Se mide antes de tocar nada: un vídeo que ya cabe se deja en
                //  paz, que reescalar hacia arriba es gastar por empeorar.
                'if [ ! -f "$d" ]; then',
                '  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$s" 2>/dev/null | head -1)',
                '  case "$w" in ""|*[!0-9]*) w=0 ;; esac',
                //  A un fichero temporal y luego `mv`: el renombrado es atómico,
                //  así que si dos pantallas piden lo mismo a la vez ninguna llega
                //  a leer una copia a medio escribir.
                //  En UNA línea: unido con saltos, cada trozo sería una
                //  orden suelta y el `&&` no encadenaría nada.
                '  if [ "$w" -gt "$a" ]; then ffmpeg -nostdin -v error -y -i "$s"'
                + ' -vf "scale=$a:-2" -c:v libx264 -preset veryfast -crf 23 -an'
                + ' "$d.parcial.mp4" && mv -f "$d.parcial.mp4" "$d"; fi',
                'fi',
                '[ -f "$d" ] && printf "%s\\t%s\\n" "$k" "$d"'
            ].join("\n"))
        }

        escaladosPedidos = ({})
        cocinaEscalados.running = false
        //  En fila y en UN proceso, como los pósters: dos ffmpeg de 4K a la vez
        //  se comen la máquina justo cuando acabas de cambiar de fondo.
        cocinaEscalados.command = ["sh", "-c",
            //  Y un `:` al final para salir en cero: si la última copia no
            //  está, su `[ -f ]` daría el código de salida de todo el guion.
            "mkdir -p " + JSON.stringify(cachePosters) + "\n"
            + ordenes.join("\n") + "\n:"]
        cocinaEscalados.running = true
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
        args.push("-maxdepth")
        args.push("3")
        //  Las carpetas excluidas se podan ANTES de mirar ficheros: con un
        //  `-not -path` cada fichero de dentro se examina igualmente, y en una
        //  carpeta de capturas con cientos eso es recorrer para descartar.
        for (let i = 0; i < carpetasFuera.length; ++i) {
            args.push("(")
            args.push("-type"); args.push("d")
            args.push("-name"); args.push(carpetasFuera[i])
            args.push("-prune")
            args.push(")")
            args.push("-o")
        }
        args.push("(")
        args.push("-type"); args.push("f")
        args.push("(")
        for (let j = 0; j < extensionesFondo.length; ++j) {
            if (j > 0)
                args.push("-o")
            args.push("-iname")
            args.push("*." + extensionesFondo[j])
        }
        args.push(")")
        args.push("-print")
        args.push(")")
        wallScan.command = args
        wallScan.running = true
    }

    //  El rastreo de fondos lo pide quien los enseña —la rejilla, al hacerse
    //  visible— y no un cambio de pestaña, que ya no existe. Aquí solo queda
    //  reaplicar si aparece la herramienta después del fondo.
    onWallToolChanged: if (wallTool.length > 0 && wallpaper.length > 0)
        applyWallpaper(wallpaper)


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
            self.encontrados = found.slice(0, 200)
            self.prepararPosters()
        }
    }

    //  Quien dibuja. Va en el plugin y no en `view` porque una vista solo
    //  existe mientras se tiene la island, y el fondo tiene que estar puesto
    //  esté abierto el módulo o no.
    Lienzo { id: lienzo; plugin: self }

    K4.Ipc {
        target: "k4.theme"
        //  Se conserva el verbo porque puede estar atado en Hyprland: abre
        //  Ajustes, que es donde vive ahora lo que esto configuraba.
        function toggle(): void { PluginManager.abrirAplicacion("settings") }
        function apply(): void { self.apply() }
        function save(): void { self.persist() }
        function preset(id: string): void { self.applyPreset(id) }
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
        //  La paleta: encenderla, apagarla y mirar lo que ha sacado.
        function paleta(auto: string): string {
            if (auto === "si" || auto === "no") {
                self.paletaAuto = (auto === "si")
                if (self.paletaAuto)
                    self.sacarPaleta()
                else
                    K4.Tema.destintar("hyprtheme")
                self.saveState()
            }
            return JSON.stringify({ auto: self.paletaAuto,
                                    fuente: self.fondoDeReferencia(),
                                    from: String(self.accentFrom),
                                    to: String(self.accentTo),
                                    inactive: String(self.inactive),
                                    sacados: self.paletaSacada })
        }

        //  Para poder probar lo de arrastrar sin arrastrar.
        function sumar(ruta: string): string {
            return JSON.stringify({ entraron: self.sumarFondos([ruta]),
                                    extras: self.extras })
        }

        function quitar(ruta: string): string {
            return JSON.stringify({ quitado: self.quitarFondo(ruta),
                                    extras: self.extras })
        }

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

}
