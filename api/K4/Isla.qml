pragma Singleton

//  El estado de la island: si está abierta, quién la ocupa y cuánto sitio hay.
//
//  Solo lectura, y a propósito. Quién ocupa la island lo decide el host con
//  las prioridades de cada plugin —es la única forma de que dos plugins no se
//  peleen por la pantalla—; tú lo pides con `active` en tu K4.Plugin y aquí
//  ves qué ha pasado. Sirve para no hacer trabajo que nadie va a ver: si tu
//  plugin no tiene la island, no animes, no sondees, no pintes.

import QtQuick

QtObject {
    readonly property var _i: Puente.isla

    readonly property bool abierta: _i ? _i.abierta : false
    //  El ratón encima de la píldora: la barra se abre sola al pasar.
    readonly property bool raton: _i ? _i.hovered : false
    //  El `name` del plugin que la tiene ahora, "" si no la tiene nadie.
    readonly property string ocupadaPor: _i ? (_i.ocupante || "") : ""

    //  Lo que como mucho puedes pedir, para no declarar un alto imposible.
    readonly property int altoMaximo: Tema.altoMaximo
}
