//  El editor dentro de la island.
//
//  Solo es la envoltura: todo lo que se ve está en CuerpoEditor.qml, que
//  comparte con la ventana grande. Aquí se dice nada más de dónde salen los
//  botones de la cabecera.

import QtQuick
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    CuerpoEditor {
        anchors.fill: parent
        plugin: view.plugin
        enVentana: false
        onAgrandar: view.plugin.abrirGrande()
    }
}
