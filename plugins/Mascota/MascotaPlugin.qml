//  La mascota en la island: cuidarla y pasear el terrario.
//
//  Toda la simulación vive en services/Mascota.qml; esto abre, cierra y
//  expone el IPC. Las reglas del juego no están aquí.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "mascota"
    title: Idioma.t("Mascota")
    priority: 64
    active: habilitado && open

    property bool open: false
    property string pestana: "cuidar"

    islandWidth: 640
    islandHeight: pestana === "terrario" ? 420 : 270

    function toggle() {
        open = !open
        if (open)
            Mascota.saludandoHasta = Date.now() / 1000 + 4
    }

    function close() { open = false }

    K4.Ipc {
        target: "k4.mascota"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
        function comer(): void { Mascota.comer() }
        function terrario(): void {
            self.pestana = "terrario"
            self.open = true
        }
    }

    view: Component { MascotaView { plugin: self } }
}
