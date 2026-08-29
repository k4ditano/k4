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

    //  Y los datos vivos del sistema, que los plugins leen a través de sus
    //  envoltorios (K4.Audio, K4.Medios…). Van uno a uno y no como un saco:
    //  así se ve de un vistazo qué le presta el host a la API, y añadir algo
    //  es una decisión y no un descuido.
    property var audio: null
    property var medios: null
    property var notificaciones: null
    property var wifi: null
    property var bluetooth: null
    property var escritorios: null
    property var portapapeles: null
    property var reloj: null

    //  El registro donde los plugins se apuntan para salir en sitios de la
    //  barra que no son suyos, y el estado de la island.
    property var enganches: null
    property var isla: null

    //  Las dos piezas de «la píldora también es de los plugins»: las
    //  extensiones de flanco (K4.Capsula) y el submapa de Hyprland
    //  (K4.Submapas). La primera es un registro; el segundo, dato vivo.
    property var extensiones: null
    property var submapas: null

    //  La huella: datos personales agregados, con doble llave.
    property var huella: null

    //  Qué terminal hay instalada y dónde conviene correr las cosas. Lo sabe
    //  el servicio, y sin esto un plugin tendría que adivinarlo.
    property var consola: null
}
