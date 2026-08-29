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
    //  Sin cazador de clics: esto sale SOLO al mover el volumen, no lo abre
    //  nadie, y se va solo. Un toque fuera no es «cierra esto» —el clic iba a
    //  otra parte— así que comérselo sería robárselo. Ver `closeOnClickOutside`
    //  en el contrato.
    closeOnClickOutside: false

    islandHeight: 40

    view: Component { VolumeView {} }
}
