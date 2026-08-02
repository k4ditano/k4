//  Tus ajustes, dentro de los Ajustes de la barra.
//
//  Sin esto, un plugin con dos opciones tenía que inventarse su propia
//  pantalla, su propio botón para abrirla y su propia forma de guardarlas —y
//  el usuario tenía que aprender un sitio nuevo para cada plugin. Con esto,
//  tus opciones salen en Ajustes como una sección más, con la misma cara.
//
//  Los valores los guardas TÚ: la barra pregunta por `valores` y avisa por
//  `cambiado`. Así lo que se enseña es siempre lo que de verdad tienes
//  guardado, y no una copia que se desincroniza al primer fallo de escritura.
//
//      K4.Ajustes {
//          plugin: "hola"
//          grupo: K4.Idioma.t("Hola")
//          opciones: [{ id: "sonar", nombre: K4.Idioma.t("Sonar al abrir"),
//                       desc: K4.Idioma.t("Un clic corto"), glifo: 0xF057E }]
//          valores: ({ sonar: self.sonar })
//          onCambiado: function (id, valor) {
//              if (id === "sonar") { self.sonar = valor; guardar() }
//          }
//      }

import QtQuick

QtObject {
    id: aporte

    //  Tu id, el mismo del manifiesto. Es lo que separa tus opciones de las
    //  de otro plugin que use el mismo nombre.
    required property string plugin

    //  El título de la sección en Ajustes.
    property string grupo: ""

    //  `[{ id, nombre, desc, glifo }]`. `glifo` es un códice de la Nerd Font
    //  —búscalo con `tools/glifos.py`—. Un interruptor por opción, salvo que
    //  digas otro `tipo`:
    //
    //   · "eleccion": chips de varias respuestas. Trae las tuyas en
    //     `alternativas: [{ codigo, nombre }]`; lo que llega por `cambiado`
    //     es el `codigo` elegido.
    //   · "texto": un campo libre — una URL, un modelo, una clave de API.
    //     `pista` es el texto gris del campo vacío y `secreto: true` lo
    //     tapa con puntos en cuanto se deja de teclear. El valor llega por
    //     `cambiado` al confirmar —Intro o clic fuera—, no tecla a tecla.
    property var opciones: []

    //  Lo que vale cada opción AHORA, por su id. La barra lo lee al pintar.
    property var valores: ({})

    //  El usuario ha tocado una: guárdalo y actualiza `valores`.
    signal cambiado(string id, var valor)

    function _registrar() {
        if (Puente.enganches)
            Puente.enganches.registrarAjustes(aporte)
    }

    Component.onCompleted: _registrar()

    //  Y otra vez cada vez que cambien, que lo de arriba es una FOTO: la barra
    //  se queda con la lista tal como estaba al nacer el plugin. Sin esto, un
    //  plugin cuyas opciones dependan de algo que se averigua después —si un
    //  programa está instalado, si hay red— o las enseña siempre o no las
    //  enseña nunca, según qué hubiera en ese instante. Dejar `opciones` vacío
    //  esconde la sección entera, que es la forma de decir «esto ahora mismo
    //  no aplica».
    onOpcionesChanged: _registrar()
    onGrupoChanged: _registrar()

    Component.onDestruction: {
        if (Puente.enganches)
            Puente.enganches.quitarDe(aporte.plugin)
    }
}
