pragma Singleton

//  Traducción, para plugins de fuera.
//
//  `t()` busca el texto en el diccionario cargado y, si no está, devuelve el
//  texto tal cual. Eso es lo que hace que un plugin de fuera funcione sin
//  traer traducciones: sus cadenas salen en el idioma en que las escribió su
//  autor, y si algún día se añaden al diccionario, se traducen sin tocarlo.
//
//      K4.Etiqueta { text: K4.Idioma.t("Récord") }
//      K4.Etiqueta { text: K4.Idioma.f("Quedan %1", n) }

import QtQuick
import "../../services" as Servicios

QtObject {
    function t(texto) { return Servicios.Idioma.t(texto) }
    function f(texto, a, b) { return Servicios.Idioma.f(texto, a, b) }

    //  El código del idioma en uso ("es", "en"…), por si un plugin trae sus
    //  propias tablas y quiere elegir él.
    readonly property string codigo: Servicios.Idioma.codigo
}
