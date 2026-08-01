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

    MouseArea {
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
