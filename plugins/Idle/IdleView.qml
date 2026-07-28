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

    // ── los escritorios asoman al cambiar ─────────────────────────
    property bool mostrandoEscritorios: false

    //  El primer cambio de `activo` es el de arrancar —pasa de -1 al que
    //  toque—, y no es un cambio de escritorio: sin esta guarda la píldora
    //  enseñaría los puntos cada vez que se recarga la barra.
    property bool arrancado: false

    Component.onCompleted: arranque.start()

    Timer {
        id: arranque
        interval: 700
        onTriggered: view.arrancado = true
    }

    Connections {
        target: Workspaces
        function onActivoChanged() {
            if (!view.arrancado)
                return
            view.mostrandoEscritorios = true
            volver.restart()
        }
    }

    Timer {
        id: volver
        interval: 1800
        onTriggered: view.mostrandoEscritorios = false
    }

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

            // Las barras, pegadas a la carátula. Estaban al otro lado de la
            // píldora, y eso obligaba a mirar a dos sitios para saber si
            // suena algo y qué es: son la misma información.
            Visualizer {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 12
                visible: Media.isPlaying
            }

        }

        // ── centro
        //
        //  La hora casi siempre, y los escritorios solo cuando cambias de uno:
        //  aparecen en su sitio, se dejan ver un par de segundos y se van. Los
        //  puntos fijos a la izquierda estaban ahí todo el día para decir algo
        //  que solo importa en el instante en que cambia.
        Item {
            id: centro
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(46, Workspaces.dotsWidth - 8)
            height: parent.height

            IslandLabel {
                anchors.centerIn: parent
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                font.pixelSize: 12
                font.weight: Font.Medium
                color: Media.hasPlayer ? Theme.ink : Theme.muted

                opacity: view.mostrandoEscritorios ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 4

                opacity: view.mostrandoEscritorios ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

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

        // ── derecha
        //  Indicadores nada más: aquí no se puede pinchar, porque al acercar el
        //  ratón la island ya ha cambiado a la vista de reloj o de reproductor.
        //  Es en esas donde la fila es pulsable.
        RowLayout {
            id: derecha
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

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
