//  Aportar resultados al lanzador de la barra.
//
//  El lanzador es lo que la gente abre con un atajo y donde escribe sin
//  pensar. Poder poner ahí lo tuyo —tus notas, tus servidores, lo que sea—
//  es lo que convierte un plugin en parte de la barra y no en otra ventana
//  más que hay que ir a buscar.
//
//  Contestas cuando puedes: la barra avisa por `buscando` y tú dejas lo que
//  tengas en `resultados`. Si tardas —una consulta por red, un proceso— no
//  bloqueas a nadie: cuando llegue, se pinta.
//
//  Lo tuyo sale DEBAJO de las aplicaciones del sistema, siempre. Ese panel es
//  el de ellas: quien escribe «fire» quiere Firefox, y un aporte por bien
//  intencionado que sea no debe colarse encima de lo que la persona venía a
//  buscar. Estás ahí para que se te pueda ENCONTRAR, no para competir.
//
//      K4.Lanzador {
//          plugin: "hola"
//          onBuscando: function (texto) {
//              resultados = texto.length < 2 ? [] : [{
//                  id: "saludo", titulo: "Saludar a " + texto,
//                  desc: "Del plugin de ejemplo", glifo: 0xF02FC
//              }]
//          }
//          onElegido: function (id) { ... }
//      }

import QtQuick

QtObject {
    id: aporte

    required property string plugin

    //  `[{ id, titulo, desc }]` — lo que se pinta ahora mismo.
    //
    //  El icono de una fila, en este orden: `glifo` —un códice de la Nerd
    //  Font— o `imagen` —una ruta `file://` tuya—; `icono`, el NOMBRE de un
    //  icono del escritorio, si lo que aportas es una aplicación instalada;
    //  y si no dices nada, el de tu plugin, que casi siempre es lo que
    //  quieres. Sin icono ninguno la fila sale con un hueco, y un hueco entre
    //  filas que sí lo tienen se lee como que algo está roto.
    property var resultados: []

    //  El usuario está escribiendo. Llega con cada tecla, así que si lo tuyo
    //  cuesta, mira la longitud antes de ponerte.
    signal buscando(string texto)

    //  Ha elegido uno de los tuyos, por su `id`.
    signal elegido(string id)

    property Connections _puente: Connections {
        target: Puente.enganches
        function onBuscando(texto) { aporte.buscando(texto) }
    }

    Component.onCompleted: {
        if (Puente.enganches)
            Puente.enganches.registrarLanzador(aporte)
    }

    Component.onDestruction: {
        if (Puente.enganches)
            Puente.enganches.quitarDe(aporte.plugin)
    }
}
