//  La miniatura EN VIVO de una ventana abierta.
//
//  Lo que se ve dentro de otra ventana, pintado aquí y actualizándose solo. Lo
//  quiere un selector de ventanas, un Alt+Tab, una vista previa al pasar el
//  ratón: sitios donde el título no basta para saber cuál es cuál —tres
//  terminales se llaman igual y no se parecen en nada—.
//
//      K4.Miniatura {
//          width: 160; height: 100
//          direccion: "0x5622613de2c0"      // la de `hyprctl clients`
//      }
//
//  Se le da la DIRECCIÓN de la ventana, no el objeto: un plugin no puede
//  hablar con el compositor —eso se toca desde un servicio— pero sí tiene la
//  dirección, que es lo que devuelve `hyprctl` y lo que ya se usa para ir a una
//  ventana. Aquí dentro se busca a quién pertenece y se engancha.
//
//  Si la ventana no existe, o se cierra mientras se mira, no pinta nada. No se
//  avisa de eso a propósito: quien la enseña ya sabe qué ventanas tiene, y una
//  miniatura que grita cuando su ventana se va es más molesta que un hueco.

import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland

ScreencopyView {
    id: self

    //  La dirección tal cual viene de Hyprland, con su `0x` delante.
    property string direccion: ""

    //  Se compara con `lastIpcObject.address` —que trae el `0x`— y, si no lo
    //  hubiera, con `address` poniéndoselo. Son la misma dirección escrita de
    //  dos maneras, y elegir solo una fallaba a ratos.
    captureSource: {
        if (self.direccion.length === 0)
            return null
        const lista = Hyprland.toplevels.values
        for (let i = 0; i < lista.length; ++i) {
            const t = lista[i]
            const d = (t.lastIpcObject && t.lastIpcObject.address)
                ? String(t.lastIpcObject.address)
                : (t.address ? "0x" + t.address : "")
            if (d === self.direccion)
                return t.wayland || null
        }
        return null
    }

    //  Viva: lo que se enseña es la ventana AHORA, no una foto de cuando se
    //  abrió el selector. Una miniatura congelada engaña más que informa.
    live: true
}
