//  La habitación de la mascota: cuidarla en una pestaña, el terrario de la
//  colección en la otra. La vista pregunta al servicio y no decide nada.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    //  El reloj de las poses transitorias, solo mientras se mira.
    property real ahora: Date.now() / 1000
    Timer {
        interval: 1500
        repeat: true
        running: view.visible
        onTriggered: view.ahora = Date.now() / 1000
    }

    function rutaSprite(id, etapa) {
        return Qt.resolvedUrl("assets/coleccion/" + id + "/e0" + etapa + ".png")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 12
        anchors.bottomMargin: 16
        spacing: 10

        // ── cabecera: nombre, humor, pestañas y cerrar
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 9

            IslandLabel {
                text: Mascota.nombre
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            IslandLabel {
                text: "· " + Idioma.t(Mascota.humor)
                color: Theme.muted
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    { id: "cuidar", nombre: Idioma.t("Cuidar") },
                    { id: "terrario", nombre: Idioma.t("Terrario") }
                ]

                delegate: Rectangle {
                    id: pestana
                    required property var modelData
                    readonly property bool puesta: view.plugin.pestana === modelData.id

                    Layout.preferredWidth: textoPestana.implicitWidth + 20
                    Layout.preferredHeight: 24
                    radius: 12
                    color: puesta ? Theme.blue
                        : (pestanaRaton.containsMouse ? Theme.surfaceHi : Theme.track)

                    IslandLabel {
                        id: textoPestana
                        anchors.centerIn: parent
                        text: pestana.modelData.nombre
                        color: pestana.puesta ? Theme.ink : Theme.muted
                        font.pixelSize: 10
                        font.weight: pestana.puesta ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: pestanaRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.plugin.pestana = pestana.modelData.id
                    }
                }
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 15
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── cuidar ────────────────────────────────────────────────
        RowLayout {
            visible: view.plugin.pestana === "cuidar"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 18

            //  La criatura, en grande.
            ColumnLayout {
                Layout.preferredWidth: 170
                Layout.fillHeight: true
                spacing: 6

                Image {
                    source: Mascota.activa === "pulpo"
                        ? Qt.resolvedUrl("assets/base/s0"
                                         + Mascota.poseDe(view.ahora) + ".png")
                        : view.rutaSprite(Mascota.activa, Mascota.etapa)
                    sourceSize.width: 96
                    sourceSize.height: 96
                    smooth: false
                    Layout.alignment: Qt.AlignHCenter

                    //  Respira.
                    SequentialAnimation on scale {
                        running: view.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.04; duration: 1600; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 1600; easing.type: Easing.InOutQuad }
                    }
                }

                IslandLabel {
                    text: Idioma.f(Idioma.t("etapa %1 · %2 días juntos"),
                                   Mascota.etapa + 1,
                                   (Mascota.coleccion[Mascota.activa] || { dias: 0 }).dias)
                    color: Theme.dim
                    font.pixelSize: 9
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            //  Necesidades y acciones.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 7

                Repeater {
                    model: [
                        { nombre: Idioma.t("Saciedad"), valor: Mascota.hambre, color: Theme.yellow },
                        { nombre: Idioma.t("Energía"), valor: Mascota.energia, color: Theme.green },
                        { nombre: Idioma.t("Ánimo"), valor: Mascota.animo, color: Theme.blue },
                        { nombre: Idioma.t("Cariño"), valor: Mascota.carino, color: "#bf5af2" }
                    ]

                    delegate: RowLayout {
                        id: barra
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        IslandLabel {
                            text: barra.modelData.nombre
                            color: Theme.muted
                            font.pixelSize: 10
                            Layout.preferredWidth: 58
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 7
                            radius: 4
                            color: Theme.track

                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, barra.modelData.valor / 100))
                                height: parent.height
                                radius: 4
                                color: barra.modelData.color

                                Behavior on width { NumberAnimation { duration: 300 } }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 2 }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Repeater {
                        model: [
                            { nombre: Idioma.t("Comer"), accion: "comer" },
                            { nombre: Idioma.t("Acariciar"), accion: "acariciar" },
                            { nombre: Idioma.t("Jugar"), accion: "jugar" }
                        ]

                        delegate: Rectangle {
                            id: boton
                            required property var modelData
                            Layout.preferredWidth: textoBoton.implicitWidth + 26
                            Layout.preferredHeight: 28
                            radius: 14
                            color: botonRaton.containsMouse ? Theme.surfaceHi : Theme.surface

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IslandLabel {
                                id: textoBoton
                                anchors.centerIn: parent
                                text: boton.modelData.nombre
                                font.pixelSize: 11
                            }

                            MouseArea {
                                id: botonRaton
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Mascota[boton.modelData.accion]()
                            }
                        }
                    }
                }
            }
        }

        // ── terrario ──────────────────────────────────────────────
        GridLayout {
            visible: view.plugin.pestana === "terrario"
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 5
            rowSpacing: 8
            columnSpacing: 8

            Repeater {
                model: Mascota.especies

                delegate: Rectangle {
                    id: celda
                    required property var modelData
                    readonly property var suya: Mascota.coleccion[modelData.id] || null
                    readonly property bool activa: Mascota.activa === modelData.id

                    Layout.fillWidth: true
                    Layout.preferredHeight: 104
                    radius: 12
                    color: celdaRaton.containsMouse && suya ? Theme.surfaceHi : Theme.surface
                    border.width: activa ? 1 : 0
                    border.color: Theme.blue

                    Behavior on color { ColorAnimation { duration: 120 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 3

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44

                            Image {
                                visible: celda.suya !== null
                                anchors.centerIn: parent
                                source: celda.suya
                                    ? view.rutaSprite(celda.modelData.id,
                                                      Mascota.etapaDe(celda.suya.dias))
                                    : ""
                                sourceSize.width: 44
                                sourceSize.height: 44
                                smooth: false
                            }

                            IconGlyph {
                                visible: celda.suya === null
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xF0AAF)   // huevo
                                color: Theme.dim
                                font.pixelSize: 24
                            }
                        }

                        IslandLabel {
                            text: celda.suya ? celda.modelData.nombre : "???"
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            Layout.fillWidth: true
                        }

                        IslandLabel {
                            text: celda.suya
                                ? Idioma.f(Idioma.t("día %1 · etapa %2"),
                                           celda.suya.dias,
                                           Mascota.etapaDe(celda.suya.dias) + 1)
                                : celda.modelData.pista
                            color: Theme.dim
                            font.pixelSize: 8
                            elide: Text.ElideRight
                            wrapMode: celda.suya ? Text.NoWrap : Text.WordWrap
                            maximumLineCount: 2
                            horizontalAlignment: Text.AlignHCenter
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: celdaRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: celda.suya ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (celda.suya) Mascota.adoptar(celda.modelData.id)
                    }
                }
            }
        }
    }
}
