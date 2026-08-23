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

    //  Lo ancho que se deja crecer a un nombre antes de recortarlo. Eran 110
    //  porque cada píxel de píldora costaba dos —la island reservaba lo mismo a
    //  los dos lados del reloj—; ahora que crece hacia un solo lado cabe un
    //  nombre de verdad sin que la island se desmadre.
    readonly property int topeTexto: 160

    //  Y lo que se deja ocupar a la fila ENTERA antes de resumir el resto en
    //  una cápsula «+N». Aunque ya no se pague doble, tres agentes trabajando
    //  son tres nombres largos, y una píldora de medio monitor sigue sin ser
    //  una píldora. El «+N» no dice cuáles son —para eso está la notificación—:
    //  dice que hay más, que es lo que te hace mirar.
    readonly property int presupuesto: 300

    //  Lo que ocupa uno, a ojo: el glifo y su separación, el texto a 11 px —de
    //  ahí los ~7 por letra— y los 6 del relleno.
    function anchoDe(ind) {
        return Math.min(topeTexto, String(ind.texto || "").length * 7) + 37
    }

    // Y lo que ocupa la cápsula del resumen, con sus dos dígitos.
    readonly property int anchoResumen: 34

    //  Cuáles se pintan y cuántos se quedan fuera.
    //
    //  Se decide aquí y no en la píldora por dos razones: hay TRES píldoras
    //  —reposo, reloj y reproductor— y las tres tienen que enseñar lo mismo, y
    //  quien reserva el hueco es el plugin, que necesita saberlo antes de que
    //  exista ninguna.
    //
    //  Se estima por el texto en vez de medir los delegates, porque medir para
    //  decidir cuántos instanciar es un bucle. El ancho de VERDAD lo sigue
    //  publicando la fila entera en cuanto está pintada, y ese manda.
    readonly property var reparto: {
        const vistos = []
        for (let i = 0; i < lista.length; ++i)
            if (lista[i].visible !== false)
                vistos.push(lista[i])

        let ancho = 0
        for (let i = 0; i < vistos.length; ++i) {
            ancho += anchoDe(vistos[i]) + (i > 0 ? 8 : 0)
            //  Siempre al menos uno: si el único que hay es larguísimo ya lo
            //  recorta el tope, y resumirlo a «+1» no ahorra sitio ni dice nada.
            if (ancho > presupuesto && i > 0)
                return { muestra: vistos.slice(0, i),
                         ocultos: vistos.length - i }
        }
        return { muestra: vistos, ocultos: 0 }
    }

    //  Lo que ocuparán más o menos, para quien tenga que reservarles sitio
    //  ANTES de que existan. Es un suelo y no una medida: el ancho de verdad
    //  depende de la fuente y solo lo sabe quien las pinta —widgets/
    //  PluginPildora.qml—, así que quien pueda medir manda sobre esto. Está
    //  aquí porque el que reserva es el plugin del reloj, y con la island
    //  cerrada no hay ninguna píldora dispuesta a la que preguntarle.
    readonly property int anchoAproximado: {
        const muestra = reparto.muestra
        let ancho = 0
        for (let i = 0; i < muestra.length; ++i)
            ancho += anchoDe(muestra[i]) + (i > 0 ? 8 : 0)
        if (reparto.ocultos > 0)
            ancho += anchoResumen + (muestra.length > 0 ? 8 : 0)
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
