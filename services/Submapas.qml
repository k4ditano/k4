pragma Singleton

//  En qué submapa está Hyprland ahora mismo.
//
//  Un submapa es el teclado hablando otro idioma un rato: las teclas de la
//  captura, las de redimensionar ventanas, lo que el usuario haya declarado.
//  Hyprland lo anuncia en su socket de eventos y en ningún otro sitio, y un
//  plugin NO puede asomarse a ese socket por su cuenta: lo de plataforma baja
//  a un servicio, que es la regla que vigila tools/api.py.
//
//  Así que aquí vive el dato y el PLUGIN hace todo lo demás: cómo se enseña el
//  nombre, hacia qué lado crece la píldora y cuánto. Esto es solo la oreja —y
//  la única pregunta que los eventos no saben contestar.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: submapas

    //  El id crudo de Hyprland para el mapa activo, "" cuando no hay ninguno.
    //  «default» es la palabra que usa Hyprland para decir «ningún submapa»;
    //  cualquier otra cosa significa que hay un modo puesto.
    property string actual: ""

    Connections {
        target: Hyprland
        ignoreUnknownSignals: true
        function onRawEvent(evento) {
            if (String(evento.name || "") !== "submap")
                return
            const d = String(evento.data || "").trim()
            submapas.actual = (d.length === 0 || d === "default") ? "" : d
        }
    }

    //  El hueco que los eventos no cubren: una barra que arranca con un
    //  submapa YA puesto —una recarga en mitad de un modo— no se entera hasta
    //  el SIGUIENTE cambio. Un `hyprctl submap` al nacer, y solo si no se ha
    //  adelantado ningún evento.
    property var sondeo: Process {
        command: ["hyprctl", "submap"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (submapas.actual.length > 0)
                    return
                const d = String(this.text).trim().split("\n")[0]
                if (d.length > 0 && d !== "default" && d !== "unknown")
                    submapas.actual = d
            }
        }
    }
}
