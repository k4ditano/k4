import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var tray: null
    property var juego: null

    //  Lo que mide de verdad el grupo de la derecha, para que el plugin sepa
    //  cuánto tiene que reservar. Se mide aquí porque es aquí donde están los
    //  widgets con su fuente puesta: cuánto ocupa «🔔 claude · k4» no se sabe
    //  contando constantes, y contándolas era como se sabía —de ahí que las
    //  píldoras de los agentes acabaran pintadas encima de la hora—.
    readonly property int anchoDerecho: grupoDer.implicitWidth

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 0
        anchors.bottomMargin: Notifs.recent.length > 0 ? 12 : 0
        spacing: 6

        // Tres zonas ancladas, igual que en la píldora: la hora al centro real
        // de la island. Antes iba pegada al grupo de la derecha, detrás de un
        // único espaciador, así que ni estaba centrada ni se quedaba quieta.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 68

            ColumnLayout {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                IslandLabel {
                    text: Clock.date.toLocaleDateString(Idioma.locale, "dddd")
                    color: Theme.muted
                    font.pixelSize: 11
                    font.capitalization: Font.Capitalize
                }

                IslandLabel {
                    text: Clock.date.toLocaleDateString(Idioma.locale, "d MMMM")
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }

            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                font.pixelSize: 30
                font.weight: Font.Light
            }

            RowLayout {
                id: grupoDer
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Minimizados {
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                }

                GrabacionPildora {
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                    onParar: Captura.parar()
                }

                JuegoPildora {
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                    onAbrir: if (view.juego) view.juego.toggle()
                }

                PluginPildora {
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                }

                // La island ya está desplegada y quieta: aquí sí se pincha.
                TrayRow {
                    max: 5
                    iconSize: 16
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                    onMenuRequested: if (view.tray) view.tray.toggle()
                }
            }
        }

        // Lo que acaba de llegar, sin tener que abrir el panel.
        NotifStrip {
            max: 3
            Layout.fillWidth: true
        }
    }
}
