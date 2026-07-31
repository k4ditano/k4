//  Capa fina sobre K4.Boton — ver core/IconGlyph.qml. Solo traduce nombres.

import K4 as K4

K4.Boton {
    id: control

    property alias glyph: control.glifo
    property alias glyphSize: control.tamano
    property alias glyphColor: control.color
    property alias enabledAction: control.activo
    signal activated()

    onPulsado: control.activated()
}
