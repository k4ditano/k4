//  Una zona que se desplaza con la rueda de verdad, aunque dentro haya cosas
//  pulsables.
//
//  Existe por una trampa que ha mordido dos veces en esta barra: un MouseArea
//  **acepta los eventos de rueda tenga o no manejador**, así que en cuanto tus
//  filas tienen hover o clic —o sea, siempre— el Flickable de fuera no ve la
//  rueda jamás. La lista solo se deja arrastrar, y el fallo no da ningún error:
//  simplemente no pasa nada, que es lo peor de encontrar.
//
//  El arreglo es la capa de abajo: un MouseArea que no escucha ningún botón y
//  por tanto no roba clics, pero sí recibe la rueda y la traduce a
//  desplazamiento. Aquí va de fábrica para que nadie más lo descubra a base de
//  no entender por qué su lista no se mueve.
//
//      K4.Rodillo {
//          anchors.fill: parent
//          Column { id: contenido; width: parent.width }
//      }

import QtQuick
import QtQuick.Controls

Flickable {
    id: rodillo

    //  Cuánto avanza cada muesca. 60 px es más o menos una fila.
    property int muesca: 60

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: width
    contentHeight: contentItem.childrenRect.height
    flickableDirection: Flickable.VerticalFlick

    //  Y el cazarruedas va en el FLICKABLE, no en el contenido.
    //
    //  Todo lo que se declara dentro de un Flickable se reparenta a su
    //  `contentItem`. Anclado a ese, este MouseArea se medía a sí mismo el
    //  `contentHeight` —que sale de `contentItem.childrenRect`, que lo
    //  incluía— y los dos se daban de comer: el recorrido solo podía subir,
    //  hasta el del contenido más alto que se hubiera enseñado, y no bajaba
    //  nunca. Cada página posterior a la más alta se quedaba con todo ese
    //  scroll muerto por debajo de su contenido de verdad. Se veía en
    //  Ajustes, que pasa TODAS las secciones por un solo Rodillo: después
    //  de abrir Grabación, las cortas seguían desplazándose en balde.
    //
    //  Reparentado aquí cubre el hueco visible, se queda quieto mientras el
    //  contenido se desplaza, y el contenido vuelve a medir solo contenido.
    MouseArea {
        parent: rodillo
        //  Debajo de todo y sordo a los botones: pasa los clics a las filas.
        z: -1
        anchors.fill: parent
        acceptedButtons: Qt.NoButton

        onWheel: function (ev) {
            const alto = rodillo.contentHeight - rodillo.height
            if (alto <= 0)
                return
            //  angleDelta viene en octavos de grado; 120 es una muesca.
            const pasos = ev.angleDelta.y / 120
            rodillo.contentY = Math.max(0, Math.min(alto,
                rodillo.contentY - pasos * rodillo.muesca))
        }
    }

    //  La barrita de la casa, de serie: sale sola cuando hay algo que
    //  recorrer y se desvanece al soltar. Quien quiera otra puede
    //  sobreescribir la adjunta, pero nadie debería tener que ponerla.
    ScrollBar.vertical: Desplazador {}
}
