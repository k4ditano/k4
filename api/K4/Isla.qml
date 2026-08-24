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

    //  ¿La ve alguien AHORA MISMO?
    //
    //  No es lo mismo que `abierta`: la píldora plegada también se ve. Esto es
    //  falso cuando la island está retirada —el modo «escondida» de Ajustes—,
    //  cuando una captura o un diálogo del sistema la aparta, y en el monitor
    //  cuya barra no está enseñándose.
    //
    //  Existe para una cosa concreta: en Qt Quick una animación NO se para
    //  porque su item deje de verse, así que una que no acaba nunca tiene que
    //  preguntar. Ver docs/PLUGINS.md.
    //
    //  Sin barra detrás —una prueba con `--test`— contesta que sí, que es el
    //  defecto prudente: una animación de más se nota menos que una que no
    //  arranca.
    readonly property bool aLaVista: _i ? _i.aLaVista : true
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
    //  el borde, algo que se cae de la barra— anclado al píxel. `rect` es la
    //  de la pantalla principal; con varios monitores, `rectEn(nombre)` da
    //  la de cada una (la K4.Ventana dice su pantalla con `pantalla`).
    readonly property var rect: (_i && _i.rect) ? _i.rect
        : ({ x: 0, y: 0, ancho: 0, alto: 0 })

    //  En qué pantalla está desplegada AHORA, por nombre (los de `hyprctl
    //  monitors`). La píldora existe en todas; una vista abierta vive en una
    //  sola, y esta es esa.
    //
    //  Es lo que hay que pasarle a `pantalla` de una K4.Ventana para asomar
    //  por la island correcta. Sin esto no había forma de saberlo desde fuera:
    //  `rect` da la de la pantalla PRINCIPAL, así que con dos monitores lo que
    //  pintaras salía anclado a una island que estaba en la otra —y como las
    //  coordenadas son locales a cada monitor, ni siquiera se veía mal: se veía
    //  en otro sitio, o no se veía—.
    readonly property string pantalla: _i ? (_i.pantallaActiva || "") : ""

    function rectEn(pantalla) {
        const d = _i ? _i.rects : null
        return (d && d[pantalla]) ? d[pantalla] : rect
    }

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
