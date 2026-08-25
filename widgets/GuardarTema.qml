//  «Esto ya está en tu config, o solo en esta sesión» — y el botón de guardar.
//
//  El tema de Hyprland se aplica al instante pero no se escribe solo: hasta que
//  no pulsas, vive en la sesión y se va al reiniciar. Eso hay que decirlo donde
//  se toca, no en otra pantalla, así que esta barra acompaña a cada sección que
//  escribe el Lua.
//
//  Los fondos NO la llevan: esos se guardan solos al elegirlos, y ofrecer un
//  «Guardar» que no hace falta es enseñar una duda que no existe.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: guardar

    property var motor: null

    readonly property bool puesto: !!guardar.motor
        && typeof guardar.motor.isPersisted === "function"
        && guardar.motor.isPersisted()

    Layout.fillWidth: true
    Layout.preferredHeight: 24
    spacing: 10

    IconGlyph {
        text: guardar.puesto ? Theme.ico.check : Theme.ico.alert
        color: guardar.puesto ? Theme.green : Theme.muted
        font.pixelSize: 12
        renderType: Text.NativeRendering
        Layout.alignment: Qt.AlignVCenter
    }

    IslandLabel {
        text: guardar.puesto
            ? Idioma.t("Guardado en config/k4-theme.lua · sobrevive al reinicio")
            : Idioma.t("Aplicado solo en esta sesión · pulsa Guardar para que persista")
        color: Theme.muted
        font.pixelSize: 10
        Layout.alignment: Qt.AlignVCenter
    }

    Item { Layout.fillWidth: true }

    Rectangle {
        visible: !!guardar.motor
        Layout.preferredWidth: etiqueta.implicitWidth + 26
        Layout.preferredHeight: 24
        Layout.alignment: Qt.AlignVCenter
        radius: 12
        color: raton.containsMouse ? Theme.blue : Theme.surfaceHi

        Behavior on color { ColorAnimation { duration: 120 } }

        IslandLabel {
            id: etiqueta
            anchors.centerIn: parent
            text: Idioma.t("Guardar")
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: raton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: guardar.motor.persist()
        }
    }
}
