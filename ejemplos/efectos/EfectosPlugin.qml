//  El escaparate de la island como escenario: teñir la barra entera, pedirle
//  gestos físicos y pintar FUERA de ella con una ventana propia.
//
//  Copia la carpeta a ~/.config/k4/plugins/efectos, enciéndelo en Ajustes y
//  `quickshell ipc -p <ruta>/shell.qml call k4.efectos toggle` lo abre.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "efectos"
    title: "Efectos"
    priority: 64
    active: abierto
    islandWidth: 620
    islandHeight: 168

    property bool abierto: false
    //  La mano vive aparte de la island: puede quedarse saludando con el
    //  módulo cerrado, que es justo lo que haría una mascota.
    property bool manoFuera: false

    view: Component { EfectosView { plugin: self } }

    //  La ventana de la mano solo existe mientras hace falta.
    property var cargadorMano: K4.Cargador {
        active: self.manoFuera
        Mano { plugin: self }
    }

    K4.Ipc {
        target: "k4.efectos"
        function toggle(): void { self.abierto = !self.abierto }
        function close(): void {
            self.abierto = false
            self.manoFuera = false
        }
        function tinte(color: string): void {
            K4.Tema.tintar("efectos", color, 0.35, 4000)
        }
        function gesto(nombre: string): void {
            K4.Isla.efecto("efectos", nombre)
        }
        function mano(): void { self.manoFuera = !self.manoFuera }
        function paseo(fraccion: string): void {
            K4.Isla.colocar("efectos", Number(fraccion), 3000)
        }
    }
}
