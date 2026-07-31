pragma Singleton

//  El puente entre la API y la barra que la aloja.
//
//  La regla que lo hace necesario: **un fichero de este módulo no puede
//  importar la barra por ruta relativa.** El módulo K4 se resuelve por
//  file:// para todo el mundo, y un import relativo desde aquí carga una
//  SEGUNDA copia de services/ y core/ — con su propio PluginManager, su
//  segunda oleada de creación y cada target de IPC registrado dos veces.
//  Pasó, costó una tarde encontrarlo, y este fichero es la vacuna.
//
//  Así que la API no importa: el host le INYECTA aquí lo que necesita, al
//  arrancar (shell.qml). Todo lo de este módulo que hable con la barra lo
//  hace a través de este objeto, con un fallback digno para cuando esté
//  vacío — que solo pasa en pruebas o si alguien carga la API suelta.
import QtQuick

QtObject {
    //  El Theme de core/: colores, fuentes, geometría.
    property var tema: null
    //  El servicio de traducción: t(), f(), codigo.
    property var idioma: null
    //  El servicio de indicadores de la píldora.
    property var indicadores: null
}
