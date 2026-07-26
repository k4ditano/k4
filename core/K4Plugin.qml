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

    // Pide foco de teclado exclusivo a la layer surface (lanzador, prompts…).
    property bool grabKeyboard: false

    // Clic en el fondo de la island. Si el plugin no lo marca, el host aplica
    // lo de siempre: abrir el centro de control.
    property bool handlesBackgroundTap: false
    signal backgroundTapped()
}
