//  El plugin mínimo: un saludo en la island.
//
//  Es el ejemplo de docs/PLUGINS.md, completo y cargable tal cual: copia la
//  carpeta a ~/.config/k4/plugins/hola, enciéndelo en Ajustes, y
//  `quickshell ipc -p <ruta>/shell.qml call k4.hola toggle` lo abre.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "hola"
    title: "Hola"
    priority: 65
    active: abierto
    islandWidth: 360
    islandHeight: 100

    property bool abierto: false
    property int visitas: 0

    view: Component { HolaView { plugin: self } }

    //  El estado propio: sobrevive a reiniciar la barra.
    property var guardado: K4.Guardado {
        plugin: "hola"
        onCargado: function (d) { self.visitas = d.visitas || 0 }
    }

    K4.Ipc {
        target: "k4.hola"
        function toggle(): void {
            self.abierto = !self.abierto
            if (self.abierto) {
                self.visitas += 1
                self.guardado.guardar({ visitas: self.visitas })
            }
        }
        function close(): void { self.abierto = false }
    }
}
