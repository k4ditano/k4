pragma Singleton

//  Los fondos de escritorio: cuáles hay, cómo se ven y dónde vive su miniatura.
//
//  Vivían dentro del plugin `HyprTheme`, y ahí estaban bien mientras solo los
//  usara su pantalla. Dejaron de estarlo cuando Ajustes quiso enseñar la misma
//  rejilla: un plugin no importa la carpeta de otro —en este repo nadie lo hace,
//  y con razón— así que lo compartido baja aquí y lo usan los dos sin conocerse.
//
//  Aquí está el CATÁLOGO y cómo se ve. Aplicar un fondo sigue siendo del
//  plugin, que es quien habla con `awww`/`swww`/`swaybg` y quien sabe de
//  transiciones: eso es hacer, no mirar, y se moverá cuando toque.
//
//  Un servicio no puede usar `K4.Process` ni `K4.Sistema` —esa es la API de
//  plugins— así que aquí se habla con Quickshell directamente, que es lo que
//  hacen los demás servicios.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: fondos

    // ── dónde se busca ────────────────────────────────────────────
    readonly property string casa: Quickshell.env("HOME") || ""

    readonly property var carpetas: [
        casa + "/Imágenes",
        casa + "/Pictures",
        casa + "/Vídeos",
        casa + "/Videos",
        casa + "/Descargas",
        "/usr/share/wallpapers",
        "/usr/share/backgrounds"
    ]

    //  Y lo que NO cuenta como fondo aunque esté ahí dentro.
    //
    //  «Capturas» es donde el propio k4 guarda las fotos y grabaciones de
    //  pantalla, así que la rejilla se llenaba de capturas de la barra: en esta
    //  máquina, de 120 imágenes encontradas la inmensa mayoría eran pantallazos
    //  de terminales. Un selector de fondos que enseña tus capturas es un
    //  selector que no has mirado nunca.
    readonly property var carpetasFuera: ["Capturas", "Screenshots", ".thumbnails"]

    //  Qué se admite. Los de siempre más lo que se mueve, que es de lo que iba
    //  todo esto.
    readonly property var extensiones: [
        "jpg", "jpeg", "png", "webp", "avif",
        "gif", "apng",
        "mp4", "webm", "mkv", "mov", "m4v"
    ]

    function admitido(ruta) {
        const r = String(ruta || "").toLowerCase()
        for (let i = 0; i < extensiones.length; ++i)
            if (r.endsWith("." + extensiones[i]))
                return true
        return false
    }

    // ── qué hay ───────────────────────────────────────────────────
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
    readonly property var lista: {
        const fuera = []
        for (let i = 0; i < fondos.extras.length; ++i)
            fuera.push(fondos.extras[i])
        for (let j = 0; j < fondos.encontrados.length; ++j)
            if (fondos.extras.indexOf(fondos.encontrados[j]) < 0)
                fuera.push(fondos.encontrados[j])
        return fuera
    }

    property bool rastreando: false

    function sumar(rutas) {
        const d = fondos.extras.slice()
        let hubo = false
        for (let i = 0; i < rutas.length; ++i) {
            const r = String(rutas[i])
            if (admitido(r) && d.indexOf(r) < 0) {
                d.unshift(r)
                hubo = true
            }
        }
        if (hubo)
            fondos.extras = d
    }

    function quitar(ruta) {
        const d = fondos.extras.filter(function (x) { return x !== String(ruta) })
        if (d.length !== fondos.extras.length)
            fondos.extras = d
    }

    // ── cómo se ven ───────────────────────────────────────────────
    readonly property string cache: casa + "/.cache/k4/fondos"

    //  Lo de `gif|webp|apng` cuenta como QUIETO aunque se mueva: eso lo pinta un
    //  AnimatedImage y no el reproductor, así que para las miniaturas vale la
    //  propia imagen.
    function esQuieto(ruta) {
        return !/\.(mp4|webm|mkv|mov|m4v|avi|gif|webp|apng)$/i.test(String(ruta))
    }

    function esVideo(ruta) {
        return /\.(mp4|webm|mkv|mov|m4v|avi)$/i.test(String(ruta))
    }

    //  Dónde vive el fotograma cacheado de un fondo que se mueve.
    //
    //  `Qt.md5` y no un `md5sum` por proceso: la ruta se calcula en el sitio,
    //  sin lanzar nada. Es el mismo nombre que escribe el plugin al preparar los
    //  pósters, así que las dos partes miran el mismo fichero.
    function posterDe(ruta) {
        return cache + "/" + Qt.md5(String(ruta)) + ".png"
    }

    //  La miniatura: la propia imagen si está quieta, y el póster si se mueve.
    //
    //  `sello` está en la cuenta a propósito: una ruta de fichero no cambia
    //  cuando el fichero aparece, así que sin algo que mueva el enlace la
    //  miniatura de un vídeo se quedaría rota hasta cerrar y volver a abrir.
    property int sello: 0

    function miniaturaDe(ruta) {
        if (esQuieto(ruta))
            return ruta
        return fondos.sello >= 0 ? posterDe(ruta) : ""
    }

    // ── cuál está puesto ──────────────────────────────────────────
    //
    //  Se LEE del estado que escribe el plugin del tema, no se duplica: quien
    //  aplica un fondo sigue siendo él, y aquí solo se mira. Con `watchChanges`
    //  para que cambiar el fondo se note en quien esté enseñándolo sin que nadie
    //  tenga que avisar a nadie.
    //
    //  `fondos` es el mapa por monitor —`{"DP-3": "/ruta/a.mp4"}`— y `wallpaper`
    //  el común, para quien no tenga uno propio.
    property var porPantalla: ({})
    property string comun: ""

    //  Los huecos de Hyprland viven en el mismo fichero, y los pide quien dibuje
    //  una previsualización del escritorio: una ventana pegada a los bordes
    //  enseñaría algo que no pasa.
    property int huecos: 8

    function actualDe(pantalla) {
        const p = String(pantalla || "")
        if (p.length > 0 && fondos.porPantalla[p])
            return String(fondos.porPantalla[p])
        if (fondos.comun.length > 0)
            return fondos.comun
        //  Sin común ni propio: el primero que haya en el mapa, que es mejor
        //  que nada cuando solo se quiere enseñar «cómo queda».
        const ks = Object.keys(fondos.porPantalla)
        return ks.length > 0 ? String(fondos.porPantalla[ks[0]]) : ""
    }

    FileView {
        path: (Quickshell.env("HOME") || "") + "/.local/state/k4/hyprtheme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                fondos.porPantalla = d.fondos || ({})
                fondos.comun = String(d.wallpaper || "")
                if (d.gapsOut !== undefined)
                    fondos.huecos = parseInt(d.gapsOut, 10) || 8
            } catch (e) {
                //  Un estado a medio escribir no es una urgencia: se queda lo
                //  que hubiera y ya llegará el siguiente cambio.
            }
        }
    }

    // ── el rastreo ────────────────────────────────────────────────
    function rastrear() {
        const args = ["find"]
        for (let i = 0; i < fondos.carpetas.length; ++i)
            args.push(fondos.carpetas[i])
        args.push("-maxdepth")
        args.push("3")
        //  Las carpetas excluidas se podan ANTES de mirar ficheros: con un
        //  `-not -path` cada fichero de dentro se examina igualmente, y en una
        //  carpeta de capturas con cientos eso es recorrer para descartar.
        for (let i = 0; i < fondos.carpetasFuera.length; ++i) {
            args.push("(")
            args.push("-type"); args.push("d")
            args.push("-name"); args.push(fondos.carpetasFuera[i])
            args.push("-prune")
            args.push(")")
            args.push("-o")
        }
        args.push("(")
        args.push("-type"); args.push("f")
        args.push("(")
        for (let j = 0; j < fondos.extensiones.length; ++j) {
            if (j > 0)
                args.push("-o")
            args.push("-iname")
            args.push("*." + fondos.extensiones[j])
        }
        args.push(")")
        args.push("-print")
        args.push(")")
        rastreo.command = args
        rastreo.running = true
    }

    Process {
        id: rastreo
        onStarted: fondos.rastreando = true
        stdout: StdioCollector {
            onStreamFinished: {
                const rutas = String(this.text).split("\n").filter(function (r) {
                    return r.length > 0 && fondos.admitido(r)
                })
                fondos.encontrados = rutas
                fondos.prepararPosters()
            }
        }
        onExited: fondos.rastreando = false
    }

    //  Los pósters, todos de una tacada y en UN proceso.
    //
    //  Uno por fichero serían treinta ffmpeg compitiendo por la CPU justo
    //  cuando acabas de abrir la pantalla y quieres verla. En fila, y el que ya
    //  existe ni se toca.
    Process {
        id: cocina
        onExited: fondos.sello += 1
    }

    function prepararPosters() {
        const ordenes = []
        for (let i = 0; i < fondos.lista.length; ++i) {
            const r = fondos.lista[i]
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
        cocina.running = false
        cocina.command = ["sh", "-c",
            "mkdir -p " + JSON.stringify(fondos.cache) + "; " + ordenes.join("; ")]
        cocina.running = true
    }
}
