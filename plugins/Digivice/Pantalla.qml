//  La pantalla del aparato.
//
//  Lo que convierte un sprite suelto en «una pantalla de Digimon» no es el
//  sprite: es la rejilla. Un LCD de puntos tiene separación entre píxeles, y
//  esa retícula finísima por encima es la mitad del trabajo de fidelidad —la
//  otra mitad es que el fondo no sea negro puro sino el verde apagado del
//  cristal—.
//
//  La rejilla va en un Canvas y no en un Repeater de rectángulos: a 4 px de
//  paso son ~2.000 celdas, y dos mil Items en una barra son dos mil Items.

import QtQuick
import K4 as K4

Item {
    id: self

    //  El cristal recorta lo suyo.
    //
    //  El brillo del plástico de ahí abajo va girado -12°, y un rectángulo
    //  girado ocupa MÁS que su caja: con 254x228 se sale unos 21 px por los
    //  lados y 24 por arriba y por abajo. Sin recortar, ese lavado blanco se
    //  derramaba fuera del cristal por encima de la fila de iconos y llegaba
    //  casi al borde de la carcasa: un cuadrilátero pálido y torcido cruzando
    //  el aparato entero, que era justo lo contrario de un reflejo. Un reflejo
    //  está EN el cristal o no está.
    clip: true

    //  Lo que se pinta dentro, en coordenadas de la pantalla.
    default property alias contenido: lienzo.data

    property color tinte: "#0d1f14"
    property int paso: 4
    property bool encendida: true

    Rectangle {
        anchors.fill: parent
        radius: 3
        color: self.tinte

        //  El cristal: un poco más claro por arriba, como cualquier LCD con
        //  luz por encima.
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(self.tinte, 1.45) }
            GradientStop { position: 0.35; color: self.tinte }
            GradientStop { position: 1.0; color: Qt.darker(self.tinte, 1.25) }
        }
    }

    //  La retícula, DEBAJO del contenido.
    //
    //  Estaba encima de todo, y con un paso de 4 px sobre letras de 9 y 10
    //  cortaba cada trazo: una línea horizontal caía justo a la altura de la
    //  equis y «Lo de siempre» se leía a duras penas. La fidelidad de un LCD
    //  no compensa no poder leer lo que pone.
    //
    //  Debajo sigue haciendo su trabajo —textura el cristal y el paisaje— y
    //  encima queda solo un susurro, lo justo para que la superficie no sea
    //  un rectángulo liso.
    Canvas {
        anchors.fill: parent
        opacity: 0.30

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = Qt.darker(self.tinte, 1.7)
            ctx.lineWidth = 1
            ctx.beginPath()
            for (let x = 0.5; x < width; x += self.paso) {
                ctx.moveTo(x, 0)
                ctx.lineTo(x, height)
            }
            for (let y = 0.5; y < height; y += self.paso) {
                ctx.moveTo(0, y)
                ctx.lineTo(width, y)
            }
            ctx.stroke()
        }

        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    Item {
        id: lienzo
        anchors.fill: parent
        anchors.margins: 4
        clip: true
        opacity: self.encendida ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    //  El susurro de retícula por encima: al 8 % una línea oscura sobre una
    //  letra clara la apaga un 8 %, que no se nota en el texto pero sí en los
    //  claros del fondo. Es lo que salva el aire de cristal sin cobrar
    //  legibilidad.
    Canvas {
        anchors.fill: parent
        opacity: 0.08

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = Qt.darker(self.tinte, 2.0)
            ctx.lineWidth = 1
            ctx.beginPath()
            for (let x = 0.5; x < width; x += self.paso) {
                ctx.moveTo(x, 0)
                ctx.lineTo(x, height)
            }
            for (let y = 0.5; y < height; y += self.paso) {
                ctx.moveTo(0, y)
                ctx.lineTo(width, y)
            }
            ctx.stroke()
        }

        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    //  Un brillo diagonal muy tenue: el reflejo del plástico. Sin esto la
    //  pantalla se lee como un rectángulo de color y no como un cristal.
    //
    //  Y la gracia está en que NO se le vea el borde. Antes era un rectángulo
    //  del tamaño del cristal, girado y con el blanco pegado a su lado de
    //  arriba: recortado o sin recortar, lo que se veía era el canto del
    //  rectángulo cruzando la pantalla en diagonal —un cuadrilátero pálido y
    //  torcido, no un reflejo—.
    //
    //  Ahora mide el doble por los cuatro costados, así que sus cantos caen
    //  fuera de lo que el cristal recorta, y el blanco vive en mitad de la
    //  franja con transparente a los dos lados. Lo único que queda dentro es
    //  la parte suave: una veladura que aparece y se va sin que se sepa dónde
    //  empieza.
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 2
        height: parent.height * 2
        opacity: 0.05
        rotation: -12
        gradient: Gradient {
            GradientStop { position: 0.22; color: "transparent" }
            GradientStop { position: 0.40; color: "white" }
            GradientStop { position: 0.60; color: "transparent" }
        }
    }

    //  El marco hundido.
    Rectangle {
        anchors.fill: parent
        radius: 3
        color: "transparent"
        border.width: 1
        border.color: Qt.darker(self.tinte, 2.2)
    }
}
