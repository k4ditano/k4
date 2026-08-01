//  El digivice en la píldora: una pantallita LCD de fósforo con el K4MON
//  dentro. Cristal con tinte de la forma, scanlines, LED de estado, y
//  parpadeo de marco cuando llama con hambre — se ve desde la otra punta
//  de la habitación, que es exactamente para lo que existe un digivice.
//
//  En la píldora no se pulsa (al acercar el ratón la island ya cambia de
//  vista); en las vistas de hover sí, con `interactive: true`.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: indicador

    property bool interactive: false
    signal abrir()

    visible: Settings.kmonActivo && Kmon.cargado
        && (interactive || Settings.kmonEnPildora)
    spacing: 4

    //  El reloj de los transitorios y del ciclo de andar: el vaivén de dos
    //  frames es lo que hace que una pantalla de fósforo parezca viva.
    property real ahora: Date.now() / 1000
    property bool alterno: false
    Timer {
        interval: 900
        repeat: true
        running: indicador.visible
        onTriggered: {
            indicador.ahora = Date.now() / 1000
            indicador.alterno = !indicador.alterno
        }
    }

    Rectangle {
        id: carcasa
        Layout.preferredWidth: 30
        Layout.preferredHeight: 24
        Layout.alignment: Qt.AlignVCenter
        radius: 6
        color: "#2b2d31"
        border.width: 1
        //  El marco parpadea con la llamada de hambre.
        border.color: Kmon.llamando && _parpadeo ? Theme.red : "#45484f"

        property bool _parpadeo: false
        Timer {
            interval: 550
            repeat: true
            running: indicador.visible && Kmon.llamando
            onTriggered: carcasa._parpadeo = !carcasa._parpadeo
        }

        //  El cristal: LCD gris verdoso de mascota virtual, píxeles negros.
        Rectangle {
            id: cristal
            anchors.fill: parent
            anchors.margins: 3
            radius: 3
            color: "#a9b39c"
            clip: true

            Image {
                id: sprite
                anchors.centerIn: parent
                //  El reloj de la píldora entra en el binding a propósito:
                //  los transitorios (salto, eclosión) caducan por tiempo y
                //  sin él la imagen no se reevaluaría.
                source: {
                    indicador.ahora
                    return Qt.resolvedUrl("../plugins/Kmon/assets/"
                                          + Kmon.spriteLcd(indicador.alterno))
                }
                sourceSize.width: 16
                sourceSize.height: 16
                smooth: false

                //  El huevo late; la criatura respira.
                SequentialAnimation on scale {
                    running: indicador.visible
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: Kmon.etapa === "huevo" ? 1.12 : 0.94
                        duration: Kmon.etapa === "huevo" ? 600 : 1400
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        to: 1.0
                        duration: Kmon.etapa === "huevo" ? 600 : 1400
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            //  Scanlines suaves sobre el fósforo claro.
            Column {
                anchors.fill: parent
                spacing: 3
                Repeater {
                    model: 6
                    Rectangle {
                        width: cristal.width
                        height: 1
                        color: "#3a4034"
                        opacity: 0.12
                    }
                }
            }

            //  Brillo de cristal en la esquina.
            Rectangle {
                width: parent.width * 0.5
                height: 2
                x: 2; y: 1
                radius: 1
                color: "#ffffff"
                opacity: 0.25
            }
        }

        //  El LED: verde en paz, ámbar con hambre, rojo llamando.
        Rectangle {
            width: 3; height: 3; radius: 1.5
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1.5
            color: Kmon.llamando ? Theme.red
                : Kmon.hambre < 50 ? Theme.yellow : Theme.green
        }

        MouseArea {
            enabled: indicador.interactive
            anchors.fill: parent
            anchors.margins: -3
            cursorShape: Qt.PointingHandCursor
            onClicked: indicador.abrir()
        }
    }
}
