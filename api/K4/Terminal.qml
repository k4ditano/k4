pragma Singleton

//  La terminal de la casa, para plugins.
//
//  Sin esto, un plugin que quisiera correr algo en una terminal tenía que
//  escribir `kitty -e …` a mano y cruzar los dedos: adivinar cuál hay
//  instalada, saberse la forma de cada una —wezterm y gnome-terminal no
//  aceptan `-e` como las demás— y quedarse sin terminal en cuanto el usuario
//  usara otra. La barra ya sabe todo eso; aquí se ofrece.
//
//      K4.Terminal.ejecutar("yay -Syu" + K4.Terminal.cierre)
//      K4.Terminal.abrir("/home/tu/proyecto")
//
//  Y si el usuario tiene k4term, lo que ejecutes se ve DENTRO de la island en
//  vez de abrir una ventana. Tu plugin no tiene que hacer nada distinto para
//  eso: `enLaIsla` te lo dice por si quieres redactar el mensaje de otra
//  forma, pero llamar a `ejecutar` es igual en los dos casos.
//
//  Pide el permiso `procesos`: correr un guion en una terminal es correr un
//  guion, y da igual que lo lance otro por ti.

import QtQuick

QtObject {
    readonly property var _c: Puente.consola

    //  Qué terminal ha encontrado la barra: "k4term", "kitty", lo que haya.
    //  Vacío mientras la busca, que tarda un instante al arrancar.
    readonly property string cual: _c ? _c.binario : ""

    //  Si lo que ejecutes se va a ver dentro de la island en vez de en una
    //  ventana. No hace falta mirarlo para usar `ejecutar`; está para cuando
    //  el texto de tu aviso cambie según dónde vaya a salir.
    readonly property bool enLaIsla: _c ? _c.usaIsla : false

    //  Lo que hay que añadir al final de un guion para que la ventana no se
    //  cierre con el error a medio leer. En la island devuelve cadena vacía:
    //  allí la sesión se queda, y un `read` de más dejaría la terminal
    //  esperando un Intro que nadie sabe que tiene que dar.
    //
    //      "cosa-que-puede-fallar || { echo mal; " + K4.Terminal.cierre + " }"
    readonly property string cierre: _c ? _c.cierre : ""

    //  Correr un guion de shell donde mejor esté.
    function ejecutar(guion) {
        if (_c && guion)
            _c.ejecutar(String(guion))
    }

    //  Una terminal a secas, en un directorio si se lo pides. Esta SIEMPRE
    //  abre ventana: es «dame una terminal para trastear», no «corre esto».
    function abrir(ruta) {
        if (_c)
            Sistema.lanzar(_c.abrir(ruta ? String(ruta) : ""))
    }
}
