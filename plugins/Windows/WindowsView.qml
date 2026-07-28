//  Las ventanas abiertas, en fila.
//
//  Icono grande y nombre debajo, como un Alt+Tab de toda la vida. El título
//  completo va solo en la seleccionada: doce títulos a la vez no se leen, y
//  el que importa es el de la que vas a abrir.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    focus: true

    Keys.onPressed: function (ev) {
        if (ev.key === Qt.Key_Tab || ev.key === Qt.Key_Right) {
            view.plugin.avanzar(); ev.accepted = true
        } else if (ev.key === Qt.Key_Backtab || ev.key === Qt.Key_Left) {
            view.plugin.retroceder(); ev.accepted = true
        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter
                   || ev.key === Qt.Key_Space) {
            view.plugin.elegir(); ev.accepted = true
        } else if (ev.key === Qt.Key_Delete || ev.key === Qt.Key_W) {
            view.plugin.cerrarActual(); ev.accepted = true
        }
    }

    // Soltar la tecla de sistema confirma, que es como se comporta un Alt+Tab.
    Keys.onReleased: function (ev) {
        if (ev.key === Qt.Key_Super_L || ev.key === Qt.Key_Super_R
            || ev.key === Qt.Key_Alt) {
            view.plugin.elegir()
            ev.accepted = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 110
            spacing: 8

            Repeater {
                model: view.plugin.lista

                delegate: Rectangle {
                    id: tarjeta
                    required property var modelData
                    required property int index

                    readonly property bool elegida: index === view.plugin.index

                    Layout.preferredWidth: 120
                    Layout.fillHeight: true
                    radius: 12
                    color: elegida ? Theme.surfaceHi
                        : (tarjetaRaton.containsMouse ? Theme.surface : "transparent")
                    border.width: elegida ? 1 : 0
                    border.color: Theme.blue

                    Behavior on color { ColorAnimation { duration: 110 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 5

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46

                            Image {
                                id: retrato
                                anchors.fill: parent
                                source: Ventanas.icono(tarjeta.modelData)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }

                            // Sin icono, un símbolo: dejar el hueco vacío
                            // descuadraba la tarjeta frente a las demás.
                            IconGlyph {
                                anchors.centerIn: parent
                                visible: retrato.status !== Image.Ready
                                text: String.fromCodePoint(0xF08C6)
                                color: Theme.muted
                                font.pixelSize: 34
                            }
                        }

                        IslandLabel {
                            Layout.fillWidth: true
                            text: Ventanas.titulo(tarjeta.modelData)
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 11
                            font.weight: tarjeta.elegida ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    // En qué escritorio vive. Es la mitad de la información
                    // cuando tienes ventanas repartidas: saber que la que
                    // buscas está en el 3 evita ir probando.
                    Rectangle {
                        visible: Ventanas.espacio(tarjeta.modelData).length > 0
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        width: Math.max(16, espacioTexto.implicitWidth + 8)
                        height: 15
                        radius: 7
                        color: tarjeta.elegida ? Theme.blue : "#66000000"

                        IslandLabel {
                            id: espacioTexto
                            anchors.centerIn: parent
                            text: Ventanas.espacio(tarjeta.modelData)
                            color: Theme.ink
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: tarjetaRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: function (raton) {
                            view.plugin.index = tarjeta.index
                            if (raton.button === Qt.MiddleButton)
                                view.plugin.cerrarActual()
                            else
                                view.plugin.elegir()
                        }
                    }
                }
            }
        }

        // ── el título de la elegida, entero
        IslandLabel {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: {
                const t = view.plugin.lista[view.plugin.index]
                return t ? Ventanas.tituloVentana(t) : ""
            }
            color: Theme.muted
            font.pixelSize: 11
            elide: Text.ElideMiddle
        }

        IslandLabel {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: view.plugin.count === 0
            text: Idioma.t("No hay ventanas abiertas")
            color: Theme.dim
            font.pixelSize: 11
        }

        IslandLabel {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: view.plugin.count > 0
            text: Idioma.t("tab pasa · intro abre · supr cierra · esc cancela")
            color: Theme.dim
            font.pixelSize: 9
        }
    }
}
