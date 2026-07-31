//  La vista: solo existe mientras el plugin tiene la island.
//
//  Un plugin de fuera importa QtQuick y K4, nada más. La paleta llega por
//  K4.Tema y el texto con los defaults de la barra por K4.Etiqueta.

import QtQuick
import K4 as K4

Item {
    required property var plugin

    Rectangle {
        anchors.centerIn: parent
        width: 320
        height: 64
        radius: 14
        color: K4.Tema.superficie

        Column {
            anchors.centerIn: parent
            spacing: 2

            K4.Etiqueta {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !plugin.saludar ? K4.Idioma.t("Contando visitas")
                    : plugin.aQuien
                      ? K4.Idioma.f(K4.Idioma.t("Hola, %1"), plugin.aQuien)
                      : K4.Idioma.t("Hola desde un plugin de fuera")
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            K4.Etiqueta {
                anchors.horizontalCenter: parent.horizontalCenter
                text: K4.Idioma.f(K4.Idioma.t("Abierto %1 veces"),
                                  plugin.visitas)
                color: K4.Tema.apagado
                font.pixelSize: 11
            }
        }
    }
}
