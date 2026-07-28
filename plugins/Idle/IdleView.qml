//  Píldora plegada, en tres zonas.
//
//  El centro va anclado al centro de verdad de la island, no metido entre dos
//  espaciadores flexibles: con espaciadores, un RowLayout centra el grupo del
//  medio respecto al CONTENIDO de los flancos, así que la hora se corría medio
//  ancho de lo que hubiera a la derecha y se movía sola al aparecer un icono de
//  bandeja o el aviso del juego.
//
//  Reparto: los espacios de trabajo a la izquierda, la hora en el centro y los
//  indicadores a la derecha. El plugin reserva el mismo hueco a los dos lados,
//  que es lo que hace que se lea simétrica aunque uno esté vacío.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var tray: null
    property int shown: 0

    Item {
        anchors.fill: parent
        anchors.leftMargin: 11
        anchors.rightMargin: 11

        // ── izquierda
        RowLayout {
            id: izquierda
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Artwork {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                visible: Media.isPlaying
            }

            RowLayout {
                spacing: 4
                Layout.alignment: Qt.AlignVCenter

                Repeater {
                    model: Workspaces.list

                    delegate: Rectangle {
                        required property var modelData
                        Layout.preferredWidth: modelData.focused ? 18 : 6
                        Layout.preferredHeight: 6
                        Layout.alignment: Qt.AlignVCenter
                        radius: 3
                        color: modelData.focused ? Theme.ink : Theme.track

                        Behavior on Layout.preferredWidth {
                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }

                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
            }
        }

        // ── centro
        IslandLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(Clock.date, "HH:mm")
            font.pixelSize: 12
            font.weight: Font.Medium
            color: Media.hasPlayer ? Theme.ink : Theme.muted
        }

        // ── derecha
        //  Indicadores nada más: aquí no se puede pinchar, porque al acercar el
        //  ratón la island ya ha cambiado a la vista de reloj o de reproductor.
        //  Es en esas donde la fila es pulsable.
        RowLayout {
            id: derecha
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Visualizer {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 12
                visible: Media.isPlaying
            }

            GrabacionPildora { Layout.alignment: Qt.AlignVCenter }

            JuegoPildora { Layout.alignment: Qt.AlignVCenter }

            TrayRow {
                max: view.shown
                iconSize: 14
                interactive: false
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
