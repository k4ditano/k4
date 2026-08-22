pragma Singleton

//  Traducción de la interfaz.
//
//  La clave de cada texto es el propio texto en español, no un identificador
//  inventado. Con 422 cadenas repartidas por 70 ficheros, bautizarlas una a una
//  habría sido un trabajo enorme y frágil, y además esto tiene tres ventajas
//  que un `ui.btn.42` no da:
//
//    · si falta una traducción sale la frase original, nunca una clave suelta;
//    · se puede ir traduciendo fichero a fichero sin romper nada por el camino;
//    · quien traduce lee frases con sentido, no etiquetas.
//
//  Un idioma es un JSON en traducciones/<código>.json con la forma
//  { "Oleada": "Wave", … } y un bloque `_meta` con el nombre y el crédito.
//  Añadir uno es copiar la plantilla, traducir y mandar el fichero: nada de
//  tocar código.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: idioma

    // El idioma en el que están escritos los textos del código: si el sistema
    // pide este, no hay nada que traducir.
    readonly property string origen: "es"

    readonly property var disponibles: [
        { codigo: "es", nombre: "Español" },
        { codigo: "en", nombre: "English" },
        { codigo: "ru", nombre: "Русский" }
    ]

    // "auto" sigue al sistema; cualquier otro valor manda sobre él.
    property string preferido: Settings.cargado ? Settings.idioma : "auto"

    // ── qué idioma toca ───────────────────────────────────────────
    //  De LANG salen cosas como «es_ES.UTF-8»: interesa la parte de delante,
    //  y se prueba primero el código completo por si algún día hay un pt_BR
    //  distinto del pt_PT.
    readonly property string delSistema: {
        const bruto = Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES")
            || Quickshell.env("LANG") || ""
        if (bruto.length === 0 || bruto.indexOf("C") === 0 || bruto.indexOf("POSIX") === 0)
            return origen
        return bruto.split(".")[0].replace("-", "_")
    }

    readonly property string codigo: preferido !== "auto" ? preferido
        : delSistema.split("_")[0]

    readonly property bool traduciendo: codigo !== origen

    // Para fechas y números: si no hay traducción, al menos el formato local.
    readonly property var locale: Qt.locale(preferido !== "auto"
        ? preferido : (delSistema.length > 0 ? delSistema : "es_ES"))

    // ── el diccionario ────────────────────────────────────────────
    property var tabla: ({})
    property bool cargado: false

    function t(texto) {
        if (!traduciendo || !texto)
            return texto
        const v = tabla[texto]
        return (v === undefined || v === "") ? texto : v
    }

    // Con una sustitución, para los textos que llevan un número dentro:
    //     Idioma.f("Quedan %1 cofres", n)
    function f(texto, a, b) {
        let s = t(texto)
        if (a !== undefined) s = s.replace("%1", a)
        if (b !== undefined) s = s.replace("%2", b)
        return s
    }

    //  ── por qué falló una herramienta ────────────────────────────
    //
    //  Los guiones de `tools/` hablan español y seguirán hablándolo: son de
    //  línea de órdenes y su público es quien los ejecuta. Pero su `motivo`
    //  acababa en una notificación, así que la barra salía en inglés y el
    //  error debajo en español. Se vio en pantalla y cantaba.
    //
    //  El reparto: el guion devuelve un CÓDIGO —`sin-audio`, `fuera-del-disco`—
    //  y la barra escribe la frase. Un código no hay que traducirlo, no cambia
    //  al reescribir un mensaje, y sirve igual para decidir qué hacer.
    //
    //  Lo que no reconoce se devuelve tal cual: más vale un motivo en español
    //  que ningún motivo, y así un guion nuevo no se queda mudo hasta que
    //  alguien se acuerde de venir aquí.
    readonly property var motivos: ({
        "cancelado":        "Cancelado",
        "fallo":            "Algo salió mal",
        "ilegible":         "No he podido leerlo",
        "no-existe":        "No existe",
        "nada-que-hacer":   "No había nada que hacer",
        "sin-fichero":      "No encuentro el fichero",
        "sin-audio":        "No tiene audio",
        "sin-video":        "No tiene vídeo",
        "sin-clips":        "No hay ningún trozo",
        "sin-fuentes":      "El proyecto no tiene fuentes",
        "sin-plan":         "No encuentro el proyecto",
        "sin-rastro":       "No hay rastro del cursor",
        "sin-fotograma":    "No he podido sacar el fotograma",
        "sin-ffmpeg":       "Falta ffmpeg",
        "sin-modelo":       "Falta el modelo de whisper",
        "sin-whisper":      "Falta whisper",
        "fallo-whisper":    "Whisper falló",
        "fuera":            "Se ha ido fuera",
        "sin pacman":       "Falta pacman",
        "sin Steam":        "Falta Steam",
        //  Los de rutas, que son los que traían la ruta dentro del texto.
        "fuera-del-disco":  "El proyecto apunta fuera del disco",
        "no-es-local":      "Eso no es un fichero de este ordenador",
        "no-responde":      "El fichero no responde",
        "fuera-de-carpeta": "La salida se sale de su carpeta",
        "sin-registro":     "No he podido leer el registro",
        "sin-clonar":       "No he podido clonar el repositorio",
        "sin-commit":       "No encuentro ese commit",
        "sin-plugin":       "No encuentro un plugin ahí dentro",
        "commit-raro":      "Eso no es un commit",
        //  Y los que salen de la propia barra, que iban igual de crudos: el
        //  problema no era solo de los guiones.
        "sin-monitor":      "No encuentro esa pantalla",
        "sin-proyecto":     "No hay ningún proyecto abierto",
        "no-es-imagen":     "Eso no es una imagen",
        "no-se-puede-soltar": "Ahí no se puede soltar",
        "no-se-puede-medir": "No he podido medir el vídeo",
        "no-se-pudo-limpiar": "No he podido limpiar el audio",
        "no-se-pudo-grabar-la-voz": "No he podido grabar la voz",
        "sin-microfono":    "El micrófono no llegó a arrancar",
        "miniatura":        "No he podido guardar la miniatura",
        "congelar":         "No he podido congelar ese momento",
        //  Por qué un plugin no carga. Se ven en Ajustes y en la tienda, y
        //  son los que más falta hace entender: cada uno tiene arreglo.
        "sin-manifiesto":   "Le falta el plugin.json",
        "manifiesto-ilegible": "Su plugin.json no se puede leer",
        "id-invalido":      "Su id no vale",
        "id-no-coincide":   "Su id no coincide con la carpeta",
        "id-ocupado":       "Ese id ya lo usa un plugin de la barra",
        "entrada-fuera":    "Su entrada apunta fuera de su carpeta",
        "sin-entrada":      "No encuentro el fichero de entrada",
        "sin-qmldir":       "No he podido escribir su qmldir",
        "barra-vieja":      "Pide una barra más nueva que esta",
        "icono-malo":       "Su icono no vale",
        "permisos-raros":   "Declara permisos que no existen",
        "sin-declarar":     "Usa cosas que no declara",
        "superficies-raras": "Declara superficies que no existen",
        "superficie-sin-declarar": "Ocupa sitios que no declara",
        "no-cargable":      "Ese plugin no se puede cargar",
    })

    //  El motivo ya escrito, con su detalle detrás si lo trae.
    function porque(codigo, detalle) {
        const c = String(codigo || "")
        if (c.length === 0)
            return ""
        const frase = motivos[c] !== undefined ? t(motivos[c]) : c
        return detalle ? frase + ": " + detalle : frase
    }

    // ── carga ─────────────────────────────────────────────────────
    //  blockLoading a propósito: el diccionario tiene que estar antes de que
    //  se construya la primera vista, o la barra arrancaría en español y
    //  cambiaría de idioma a la vista del usuario.
    FileView {
        id: fichero
        path: Quickshell.shellPath("traducciones/" + idioma.codigo + ".json")
        blockLoading: true
        onLoaded: idioma.aplicar(text())
        onLoadFailed: {
            idioma.tabla = ({})
            idioma.cargado = true
        }
    }

    function aplicar(bruto) {
        try {
            const d = JSON.parse(bruto)
            delete d._meta
            tabla = d
        } catch (e) {
            tabla = ({})
        }
        cargado = true
    }

    onCodigoChanged: fichero.reload()
}
