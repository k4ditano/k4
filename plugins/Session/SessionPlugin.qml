//  Sesión: el menú de apagado y la pantalla de bloqueo.
//
//  Son dos cosas muy distintas viviendo juntas porque comparten servicio. El
//  menú es un módulo normal de la island. El bloqueo NO: es una superficie de
//  `ext-session-lock`, un protocolo aparte que el compositor dibuja por encima
//  de todo y al que le da el teclado en exclusiva. Ni la island ni ninguna
//  ventana pueden pintar encima, que es justo el punto.
//
//  Cuidado con eso último: si quickshell se muere con el bloqueo puesto, el
//  compositor deja la sesión bloqueada y sin nadie que la abra. La salida es un
//  tty (Ctrl+Alt+F2) y matar Hyprland desde ahí. Por eso hay `k4.session
//  probar`: comprueba la contraseña con el mismo PAM que usa el bloqueo, pero
//  sin bloquear nada, y así se puede verificar antes de fiarse.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "session"
    title: Idioma.t("Sesión")
    priority: 86
    active: habilitado && open
    viewLoaded: open
    grabKeyboard: open

    property var panel: null

    property bool open: false
    property int index: 0

    // "menu" · "comprobar" — el segundo es el ensayo de la contraseña.
    property string modo: "menu"

    // Qué se está a punto de hacer, si es de lo que no tiene vuelta atrás.
    property int confirmando: -1

    // ── las acciones del menú ─────────────────────────────────────
    //
    //  `confirma` marca las que no se pueden deshacer: hacen falta dos
    //  pulsaciones. Apagar el equipo por rozar una tecla es la clase de cosa
    //  que solo pasa una vez y ya no se te olvida.
    readonly property var acciones: {
        const l = [
            { clave: "bloquear", texto: Idioma.t("Bloquear"),
              icono: 0xF033E, color: Theme.blue, confirma: false },
            { clave: "suspender", texto: Idioma.t("Suspender"),
              icono: 0xF04B2, color: Theme.blue, confirma: false }
        ]
        if (Sesion.hibernacionPosible)
            l.push({ clave: "hibernar", texto: Idioma.t("Hibernar"),
                     icono: 0xF0904, color: Theme.blue, confirma: true })
        l.push({ clave: "salir", texto: Idioma.t("Cerrar sesión"),
                 icono: 0xF0343, color: Theme.muted, confirma: true })
        l.push({ clave: "reiniciar", texto: Idioma.t("Reiniciar"),
                 icono: 0xF0709, color: Theme.muted, confirma: true })
        l.push({ clave: "apagar", texto: Idioma.t("Apagar"),
                 icono: 0xF0425, color: Theme.red, confirma: true })
        return l
    }

    readonly property int count: acciones.length

    islandWidth: modo === "comprobar" ? 420 : Math.min(760, 40 + count * 118)
    islandHeight: modo === "comprobar" ? 172 : 200

    view: Component {
        SessionView { plugin: self }
    }

    // ── el menú ───────────────────────────────────────────────────
    function abrir() {
        index = 0
        confirmando = -1
        modo = "menu"
        open = true
        if (panel)
            panel.close()
    }

    function close() {
        open = false
        confirmando = -1
        modo = "menu"
    }

    // El ensayo: la misma comprobación que hará el bloqueo, sin bloquear. Si
    // aquí entra, allí entrará.
    function comprobarClave() {
        modo = "comprobar"
        open = true
    }

    // ESC vuelve al menú antes de cerrar del todo: estando en el comprobador,
    // salirse entero de un tecleo es más brusco de lo que se espera.
    function atras() {
        if (modo === "comprobar")
            modo = "menu"
        else
            close()
    }

    function toggle() { open ? close() : abrir() }

    function avanzar()    { index = (index + 1) % count; confirmando = -1 }
    function retroceder() { index = (index - 1 + count) % count; confirmando = -1 }

    function ejecutar(i) {
        const a = acciones[i]
        if (!a)
            return

        // primera pulsación en algo irreversible: pregunta, no obedece
        if (a.confirma && confirmando !== i) {
            index = i
            confirmando = i
            return
        }

        close()
        if (a.clave === "bloquear")       Sesion.bloquear()
        else if (a.clave === "suspender") Sesion.suspender()
        else if (a.clave === "hibernar")  Sesion.hibernar()
        else if (a.clave === "salir")     Sesion.cerrarSesion()
        else if (a.clave === "reiniciar") Sesion.reiniciar()
        else if (a.clave === "apagar")    Sesion.apagar()
    }

    function elegir() { ejecutar(index) }

    onCountChanged: if (index >= count) index = Math.max(0, count - 1)

    // ── la pantalla de bloqueo ────────────────────────────────────
    K4.BloqueoSesion {
        id: cerradura
        surface: BloqueoSurface {}
    }

    //  Ojo con dos cosas aquí, que costaron una sesión.
    //
    //  Una: la propiedad por defecto de WlSessionLock es `surface`, así que
    //  esto NO puede ir dentro del bloque de arriba —acabaría asignado como
    //  superficie, y sin una sola queja: el bloqueo simplemente no se pone.
    //
    //  Dos: se abre y se cierra escribiendo en `locked`. El `unlock()` que
    //  aparece en la documentación existe en C++ pero no está expuesto a QML,
    //  y al llamarlo el aviso se pierde entre los del arranque mientras la
    //  sesión se queda bloqueada. Es la clase de fallo que solo se nota cuando
    //  ya no puedes salir.
    Connections {
        target: Sesion

        function onBloqueadoChanged() {
            if (Sesion.bloqueado)
                self.close()
            if (cerradura.locked !== Sesion.bloqueado)
                cerradura.locked = Sesion.bloqueado
        }

        //  Al recargar la configuración —y quickshell recarga solo en cuanto
        //  tocas un fichero— el objeto de bloqueo conserva el estado real y el
        //  servicio arranca de cero. Aquí manda el compositor, siempre.
        //
        //  Al revés era tentador y es exactamente lo que rompe: el servicio
        //  diría «no estás bloqueado» y soltaría el bloqueo a medias, dejando
        //  a Hyprland con uno huérfano. A partir de ahí toda petición de
        //  bloquear es un error de protocolo que se lleva por delante la
        //  conexión Wayland entera, o sea la barra completa, y no hay forma de
        //  arreglarlo sin cerrar la sesión.
        Component.onCompleted: {
            if (cerradura.locked !== Sesion.bloqueado)
                Sesion.bloqueado = cerradura.locked
        }
    }

    K4.Ipc {
        target: "k4.session"

        function toggle(): void { self.toggle() }
        function open(): void { self.abrir() }
        function close(): void { self.close() }

        function lock(): void { Sesion.bloquear() }
        function unlock(): void { Sesion.desbloquear() }

        // Ensaya la contraseña con el mismo PAM que usa el bloqueo, sin
        // bloquear nada: sirve para comprobar que vas a poder salir antes de
        // confiarle la sesión.
        function check(): void { self.comprobarClave() }
    }
}
