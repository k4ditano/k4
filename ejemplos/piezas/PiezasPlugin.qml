//  El muestrario de las piezas visuales de la API.
//
//  Sirve de dos cosas: de catálogo para quien escribe un plugin y de prueba de
//  que todas siguen funcionando —si una se rompe, se ve aquí—. Y de paso
//  demuestra lo que importa: un plugin de FUERA puede tener exactamente la
//  misma cara que la barra sin dibujar ni un rectángulo a mano.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "piezas"
    title: "Piezas"
    priority: 64
    active: abierto
    islandWidth: 480
    islandHeight: 560

    property bool abierto: false

    //  El estado que mueven las piezas, para que se vea que responden.
    property bool encendido: true
    property real nivel: 40
    property bool baldosaActiva: false
    property int pulsaciones: 0

    view: Component { PiezasView { plugin: self } }

    K4.Ipc {
        target: "k4.piezas"
        function toggle(): void { self.abierto = !self.abierto }
        function close(): void { self.abierto = false }
        function estado(): string {
            return JSON.stringify({ encendido: self.encendido,
                                    nivel: self.nivel,
                                    baldosa: self.baldosaActiva,
                                    pulsaciones: self.pulsaciones })
        }
    }
}
