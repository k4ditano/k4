//  El contrato de un plugin de k4.
//
//  Un plugin declara cuándo quiere la island, qué tamaño necesita y qué pinta
//  dentro. Todo lo demás —procesos, timers, IpcHandler— va como hijo directo,
//  vive mientras vive la barra y no depende de que la vista esté montada.
//
//      K4Plugin {
//          name: "hyprtheme"
//          priority: 60
//          active: open
//          islandWidth: 720
//          islandHeight: 480
//          view: Component { HyprThemeView {} }
//
//          IpcHandler { target: "hyprtheme"; function open() { ... } }
//          Process { id: apply }
//      }

import QtQuick

QtObject {
    // Procesos, timers e IpcHandler del plugin. Es la propiedad por defecto,
    // así que se declaran como hijos sueltos.
    default property list<QtObject> services

    // Identificador corto y único. Se usa en los logs y como target IPC sugerido.
    required property string name

    // Nombre legible, por si algún día hay un menú de módulos.
    property string title: name

    // Quién se queda la island cuando varios plugins la piden a la vez.
    // Referencia de los actuales: idle 0 · volume 40 · clock 50 · player 55 ·
    // panel 60 · toast 70 · launcher 80 · ask 90.
    property int priority: 50

    // ¿Este plugin quiere ser la vista actual ahora mismo?
    property bool active: false

    // Tamaño que necesita la island cuando está activo.
    property int islandWidth: 300
    property int islandHeight: 60

    // Lo que se pinta dentro. Se instancia solo mientras el plugin está activo.
    property Component view: null

    // Permite soltar la vista sin ceder la island: sirve para animar el cierre
    // manteniendo el tamaño mientras el contenido ya se ha ido.
    property bool viewLoaded: true

    // Pide foco de teclado EXCLUSIVO: mientras esté activo, ninguna ventana
    // recibe una tecla. Solo para lo que se escribe de verdad —el lanzador, la
    // pregunta a la IA, la clave del wifi—, porque bloquea el resto del
    // escritorio.
    property bool grabKeyboard: false

    // Foco BAJO DEMANDA: la capa recibe teclas si interactúas con ella y se las
    // devuelve al escritorio si no. Es lo que quiere un módulo que solo
    // necesita enterarse de un ESC sin secuestrarte el teclado mientras lo
    // tienes abierto de fondo.
    property bool tecladoOpcional: false

    // Clic en el fondo de la island. Si el plugin no lo marca, el host aplica
    // lo de siempre: abrir el centro de control.
    property bool handlesBackgroundTap: false
    signal backgroundTapped()

    // Módulos que se abren con el ratón y deben irse al sacarlo. El host emite
    // `hoverTimedOut` cuando el puntero lleva `hoverExitDelay` fuera de la
    // island; qué hacer entonces lo decide el plugin, porque no siempre es
    // cerrar sin más (el panel, por ejemplo, se queda si el lanzador está
    // encima). El temporizador solo se arma al salir, así que un módulo
    // abierto por atajo sigue abierto hasta que lo toques.
    property bool closeOnHoverExit: false
    property int hoverExitDelay: 700
    signal hoverTimedOut()
}
