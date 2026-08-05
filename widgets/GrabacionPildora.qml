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

//  Raíz Item y no el propio RowLayout: un MouseArea colgado directamente de un
//  layout es una celda más, así que el layout le impone la geometría y descarta
//  el x/y/width/height puesto a mano. Con tamaño implícito cero medía 0×0 y
//  parar la grabación desde aquí no funcionaba. Ver JuegoPildora, que tenía lo
//  mismo.
Item {
    id: indicador

    property bool interactive: false
    signal parar()

    visible: Captura.grabando || Captura.estado === "cerrando"

    implicitWidth: fila.implicitWidth
    implicitHeight: fila.implicitHeight

    RowLayout {
        id: fila
        anchors.fill: parent
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
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -3
        enabled: indicador.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: indicador.parar()
    }
}
