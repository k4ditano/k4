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
        { id: "cazador1", nombre: Idioma.t("Cazador I"), desc: Idioma.t("Derrota 100 monstruos"),
          tipo: "muertes", meta: 100, reliquias: 40, cofre: -1 },
        { id: "cazador2", nombre: Idioma.t("Cazador II"), desc: Idioma.t("Derrota 1000 monstruos"),
          tipo: "muertes", meta: 1000, reliquias: 150, cofre: -1 },
        { id: "cazador3", nombre: Idioma.t("Cazador III"), desc: Idioma.t("Derrota 5000 monstruos"),
          tipo: "muertes", meta: 5000, reliquias: 500, cofre: 0 },
        { id: "cazador4", nombre: Idioma.t("Cazador IV"), desc: Idioma.t("Derrota 25000 monstruos"),
          tipo: "muertes", meta: 25000, reliquias: 1800, cofre: 0 },
        { id: "cazador5", nombre: Idioma.t("Cazador V"), desc: Idioma.t("Derrota 100000 monstruos"),
          tipo: "muertes", meta: 100000, reliquias: 6000, cofre: 0 },
        { id: "verdugo1", nombre: Idioma.t("Verdugo I"), desc: Idioma.t("Derrota 10 jefes"),
          tipo: "jefes", meta: 10, reliquias: 60, cofre: -1 },
        { id: "verdugo2", nombre: Idioma.t("Verdugo II"), desc: Idioma.t("Derrota 50 jefes"),
          tipo: "jefes", meta: 50, reliquias: 220, cofre: 1 },
        { id: "verdugo3", nombre: Idioma.t("Verdugo III"), desc: Idioma.t("Derrota 200 jefes"),
          tipo: "jefes", meta: 200, reliquias: 900, cofre: 1 },
        { id: "verdugo4", nombre: Idioma.t("Verdugo IV"), desc: Idioma.t("Derrota 1000 jefes"),
          tipo: "jefes", meta: 1000, reliquias: 4000, cofre: 1 },
        { id: "explorador1", nombre: Idioma.t("Explorador I"), desc: Idioma.t("Llega a la oleada 25"),
          tipo: "oleada", meta: 25, reliquias: 50, cofre: -1 },
        { id: "explorador2", nombre: Idioma.t("Explorador II"), desc: Idioma.t("Llega a la oleada 80"),
          tipo: "oleada", meta: 80, reliquias: 200, cofre: -1 },
        { id: "explorador3", nombre: Idioma.t("Explorador III"), desc: Idioma.t("Llega a la oleada 160"),
          tipo: "oleada", meta: 160, reliquias: 700, cofre: 1 },
        { id: "explorador4", nombre: Idioma.t("Explorador IV"), desc: Idioma.t("Llega a la oleada 320"),
          tipo: "oleada", meta: 320, reliquias: 2500, cofre: 1 },
        { id: "explorador5", nombre: Idioma.t("Explorador V"), desc: Idioma.t("Llega a la oleada 640"),
          tipo: "oleada", meta: 640, reliquias: 9000, cofre: 1 },
        { id: "saqueador1", nombre: Idioma.t("Saqueador I"), desc: Idioma.t("Abre 20 cofres"),
          tipo: "cofres", meta: 20, reliquias: 40, cofre: -1 },
        { id: "saqueador2", nombre: Idioma.t("Saqueador II"), desc: Idioma.t("Abre 100 cofres"),
          tipo: "cofres", meta: 100, reliquias: 160, cofre: 0 },
        { id: "saqueador3", nombre: Idioma.t("Saqueador III"), desc: Idioma.t("Abre 400 cofres"),
          tipo: "cofres", meta: 400, reliquias: 600, cofre: 0 },
        { id: "saqueador4", nombre: Idioma.t("Saqueador IV"), desc: Idioma.t("Abre 1500 cofres"),
          tipo: "cofres", meta: 1500, reliquias: 2200, cofre: 0 },
        { id: "maestro1", nombre: Idioma.t("Maestro I"), desc: Idioma.t("Alcanza el nivel 15 con un héroe"),
          tipo: "nivel", meta: 15, reliquias: 50, cofre: -1 },
        { id: "maestro2", nombre: Idioma.t("Maestro II"), desc: Idioma.t("Alcanza el nivel 40 con un héroe"),
          tipo: "nivel", meta: 40, reliquias: 180, cofre: -1 },
        { id: "maestro3", nombre: Idioma.t("Maestro III"), desc: Idioma.t("Alcanza el nivel 80 con un héroe"),
          tipo: "nivel", meta: 80, reliquias: 700, cofre: 2 },
        { id: "maestro4", nombre: Idioma.t("Maestro IV"), desc: Idioma.t("Alcanza el nivel 150 con un héroe"),
          tipo: "nivel", meta: 150, reliquias: 3000, cofre: 2 },
        { id: "veterano1", nombre: Idioma.t("Veterano I"), desc: Idioma.t("Completa 5 partidas"),
          tipo: "partidas", meta: 5, reliquias: 40, cofre: -1 },
        { id: "veterano2", nombre: Idioma.t("Veterano II"), desc: Idioma.t("Completa 25 partidas"),
          tipo: "partidas", meta: 25, reliquias: 150, cofre: -1 },
        { id: "veterano3", nombre: Idioma.t("Veterano III"), desc: Idioma.t("Completa 100 partidas"),
          tipo: "partidas", meta: 100, reliquias: 800, cofre: -1 },
        { id: "chatarrero1", nombre: Idioma.t("Chatarrero I"), desc: Idioma.t("Desguaza 50 piezas"),
          tipo: "desguaces", meta: 50, reliquias: 40, cofre: -1 },
        { id: "chatarrero2", nombre: Idioma.t("Chatarrero II"), desc: Idioma.t("Desguaza 300 piezas"),
          tipo: "desguaces", meta: 300, reliquias: 200, cofre: -1 },
        { id: "chatarrero3", nombre: Idioma.t("Chatarrero III"), desc: Idioma.t("Desguaza 1200 piezas"),
          tipo: "desguaces", meta: 1200, reliquias: 900, cofre: -1 },

        // Los del modo vibecoding: no se consiguen jugando, sino trabajando.
        // Cuentan tokens crudos de todo tu historial, no la chispa del juego.
        { id: "vibecoder1", nombre: Idioma.t("Vibecoder I"), desc: Idioma.t("Gasta 10M de tokens en IA"),
          tipo: "tokens", meta: 10e6, reliquias: 120, cofre: -1 },
        { id: "vibecoder2", nombre: Idioma.t("Vibecoder II"), desc: Idioma.t("Gasta 100M de tokens en IA"),
          tipo: "tokens", meta: 100e6, reliquias: 500, cofre: 0 },
        { id: "vibecoder3", nombre: Idioma.t("Vibecoder III"), desc: Idioma.t("Gasta 500M de tokens en IA"),
          tipo: "tokens", meta: 500e6, reliquias: 1800, cofre: 1 },
        { id: "vibecoder4", nombre: Idioma.t("Vibecoder IV"), desc: Idioma.t("Gasta 2B de tokens en IA"),
          tipo: "tokens", meta: 2e9, reliquias: 6000, cofre: 1 },
        { id: "vibecoder5", nombre: Idioma.t("Vibecoder V"), desc: Idioma.t("Gasta 10B de tokens en IA"),
          tipo: "tokens", meta: 10e9, reliquias: 20000, cofre: 2 },
        { id: "constante1", nombre: Idioma.t("Constante I"), desc: Idioma.t("3 dias seguidos gastando tokens"),
          tipo: "racha", meta: 3, reliquias: 80, cofre: -1 },
        { id: "constante2", nombre: Idioma.t("Constante II"), desc: Idioma.t("7 dias seguidos gastando tokens"),
          tipo: "racha", meta: 7, reliquias: 300, cofre: 0 },
        { id: "constante3", nombre: Idioma.t("Constante III"), desc: Idioma.t("30 dias seguidos gastando tokens"),
          tipo: "racha", meta: 30, reliquias: 2000, cofre: 1 },
        { id: "constante4", nombre: Idioma.t("Constante IV"), desc: Idioma.t("100 dias seguidos gastando tokens"),
          tipo: "racha", meta: 100, reliquias: 9000, cofre: 2 }
    ]

    function progresoDe(l, juego) {
        const cuanto = valorDe(l.tipo, juego)
        return Math.min(1, cuanto / l.meta)
    }

    function valorDe(tipo, juego) {
        if (tipo === "oleada")    return juego.mejorOleada
        if (tipo === "nivel")     return juego.nivelMaximo
        if (tipo === "partidas")  return juego.partidas
        // Estos dos no los lleva la partida: salen de lo que gastas en IA.
        if (tipo === "tokens")    return Tokens.totalTokens
        if (tipo === "racha")     return Tokens.racha
        return juego.cuentas[tipo] || 0
    }

    function textoProgreso(l, juego) {
        const cuanto = Math.min(valorDe(l.tipo, juego), l.meta)
        // 487M / 500M se lee de un vistazo; 487201712 / 500000000 no.
        return l.meta >= 1e5
            ? Tokens.cifra(cuanto) + " / " + Tokens.cifra(l.meta)
            : cuanto + " / " + l.meta
    }
}
