pragma Singleton

//  El tema de la casa, publicado en un fichero para quien vive fuera de la
//  barra.
//
//  Theme.qml es QML y no lo puede leer nadie más; k4term —la terminal de la
//  casa— está escrita en Rust. El puente entre los dos es este fichero: la
//  barra lo escribe al arrancar y cada vez que el ambiente cambia, y quien
//  esté fuera lo vigila con inotify. Cero procesos por ambos lados.
//
//  Se publican los colores YA TEÑIDOS, que es el objetivo entero: cuando la
//  mazmorra tiñe la barra, la terminal se tiñe con ella. Los que tienen
//  significado —verde, rojo, azul, amarillo— van sin teñir, igual que en
//  Theme: un rojo de error tiene que seguir siendo rojo bajo cualquier
//  ambiente.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: ambiente

    readonly property string carpeta: Quickshell.env("HOME") + "/.local/state/k4"
    readonly property string ruta: carpeta + "/tema.json"

    //  Un solo centinela para todo el ambiente: los cuatro colores del andamio
    //  salen del mismo tinte, así que con vigilar el fondo se enteran todos.
    property color fondo: Theme.islandBg
    onFondoChanged: if (listo) retardo.restart()

    //  Y el estado del depósito de chispa, para quien quiera enterarse de
    //  que se ha quedado seco sin abrir la mazmorra. Solo cuenta con el modo
    //  encendido: con él apagado nadie llena el depósito y «seco» no
    //  significaría nada.
    readonly property bool seco: Settings.juegoActivo && !Tokens.hay
    onSecoChanged: if (listo) retardo.restart()

    property bool listo: false

    function contenido() {
        return JSON.stringify({
            fondo: String(Theme.islandBg),
            tinta: String(Theme.ink),
            apagado: String(Theme.muted),
            tenue: String(Theme.dim),
            superficie: String(Theme.surface),
            superficieAlta: String(Theme.surfaceHi),
            carril: String(Theme.track),
            verde: String(Theme.green),
            rojo: String(Theme.red),
            azul: String(Theme.blue),
            amarillo: String(Theme.yellow),
            radio: Theme.wing,
            fuente: Theme.iconFont,
            fuenteUi: Theme.uiFont,
            tinte: {
                dueno: Theme.tinteDueno,
                color: String(Theme.tinteColor),
                fuerza: Theme.tinteFuerza
            },
            tokens: {
                seco: ambiente.seco,
                resto: Settings.juegoActivo ? Tokens.resto() : ""
            }
        }, null, 1)
    }

    function publicar() {
        if (listo)
            vista.setText(contenido())
    }

    FileView { id: vista; path: ambiente.ruta }

    //  El tinte se anima durante 420 ms: sin freno serían decenas de
    //  escrituras por transición. Con este respiro salen dos o tres, que es
    //  todo lo que una terminal necesita para acompañar el cambio.
    Timer { id: retardo; interval: 180; onTriggered: ambiente.publicar() }

    Process {
        command: ["mkdir", "-p", ambiente.carpeta]
        running: true
        onExited: {
            ambiente.listo = true
            ambiente.publicar()
        }
    }
}
