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
}
