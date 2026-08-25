pragma Singleton

//  Estado de la propia island, el que no pertenece a ningún módulo.
//
//  Lo mantiene el host (shell.qml); los plugins lo leen para decidir si quieren
//  la island — el de reloj se activa al pasar el ratón, por ejemplo.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: isla

    // ¿el ratón está encima de la island?
    property bool hovered: false

    //  Quién tiene la island ahora mismo y si está desplegada. Lo pone
    //  shell.qml —que es quien lo decide, comparando prioridades— y lo leen
    //  los plugins a través de K4.Isla, para no gastar en animaciones y
    //  sondeos que nadie va a ver.
    property string ocupante: ""
    property bool abierta: false

    // La píldora existe en todas las pantallas; una vista desplegada, en una.
    // `pantallaPedida` conserva el origen de la acción hasta que el host sabe
    // qué plugin ganó. Un clic la rellena con su pantalla; un atajo cae en el
    // monitor enfocado de Hyprland.
    property string pantallaActiva: ""
    property string pantallaPedida: ""

    function pedirPantalla(nombre) {
        if (nombre)
            pantallaPedida = String(nombre)
    }

    function pantallaConFoco() {
        const monitor = Hyprland.focusedMonitor
        if (monitor && monitor.name)
            return monitor.name
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }

    function pedirPantallaConFoco() { pedirPantalla(pantallaConFoco()) }

    function tomarPantallaPedida() {
        const elegida = pantallaPedida || pantallaConFoco()
        pantallaPedida = ""
        return elegida
    }

    function usarPantalla(nombre) {
        pantallaActiva = nombre || pantallaConFoco()
        pantallaPedida = ""
    }

    // fuerza un modo concreto; se usa desde IPC para depurar
    property string debugMode: ""

    //  En qué borde vive la barra ahora mismo: "arriba" o "abajo". Lo decide
    //  el usuario en Ajustes; un plugin que pinte fuera de la island lo lee
    //  para saber hacia dónde asomar.
    readonly property string posicion: Settings.posicionBarra

    //  Dónde está la island en la pantalla, en coordenadas de pantalla.
    //
    //  `rect` es la de la pantalla principal — el caso de un monitor y el
    //  plugin que no pregunta más. `rects` es el mapa completo por nombre de
    //  pantalla: con varios monitores la island se repite, y lo que asome
    //  con una K4.Ventana debe poder anclarse a la SUYA.
    property var rect: ({ x: 0, y: 0, ancho: 0, alto: 0 })

    //  Lo que mide el monitor donde vive la barra. Lo pide la
    //  previsualización de Ajustes para dibujar la island a escala de verdad:
    //  sin esto tendría que suponer 1920×1080 y la proporción sería inventada
    //  en cualquier otra pantalla.
    //
    //  Vive aquí y no en el plugin porque `tools/api.py` no deja importar
    //  `Quickshell` desde un plugin —lo que la API no da, se baja a un
    //  servicio— y este ya lo importa para saber en qué pantalla está.
    readonly property real altoPantalla: {
        const p = Quickshell.screens
        return p.length > 0 && p[0].height > 0 ? p[0].height : 1080
    }

    readonly property real anchoPantalla: {
        const p = Quickshell.screens
        return p.length > 0 && p[0].width > 0 ? p[0].width : 1920
    }
    property var rects: ({})

    function publicarRect(pantalla, r, esPrincipal) {
        const d = Object.assign({}, rects)
        d[pantalla] = r
        rects = d
        if (esPrincipal)
            rect = r
    }

    // ── ¿la ve alguien? ───────────────────────────────────────────
    //
    //  Existe por una razón concreta: **en Qt Quick una animación NO se para
    //  porque su item deje de verse.** Sigue corriendo, y con ella el repintado
    //  de la escena entera a la tasa del monitor. Las que no acaban nunca —las
    //  barritas del audio, el pulso de los cofres— tienen que preguntar antes,
    //  y esto es lo que preguntan.
    //
    //  Por pantalla y publicado por cada barra, igual que `rects`: con la
    //  island retirada en un monitor y puesta en el otro, la respuesta correcta
    //  es que sí la ve alguien.
    property var vistas: ({})

    function publicarVista(pantalla, seVe) {
        if (vistas[pantalla] === !!seVe)
            return
        const d = Object.assign({}, vistas)
        d[pantalla] = !!seVe
        vistas = d
    }

    //  `apartada` manda sobre todo lo demás: durante una captura o un diálogo
    //  del sistema no la ve nadie, la publique quien la publique.
    //
    //  Y sin nadie publicando se contesta que SÍ. Es el defecto prudente: una
    //  animación de más se nota menos que una que no arranca nunca, y así esto
    //  no rompe nada si algún día se monta la island sin pasar por shell.qml
    //  —una prueba de plugin con `--test`, sin ir más lejos—.
    readonly property bool aLaVista: {
        if (apartada)
            return false
        const nombres = Object.keys(vistas)
        for (let i = 0; i < nombres.length; ++i)
            if (vistas[nombres[i]])
                return true
        return nombres.length === 0
    }

    // ── colocación ────────────────────────────────────────────────
    //
    //  Dónde está la island a lo largo de su borde, como fracción del ancho
    //  libre: 0 pegada a la izquierda, 1 a la derecha. La base la pone el
    //  usuario en Ajustes (alineacionBarra); un plugin puede desplazarla
    //  TEMPORALMENTE con colocar() — la island que esquiva, que hace de pala,
    //  que se aparta para enseñar algo — y vuelve sola: por plazo, al soltar,
    //  o al deshabilitar al dueño (PluginManager llama a soltar al destruir).
    property string colocacionDueno: ""
    property real colocacionPedida: -1      // -1 = ninguna, manda Ajustes

    readonly property real colocacion: colocacionPedida >= 0
        ? colocacionPedida : Settings.alineacionBarra / 100

    function colocar(dueno, fraccion, duracionMs) {
        if (!dueno)
            return
        colocacionDueno = String(dueno)
        colocacionPedida = Math.max(0, Math.min(1, Number(fraccion) || 0))
        if (duracionMs > 0)
            _suelta.armar(duracionMs)
        else
            _suelta.stop()
    }

    function soltar(dueno) {
        if (colocacionDueno === "" || (dueno && dueno !== colocacionDueno))
            return
        colocacionDueno = ""
        colocacionPedida = -1
        _suelta.stop()
    }

    property var _suelta: Timer {
        onTriggered: isla.soltar(isla.colocacionDueno)
        function armar(ms) { stop(); interval = ms; start() }
    }

    // ── gestos ────────────────────────────────────────────────────
    //
    //  La island como objeto físico: una sacudida, un empujón, un tirón. El
    //  plugin lo pide y el host lo anima; aquí solo vive el arbitraje, que es
    //  deliberadamente simple: un gesto cada medio segundo como mucho, y la
    //  fuerza recortada. El efecto raro impresiona porque la barra es sobria
    //  el resto del tiempo — sin el freno, la primera feria lo estropea para
    //  todos.
    signal gesto(string nombre, real fuerza)

    property real _ultimoGesto: 0

    function efecto(dueno, nombre, fuerza) {
        const ahora = Date.now()
        if (ahora - _ultimoGesto < 500)
            return
        _ultimoGesto = ahora
        const f = fuerza === undefined ? 1
            : Math.max(0.2, Math.min(1, Number(fuerza) || 0))
        gesto(String(nombre), f)
    }

    //  Aparta la island un instante, para que no salga en las capturas.
    //
    //  No se esconde la ventana: reserva 34 px de zona exclusiva y ocultarla
    //  reajustaría todas las ventanas del escritorio, que es un parpadeo mucho
    //  peor que el problema. Se deja mapeada y simplemente no se dibuja.
    property bool escondida: false

    //  Cuántos diálogos del sistema hay abiertos ahora mismo.
    //
    //  La island va en una capa por encima de todo, así que un selector de
    //  ficheros abierto desde ella le sale POR DEBAJO y no se ve. Mientras haya
    //  uno, la island se aparta —y además deja de aceptar clics, o se los
    //  comería en su franja aunque no se vea—.
    //
    //  Un contador y no un booleano porque se puede pedir una imagen desde el
    //  editor y un vídeo desde el selector sin que el primero haya contestado:
    //  con un booleano, cerrar uno reaparecería la island con el otro abierto.
    //
    //  Y aparte de `escondida` porque aquello dura noventa milisegundos y tiene
    //  su red de seguridad de veinte segundos; buscar un fichero lleva lo que
    //  lleve, y esa red lo dejaría a medias.
    property int dialogos: 0

    function abrirDialogo() { dialogos += 1 }
    function cerrarDialogo() { dialogos = Math.max(0, dialogos - 1) }

    readonly property bool apartada: escondida || dialogos > 0

    //  Y un vigilante, porque quedarse sin barra no puede pasar.
    //
    //  El contador sube al arrancar el proceso y baja al terminar, y eso basta
    //  mientras el proceso viva lo suficiente para avisar. Si algo se lo lleva
    //  por delante —la vista que lo contenía se destruye, el proceso muere de
    //  malas maneras— el aviso no llega y la island se queda apartada para
    //  siempre. Sin barra y sin forma de recuperarla salvo reiniciándola.
    //
    //  Así que mientras el contador esté arriba se comprueba de vez en cuando
    //  que de verdad haya algún zenity vivo. Si no lo hay, se baja. Solo corre
    //  mientras hay un diálogo abierto, así que no cuesta nada el resto del
    //  tiempo.
    property var _sonda: Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("island:", l)
            }
        }
        command: ["pgrep", "-c", "-x", "zenity"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(String(this.text).trim(), 10)
                if (isFinite(n) && n <= 0)
                    isla.dialogos = 0
            }
        }
    }

    property var _vigilante: Timer {
        interval: 3000
        repeat: true
        running: isla.dialogos > 0
        onTriggered: isla._sonda.running = true
    }
}
