import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    readonly property var notification: Notifs.latest
    readonly property string icon: Notifs.iconFor(notification)
    readonly property var actions: Notifs.buttons(notification)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            Layout.alignment: Qt.AlignVCenter
            radius: 19
            color: Theme.surface
            clip: true

            // el icono que manda la aplicación; la campana es el último recurso
            Image {
                anchors.fill: parent
                anchors.margins: 6
                source: view.icon
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 76
                sourceSize.height: 76
                visible: status === Image.Ready
            }

            IconGlyph {
                anchors.centerIn: parent
                visible: view.icon.length === 0
                text: Theme.ico.bell
                color: Theme.ink
                font.pixelSize: 17
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 6

                IslandLabel {
                    //  Sin saltos: el título es UNA línea, y uno con `\n`
                    //  dentro empujaba la banda entera hacia abajo.
                    text: view.notification
                        ? view.notification.summary.replace(/\s*\n\s*/g, " ")
                        : Idioma.t("Notificación")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.fillWidth: true
                }

                IslandLabel {
                    text: view.notification ? view.notification.appName : ""
                    color: Theme.muted
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.maximumWidth: 90
                }
            }

            IslandLabel {
                Layout.fillWidth: true
                //  Los saltos de línea del cuerpo, a espacios: aquí SÍ hay
                //  tope de líneas, pero un cuerpo de tres renglones cortos
                //  gastaba las dos en el salto y dejaba media banda vacía
                //  con lo importante fuera. Corrido, el elide remata.
                text: view.notification
                    ? view.notification.body.replace(/\s*\n\s*/g, " ") : ""
                color: Theme.muted
                font.pixelSize: 11
                maximumLineCount: view.actions.length > 0 ? 1 : 2
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
            }

            // Botones que manda la aplicación. k4 declara actionsSupported, así
            // que si no se pintan el usuario nunca puede pulsarlos.
            RowLayout {
                visible: view.actions.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 6

                Repeater {
                    model: view.actions

                    delegate: Rectangle {
                        id: actionChip
                        required property var modelData
                        Layout.preferredWidth: Math.min(actionLabel.implicitWidth + 20, 150)
                        Layout.preferredHeight: 20
                        radius: 10
                        color: actionMouse.containsMouse ? Theme.blue : Theme.surfaceHi

                        Behavior on color { ColorAnimation { duration: 120 } }

                        IslandLabel {
                            id: actionLabel
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: actionChip.modelData.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Notifs.invokeAction(view.notification, actionChip.modelData)
                                Notifs.dismissToast()
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        MediaButton {
            glyph: Theme.ico.close
            glyphSize: 14
            glyphColor: Theme.muted
            onActivated: Notifs.dismissToast()
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
