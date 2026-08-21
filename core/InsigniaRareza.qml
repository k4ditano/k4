//  Insignia de rareza: el nombre del grado sobre su color.
//
//  Distinguir diez grados solo por el tinte del texto es pedir demasiado —el
//  celeste y el divino se parecen bastante—, así que el nombre va escrito.

import QtQuick
import "../services"

Rectangle {
    id: insignia

    property int rareza: 0
    property int nivel: 0        // 0 = no mostrarlo
    property bool compacta: false

    readonly property var grado: Items.rarezaDe(rareza)

    implicitWidth: etiqueta.implicitWidth + (compacta ? 8 : 12)
    implicitHeight: compacta ? 12 : 15
    radius: height / 2
    color: Qt.rgba(grado.color.r, grado.color.g, grado.color.b, 0.18)
    border.width: 1
    border.color: Qt.rgba(grado.color.r, grado.color.g, grado.color.b, 0.75)

    Text {
        id: etiqueta
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: (insignia.compacta ? insignia.grado.nombre.substring(0, 3) : insignia.grado.nombre)
            + (insignia.nivel > 0 ? " " + insignia.nivel : "")
        color: insignia.grado.color
        font.family: Theme.uiFont
        font.pixelSize: insignia.compacta ? 8 : 9
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
    }
}
