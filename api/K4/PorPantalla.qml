//  Una copia de lo que sea por cada pantalla.
//
//  Con dos monitores casi nada quiere existir una sola vez: una superficie a
//  pantalla completa tiene que estar en las dos, y cada copia sabe en cuál
//  está. Reexporta `Variants` con el modelo ya puesto, que es el 100 % de los
//  casos.
//
//      K4.PorPantalla {
//          delegate: K4.Ventana { required property var modelData; screen: modelData }
//      }

import Quickshell

Variants {
    model: Quickshell.screens
}
