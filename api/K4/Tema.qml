pragma Singleton

//  La paleta y las fuentes de la barra, para plugins de fuera.
//
//  Un plugin de casa llega a `Theme` importando core/ por ruta relativa; uno
//  instalado en ~/.config/k4/plugins no tiene ese camino, y no debe tenerlo:
//  su superficie es el módulo K4 y nada más. Esto reexporta el MISMO objeto
//  —no una copia—, así que si algún día el tema es configurable, los plugins
//  de fuera lo siguen sin enterarse.
//
//      Rectangle { color: K4.Tema.superficie }
//      Text { color: K4.Tema.tinta; font.family: K4.Tema.fuente }

import QtQuick
import "../../core" as Nucleo

QtObject {
    //  Colores, con los nombres en el idioma de la API.
    readonly property color fondo: Nucleo.Theme.islandBg
    readonly property color tinta: Nucleo.Theme.ink
    readonly property color apagado: Nucleo.Theme.muted
    readonly property color tenue: Nucleo.Theme.dim
    readonly property color superficie: Nucleo.Theme.surface
    readonly property color superficieAlta: Nucleo.Theme.surfaceHi
    readonly property color carril: Nucleo.Theme.track
    readonly property color verde: Nucleo.Theme.green
    readonly property color rojo: Nucleo.Theme.red
    readonly property color azul: Nucleo.Theme.blue
    readonly property color amarillo: Nucleo.Theme.yellow

    //  Tipografías.
    readonly property string fuente: Nucleo.Theme.uiFont
    readonly property string fuenteIconos: Nucleo.Theme.iconFont

    //  Geometría que a un plugin le puede hacer falta respetar.
    readonly property int altoPlegado: Nucleo.Theme.baseHeight
    readonly property int altoMaximo: Nucleo.Theme.maxIslandHeight
}
