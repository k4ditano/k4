pragma Singleton

//  Dónde vive cada cosa.
//
//  Un plugin no debería construir rutas a mano ni saber que existe
//  ~/.local/state: pide la que necesita y se acabó.

import QtQuick
import Quickshell

Singleton {
    readonly property string hogar: Quickshell.env("HOME") || ""

    // Estado que sobrevive a los reinicios: partidas, historiales, ajustes.
    readonly property string estado: hogar + "/.local/state/k4"

    // La carpeta del propio k4, para llegar a los guiones y a los assets.
    readonly property string raiz: Quickshell.shellPath("")

    function guion(nombre) { return Quickshell.shellPath("tools/" + nombre) }

    // Cualquier otra cosa que viva en la carpeta de k4.
    function enRaiz(relativa) { return Quickshell.shellPath(relativa) }
}
