//  Que estás grabando, siempre a la vista.
//
//  Va en la píldora y no como módulo propio a propósito: un plugin activo
//  durante diez minutos se quedaría la island entera y no dejaría ni ver la
//  hora. Esto es un indicador, ocupa lo que ocupa un reloj y no estorba.
//
//  El punto late porque un círculo rojo quieto se confunde con cualquier otro
//  adorno; latiendo se lee como «esto está pasando ahora».

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: indicador

    property bool interactive: false
    signal parar()

    visible: Captura.grabando || Captura.estado === "cerrando"
    spacing: 5

    Rectangle {
        Layout.preferredWidth: 8
        Layout.preferredHeight: 8
        Layout.alignment: Qt.AlignVCenter
        radius: 4
        color: Theme.red

        SequentialAnimation on opacity {
            running: Captura.grabando
            loops: Animation.Infinite
            NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1;    duration: 700; easing.type: Easing.InOutSine }
        }
    }

    IslandLabel {
        text: Captura.estado === "cerrando"
            ? Idioma.t("cerrando…") : Captura.duracionTexto
        color: Theme.muted
        font.pixelSize: 11
        font.weight: Font.Medium
        Layout.alignment: Qt.AlignVCenter
    }

    // Sin anchors: esto vive dentro de un RowLayout, y anclar algo gobernado
    // por un layout es comportamiento indefinido —Qt avisa en cada arranque—.
    MouseArea {
        x: -3
        y: -3
        width: indicador.width + 6
        height: indicador.height + 6
        enabled: indicador.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: indicador.parar()
    }
}
