//  La barra de desplazamiento de la casa, para plugins.
//
//  Fina, redondeada, del tono tenue de la island, sin surco pintado —sobre el
//  fondo oscuro un carril permanente es una raya que no dice nada— y que se
//  desvanece sola al medio segundo de soltar, aunque su zona de agarre sigue
//  ahí para ir a por ella. Es LA MISMA barra que usa la barra entera: un
//  plugin que la ponga queda vestido igual que el resto sin dibujar nada.
//
//      ListView {
//          ScrollBar.vertical: K4.Desplazador {}
//      }
//
//  Con `K4.Rodillo` no hace falta ni eso: la trae puesta.

import QtQuick
import QtQuick.Controls

ScrollBar {
    id: barra

    policy: ScrollBar.AsNeeded
    minimumSize: 0.08

    //  Fina de fábrica y un pelo más ancha bajo el ratón, que agarrar tres
    //  píxeles es pedir puntería.
    implicitWidth: 10
    implicitHeight: 10

    contentItem: Rectangle {
        implicitWidth: barra.hovered || barra.pressed ? 6 : 3
        implicitHeight: implicitWidth
        radius: width / 2
        color: barra.pressed ? Qt.rgba(1, 1, 1, 0.5)
             : barra.hovered ? Qt.rgba(1, 1, 1, 0.35)
                             : Qt.rgba(1, 1, 1, 0.22)

        Behavior on implicitWidth { NumberAnimation { duration: 100 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        //  Visible mientras hay movimiento o intención, y fuera después. La
        //  opacidad va aquí y no en la barra entera: la zona de agarre sigue
        //  existiendo aunque no se vea, que es lo que permite ir a por ella.
        opacity: barra.active || barra.hovered || barra.pressed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    background: null
}
