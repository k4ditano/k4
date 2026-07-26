//  Juego idle en la island.
//
//  Toda la simulación vive en services/Game.qml; esto es la vista y poco más.
//  A diferencia del resto de módulos NO se cierra al sacar el ratón: aquí se
//  está clicando, y cerrarse solo a mitad de una pelea sería insufrible.

import QtQuick
import Quickshell.Io
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "game"
    title: "Mazmorra"
    priority: 64
    active: open

    property bool open: false

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    islandWidth: 720
    islandHeight: 420

    handlesBackgroundTap: true
    onBackgroundTapped: {}      // el fondo no cierra: se juega aquí dentro

    // se queda abierto hasta que lo cierres tú
    closeOnHoverExit: false

    function toggle() {
        open = !open
        if (open) {
            if (panel) panel.close()
            Notifs.dismissToast()
        }
    }

    function close() { open = false }

    IpcHandler {
        target: "k4.game"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }

        // Golpear sin ratón: se puede atar a una tecla y jugar sin apuntar.
        function golpear(): void { Game.golpear() }

        // Para afinar el balance sin pasarse horas clicando: adelanta el reloj
        // del juego los segundos que le digas y aplica el progreso pasivo.
        function adelantar(segundos: int): void {
            const r = Game.recuperarOffline(Game.ahora() - segundos)
            console.log("adelantar " + segundos + "s →",
                        r ? (Game.cifra(r.oro) + " de oro, " + r.muertes + " muertes")
                          : "sin progreso (dps 0)")
        }

        function estado(): void {
            console.log("zona " + Game.zona + " · oro " + Game.cifra(Game.oro)
                + " · golpe " + Game.cifra(Game.dañoGolpe)
                + " · dps " + Game.cifra(Game.dps)
                + " · niveles a" + Game.niveles.ataque
                + " y" + Game.niveles.ayudantes + " b" + Game.niveles.botin)
        }
    }

    view: Component {
        GameView { plugin: self }
    }
}
