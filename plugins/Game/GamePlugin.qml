//  Juego idle en la island.
//
//  Toda la simulación vive en services/Game.qml; esto es la vista y poco más.
//  A diferencia del resto de módulos NO se cierra al sacar el ratón: aquí se
//  está clicando, y cerrarse solo a mitad de una pelea sería insufrible.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "game"
    title: Idioma.t("Mazmorra")
    priority: 64
    active: habilitado && open
    tecladoOpcional: open

    property bool open: false
    property string pestaña: "lucha"

    // Cofre en plena ceremonia de apertura. Vive aquí y no en el panel para
    // que se pueda disparar desde fuera —y para que no se pierda al cambiar
    // de pestaña a media animación.
    property var abriendo: null
    property int tipoAbriendo: 0

    function abrirConCeremonia(tipo) {
        const salio = Game.abrirCofre(tipo)
        if (!salio) {
            enCadena = -1
            return
        }
        tipoAbriendo = tipo
        abriendo = salio
        pestaña = "bolsa"
        open = true
    }

    // ── apertura en cadena ────────────────────────────────────────
    //  Con cuarenta cofres guardados, abrirlos de uno en uno es un peaje. En
    //  cadena van solos y con la ceremonia acelerada; se para cuando quieras o
    //  cuando se acaben los de ese tipo.
    property int enCadena: -1
    readonly property bool encadenando: enCadena >= 0

    function abrirEnCadena(tipo) {
        enCadena = tipo
        abrirConCeremonia(tipo)
    }

    function pararCadena() { enCadena = -1 }

    function seguirCadena() {
        if (enCadena < 0)
            return
        if (Game.cofresPorTipo[enCadena] <= 0) {
            enCadena = -1
            return
        }
        // un respiro entre uno y otro, o se solapan las animaciones
        relevoCofre.restart()
    }

    Timer {
        id: relevoCofre
        interval: 120
        onTriggered: if (self.enCadena >= 0) self.abrirConCeremonia(self.enCadena)
    }

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    // Ancho pensado para la cabecera, que es lo que manda: seis pestañas, el
    // título, dos contadores y dos botones. Con 700 se salía por la derecha.
    islandWidth: 820

    // A quien has pulsado en el campo: la ficha del grupo lo resalta para que
    // no tengas que buscarlo entre los tres.
    property string heroeElegido: ""

    function verHeroe(clase) {
        heroeElegido = clase
        pestaña = "grupo"
    }
    // la bolsa y el altar necesitan más alto que la pelea
    islandHeight: pestaña === "lucha" ? 300 : 380

    handlesBackgroundTap: true
    onBackgroundTapped: {}      // el fondo no cierra: se juega aquí dentro

    // se queda abierto hasta que lo cierres tú
    closeOnHoverExit: false

    function toggle() {
        // apagada no se abre: el interruptor de Ajustes manda
        if (!Settings.juegoActivo && !open)
            return

        open = !open
        if (open) {
            if (panel) panel.close()
            Notifs.dismissToast()
        }
    }

    // y si la apagas con el tablero delante, se cierra en vez de quedarse
    // colgado ocupando la island
    Connections {
        target: Settings
        function onJuegoActivoChanged() {
            if (!Settings.juegoActivo && self.open)
                self.close()
        }
    }

    function close() {
        // Con una tanda de cofres en marcha, el primer ESC la corta y el
        // segundo cierra: cerrar de golpe dejaría la cadena viva por detrás.
        if (enCadena >= 0) {
            pararCadena()
            return
        }
        open = false
    }

    K4.Ipc {
        target: "k4.game"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }

        function nueva(): void { Game.nuevaPartida() }
        function pausa(): void { Game.pausada = !Game.pausada }
        function ver(cual: string): void { self.pestaña = cual; self.open = true }
        function cofre(tipo: int): void { self.abrirConCeremonia(tipo) }
        function cadena(tipo: int): void { self.abrirEnCadena(tipo) }
        function parar(): void { self.pararCadena() }
        function limpiar(): void { Game.desguazarSobrantes() }
        function mover(desde: int, hasta: int): void { Game.moverEnBolsa(desde, hasta) }
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
