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
}
