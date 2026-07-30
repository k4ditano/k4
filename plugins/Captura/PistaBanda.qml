//  Una fila de la línea de tiempo: las capas de una banda.
//
//  Sale de `LineaTiempo` porque desde que el vídeo es la banda 1 las filas se
//  eligen con un `Loader` —clips o capas— y tener el cuerpo entero de las capas
//  metido en el delegado dejaba de leerse.
//
//  Lo que se apila es la BANDA. Dentro de una pueden convivir varias cosas, y lo
//  normal es que estén en instantes distintos: tres logos seguidos comparten
//  fila. Subir algo de banda es lo que cambia qué tapa a qué, y eso vale igual
//  para el render que para la previa.

import QtQuick
import "../../core"
import "../../services"

Pista {
    id: fila

    //  `{ banda, capas, clips }`, tal como lo arma `LineaTiempo.bandasVista`.
    required property var banda
    //  Quien manda: el cabezal, el total y a dónde saltar salen de ahí.
    required property var linea

    modelo: banda.capas
    total: linea.total
    cabezal: linea.cabezal
    tono: Theme.green

    // Una capa necesita un fichero detrás, y eso se elige, no se dibuja
    // arrastrando en un hueco.
    creable: false

    //  `Pista` elige por índice y la selección va por id, porque con varias
    //  pistas el índice no dice de qué es. Aquí se traduce.
    elegido: {
        for (let i = 0; i < banda.capas.length; ++i)
            if (Editor.tipoSel === "capa" && banda.capas[i].id === Editor.idSel)
                return i
        return -1
    }

    onSaltar: function (t) { linea.saltar(t) }

    onElegir: function (i) {
        if (i < 0 || i >= banda.capas.length)
            return
        const c = banda.capas[i]
        Editor.seleccionar("capa", c.id)
        //  Y si el cabezal está fuera de su tramo, llevarlo dentro: una capa
        //  solo se puede mover y escalar mientras se ve, así que elegirla sin
        //  poder tocarla no sirve de nada.
        if (linea.cabezal < c.t0 || linea.cabezal > c.t1)
            linea.saltar(c.t0 + Math.min(0.3, (c.t1 - c.t0) / 2))
    }

    onEditar: function (id, a, b) { Editor.fijarCapa(id, { t0: a, t1: b }) }

    //  Sacar una cosa de su capa y llevarla a otra.
    //
    //  Bajar en la LISTA es bajar de banda en el plan, y la lista va del revés,
    //  de ahí el signo menos. Arrastrar por encima de la primera fila da banda
    //  `cuantasBandas + 1`, que `ponerCapaEnBanda` acepta creando una capa
    //  nueva; y por debajo se topa en la 2, porque la 1 es del vídeo.
    porFilas: true
    pasoFila: linea.altoPista + linea.hueco
    onMoverFila: function (id, filas) {
        Editor.ponerCapaEnBanda(id, banda.banda - filas)
    }
}
