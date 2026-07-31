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

    //  El estado PROPIO de un plugin: ~/.local/state/k4/plugins/<id>/.
    //
    //  Propio y no compartido, porque en el directorio común dos plugins con
    //  un fichero del mismo nombre se pisan sin que nadie avise. Quien guarda
    //  ahí es K4.Guardado, que además se encarga de crear el directorio.
    function estadoDe(id) { return estado + "/plugins/" + id }

    // Cualquier otra cosa que viva en la carpeta de k4.
    function enRaiz(relativa) { return Quickshell.shellPath(relativa) }
}
