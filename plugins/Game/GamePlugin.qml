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
    property string pestaña: "lucha"

    // Cofre en plena ceremonia de apertura. Vive aquí y no en el panel para
    // que se pueda disparar desde fuera —y para que no se pierda al cambiar
    // de pestaña a media animación.
    property var abriendo: null
    property int tipoAbriendo: 0

    function abrirConCeremonia(tipo) {
        const salio = Game.abrirCofre(tipo)
        if (!salio)
            return
        tipoAbriendo = tipo
        abriendo = salio
        pestaña = "bolsa"
        open = true
    }

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    islandWidth: 700
    // la bolsa y el altar necesitan más alto que la pelea
    islandHeight: pestaña === "lucha" ? 300 : 380

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

        function nueva(): void { Game.nuevaPartida() }
        function pausa(): void { Game.pausada = !Game.pausada }
        function ver(cual: string): void { self.pestaña = cual; self.open = true }
        function cofre(tipo: int): void { self.abrirConCeremonia(tipo) }
        function habilidad(indice: int, id: string): void { Game.lanzar(indice, id) }

        // Para afinar el balance sin pasarse horas clicando: adelanta el reloj
        // del juego los segundos que le digas y aplica el progreso pasivo.
        function adelantar(segundos: int): void {
            const r = Game.recuperarOffline(Game.ahora() - segundos)
            console.log("adelantar " + segundos + "s →",
                        r ? (r.cofres + " cofres") : "nada (hace falta más rato)")
        }

        function estado(): void {
            const vivos = Game.grupo.filter(function (h) { return h.vida > 0 }).length
            console.log("oleada " + Game.oleada + " · oro " + Game.cifra(Game.oro)
                + " · héroes vivos " + vivos + "/" + Game.grupo.length
                + " · enemigos " + Game.enemigos.filter(function (e) { return e.vida > 0 }).length
                + " · cofres " + Game.cofres + " · récord " + Game.mejorOleada
                + " · partida " + (Game.viva ? "en curso" : "terminada"))
        }
    }

    view: Component {
        GameView { plugin: self }
    }
}
