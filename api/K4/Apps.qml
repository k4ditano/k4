pragma Singleton

//  Las aplicaciones instaladas.
//
//  Lo que el escritorio sabe de ellas: nombre, icono, orden de arranque. Un
//  plugin no debería tener que saber que esto sale de leer ficheros .desktop
//  repartidos por medio sistema.

import QtQuick
import Quickshell

Singleton {
    // [{ id, name, icon, comment, execString, ... }]
    readonly property var lista: DesktopEntries.applications.values

    readonly property int count: lista.length

    // Buscar por identificador, que es como las nombra todo el mundo.
    function porId(id) {
        const bajo = String(id).toLowerCase()
        for (let i = 0; i < lista.length; ++i)
            if (String(lista[i].id || "").toLowerCase() === bajo)
                return lista[i]
        return null
    }

    // El icono de una aplicación, ya resuelto a ruta.
    function icono(nombre) {
        return nombre && nombre.length > 0
            ? (Quickshell.iconPath(nombre, true) || "") : ""
    }
}
