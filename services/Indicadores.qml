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
