pragma Singleton

//  Lo suelto: lanzar cosas, mirar el entorno, encontrar iconos.
//
//  Todo lo que en Quickshell son funciones sueltas del objeto global, aquí
//  agrupado para que un plugin no tenga que importarlo.

import QtQuick
import Quickshell

Singleton {
    // Lanzar y olvidarse. Para lo que no hace falta escuchar: abrir una
    // carpeta, copiar algo, avisar.
    function lanzar(orden) { Quickshell.execDetached(orden) }

    function entorno(nombre) { return Quickshell.env(nombre) || "" }

    // El icono de una aplicación, buscado por su nombre.
    function icono(nombre) { return Quickshell.iconPath(nombre, true) || "" }

    // Abrir con lo que el escritorio tenga puesto para ese tipo de fichero.
    function abrir(ruta) {
        if (ruta && String(ruta).length > 0)
            Quickshell.execDetached(["xdg-open", String(ruta)])
    }

    // Un aviso del sistema. Sale aunque la barra esté cerrada, que es
    // justamente para lo que sirve.
    function avisar(titulo, detalle, urgente) {
        const orden = ["notify-send", "-a", "k4"]
        if (urgente === true)
            orden.push("-u", "critical")
        orden.push(String(titulo || ""))
        if (detalle !== undefined && String(detalle).length > 0)
            orden.push(String(detalle))
        Quickshell.execDetached(orden)
    }

    // Al portapapeles. El tipo explícito no sobra: sin él una imagen pegada en
    // otra aplicación se degrada a lo que el portapapeles decida.
    function copiar(texto) {
        Quickshell.execDetached(["wl-copy", "--", String(texto)])
    }

    function copiarImagen(ruta) {
        Quickshell.execDetached(["sh", "-c",
            "wl-copy -t image/png < " + entrecomillar(ruta)])
    }

    // Comillas al estilo del shell, doblando las que vengan dentro. Lo único
    // que separa una ruta con espacios de un mandato roto.
    function entrecomillar(s) {
        return "'" + String(s).split("'").join("'\\''") + "'"
    }
}
