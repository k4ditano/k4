pragma Singleton

//  Lo suelto: lanzar cosas, mirar el entorno, encontrar iconos.
//
//  Todo lo que en Quickshell son funciones sueltas del objeto global, aquí
//  agrupado para que un plugin no tenga que importarlo.

import QtQuick
import Quickshell

Singleton {
    //  Las marcas con las que un agente señala a sus hijos.
    //
    //  Una barra reiniciada desde dentro de una sesión de Claude —que es como
    //  se reinicia mientras se trabaja con un agente— las hereda y ya no las
    //  suelta: se las pasa a cada terminal y a cada aplicación que abre. Y un
    //  `claude` que las ve se toma por sesión hija; una sesión hija no escribe
    //  su transcripción, así que el historial deja de guardarse y `/resume` no
    //  lista nada. Pasó, y desde fuera parecía un fallo de Claude Code.
    //
    //  La barra no es una subshell de nadie: lo que lanza empieza de cero.
    readonly property var marcasDeAgente: [
        "CLAUDECODE",
        "CLAUDE_CODE_CHILD_SESSION",
        "CLAUDE_CODE_SESSION_ID",
        "CLAUDE_CODE_ENTRYPOINT",
        "CLAUDE_CODE_EXECPATH",
        "CLAUDE_PID",
        "CLAUDE_EFFORT",
        "AI_AGENT"
    ]

    //  Solo se envuelve si esta barra las lleva puestas: en un arranque normal
    //  el mandato sale exactamente como venía.
    function sinMarcas(orden) {
        const fuera = []
        for (let i = 0; i < marcasDeAgente.length; i++)
            if (Quickshell.env(marcasDeAgente[i]))
                fuera.push("-u", marcasDeAgente[i])

        return fuera.length > 0 ? ["env"].concat(fuera).concat(orden) : orden
    }

    // Lanzar y olvidarse. Para lo que no hace falta escuchar: abrir una
    // carpeta, copiar algo, avisar.
    function lanzar(orden) { Quickshell.execDetached(sinMarcas(orden)) }

    function entorno(nombre) { return Quickshell.env(nombre) || "" }

    // El icono de una aplicación, buscado por su nombre.
    function icono(nombre) { return Quickshell.iconPath(nombre, true) || "" }

    // Abrir con lo que el escritorio tenga puesto para ese tipo de fichero.
    function abrir(ruta) {
        if (ruta && String(ruta).length > 0)
            lanzar(["xdg-open", String(ruta)])
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
