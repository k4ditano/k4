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
                text: (Game.pausada ? Idioma.t("En pausa · ") : "") + Idioma.t("Oleada ") + Game.oleada
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Game.esJefe ? Theme.red : Theme.ink
                elide: Text.ElideRight
                // cede el primero si la cabecera se queda corta, en vez de
                // empujar las pestañas fuera de la island
                Layout.maximumWidth: 150
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            // ── pestañas
            Repeater {
                model: [
                    { id: "lucha", etiqueta: "Lucha", glifo: 0xF04E5 },
                    { id: "grupo", etiqueta: "Grupo", glifo: 0xF0849 },
                    { id: "equipo", etiqueta: "Plantilla", glifo: 0xF0004 },
                    { id: "bolsa", etiqueta: "Bolsa", glifo: 0xF04D6 },
                    { id: "altar", etiqueta: "Altar", glifo: 0xF0BC2 },
                    { id: "logros", etiqueta: "Logros", glifo: 0xF012C }
                ]

                delegate: Rectangle {
                    id: pestaña
                    required property var modelData
                    readonly property bool actual: view.plugin.pestaña === modelData.id

                    Layout.preferredWidth: contenido.implicitWidth + 11
                    Layout.preferredHeight: 20
                    radius: 10
                    color: actual ? Theme.surfaceHi
                        : (pestañaMouse.containsMouse ? Theme.surface : "transparent")

                    Behavior on color { ColorAnimation { duration: 110 } }

                    RowLayout {
                        id: contenido
                        anchors.centerIn: parent
                        spacing: 3

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

                            // Crece con la cifra, que con seiscientos cofres se
                            // salía del círculo. Y morado oscuro con letra
                            // blanca: en negro sobre lila claro no se leía.
                            Layout.preferredWidth: Math.max(14, cuantosCofres.implicitWidth + 9)
                            Layout.preferredHeight: 13
                            radius: height / 2
                            color: "#7b3fe4"

                            IslandLabel {
                                id: cuantosCofres
                                anchors.centerIn: parent
                                text: Game.cifra(Game.cofres)
                                color: "#ffffff"
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

            // ── depósito de chispa
            //  Solo en modo vibecoding. El relleno es el depósito y el rayo se
            //  enciende mientras estás gastando: de un vistazo sabes si el
            //  grupo pelea con lo que ganas ahora o con lo ahorrado.
            Rectangle {
                id: deposito
                visible: Settings.juegoPorTokens
                Layout.preferredWidth: chispaFila.implicitWidth + 18
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                radius: 9
                color: Theme.surface

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    // El relleno lleva el mismo radio que la píldora: `clip`
                    // recorta en rectángulo, no en redondeado, y ademas se
                    // comia el aviso de abajo.
                    width: Math.max(parent.height, parent.width * Tokens.llenado)
                    radius: parent.radius
                    visible: Tokens.deposito > 0
                    color: Tokens.activo ? "#3affd60a" : "#1fffd60a"

                    Behavior on width { NumberAnimation { duration: 400 } }
                    Behavior on color { ColorAnimation { duration: 300 } }
                }

                RowLayout {
                    id: chispaFila
                    anchors.centerIn: parent
                    spacing: 4

                    IconGlyph {
                        text: String.fromCodePoint(0xF0241)
                        color: Tokens.activo && !Game.pausada ? "#ffd60a" : Theme.dim
                        font.pixelSize: 11
                    }

                    IslandLabel {
                        // El título ya dice «En pausa»: repetirlo aquí lo
                        // decía dos veces y ensanchaba la cabecera hasta pegar
                        // los botones al borde. Basta con apagar el color para
                        // que se vea que el depósito no está bajando.
                        text: Tokens.resto()
                        color: Game.pausada ? Theme.dim
                            : (Tokens.hay ? Theme.ink : Theme.muted)
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }

                // el ingreso se ve caer: sin esto no hay forma de saber que
                // lo que acabas de escribir ha entrado
                IslandLabel {
                    id: aviso
                    // a la izquierda, no debajo: debajo se salia de la banda
                    // de la cabecera y quedaba tapado
                    anchors.right: parent.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+" + Tokens.cifra(Tokens.ultimaCantidad) + " " + Tokens.ultimaFuente
                    color: "#ffd60a"
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    opacity: 0

                    SequentialAnimation {
                        id: destello
                        NumberAnimation {
                            target: aviso; property: "opacity"
                            to: 1; duration: 140
                        }
                        PauseAnimation { duration: 900 }
                        NumberAnimation {
                            target: aviso; property: "opacity"
                            to: 0; duration: 420
                        }
                    }

                    Connections {
                        target: Tokens
                        function onIngreso() { destello.restart() }
                    }
                }
            }

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
                : view.plugin.pestaña === "equipo" ? panelPlantilla
                : view.plugin.pestaña === "logros" ? panelLogros
                : view.plugin.pestaña === "bolsa" ? panelBolsa
                : view.plugin.pestaña === "altar" ? panelAltar
                : panelLucha
        }
    }

    Component { id: panelLucha; PanelLucha { plugin: view.plugin } }
    Component { id: panelGrupo; PanelGrupo { plugin: view.plugin } }
    Component { id: panelBolsa; PanelBolsa { plugin: view.plugin } }
    Component { id: panelAltar; PanelAltar {} }
    Component { id: panelPlantilla; PanelPlantilla {} }
    Component { id: panelLogros; PanelLogros {} }
}
