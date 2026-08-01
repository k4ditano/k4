pragma Singleton

//  Cerrar, apagar, reiniciar, dormir… y el estado del bloqueo.
//
//  Aquí solo vive el «qué»: quién eres, qué acciones puede hacer esta máquina y
//  si la sesión está bloqueada. El «cómo se ve» —el menú y la pantalla de
//  bloqueo— es cosa de plugins/Session, porque son superficies.
//
//  Sobre hibernar: no basta con que el núcleo diga que sabe («disk» en
//  /sys/power/state). Hace falta un swap de verdad al que volcar la memoria y
//  un `resume=` en la línea de arranque que le diga al núcleo dónde buscarlo al
//  encender. Con solo zram —que vive en la RAM que precisamente se va a
//  apagar— hibernar no lleva a ninguna parte, así que la opción ni se ofrece.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: sesion

    // ── quién eres ────────────────────────────────────────────────
    readonly property string usuario: Quickshell.env("USER") || ""
    property string nombre: ""              // el del GECOS, si lo hay
    readonly property string visible: nombre.length > 0 ? nombre : usuario
    readonly property string inicial:
        visible.length > 0 ? visible.charAt(0).toUpperCase() : "?"

    // ── bloqueo ───────────────────────────────────────────────────
    property bool bloqueado: false

    function bloquear() { bloqueado = true }
    function desbloquear() { bloqueado = false }

    // ── qué puede hacer esta máquina ──────────────────────────────
    property bool swapReal: false
    property bool resumeConfigurado: false
    readonly property bool hibernacionPosible: swapReal && resumeConfigurado

    // ── acciones ──────────────────────────────────────────────────
    //
    //  systemd-logind se encarga de todas menos cerrar sesión, que es del
    //  compositor: salir de Hyprland cierra la sesión gráfica sin tirar de
    //  `loginctl terminate-user`, que se llevaría por delante también lo que
    //  tengas corriendo en un tty.
    function apagar()    { correr(["systemctl", "poweroff"]) }
    function reiniciar() { correr(["systemctl", "reboot"]) }
    function hibernar()  { correr(["systemctl", "hibernate"]) }

    // Dormir con la sesión ya bloqueada: si no, al despertar queda el
    // escritorio a la vista el instante que tarda el bloqueo en montarse.
    function suspender() {
        bloquear()
        dormir.start()
    }

    function cerrarSesion() { Hyprland.dispatch("hl.dsp.exit()") }

    function correr(cmd) {
        accion.command = cmd
        accion.running = true
    }

    Process { id: accion }

    // Un respiro antes de suspender para que la pantalla de bloqueo esté
    // dibujada cuando la máquina se duerma, no a medio montar.
    Timer {
        id: dormir
        interval: 400
        onTriggered: sesion.correr(["systemctl", "suspend"])
    }

    // El nombre bonito sale del quinto campo de passwd, hasta la primera coma:
    // el resto del GECOS son despacho y teléfonos que no pintan nada aquí.
    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("sesion:", l)
            }
        }
        command: ["getent", "passwd", sesion.usuario]
        running: sesion.usuario.length > 0

        stdout: StdioCollector {
            onStreamFinished: {
                const campos = String(this.text).trim().split(":")
                if (campos.length >= 5)
                    sesion.nombre = campos[4].split(",")[0].trim()
            }
        }
    }

    // ¿Hay algún swap que no sea zram? Es la condición que falla en la mayoría
    // de equipos actuales, y sin ella hibernar no vuelve.
    FileView {
        path: "/proc/swaps"
        blockLoading: true

        onLoaded: {
            const lineas = String(text()).trim().split("\n")
            for (let i = 1; i < lineas.length; ++i) {
                const dispositivo = lineas[i].split(/\s+/)[0] || ""
                if (dispositivo.length > 0 && dispositivo.indexOf("zram") === -1)
                    sesion.swapReal = true
            }
        }
    }

    FileView {
        path: "/proc/cmdline"
        blockLoading: true
        onLoaded: sesion.resumeConfigurado = String(text()).indexOf("resume=") !== -1
    }
}
