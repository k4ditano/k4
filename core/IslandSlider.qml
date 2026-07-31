//  Capa fina sobre K4.Deslizador — ver core/IconGlyph.qml. Solo traduce
//  nombres: la lógica del cuantizado y del aviso vive en la pieza de la API.

import K4 as K4

K4.Deslizador {
    id: control

    property alias label: control.etiqueta
    property alias value: control.valor
    property alias from: control.desde
    property alias to: control.hasta
    property alias step: control.paso
    property alias suffix: control.sufijo
    signal moved(real value)

    onMovido: function (v) { control.moved(v) }
}
