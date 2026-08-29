//  El contrato de un plugin de k4.
//
//  Un plugin declara cuándo quiere la island, qué tamaño necesita y qué pinta
//  dentro. Todo lo demás —procesos, timers, IpcHandler— va como hijo directo,
//  vive mientras vive la barra y no depende de que la vista esté montada.
//
//      K4Plugin {
//          name: "hyprtheme"
//          priority: 60
//          habilitado: true
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
    //  Dónde vive este plugin, en el disco. La rellena el host al crearlo.
    //
    //  Es lo que hace falta para traerte cosas tuyas: un guion en Python, un
    //  binario, un modelo, un asset que no vaya por `Qt.resolvedUrl`. Sin esto
    //  solo se podían pintar imágenes —con una URL relativa— pero no ejecutar
    //  nada propio, porque un `Process` quiere una ruta y no una URL.
    property string carpeta: ""

    //  Un fichero tuyo, con su ruta entera:
    //
    //      command: ["python3", fichero("tools/mio.py")]
    function fichero(relativa) {
        return carpeta.length > 0 ? carpeta + "/" + relativa : relativa
    }

    required property string name

    // Nombre legible, por si algún día hay un menú de módulos.
    property string title: name

    // El host lo enlaza con PluginManager. No se llama `active`: activo es
    // ocupar la island ahora; habilitado significa que el usuario permite que
    // el módulo participe en la barra.
    property bool habilitado: true

    // Quién se queda la island cuando varios plugins la piden a la vez.
    // Referencia de los actuales: idle 0 · volume 40 · clock 50 · player 55 ·
    // toast 59 · panel 60 · launcher 80 · ask 90.
    property int priority: 50

    // ¿Este plugin quiere ser la vista actual ahora mismo?
    property bool active: false

    //  ── lo que se va solo ─────────────────────────────────────────
    //
    //  Márcalo si tu vista aparece sin que nadie la pida y se cierra sola a los
    //  pocos segundos: un aviso, la confirmación de que la captura salió. No lo
    //  marques si el usuario la abrió él.
    //
    //  Lo que cambia: en cuanto OTRO plugin se queda la island, este se cierra
    //  en el acto en vez de esperar a que venza su reloj. Pulsar el atajo del
    //  lanzador con la confirmación de una captura delante enseñaba la captura
    //  cinco segundos más y el lanzador después, que no es lo que pide quien
    //  pulsa un atajo. La regla se aplica en un sitio —shell.qml— y no plugin a
    //  plugin, porque acordarse de llamar a `dismissToast()` en cada sitio que
    //  abre algo es justo lo que se olvida.
    //
    //  Va con la prioridad, no en lugar de ella: quien se marque transitorio
    //  tiene que quedar POR ENCIMA de las vistas de reposo —reloj, reproductor,
    //  volumen, que están por debajo de 60— para que pasar el ratón no se lo
    //  lleve por delante, y POR DEBAJO de todo lo que el usuario abre a
    //  propósito. Entre 56 y 59 es el hueco.
    property bool transitorio: false

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
    // devuelve al escritorio si no. Es lo que quiere un módulo que se queda
    // abierto de fondo mientras trabajas en otra ventana —la mazmorra— y que
    // solo necesita el teclado cuando lo miras.
    //
    // OJO CON EL ESC, que costó encontrarlo: «bajo demanda» significa que el
    // compositor da el teclado SOLO cuando PINCHAS la superficie. Si te abren
    // desde el centro de aplicaciones, desde el lanzador o por un atajo, nadie
    // la pincha, así que no recibes ni una tecla y el ESC que cierra el módulo
    // no te llega. Cierra con ESC solo si antes te habían puesto el ratón
    // encima, que parece que funciona hasta que alguien lo usa.
    //
    // Si lo tuyo se abre, se mira y se cierra, lo que quieres es
    // `grabKeyboard`, aunque parezca de más para un módulo que no se escribe.
    property bool tecladoOpcional: false

    // Foco MIENTRAS EL PUNTERO ESTÉ ENCIMA. El punto medio que faltaba.
    //
    // Los dos de arriba no sirven para un juego: `grabKeyboard` te deja sin
    // escribir en ninguna ventana mientras la partida esté abierta —y una
    // partida se queda abierta—, y `tecladoOpcional` solo te da teclas si
    // PINCHAS, así que las que se pulsan sin clicar no llegan nunca. Un
    // Digivice se quedó sin ESC exactamente por eso.
    //
    // Con esto el teclado es tuyo mientras juegas —el puntero está sobre la
    // island, que es donde se juega— y vuelve al escritorio en cuanto lo
    // apartas, con el mismo margen de salida que el resto del hover para que
    // no parpadee al pasar por un borde.
    //
    // Wayland no tiene un modo «al pasar»: solo None, OnDemand y Exclusive.
    // Esto es Exclusive conmutado por `Island.hovered`, o sea que mientras
    // tengas el ratón encima te llevas TODAS las teclas. Es aceptable porque
    // lo pides tú y porque se deshace solo al mover el ratón; no lo uses
    // para un módulo que solo se mira.
    //
    // OJO, LA SEGUNDA MITAD: que la capa tenga el teclado no significa que tu
    // vista reciba una tecla. La raíz de la island también pide foco —ahí vive
    // el ESC— y se lo queda. Hay que reclamarlo con `K4.FocoInicial`, y NO
    // solo al abrir: con esto el teclado llega al pasar el ratón, y para
    // entonces FocoInicial ya se rindió (insiste seis veces en menos de un
    // segundo). Recláma­lo también al entrar el puntero:
    //
    //     property var foco: K4.FocoInicial { objetivo: raiz }
    //     HoverHandler { onHoveredChanged: if (hovered) raiz.foco.reclamar() }
    property bool tecladoAlPasar: false

    // Clic en el fondo de la island. Si el plugin no lo marca, el host aplica
    // lo de siempre: abrir el centro de control.
    //  Abrirte desde fuera: el centro de aplicaciones y los accesos directos
    //  del centro de control llaman a esto. Por defecto usa tu `toggle()`, que
    //  es lo que ya tienen casi todos; redefínela si necesitas otra cosa —por
    //  ejemplo abrir siempre en vez de alternar.
    function abrir() {
        if (typeof toggle === "function")
            toggle()
        else
            active = true
    }

    property bool handlesBackgroundTap: false
    signal backgroundTapped()

    //  ── ¿te cierra un clic fuera de la island? ────────────────────
    //
    //  Sí de fábrica, y lo mismo que ya hace Escape: si tu vista se cierra con
    //  Escape —y se cierra, el host lo aplica a todas—, un toque fuera la
    //  cierra igual. El clic se gasta en cerrarte y no llega a la ventana de
    //  debajo, que es lo que quiere quien lo da.
    //
    //  Márcalo `false` si tu vista aparece SIN QUE NADIE LA PIDA y se va sola:
    //  el reloj y el reproductor al pasar el ratón, el asomo de un cambio de
    //  pista, el HUD del volumen. Ahí el toque de fuera no significa «cierra
    //  esto» —nadie lo abrió— sino que iba dirigido a otra cosa, y comérselo
    //  es robarle un clic al usuario. Lo que se va solo ya se va solo.
    //
    //  Lo transitorio (`transitorio`) no hace falta marcarlo: el host ya lo
    //  excluye por su cuenta.
    //
    //  Y el usuario manda por encima de esto: en Ajustes → Island puede apagar
    //  el clic fuera entero y volver a lo de antes.
    property bool closeOnClickOutside: true

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
