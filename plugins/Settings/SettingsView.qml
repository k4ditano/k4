import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 12
        anchors.bottomMargin: 14
        spacing: 10

        // ── cabecera
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 24
            spacing: 9

            IconGlyph {
                text: Theme.ico.cog
                color: Theme.muted
                font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: "Ajustes"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 15
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── grupos de opciones
        Repeater {
            model: Settings.definicion

            delegate: ColumnLayout {
                id: seccion
                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 4

                IslandLabel {
                    text: seccion.modelData.grupo
                    color: Theme.dim
                    font.pixelSize: 9
                    font.capitalization: Font.AllUppercase
                    Layout.leftMargin: 2
                }

                Repeater {
                    model: seccion.modelData.opciones

                    delegate: Rectangle {
                        id: opcion
                        required property var modelData
                        readonly property bool activa: Settings.valor(modelData.id)

                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: 10
                        color: filaMouse.containsMouse ? Theme.surfaceHi : Theme.surface

                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 11

                            IconGlyph {
                                text: String.fromCodePoint(opcion.modelData.glifo)
                                color: opcion.activa ? Theme.ink : Theme.dim
                                font.pixelSize: 15
                                Layout.preferredWidth: 18
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0

                                IslandLabel {
                                    text: opcion.modelData.nombre
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }

                                IslandLabel {
                                    text: opcion.modelData.desc
                                    color: Theme.muted
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            IslandSwitch {
                                checked: opcion.activa
                                onToggled: Settings.alternar(opcion.modelData.id)
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        // toda la fila conmuta, no solo el interruptor: son
                        // objetivos de 40 px de alto, sería absurdo obligar a
                        // apuntar al de 24
                        MouseArea {
                            id: filaMouse
                            anchors.fill: parent
                            anchors.rightMargin: 54     // deja pasar el interruptor
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Settings.alternar(opcion.modelData.id)
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // ── herramientas del sistema
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 30
            spacing: 8

            IslandLabel {
                text: "Herramientas del sistema"
                color: Theme.dim
                font.pixelSize: 9
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    { nombre: "Redes", glifo: 0xF05A9, orden: ["nm-connection-editor"] },
                    { nombre: "Sonido", glifo: 0xF057E, orden: ["pavucontrol"] }
                ]

                delegate: Rectangle {
                    id: herramienta
                    required property var modelData

                    Layout.preferredWidth: contenido.implicitWidth + 22
                    Layout.preferredHeight: 26
                    radius: 13
                    color: herramientaMouse.containsMouse ? Theme.surfaceHi : Theme.surface

                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        id: contenido
                        anchors.centerIn: parent
                        spacing: 6

                        IconGlyph {
                            text: String.fromCodePoint(herramienta.modelData.glifo)
                            color: Theme.muted
                            font.pixelSize: 12
                        }

                        IslandLabel {
                            text: herramienta.modelData.nombre
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: herramientaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(herramienta.modelData.orden)
                            view.plugin.close()
                        }
                    }
                }
            }
        }
    }
}
