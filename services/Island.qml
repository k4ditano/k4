pragma Singleton

//  Estado de la propia island, el que no pertenece a ningún módulo.
//
//  Lo mantiene el host (shell.qml); los plugins lo leen para decidir si quieren
//  la island — el de reloj se activa al pasar el ratón, por ejemplo.

import QtQuick
import Quickshell

Singleton {
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
}
