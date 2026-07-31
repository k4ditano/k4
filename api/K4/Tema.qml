pragma Singleton

//  La paleta y las fuentes de la barra, para plugins de fuera.
//
//  Reexporta el MISMO objeto del tema —no una copia— a través del Puente: si
//  algún día el tema es configurable, los plugins de fuera lo siguen sin
//  enterarse. Los fallbacks existen para que la API cargue sola en pruebas;
//  con la barra delante nunca se usan.
//
//      Rectangle { color: K4.Tema.superficie }
//      Text { color: K4.Tema.tinta; font.family: K4.Tema.fuente }

import QtQuick

QtObject {
    readonly property var _t: Puente.tema

    //  Colores, con los nombres en el idioma de la API.
    readonly property color fondo: _t ? _t.islandBg : "#000000"
    readonly property color tinta: _t ? _t.ink : "#ffffff"
    readonly property color apagado: _t ? _t.muted : "#8e8e93"
    readonly property color tenue: _t ? _t.dim : "#48484a"
    readonly property color superficie: _t ? _t.surface : "#1c1c1e"
    readonly property color superficieAlta: _t ? _t.surfaceHi : "#2c2c2e"
    readonly property color carril: _t ? _t.track : "#3a3a3c"
    readonly property color verde: _t ? _t.green : "#30d158"
    readonly property color rojo: _t ? _t.red : "#ff453a"
    readonly property color azul: _t ? _t.blue : "#0a84ff"
    readonly property color amarillo: _t ? _t.yellow : "#ffd60a"

    //  Tipografías.
    readonly property string fuente: _t ? _t.uiFont : "Adwaita Sans"
    readonly property string fuenteIconos: _t ? _t.iconFont
                                              : "MesloLGS Nerd Font"

    //  Geometría que a un plugin le puede hacer falta respetar.
    readonly property int altoPlegado: _t ? _t.baseHeight : 34
    readonly property int altoMaximo: _t ? _t.maxIslandHeight : 880

    // ── tinte ─────────────────────────────────────────────────────
    //
    //  El ambiente de la barra, prestado: tiñe el andamio neutro —island,
    //  superficies, carriles— y todo lo que pinta con el tema se recolorea
    //  solo. La tinta y los colores con significado no se tocan, la fuerza
    //  se recorta en el host, y al deshabilitar tu plugin se destiñe solo.
    //
    //      K4.Tema.tintar("mi-juego", "#2e5c3a", 0.3, 4000)   // 4 s
    //      K4.Tema.tintar("mi-juego", "#5c2e2e", 0.35, 0)     // hasta...
    //      K4.Tema.destintar("mi-juego")                       // ...esto
    //
    //  Última llamada gana. `fuerza` 0..0.45; `duracionMs` 0 = sin plazo.
    readonly property string tinteDueno: _t ? _t.tinteDueno : ""

    function tintar(dueno, color, fuerza, duracionMs) {
        if (_t)
            _t.tintar(dueno, color, fuerza, duracionMs || 0)
    }

    function destintar(dueno) {
        if (_t)
            _t.destintar(dueno)
    }
}
