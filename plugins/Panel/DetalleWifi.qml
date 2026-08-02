//  El detalle de Wi‑Fi del centro de control. Vivía dentro de
//  PanelView (870 líneas, siete secciones); ahora es una pieza con nombre.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

IslandTile {
    required property var view

    Layout.fillWidth: true
    Layout.fillHeight: true
    pulsable: false
    visible: view.plugin.tab === "wifi"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 26
            spacing: 10

            IslandLabel {
                text: Wifi.activada
                    ? (Wifi.device && Wifi.device.scannerEnabled ? Idioma.t("Buscando redes…") : Idioma.t("Redes"))
                    : Idioma.t("Wi‑Fi desactivado")
                color: Theme.muted
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            IslandSwitch {
                checked: Wifi.activada
                onToggled: Wifi.activada = !Wifi.activada
                Layout.alignment: Qt.AlignVCenter
            }
        }

        ListView {
            //  La barra de la casa: sale sola si hay más de lo que cabe.
            ScrollBar.vertical: IslandScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: Wifi.networks
            boundsBehavior: Flickable.StopAtBounds

            delegate: ConnectionRow {
                required property var modelData
                width: ListView.view.width
                glyph: Wifi.strengthIcon(modelData)
                title: modelData.name.length > 0 ? modelData.name : Idioma.t("(red oculta)")
                subtitle: Wifi.status(modelData)
                active: modelData.connected
                busy: modelData.stateChanging
                secure: Wifi.isSecure(modelData) && !modelData.known
                forgettable: modelData.known
                onActivated: Wifi.activate(modelData)
                onForgotten: modelData.forget()
            }

            IslandLabel {
                anchors.centerIn: parent
                visible: Wifi.networks.length === 0
                text: Wifi.activada ? Idioma.t("Buscando redes…") : Idioma.t("Activa el Wi‑Fi para ver redes")
                color: Theme.muted
                font.pixelSize: 12
            }
        }

        // contraseña de una red protegida
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Wifi.pskTarget ? 40 : 0
            visible: Wifi.pskTarget !== null
            radius: 12
            color: Theme.surfaceHi

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                IconGlyph {
                    text: Theme.ico.lock
                    color: Theme.muted
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignVCenter

                    IslandLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Wifi.pskInput.length === 0
                        text: Wifi.pskTarget ? Idioma.t("Contraseña de ") + Wifi.pskTarget.name : ""
                        color: Theme.dim
                        font.pixelSize: 12
                    }

                    TextInput {
                        id: pskInput
                        cursorDelegate: IslandCursor {}
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true
                        selectionColor: Theme.blue
                        text: Wifi.pskInput
                        onTextEdited: Wifi.pskInput = text

                        Connections {
                            target: Wifi
                            function onPskTargetChanged() {
                                if (Wifi.pskTarget)
                                    Qt.callLater(function () { pskInput.forceActiveFocus() })
                            }
                        }

                        Keys.onPressed: function (event) {
                            if (event.key === Qt.Key_Escape) {
                                Wifi.cancelPsk()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                Wifi.submitPsk()
                                event.accepted = true
                            }
                        }
                    }
                }

                MediaButton {
                    glyph: Theme.ico.check
                    glyphSize: 15
                    glyphColor: Wifi.pskInput.length > 0 ? Theme.green : Theme.dim
                    enabledAction: Wifi.pskInput.length > 0
                    onActivated: Wifi.submitPsk()
                    Layout.alignment: Qt.AlignVCenter
                }

                MediaButton {
                    glyph: Theme.ico.close
                    glyphSize: 14
                    glyphColor: Theme.muted
                    onActivated: Wifi.cancelPsk()
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }
}
