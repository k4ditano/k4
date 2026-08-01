//  K4MON en la island: el digivice. Toda la simulación vive en
//  services/Kmon.qml; esto abre, cierra y expone el IPC — incluido el
//  acelerador de tiempo para probar la crianza sin esperar un día real.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "kmon"
    title: "K4MON"
    priority: 64
    active: habilitado && open

    property bool open: false
    property string pestana: "estado"   // estado · entrenar

    islandWidth: 660
    islandHeight: 350

    function toggle() { open = !open }
    function close() { open = false }

    K4.Ipc {
        target: "k4.kmon"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
        function tocar(): void { Kmon.tocar() }
        function comer(): void { Kmon.comer() }
        function nueva(): void { Kmon.nuevaPartida() }
        //  Depuración: adelanta el reloj del juego N minutos.
        function avanzar(minutos: string): void {
            Kmon.desfase += Number(minutos) * 60
            Kmon._tic()
        }
    }

    view: Component { KmonView { plugin: self } }
}
