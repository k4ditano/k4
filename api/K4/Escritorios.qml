pragma Singleton

//  Los escritorios de Hyprland: cuáles hay y en cuál estás.
//
//  Da para un paginador propio, un indicador distinto al de la píldora, o un
//  plugin que cambie de comportamiento según dónde estés. Cambiar de
//  escritorio no está aquí: para eso está `K4.Process` con `hyprctl`, que es
//  explícito y pide el permiso `procesos`.

import QtQuick

QtObject {
    readonly property var _e: Puente.escritorios

    //  Cada uno tal cual lo da Hyprland: `{ id, name, … }`.
    readonly property var lista: _e ? _e.list : []
    readonly property int activo: _e ? _e.activo : 0

    //  ¿Lo que se ve en esa pantalla ocupa todo? Por nombre de monitor —el
    //  mismo que trae `K4.Isla.rects` o el que le toca a una `K4.Ventana`—,
    //  para que un plugin pueda quitarse de en medio cuando estorbe.
    function lleno(pantalla) { return _e ? _e.lleno(pantalla) : false }
}
