pragma Singleton

//  Qué terminal usa la casa.
//
//  k4 abre terminales para cosas que no caben en la barra: actualizar el
//  sistema, instalar del AUR, sacar una sesión a lo grande. La nuestra
//  —k4term— es la primera opción, pero **k4 tiene que funcionar sin ella**:
//  quien clone la barra no tiene por qué tener instalada la terminal, y
//  quedarse sin poder actualizar el sistema por eso sería absurdo.
//
//  Así que se busca una y se recuerda cuál: k4term si está, si no la que el
//  usuario declare en $TERMINAL, y si tampoco, la primera de las de siempre.
//  La mini-terminal de la island es aparte (`hayIsla`): esa sí necesita
//  k4term-isla concretamente, porque habla un protocolo que es nuestro.
//
//  El «-e mandato» lo entienden casi todas igual; las dos que no —wezterm y
//  gnome-terminal— tienen su forma aquí. Añadir una nueva es tocar solo esta
//  función.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: consola

    //  La terminal elegida, y si tenemos la sesión de la island.
    property string binario: ""
    property bool hayIsla: false

    readonly property bool esNuestra: binario === "k4term"

    //  ── correr algo, donde mejor esté ─────────────────────────────
    //
    //  Actualizar el sistema abría siempre una ventana. Teniendo una terminal
    //  DENTRO de la barra eso es dar un rodeo: lo suyo es verlo ahí mismo, sin
    //  que nada te tape lo que estabas haciendo.
    //
    //  El plugin de la terminal se ofrece al cargarse y este servicio no sabe
    //  nada de él: si no está —o si el usuario no tiene k4term-isla— esto
    //  sigue abriendo una ventana como toda la vida. Al revés no valdría, que
    //  un servicio no puede depender de que exista un plugin.
    property var enIsla: null

    function registrarIsla(f) {
        enIsla = f
    }

    readonly property bool usaIsla: enIsla !== null && hayIsla

    //  Lo que hay que poner al final de un guion para que la ventana no se
    //  cierre con el error a medio leer. En la island sobra —la sesión se
    //  queda ahí— y encima estorbaría: dejaría la terminal esperando un Intro.
    readonly property string cierre: usaIsla
        ? "" : " printf '\\nPulsa Enter para cerrar…'; read _;"

    //  ── una conexión en marcha ────────────────────────────────────
    //
    //  Lo apunta quien la lanza (el plugin de servidores) y lo apaga quien ve
    //  llegar la respuesta (el de la terminal). Va aquí porque son dos plugins
    //  distintos y este servicio es lo que ya comparten — y porque un `ssh`
    //  que tarda tres segundos sin decir nada parece una terminal colgada.
    property string conectando: ""
    property double conectandoDesde: 0
    //  Y de qué color se pone la terminal mientras estés dentro. Viaja con el
    //  destino porque es parte de «a dónde vas».
    property string tinteConexion: ""

    //  Y la contraseña, si ese servidor va con contraseña. Está aquí de paso
    //  y nada más: la pone quien lanza la conexión, se la lleva la terminal en
    //  cuanto escribe el mandato y se borra. No se guarda, no se enseña y no
    //  sale de la sesión que la va a necesitar.
    property string claveConexion: ""

    function conectandoA(destino, tinte, clave) {
        conectando = String(destino || "")
        tinteConexion = String(tinte || "")
        claveConexion = String(clave || "")
        conectandoDesde = Date.now()
    }

    function conectado() {
        conectando = ""
        claveConexion = ""
    }

    //  Se ha salido de un servidor. Lo dice quien ve terminar el mandato —el
    //  plugin de la terminal— y lo escucha quien tenga algo montado sobre esa
    //  conexión: hoy, los túneles del plugin de servidores.
    signal salioDe(string destino)

    //  Y un tope. Lo apaga la primera salida que llegue, pero si el otro lado
    //  no contesta nunca —una máquina apagada tarda dos minutos en rendirse—
    //  no puede quedarse el camino encendido esperando.
    property Timer topeConexion: Timer {
        interval: 25000
        running: consola.conectando !== ""
        onTriggered: consola.conectado()
    }

    function ejecutar(guion) {
        if (usaIsla)
            enIsla(guion)
        else
            Quickshell.execDetached(orden(guion))
    }

    //  Se lanza por uwsm como todo lo que abre la barra: así la ventana
    //  hereda el ámbito de la sesión y no muere con quickshell.
    function envoltura(orden) {
        return ["uwsm", "app", "--"].concat(orden)
    }

    //  Correr un guion en una terminal, con la ventana abierta hasta que
    //  termine.
    function orden(guion) {
        const bin = binario || "k4term"
        if (bin === "wezterm")
            return envoltura(["wezterm", "start", "--", "sh", "-c", guion])
        if (bin === "gnome-terminal")
            return envoltura(["gnome-terminal", "--", "sh", "-c", guion])
        return envoltura([bin, "-e", "sh", "-c", guion])
    }

    //  Una terminal a secas, en un directorio si se pide. La nuestra sabe
    //  `-d`; a las demás se les entra por la puerta de siempre, con la ruta
    //  como argumento para no pelearse con las comillas.
    function abrir(ruta) {
        const bin = binario || "k4term"
        if (!ruta)
            return envoltura([bin])
        if (bin === "k4term")
            return envoltura(["k4term", "-d", ruta])

        const guion = "cd \"$0\" && exec ${SHELL:-/bin/sh}"
        if (bin === "wezterm")
            return envoltura(["wezterm", "start", "--", "sh", "-c", guion, ruta])
        if (bin === "gnome-terminal")
            return envoltura(["gnome-terminal", "--", "sh", "-c", guion, ruta])
        return envoltura([bin, "-e", "sh", "-c", guion, ruta])
    }

    //  Qué hay instalado.
    //
    //  Se mira al arrancar y se VUELVE a mirar mientras falte algo. La regla
    //  vieja —«una sola pasada, y si cambia reinicias»— dejaba un agujero
    //  feo: quien instala la barra primero y la terminal después se
    //  encontraba la terminal de la isla apagada sin saber por qué, y la
    //  única pista era reiniciar. Ahora, si k4term aparece, la barra se
    //  entera sola en un minuto.
    //
    //  Y en cuanto está todo, el reloj se para: preguntar por lo que ya
    //  tienes es gastar por gastar.
    property Timer revisor: Timer {
        interval: 60000
        repeat: true
        running: consola.binario === "" || !consola.hayIsla
        onTriggered: buscador.running = true
    }

    //  Y a mano, para lo contrario: si k4term DESAPARECE, el reloj de arriba
    //  ya no corre —está todo puesto, no hay nada que esperar—, así que hay
    //  que preguntar en los dos momentos en que importa: cuando abres los
    //  Ajustes (ahí es donde se lee qué está encendido y por qué) y cuando
    //  una terminal nuestra se muere nada más nacer, que es exactamente lo
    //  que pasa cuando el binario ya no está.
    function revisar() {
        buscador.running = true
    }

    Process {
        id: buscador
        running: true
        command: ["sh", "-c",
            "elegida=''\n" +
            "for t in k4term \"$TERMINAL\" kitty alacritty foot wezterm konsole gnome-terminal xterm; do\n" +
            "  [ -z \"$t\" ] && continue\n" +
            "  command -v \"$t\" >/dev/null 2>&1 && { elegida=\"$t\"; break; }\n" +
            "done\n" +
            "isla=no\n" +
            "command -v k4term-isla >/dev/null 2>&1 && isla=si\n" +
            "printf '%s %s\\n' \"$elegida\" \"$isla\"\n"]

        stdout: StdioCollector {
            onStreamFinished: {
                const trozos = this.text.trim().split(/\s+/)
                consola.binario = trozos[0] || ""
                consola.hayIsla = trozos[1] === "si"
            }
        }
    }
}
