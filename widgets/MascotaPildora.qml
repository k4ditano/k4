//  La mascota en la píldora: el sprite de la especie activa, con su pose
//  según lo que pasa de verdad en la máquina (services/Mascota.qml decide).
//
//  Como el resto de indicadores, en la píldora no se pulsa —al acercar el
//  ratón la island ya ha cambiado de vista—; en las vistas de hover sí, con
//  `interactive: true`.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: indicador

    property bool interactive: false
    signal abrir()

    visible: Settings.mascotaActiva && Mascota.cargado
        && (interactive || Settings.mascotaEnPildora)
    spacing: 4

    //  El reloj de las poses transitorias (comer, saludar): barato y solo
    //  mientras se ve.
    property real ahora: Date.now() / 1000
    Timer {
        interval: 2000
        repeat: true
        running: indicador.visible
        onTriggered: indicador.ahora = Date.now() / 1000
    }

    Image {
        id: sprite

        //  El pulpo tiene hoja de poses; el resto enseña su etapa evolutiva.
        source: Mascota.activa === "pulpo"
            ? Qt.resolvedUrl("../plugins/Mascota/assets/base/s0"
                             + Mascota.poseDe(indicador.ahora) + ".png")
            : Qt.resolvedUrl("../plugins/Mascota/assets/coleccion/"
                             + Mascota.activa + "/e0" + Mascota.etapa + ".png")
        sourceSize.width: 18
        sourceSize.height: 18
        smooth: false
        Layout.preferredWidth: 18
        Layout.preferredHeight: 18
        Layout.alignment: Qt.AlignVCenter

        //  Con hambre, un balanceo lento de queja; al calmarse, recta.
        readonly property bool quejando: indicador.visible
            && Mascota.humor === "hambrienta"
        onQuejandoChanged: if (!quejando) rotation = 0

        SequentialAnimation on rotation {
            running: sprite.quejando
            loops: Animation.Infinite
            NumberAnimation { to: -9; duration: 500; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 9; duration: 500; easing.type: Easing.InOutQuad }
        }

        //  Dentro del sprite y no del layout: un MouseArea anclado a un hijo
        //  directo de un layout es comportamiento indefinido.
        MouseArea {
            enabled: indicador.interactive
            anchors.fill: parent
            anchors.margins: -3
            cursorShape: Qt.PointingHandCursor
            onClicked: indicador.abrir()
        }
    }
}
