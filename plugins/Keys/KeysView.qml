//  Chuleta de atajos de teclado.
//
//  Cada combinación se pinta con sus teclas en cápsulas sueltas, que se lee
//  mucho mejor que «SUPER + CONTROL + SHIFT + Right» de corrido, y la lista va
//  agrupada por las mismas secciones que tienes en tu configuración.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    // Sin esto hay que hacer clic antes de poder escribir: la raíz de la
    // island se queda el foco y la superficie tarda en recibirlo.
    FocoInicial { id: foco; objetivo: entrada }
    Component.onCompleted: foco.reclamar()

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        // ── cabecera ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF030C)
                color: Theme.muted
                font.pixelSize: 15
                Layout.alignment: Qt.AlignVCenter
            }

            TextInput {
                id: entrada
                cursorDelegate: IslandCursor {}
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                text: view.plugin.query
                onTextEdited: view.plugin.query = text

                color: Theme.ink
                font.pixelSize: 15
                font.family: Theme.uiFont
                selectByMouse: true
                selectionColor: Theme.blue
                cursorVisible: true
                verticalAlignment: TextInput.AlignVCenter
                focus: true
                clip: true

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: entrada.text.length === 0
                    text: Idioma.t("Buscar atajo, tecla o acción…")
                    color: Theme.dim
                    font.pixelSize: 15
                }
            }

            IslandLabel {
                text: view.plugin.count + Idioma.t(" de ") + Atajos.lista.length
                color: Theme.dim
                font.pixelSize: 10
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

        // ── la lista ──────────────────────────────────────────────
        ListView {
            //  La barra de la casa: se ve solo si hay más de lo que cabe.
            ScrollBar.vertical: IslandScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 1
            model: view.plugin.lista
            boundsBehavior: Flickable.StopAtBounds

            delegate: Column {
                id: fila
                required property var modelData
                required property int index

                // el título de sección solo cuando cambia, no en cada fila
                readonly property bool abreSeccion: index === 0
                    || view.plugin.lista[index - 1].seccion !== modelData.seccion

                width: ListView.view.width
                spacing: 0

                IslandLabel {
                    visible: fila.abreSeccion
                    height: visible ? 22 : 0
                    verticalAlignment: Text.AlignBottom
                    leftPadding: 4
                    bottomPadding: 3
                    text: fila.modelData.seccion
                    color: Theme.dim
                    font.pixelSize: 9
                    font.capitalization: Font.AllUppercase
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    width: parent.width
                    height: 30
                    radius: 8
                    color: filaRaton.containsMouse ? Theme.surface : "transparent"

                    Behavior on color { ColorAnimation { duration: 110 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 10
                        spacing: 10

                        // ── las teclas, una a una
                        RowLayout {
                            spacing: 3
                            // Sin esto se lleva todo el ancho: un layout dentro
                            // de otro da por hecho que quiere crecer, y la
                            // acción acababa empujada al borde derecho.
                            Layout.fillWidth: false
                            Layout.preferredWidth: 250
                            Layout.alignment: Qt.AlignVCenter

                            Repeater {
                                model: Atajos.teclas(fila.modelData.combo)

                                delegate: Rectangle {
                                    required property var modelData

                                    Layout.preferredWidth: capsula.implicitWidth + 12
                                    Layout.preferredHeight: 18
                                    radius: 5
                                    color: Theme.surfaceHi
                                    border.width: 1
                                    border.color: "#1affffff"

                                    IslandLabel {
                                        id: capsula
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        IslandLabel {
                            //  Por el servicio, que es quien sabe juntar la
                            //  frase traducida con su detalle crudo. Aquí se
                            //  pintaba `hace` a secas y era español dentro de
                            //  una barra en inglés.
                            text: Atajos.hace(fila.modelData)
                            color: Theme.ink
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignLeft
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: filaRaton
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
            }
        }

        IslandLabel {
            Layout.fillWidth: true
            visible: view.plugin.count === 0
            text: Atajos.cargado
                ? Idioma.t("Ningún atajo coincide") : Idioma.t("Leyendo la configuración…")
            color: Theme.muted
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
