pragma Singleton

//  Módulos apartados a un lado, para retomarlos luego.
//
//  Cerrar no siempre quiere decir «tira esto». Una conversación con la IA o un
//  vídeo a medio editar son cosas en las que estabas, y que al cerrarlas se
//  pierdan obliga a no cerrarlas nunca —o sea, a tener la island ocupada
//  mientras haces otra cosa—. Aquí se apuntan las que están apartadas para que
//  la píldora pueda enseñarlas y devolverlas de un clic.
//
//  El estado NO vive aquí: cada módulo se queda con el suyo, que para eso es
//  suyo. Esto es solo la lista de quién está esperando.

import QtQuick
import Quickshell

Singleton {
    id: modulos

    // [{ id, titulo, detalle, glifo }]
    property var lista: []

    readonly property int count: lista.length

    // Quien lo tenga apuntado escucha y se restaura solo.
    signal restaurado(string id)

    function minimizar(id, titulo, detalle, glifo) {
        const sin = lista.filter(function (m) { return m.id !== id })
        // Reasignar el array entero: mutarlo en su sitio no emite el cambio y
        // la píldora se quedaría como estaba.
        lista = sin.concat([{ id: id, titulo: titulo,
                              detalle: detalle || "", glifo: glifo || 0 }])
    }

    function actualizar(id, detalle) {
        lista = lista.map(function (m) {
            if (m.id !== id)
                return m
            const d = Object.assign({}, m)
            d.detalle = detalle
            return d
        })
    }

    function restaurar(id) {
        quitar(id)
        restaurado(id)
    }

    function quitar(id) {
        lista = lista.filter(function (m) { return m.id !== id })
    }
}
