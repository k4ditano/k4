pragma Singleton

// Indicadores pequeños que aparecen en la píldora plegada.

import QtQuick
import Quickshell
import "../core"

Singleton {
    id: indicadores

    // [{ id, texto, glifo, color, orden, visible }]
    property var lista: []
    signal invocado(string id)

    //  Lo que ocuparán más o menos, para quien tenga que reservarles sitio
    //  ANTES de que existan. Es un suelo y no una medida: el ancho de verdad
    //  depende de la fuente y solo lo sabe quien las pinta —widgets/
    //  PluginPildora.qml—, así que quien pueda medir manda sobre esto. Está
    //  aquí porque el que reserva es el plugin del reloj, y con la island
    //  cerrada no hay ninguna píldora dispuesta a la que preguntarle.
    //
    //  Por píldora: el glifo y su separación, el texto a 11 px —de ahí los ~7
    //  por letra— y los 6 del relleno, más los 8 que las separan entre sí.
    readonly property int anchoAproximado: {
        let ancho = 0
        for (let i = 0; i < lista.length; ++i) {
            if (lista[i].visible === false)
                continue
            ancho += String(lista[i].texto || "").length * 7 + 37
        }
        return ancho
    }

    function registrar(id, texto, glifo, color, orden, visible) {
        if (!id || String(id).length === 0)
            return
        const nuevo = { id: String(id), texto: String(texto || ""),
                        glifo: Number(glifo) || 0, color: color || Theme.muted,
                        orden: Number(orden) || 0,
                        visible: visible !== false }
        lista = lista.filter(function (x) { return x.id !== nuevo.id })
            .concat([nuevo]).sort(function (a, b) { return a.orden - b.orden })
    }

    function actualizar(id, campos) {
        lista = lista.map(function (x) {
            return x.id === id ? Object.assign({}, x, campos) : x
        })
    }

    function quitar(id) {
        lista = lista.filter(function (x) { return x.id !== id })
    }

    function quitarDe(owner) {
        const prefijo = String(owner) + "."
        lista = lista.filter(function (x) {
            return x.id.indexOf(prefijo) !== 0
        })
    }
}
