pragma Singleton

//  Estado de la propia island, el que no pertenece a ningún módulo.
//
//  Lo mantiene el host (shell.qml); los plugins lo leen para decidir si quieren
//  la island — el de reloj se activa al pasar el ratón, por ejemplo.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: isla

    // ¿el ratón está encima de la island?
    property bool hovered: false

    // fuerza un modo concreto; se usa desde IPC para depurar
    property string debugMode: ""

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
