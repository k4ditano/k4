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
}
