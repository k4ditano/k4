//  Banco de pruebas del balance.
//
//  Carga el servicio de juego de verdad —no una copia de las fórmulas, que se
//  desincroniza al primer cambio— y le da miles de tics seguidos para ver por
//  dónde se rompe la curva: cuánto se tarda en matar, cuánto daño entra de
//  verdad, en qué oleada se atasca.
//
//  Se ejecuta con un HOME temporal para no tocar tu partida:
//
//      HOME=$(mktemp -d) quickshell -p tools/banco-balance.qml
//
//  Sale por stderr una tabla por oleadas y un resumen. Cambia `hasta` para
//  llegar más lejos.

import QtQuick
import Quickshell
import "../services"

ShellRoot {
    id: banco

    readonly property int hasta: 260             // hasta qué oleada mirar
    readonly property int topeSegundos: 400000   // freno por si se atasca

    property real reloj: 0
    property int ultimaOleada: 0
    property real inicioOleada: 0

    // lo que entra de verdad frente a lo que absorbe el escudo
    property real dañoALaVida: 0
    property real dañoAlEscudo: 0

    Connections {
        target: Game
        function onHeroeHerido(i, cantidad) { banco.dañoALaVida += cantidad }
    }

    function nivelDe(clase) {
        const h = Game.heroes[clase]
        return h ? h.nivel : 1
    }

    function escudoTotal() {
        let t = 0
        for (let i = 0; i < Game.grupo.length; ++i)
            t += Game.grupo[i].escudo || 0
        return t
    }

    function vidaPorcentaje() {
        let v = 0, m = 0
        for (let i = 0; i < Game.grupo.length; ++i) {
            v += Math.max(0, Game.grupo[i].vida)
            m += Game.vidaMaxDe(Game.grupo[i])
        }
        return m > 0 ? v / m * 100 : 0
    }

    function correr() {
        // Nada de poner el juego en pausa: tic() se sale antes de hacer nada
        // si `pausada` esta puesto. Tampoco hace falta, porque este bucle es
        // sincrono y no deja correr al reloj del servicio mientras dura.
        console.warn("oleada  seg/oleada  nivel  vida%   escudo      "
            + "vidaEnemigo   dañoEnemigo   muertes")

        for (let paso = 0; paso < topeSegundos; ++paso) {
            if (!Game.viva) {
                console.warn("· muere en la oleada " + Game.oleada
                    + " a los " + Math.round(reloj) + " s")
                Game.nuevaPartida()
            }

            Game.tic(1)
            reloj += 1

            if (Game.oleada !== ultimaOleada) {
                const dur = reloj - inicioOleada
                if (ultimaOleada > 0 && ultimaOleada % 10 === 0) {
                    const e = Game.enemigos[0] || ({})
                    console.warn(
                        pad(ultimaOleada, 6) + pad(dur.toFixed(1), 11)
                        + pad(nivelDe("tanque"), 7) + pad(vidaPorcentaje().toFixed(0), 7)
                        + pad(Game.cifra(escudoTotal()), 12)
                        + pad(Game.cifra(e.vidaMax || 0), 14)
                        + pad(Game.cifra(e.daño || 0), 14)
                        + pad(Game.cuentas.muertes, 9))
                }
                ultimaOleada = Game.oleada
                inicioOleada = reloj

                if (Game.oleada > hasta)
                    break
            }
        }

        console.warn("")
        console.warn("resumen: oleada " + Game.oleada + " en " + Math.round(reloj / 60)
            + " min de combate · nivel " + nivelDe("tanque")
            + " · bolsa " + Game.bolsa.length + " piezas"
            + " · cofres " + Game.cofres)
        console.warn("daño recibido en la vida: " + Game.cifra(dañoALaVida))

        Qt.exit(0)
    }

    function pad(v, n) {
        let s = String(v)
        while (s.length < n) s = s + " "
        return s
    }

    // El servicio carga la partida de forma asíncrona: hay que esperarla.
    Timer {
        interval: 150
        repeat: true
        running: true
        onTriggered: {
            if (!Game.cargado)
                return
            running = false
            banco.correr()
        }
    }
}
