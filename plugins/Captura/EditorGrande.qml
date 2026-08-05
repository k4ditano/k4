//  El editor en grande, en su propia ventana.
//
//  No es la island estirada, y a propósito: la island reserva 34 px de zona
//  exclusiva y redimensionarla cuesta un ciclo configure/ack del compositor
//  —por eso ya parpadeaba—, y con media pantalla eso se nota. Esto es una
//  superficie aparte que se limita a parecerse: mismas esquinas, mismo negro.
//
//  Comparte cuerpo con el editor de la island, así que lo que se arregle en
//  uno vale para los dos.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4.Ventana {
    id: ventana

    nombre: "k4-editor"

    //  El teclado en exclusiva mientras está delante: aquí se usan el espacio,
    //  las flechas y Supr, y sin esto se los quedaría la ventana de debajo.
    conTeclado: true

    //  Solo el panel captura clics: lo de fuera sigue siendo utilizable
    //  mientras editas, que es la diferencia entre una ventana y un modal.
    zonaActiva: panel

    Rectangle {
        id: panel
        anchors.centerIn: parent

        //  Tamaño: lo más grande que quepa dejando aire, con tope para que en
        //  un monitor enorme no acabe siendo incómodo.
        //
        //  Más ALTO que antes —0,70 del ancho en vez de 0,62, y menos aire
        //  arriba y abajo— porque lo que escaseaba era el alto: la previa se
        //  llevaba la ventana y las bandas se quedaban en una tira que había que
        //  desplazar. Un editor de vídeo se pasa el rato mirando abajo.
        width: Math.min(1680, parent.width - 160)
        height: Math.min(parent.height - 90, Math.round(width * 0.70))

        radius: 32
        color: Theme.islandBg

        // El mismo borde tenue que la island, para que se reconozca como suya.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.07)
        }

        CuerpoEditor {
            anchors.fill: parent
            anchors.margins: 6
            plugin: ventana.plugin
            enVentana: true
            onEncoger: ventana.plugin.cerrarGrande()
        }
    }

    property var plugin: null
}
