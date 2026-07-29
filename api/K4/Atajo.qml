//  Un atajo global, de los que funcionan tenga el foco quien lo tenga.
//
//  Reexporta GlobalShortcut. El compositor es quien los reparte: aquí solo se
//  declara el nombre, y en la configuración del compositor se ata a una tecla.
//  Por eso lleva `appid` y `name`: juntos forman el identificador que allí se
//  escribe como `k4:loquesea`.

import Quickshell.Hyprland

GlobalShortcut {
    appid: "k4"
}
