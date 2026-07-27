pragma Singleton

//  Logros: metas largas que sobreviven a muchas partidas.
//
//  Van en familias escalonadas —cazador I a V, explorador I a V…— porque una
//  lista de metas sueltas se agota en una tarde. Cada escalón multiplica la
//  meta anterior, así que siempre queda uno lejos al que apuntar.
//
//  Lo conseguido se guarda con la partida; el progreso se lee de las cuentas
//  que lleva el propio juego.

import QtQuick
import Quickshell

Singleton {
    id: logros

    readonly property var definicion: [
        { id: "cazador1", nombre: "Cazador I", desc: "Derrota 100 monstruos",
          tipo: "muertes", meta: 100, reliquias: 40, cofre: -1 },
        { id: "cazador2", nombre: "Cazador II", desc: "Derrota 1000 monstruos",
          tipo: "muertes", meta: 1000, reliquias: 150, cofre: -1 },
        { id: "cazador3", nombre: "Cazador III", desc: "Derrota 5000 monstruos",
          tipo: "muertes", meta: 5000, reliquias: 500, cofre: 0 },
        { id: "cazador4", nombre: "Cazador IV", desc: "Derrota 25000 monstruos",
          tipo: "muertes", meta: 25000, reliquias: 1800, cofre: 0 },
        { id: "cazador5", nombre: "Cazador V", desc: "Derrota 100000 monstruos",
          tipo: "muertes", meta: 100000, reliquias: 6000, cofre: 0 },
        { id: "verdugo1", nombre: "Verdugo I", desc: "Derrota 10 jefes",
          tipo: "jefes", meta: 10, reliquias: 60, cofre: -1 },
        { id: "verdugo2", nombre: "Verdugo II", desc: "Derrota 50 jefes",
          tipo: "jefes", meta: 50, reliquias: 220, cofre: 1 },
        { id: "verdugo3", nombre: "Verdugo III", desc: "Derrota 200 jefes",
          tipo: "jefes", meta: 200, reliquias: 900, cofre: 1 },
        { id: "verdugo4", nombre: "Verdugo IV", desc: "Derrota 1000 jefes",
          tipo: "jefes", meta: 1000, reliquias: 4000, cofre: 1 },
        { id: "explorador1", nombre: "Explorador I", desc: "Llega a la oleada 25",
          tipo: "oleada", meta: 25, reliquias: 50, cofre: -1 },
        { id: "explorador2", nombre: "Explorador II", desc: "Llega a la oleada 80",
          tipo: "oleada", meta: 80, reliquias: 200, cofre: -1 },
        { id: "explorador3", nombre: "Explorador III", desc: "Llega a la oleada 160",
          tipo: "oleada", meta: 160, reliquias: 700, cofre: 1 },
        { id: "explorador4", nombre: "Explorador IV", desc: "Llega a la oleada 320",
          tipo: "oleada", meta: 320, reliquias: 2500, cofre: 1 },
        { id: "explorador5", nombre: "Explorador V", desc: "Llega a la oleada 640",
          tipo: "oleada", meta: 640, reliquias: 9000, cofre: 1 },
        { id: "saqueador1", nombre: "Saqueador I", desc: "Abre 20 cofres",
          tipo: "cofres", meta: 20, reliquias: 40, cofre: -1 },
        { id: "saqueador2", nombre: "Saqueador II", desc: "Abre 100 cofres",
          tipo: "cofres", meta: 100, reliquias: 160, cofre: 0 },
        { id: "saqueador3", nombre: "Saqueador III", desc: "Abre 400 cofres",
          tipo: "cofres", meta: 400, reliquias: 600, cofre: 0 },
        { id: "saqueador4", nombre: "Saqueador IV", desc: "Abre 1500 cofres",
          tipo: "cofres", meta: 1500, reliquias: 2200, cofre: 0 },
        { id: "maestro1", nombre: "Maestro I", desc: "Alcanza el nivel 15 con un héroe",
          tipo: "nivel", meta: 15, reliquias: 50, cofre: -1 },
        { id: "maestro2", nombre: "Maestro II", desc: "Alcanza el nivel 40 con un héroe",
          tipo: "nivel", meta: 40, reliquias: 180, cofre: -1 },
        { id: "maestro3", nombre: "Maestro III", desc: "Alcanza el nivel 80 con un héroe",
          tipo: "nivel", meta: 80, reliquias: 700, cofre: 2 },
        { id: "maestro4", nombre: "Maestro IV", desc: "Alcanza el nivel 150 con un héroe",
          tipo: "nivel", meta: 150, reliquias: 3000, cofre: 2 },
        { id: "veterano1", nombre: "Veterano I", desc: "Completa 5 partidas",
          tipo: "partidas", meta: 5, reliquias: 40, cofre: -1 },
        { id: "veterano2", nombre: "Veterano II", desc: "Completa 25 partidas",
          tipo: "partidas", meta: 25, reliquias: 150, cofre: -1 },
        { id: "veterano3", nombre: "Veterano III", desc: "Completa 100 partidas",
          tipo: "partidas", meta: 100, reliquias: 800, cofre: -1 },
        { id: "chatarrero1", nombre: "Chatarrero I", desc: "Desguaza 50 piezas",
          tipo: "desguaces", meta: 50, reliquias: 40, cofre: -1 },
        { id: "chatarrero2", nombre: "Chatarrero II", desc: "Desguaza 300 piezas",
          tipo: "desguaces", meta: 300, reliquias: 200, cofre: -1 },
        { id: "chatarrero3", nombre: "Chatarrero III", desc: "Desguaza 1200 piezas",
          tipo: "desguaces", meta: 1200, reliquias: 900, cofre: -1 }
    ]

    function progresoDe(l, juego) {
        const cuanto = valorDe(l.tipo, juego)
        return Math.min(1, cuanto / l.meta)
    }

    function valorDe(tipo, juego) {
        if (tipo === "oleada")    return juego.mejorOleada
        if (tipo === "nivel")     return juego.nivelMaximo
        if (tipo === "partidas")  return juego.partidas
        return juego.cuentas[tipo] || 0
    }

    function textoProgreso(l, juego) {
        const cuanto = Math.min(valorDe(l.tipo, juego), l.meta)
        return cuanto + " / " + l.meta
    }

    // Cuántos quedan por delante: da la medida de lo que falta de un vistazo.
    function pendientes(conseguidos) {
        return definicion.length - (conseguidos ? conseguidos.length : 0)
    }
}
