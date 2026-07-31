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

    Component.onCompleted: {
        if (Puente.enganches)
            Puente.enganches.registrarAjustes(aporte)
    }

    Component.onDestruction: {
        if (Puente.enganches)
            Puente.enganches.quitarDe(aporte.plugin)
    }
}
