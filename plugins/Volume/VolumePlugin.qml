//  HUD de volumen. Aparece solo cuando el volumen cambia por fuera (teclas de
//  multimedia, mixer…) y se va solo; por eso va por debajo del hover.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    name: "volume"
    title: Idioma.t("Volumen")
    priority: 40
    active: habilitado && Audio.overlayOpen

    islandWidth: 240
    islandHeight: 40

    view: Component { VolumeView {} }
}
