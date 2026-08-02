import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var panel: null
    property var tray: null
    property var juego: null

    readonly property var player: Media.activePlayer
    readonly property real progress: player && player.length > 0
        ? Math.max(0, Math.min(1, player.position / player.length))
        : 0

    // MPRIS no notifica la posición: se sondea solo mientras esta vista existe
    Component.onCompleted: Media.watchPosition()
    Component.onDestruction: Media.unwatchPosition()

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        spacing: 13

        // ── pista
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 44
            spacing: 11

            Artwork {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                IslandLabel {
                    Layout.fillWidth: true
                    text: view.player && view.player.trackTitle.length > 0
                        ? view.player.trackTitle
                        : Idioma.t("Sin reproducción")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                IslandLabel {
                    Layout.fillWidth: true
                    text: view.player && view.player.trackArtist.length > 0
                        ? view.player.trackArtist
                        : (view.player ? view.player.identity : "")
                    color: Theme.muted
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Visualizer {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 4
            }

            // Con música sonando, la island que se abre al pasar el ratón es
            // esta y no la del reloj: si el contador de grabación no fuera
            // pulsable aquí, no habría forma de pararla con el ratón.
            Minimizados {
                interactive: true
                Layout.leftMargin: 4
                Layout.alignment: Qt.AlignVCenter
            }

            GrabacionPildora {
                interactive: true
                Layout.leftMargin: 4
                Layout.alignment: Qt.AlignVCenter
                onParar: Captura.parar()
            }

            JuegoPildora {
                interactive: true
                Layout.leftMargin: 2
                Layout.alignment: Qt.AlignVCenter
                onAbrir: if (view.juego) view.juego.toggle()
            }

            PluginPildora {
                interactive: true
                Layout.leftMargin: 2
                Layout.alignment: Qt.AlignVCenter
            }

            // Igual que en el reloj: es aquí, con la island ya desplegada,
            // donde los iconos de bandeja se pueden pulsar.
            TrayRow {
                max: 4
                iconSize: 16
                interactive: true
                Layout.leftMargin: 4
                Layout.alignment: Qt.AlignVCenter
                onMenuRequested: if (view.tray) view.tray.toggle()
            }
        }

        // ── línea de tiempo
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 12
            spacing: 8
            visible: Media.hasTimeline

            IslandLabel {
                text: view.player ? Media.formatTime(view.player.position) : "0:00"
                color: Theme.muted
                font.pixelSize: 10
                Layout.preferredWidth: 28
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 12
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    id: seekTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: seekMouse.containsMouse ? 6 : 4
                    radius: height / 2
                    color: Theme.track

                    Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    Rectangle {
                        width: seekTrack.width * view.progress
                        height: parent.height
                        radius: parent.radius
                        color: Theme.ink

                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    }
                }

                MouseArea {
                    id: seekMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function (mouse) { Media.seekTo(mouse.x / width) }
                }
            }

            IslandLabel {
                text: view.player && view.player.length > 0
                    ? "-" + Media.formatTime(view.player.length - view.player.position)
                    : "0:00"
                color: Theme.muted
                font.pixelSize: 10
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 32
            }
        }

        // ── transporte
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 30
            spacing: 0

            MediaButton {
                glyph: Theme.ico.shuffle
                glyphSize: 14
                glyphColor: view.player && view.player.shuffle ? Theme.ink : Theme.muted
                enabledAction: !!view.player && view.player.shuffleSupported
                onActivated: view.player.shuffle = !view.player.shuffle
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            MediaButton {
                glyph: Theme.ico.prev
                glyphSize: 20
                enabledAction: !!view.player && view.player.canGoPrevious
                onActivated: view.player.previous()
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Media.isPlaying ? Theme.ico.pause : Theme.ico.play
                glyphSize: 24
                enabledAction: !!view.player && view.player.canTogglePlaying
                onActivated: view.player.togglePlaying()
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.next
                glyphSize: 20
                enabledAction: !!view.player && view.player.canGoNext
                onActivated: view.player.next()
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            MediaButton {
                glyph: Theme.ico.output
                glyphSize: 15
                glyphColor: Theme.muted
                onActivated: if (view.panel) view.panel.toggle()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Lo que acaba de llegar, también con música sonando.
        NotifStrip {
            max: 3
            Layout.fillWidth: true
            Layout.topMargin: 2
        }
    }
}
