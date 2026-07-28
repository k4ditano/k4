//  Lleva el cursor al campo de texto en cuanto se abre un módulo.
//
//  Parece que debería bastar con `focus: true` en el campo, y no basta, por dos
//  cosas que se suman. Una: la raíz de la island también pide foco —es donde
//  vive el ESC que cierra cualquier módulo—, así que se lo queda ella. Y dos:
//  la superficie de capa no tiene el foco del teclado en el instante en que se
//  crea; se lo da el compositor un poco después, y hasta entonces pedirlo no
//  sirve de nada.
//
//  De ahí que se insista en vez de pedirlo una vez: se reintenta cada poco
//  hasta que el campo conteste que sí lo tiene, o hasta rendirse. Sin esto hay
//  que hacer clic antes de escribir, que en un buscador que abres con un atajo
//  es exactamente lo que no quieres.
//
//      FocoInicial { id: foco; objetivo: entrada }
//      Component.onCompleted: foco.reclamar()

import QtQuick

Timer {
    id: caza

    // El campo que tiene que acabar con el cursor.
    required property Item objetivo

    property int intentos: 0
    readonly property int tope: 6

    interval: 140
    repeat: false

    function reclamar() {
        intentos = 0
        objetivo.forceActiveFocus()
        restart()
    }

    onTriggered: {
        // Si el módulo se cerró mientras tanto, no hay a quién dárselo.
        if (!objetivo.visible)
            return

        objetivo.forceActiveFocus()
        if (!objetivo.activeFocus && intentos < tope) {
            intentos += 1
            restart()
        }
    }
}
