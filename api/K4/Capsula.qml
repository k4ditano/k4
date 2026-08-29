//  Una extensión de flanco en la píldora: la cápsula crece hacia un borde de
//  la pantalla llevando tu texto, y se pliega cuando has terminado.
//
//  Para eso que tu plugin quiere decir MIENTRAS pasa —un modo que se ha
//  quedado el teclado, una grabación en marcha— cuando un indicador
//  (`K4.Pildora`) se queda pequeño para leerlo de un vistazo. La píldora sigue
//  siendo ella: su carátula, su hora y su bandeja no se mueven de sitio, y tu
//  nombre viaja en el flanco.
//
//  ```qml
//  K4.Capsula {
//      plugin: "rec"
//      extension: grabando ? ({
//          lado: "derecha",            // "izquierda" · "derecha"
//          texto: "Grabando",
//          glifo: 0xF037E,             // md-record_circle_outline
//          color: K4.Tema.rojo,
//          largoMaximo: 300            // px hasta donde puede crecer
//      }) : null
//  }
//  ```
//
//  `extension` es una binding o no es nada: tiene que producir un objeto NUEVO
//  cuando cambie tu estado, porque mutar el de antes por dentro no se lo dice
//  a nadie. Ponla a null para plegar la cápsula.
//
//  El ancho no es tuyo y no hay que pelearlo: la barra abraza tu texto con la
//  fuente de la propia píldora y lo capa por tu `largoMaximo` Y por el hueco
//  que quede hasta el borde de la pantalla. Mientras una vista desplegada se
//  queda la island, la extensión se pliega con la píldora y vuelve con ella.

import QtQuick

QtObject {
    id: caps

    //  Tu id de plugin, el mismo del manifiesto. Es lo que nombra a la
    //  extensión —una por plugin— y lo que la recoge cuando te mueras.
    required property string plugin

    //  La extensión que enseñar, o null para ninguna:
    //  { lado: "izquierda"|"derecha", texto, glifo, color?, largoMaximo? }
    property var extension: null

    function _sincronizar() {
        const reg = Puente.extensiones
        if (!reg)
            return
        if (extension)
            reg.registrar(plugin, extension)
        else
            reg.quitar(plugin)
    }

    onExtensionChanged: _sincronizar()
    Component.onCompleted: _sincronizar()

    Component.onDestruction: {
        if (Puente.extensiones)
            Puente.extensiones.quitar(plugin)
    }
}
