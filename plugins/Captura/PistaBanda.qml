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

    //  Y el rótulo del bloque: de qué pista sale, cuando sale de alguna.
    //  Separar el audio deja dos bloques amarillos idénticos, y sin esto hay
    //  que ir pinchándolos para saber cuál es el micro. Se pone desde aquí
    //  porque este fichero sí conoce a `Editor`.
    etiquetaDe: function (capa) { return Editor.nombreDePista(capa) }

    //  Y el imán: al cabezal, a los bordes de los trozos, a los marcadores y a
    //  las otras capas. Ver `Editor.ajustarTiempo`.
    ajustar: function (t, id) { return Editor.ajustarTiempo(t, id) }

    //  Y la onda de los bloques que suenan: capas de audio y vídeos
    //  incrustados a los que se les ha traído el sonido.
    ondaDe: function (capa) { return Editor.ondaDe(capa) }

    //  Y si está entre lo elegido con Ctrl, para que se resalte igual que el
    //  principal: para el bloque los dos casos son «estoy elegido».
    tambienElegido: function (capa) {
        return Editor.estaSeleccionado("capa", capa.id)
    }

    //  Pinchar el hueco suelta lo elegido y devuelve la ficha a las
    //  opciones generales.
    onFondoPulsado: Editor.seleccionar("", 0)

    //  `Pista` elige por índice y la selección va por id, porque con varias
    //  pistas el índice no dice de qué es. Aquí se traduce.
    elegido: {
        for (let i = 0; i < banda.capas.length; ++i)
            if (Editor.tipoSel === "capa" && banda.capas[i].id === Editor.idSel)
                return i
        return -1
    }

    onSaltar: function (t) { linea.saltar(t) }

    //  Al soltar se apaga la guía del imán. Si se quedara encendida, la línea
    //  amarilla se clavaría donde te pegaste la última vez y parecería un
    //  marcador que nadie ha puesto.
    onSoltar: Editor.soltarIman()

    onElegir: function (i, conControl) {
        if (i < 0 || i >= banda.capas.length)
            return
        const c = banda.capas[i]
        //  Con Ctrl se SUMA a lo elegido en vez de sustituirlo, que es como se
        //  cogen varias cosas en cualquier sitio.
        if (conControl) {
            Editor.alternarEnSeleccion("capa", c.id)
            return
        }
        Editor.seleccionar("capa", c.id)
        //  Y si el cabezal está fuera de su tramo, llevarlo dentro: una capa
        //  solo se puede mover y escalar mientras se ve, así que elegirla sin
        //  poder tocarla no sirve de nada.
        if (linea.cabezal < c.t0 || linea.cabezal > c.t1)
            linea.saltar(c.t0 + Math.min(0.3, (c.t1 - c.t0) / 2))
    }

    onEditar: function (id, a, b) {
        const c = Editor.capaPorId(id)
        if (Editor.capaBloqueada(c))
            return
        const dur = Math.max(0.05, b - a)
        const na = Editor.ajustarTiempo(a, id)
        //  Lo que se ha movido de verdad, para llevarse con él a lo demás que
        //  esté elegido. Se calcula ANTES de escribir: después, `c.t0` ya sería
        //  el nuevo y el desplazamiento saldría cero.
        const delta = c ? na - c.t0 : 0
        Editor.fijarCapa(id, { t0: na, t1: Math.min(linea.total, na + dur) })
        Editor.arrastrarSeleccion(id, delta)
    }

    //  Sacar una cosa de su capa y llevarla a otra.
    //
    //  Bajar en la LISTA es bajar de banda en el plan, y la lista va del revés,
    //  de ahí el signo menos. Arrastrar por encima de la primera fila da banda
    //  `cuantasBandas + 1`, que `ponerCapaEnBanda` acepta creando una capa
    //  nueva; y por debajo se topa en la 2, porque la 1 es del vídeo.
    porFilas: true
    pasoFila: linea.altoPista + linea.hueco
    onMoverFila: function (id, filas) {
        if (Editor.bandaBloqueada(banda.banda))
            return
        Editor.ponerCapaEnBanda(id, banda.banda - filas)
    }

    //  Los rombos: mover un fotograma clave por la línea y quitarlo con el
    //  clic derecho, sin pasar por la ficha.
    onMoverClave: function (id, indice, t) { Editor.moverKeyframe(id, indice, t) }
    onQuitarClave: function (id, indice) { Editor.quitarKeyframe(id, indice) }
}
