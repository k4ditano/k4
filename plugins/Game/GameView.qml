import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 10
        anchors.bottomMargin: 12
        spacing: 8

        // ── cabecera ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            spacing: 7

            IconGlyph {
                text: String.fromCodePoint(Game.esJefe ? 0xF0BC2 : 0xF04E5)
                color: Game.esJefe ? Theme.red : Theme.muted
                font.pixelSize: 13
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: (Game.pausada ? "En pausa · " : "") + "Oleada " + Game.oleada
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Game.esJefe ? Theme.red : Theme.ink
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            // ── pestañas
            Repeater {
                model: [
                    { id: "lucha", etiqueta: "Lucha", glifo: 0xF04E5 },
                    { id: "grupo", etiqueta: "Grupo", glifo: 0xF0849 },
                    { id: "bolsa", etiqueta: "Bolsa", glifo: 0xF04D6 },
                    { id: "altar", etiqueta: "Altar", glifo: 0xF0BC2 }
                ]

                delegate: Rectangle {
                    id: pestaña
                    required property var modelData
                    readonly property bool actual: view.plugin.pestaña === modelData.id

                    Layout.preferredWidth: contenido.implicitWidth + 14
                    Layout.preferredHeight: 20
                    radius: 10
                    color: actual ? Theme.surfaceHi
                        : (pestañaMouse.containsMouse ? Theme.surface : "transparent")

                    Behavior on color { ColorAnimation { duration: 110 } }

                    RowLayout {
                        id: contenido
                        anchors.centerIn: parent
                        spacing: 4

                        IconGlyph {
                            text: String.fromCodePoint(pestaña.modelData.glifo)
                            color: pestaña.actual ? Theme.ink : Theme.muted
                            font.pixelSize: 11
                        }

                        IslandLabel {
                            text: pestaña.modelData.etiqueta
                            color: pestaña.actual ? Theme.ink : Theme.muted
                            font.pixelSize: 10
                            font.weight: pestaña.actual ? Font.DemiBold : Font.Normal
                        }

                        // cuántos cofres esperan, para que no se olviden
                        Rectangle {
                            visible: pestaña.modelData.id === "bolsa" && Game.cofres > 0
                            Layout.preferredWidth: 13
                            Layout.preferredHeight: 12
                            radius: 6
                            color: "#c78fff"

                            IslandLabel {
                                anchors.centerIn: parent
                                text: Game.cofres
                                color: "#000000"
                                font.pixelSize: 8
                                font.weight: Font.Bold
                            }
                        }
                    }

                    MouseArea {
                        id: pestañaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.plugin.pestaña = pestaña.modelData.id
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    { g: 0xF0114, v: Game.cifra(Game.oro), c: "#ffd60a" },
                    { g: 0xF0BC2, v: Game.cifra(Game.reliquias), c: "#c78fff" }
                ]

                delegate: RowLayout {
                    id: dato
                    required property var modelData
                    spacing: 3
                    Layout.alignment: Qt.AlignVCenter

                    IconGlyph {
                        text: String.fromCodePoint(dato.modelData.g)
                        color: dato.modelData.c
                        font.pixelSize: 11
                    }

                    IslandLabel {
                        text: dato.modelData.v
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            // parar la pelea: para mirar la bolsa con calma, o para dejar de
            // perder héroes mientras se decide algo
            MediaButton {
                glyph: String.fromCodePoint(Game.pausada ? 0xF040A : 0xF03E4)
                glyphSize: 15
                glyphColor: Game.pausada ? "#ffd60a" : Theme.muted
                onActivated: Game.pausada = !Game.pausada
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── panel según pestaña ───────────────────────────────────
        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: view.plugin.pestaña === "grupo" ? panelGrupo
                : view.plugin.pestaña === "bolsa" ? panelBolsa
                : view.plugin.pestaña === "altar" ? panelAltar
                : panelLucha
        }
    }

    Component { id: panelLucha; PanelLucha {} }
    Component { id: panelGrupo; PanelGrupo {} }
    Component { id: panelBolsa; PanelBolsa { plugin: view.plugin } }
    Component { id: panelAltar; PanelAltar {} }
}
