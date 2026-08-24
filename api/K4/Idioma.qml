pragma Singleton

//  Traducción, para plugins de fuera.
//
//  `t()` busca el texto en el diccionario de la barra y, si no está, lo
//  devuelve tal cual. Eso es lo que hace que un plugin de fuera funcione sin
//  traer traducciones: sus cadenas salen como las escribió su autor, y si
//  algún día entran al diccionario, se traducen sin tocarlo.
//
//      K4.Etiqueta { text: K4.Idioma.t("Récord") }
//      K4.Etiqueta { text: K4.Idioma.f("Quedan %1", n) }

import QtQuick

QtObject {
    //  `t()` y `f()` se llaman desde bindings de plugins cargados a través
    //  del puente. La llamada al método del servicio no deja por sí sola una
    //  dependencia que QML pueda invalidar al cambiar de idioma: el menú del
    //  dock conservaba el texto con el que se había construido.
    //
    //  Estas dos propiedades son la señal reactiva del puente: `codigo`
    //  cambia al elegir otro idioma y `_tabla` vuelve a cambiar cuando termina
    //  de cargarse su JSON. Tocar ambas dentro de `t()` cubre los dos pasos.
    readonly property var _tabla: Puente.idioma ? Puente.idioma.tabla : null

    function t(texto) {
        void codigo
        void _tabla
        return Puente.idioma ? Puente.idioma.t(texto) : texto
    }

    function f(texto, a, b) {
        let s = t(texto)
        if (a !== undefined) s = s.replace("%1", a)
        if (b !== undefined) s = s.replace("%2", b)
        return s
    }

    //  El código del idioma en uso ("es", "en"…), por si un plugin trae sus
    //  propias tablas y quiere elegir él.
    readonly property string codigo: Puente.idioma ? Puente.idioma.codigo : "es"
}
