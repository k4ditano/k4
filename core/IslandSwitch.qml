//  Capa fina sobre K4.Interruptor — ver core/IconGlyph.qml. Solo traduce los
//  nombres: `checked`/`toggled` es lo que escriben los veinte de casa.

import K4 as K4

K4.Interruptor {
    id: control

    property alias checked: control.marcado
    signal toggled()

    onAlternado: control.toggled()
}
