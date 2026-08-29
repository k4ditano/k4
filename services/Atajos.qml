pragma Singleton

//  Los atajos de teclado que tienes configurados en Hyprland.
//
//  La fuente es el fichero de configuración, no `hyprctl binds`, y no por
//  comodidad: con configuración en Lua, hyprctl informa de todos con
//  `dispatcher: __lua`, o sea la tecla sí pero no qué hace, y encima su salida
//  JSON viene desparejada en esta versión. El fichero dice exactamente qué
//  hace cada uno y ya viene agrupado por los comentarios de sección.
//
//  Quien lo lee es tools/atajos.py. Aquí solo se pide, se guarda y se filtra.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: atajos

    property var lista: []
    property bool cargado: false

    function recargar() { lector.running = true }

    //  Qué hace un atajo, en el idioma de la barra.
    //
    //  `tools/atajos.py` manda la frase y su detalle por separado justo para
    //  esto: la frase es prosa —«Cerrar la ventana»— y pasa por `Idioma`,
    //  mientras que el detalle suele ser un identificador —«left»,
    //  «togglesplit»— y se queda como está. Traducirlo sería inventarse un
    //  nombre para algo que el usuario escribió en su configuración.
    //
    //  Sin frase, `hace` tal cual: es un despachador que no conocemos o una
    //  orden suya, y ahí no hay nada que traducir.
    //  Y con el detalle detrás de un « · », salvo que la frase diga dónde va.
    //  «Abrir %1» lo lleva dentro —el nombre de la aplicación es el objeto del
    //  verbo, no una coletilla— y las demás lo quieren al final.
    function hace(a) {
        if (!a.frase || a.frase.length === 0)
            return a.hace || ""
        const d = a.detalleFrase && a.detalleFrase.length > 0
            ? Idioma.t(a.detalleFrase) : (a.detalle || "")
        if (a.frase.indexOf("%1") !== -1)
            return Idioma.f(a.frase, d)
        return Idioma.t(a.frase) + (d.length > 0 ? " · " + d : "")
    }

    function filtrar(texto) {
        const q = (texto || "").trim().toLowerCase()
        if (q.length === 0)
            return lista

        const salida = []
        for (let i = 0; i < lista.length; ++i) {
            const a = lista[i]
            //  Se busca por lo que SE VE y también por el original: con la
            //  barra en inglés, «close» tiene que encontrar el atajo, y quien
            //  se sepa el nombre español no debe perderlo por cambiar de
            //  idioma.
            if (a.combo.toLowerCase().indexOf(q) !== -1
                || atajos.hace(a).toLowerCase().indexOf(q) !== -1
                || (a.hace || "").toLowerCase().indexOf(q) !== -1
                || a.seccion.toLowerCase().indexOf(q) !== -1)
                salida.push(a)
        }
        return salida
    }

    // Las piezas de una combinación, para pintarlas como teclas sueltas.
    function teclas(combo) {
        const partes = String(combo).split("+")
        const salida = []
        for (let i = 0; i < partes.length; ++i) {
            const t = partes[i].trim()
            if (t.length > 0)
                salida.push(t)
        }
        return salida
    }

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("atajos:", l)
            }
        }
        id: lector
        command: ["python3", Quickshell.shellPath("tools/atajos.py")]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    atajos.lista = d.atajos || []
                } catch (e) {
                    atajos.lista = []
                }
                atajos.cargado = true
            }
        }
    }
}
