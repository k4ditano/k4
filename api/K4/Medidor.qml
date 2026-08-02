//  Una barra que mide: el carril y lo que va lleno.
//
//  Existe porque ya se estaba copiando. El volumen, el avance de la canción,
//  lo que llevas gastado de un cupo: los tres son el mismo rectángulo dentro
//  de otro rectángulo, con la misma curva y la misma animación, y cada copia
//  se inventaba su altura y su duración. Ahora un plugin de fuera pinta una
//  igual sin dibujarla a mano —que es toda la razón de que esta carpeta
//  exista— y las de casa dejan de divergir.
//
//      K4.Medidor { valor: 0.4 }                        // de 0 a 1
//      K4.Medidor { valor: 72; maximo: 100              // …o en porcentaje
//                   tono: K4.Tema.verde; minimo: 3 }
//
//  No es un `K4.Deslizador`: aquello se toca y esto se mira. Un medidor no
//  lleva ratón a propósito —quien quiera que se pueda arrastrar tiene el
//  deslizador, y quien quiera un clic suyo le pone encima su MouseArea.

import QtQuick

Item {
    id: control

    //  Lo medido, entre 0 y `maximo`. Se recorta: un valor fuera de rango es
    //  un error de quien mide, y una barra que se sale del carril lo convierte
    //  en un error de pintado que cuesta más encontrar.
    property real valor: 0
    property real maximo: 1

    property color tono: Tema.tinta
    property color fondo: Tema.carril

    property int grosor: 4

    //  Anchura mínima de lo lleno cuando hay algo que enseñar. Con 0 —lo de
    //  siempre— un valor diminuto no se ve, que para el volumen está bien
    //  pero para un cupo recién tocado engaña: parece que no has gastado
    //  nada. Ponle 3 y el hilito aparece.
    property int minimo: 0

    //  Cuánto tarda en llegar al sitio. 0 lo pone ahí de golpe, que es lo que
    //  quiere quien pinta un medidor por frame.
    property int duracion: 260

    readonly property real fraccion: maximo > 0
        ? Math.max(0, Math.min(1, valor / maximo)) : 0

    implicitWidth: 120
    implicitHeight: grosor

    Rectangle {
        id: carril
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: control.grosor
        radius: height / 2
        color: control.fondo

        Behavior on height {
            enabled: control.duracion > 0
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Rectangle {
            width: control.fraccion <= 0 ? 0
                : Math.max(control.minimo, carril.width * control.fraccion)
            height: parent.height
            radius: parent.radius
            color: control.tono

            Behavior on width {
                enabled: control.duracion > 0
                NumberAnimation {
                    duration: control.duracion
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                enabled: control.duracion > 0
                ColorAnimation { duration: 200 }
            }
        }
    }
}
