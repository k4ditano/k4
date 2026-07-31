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

    //  En qué borde vive la barra: "arriba" o "abajo". Lo decide el usuario
    //  en Ajustes; léelo para saber hacia dónde asoma lo que pintes fuera.
    readonly property string posicion: _i ? (_i.posicion || "arriba") : "arriba"

    //  Dónde está la island, en coordenadas de pantalla: { x, y, ancho, alto }.
    //
    //  Para pintar FUERA de ella con una K4.Ventana —una mano que asoma por
    //  el borde, algo que se cae de la barra— anclado al píxel. Con varios
    //  monitores es la de la pantalla principal.
    readonly property var rect: (_i && _i.rect) ? _i.rect
        : ({ x: 0, y: 0, ancho: 0, alto: 0 })

    //  Dónde cae la island a lo largo de su borde, como fracción del ancho
    //  libre: 0 pegada a la izquierda, 0.5 en el centro, 1 a la derecha. La
    //  base la elige el usuario en Ajustes; esto es lo efectivo ahora mismo.
    readonly property real colocacion: _i ? _i.colocacion : 0.5

    //  Desplazarla TEMPORALMENTE a un punto del borde, animado:
    //
    //      K4.Isla.colocar("mi-juego", 0.3, 3000)   // al 30%, 3 segundos
    //      K4.Isla.colocar("mi-juego", 0.92, 0)     // al rincón, hasta...
    //      K4.Isla.soltar("mi-juego")               // ...esto
    //
    //  Vuelve sola a la base del usuario: por plazo, al soltar, o al
    //  deshabilitar tu plugin. Para lo que dura una escena —la island que
    //  esquiva, que hace de pala, que se aparta— no para quedarse: la
    //  posición permanente es del usuario y se elige en Ajustes.
    function colocar(dueno, fraccion, duracionMs) {
        if (_i && _i.colocar)
            _i.colocar(dueno, fraccion, duracionMs || 0)
    }

    function soltar(dueno) {
        if (_i && _i.soltar)
            _i.soltar(dueno)
    }

    //  La island como objeto físico: pide un gesto y el host lo anima.
    //
    //      K4.Isla.efecto("mi-juego", "sacudida")        // golpe recibido
    //      K4.Isla.efecto("mi-juego", "empujon", 0.6)    // algo pesado cae
    //      K4.Isla.efecto("mi-juego", "tiron")           // ¡pica un pez!
    //
    //  Nombres: "sacudida", "empujon", "tiron". `fuerza` 0.2..1 (1 si no se
    //  da). El host limita la cadencia —un gesto cada medio segundo— porque
    //  el efecto raro impresiona justo porque la barra es sobria: pide el
    //  gesto en el momento que importa y déjalo respirar.
    function efecto(dueno, nombre, fuerza) {
        if (_i && _i.efecto)
            _i.efecto(dueno, nombre, fuerza)
    }
}
