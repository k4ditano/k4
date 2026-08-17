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
