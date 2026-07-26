import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    // ── reacciones a la simulación ────────────────────────────────
    Connections {
        target: Game

        function onImpacto(indice, daño) {
            const celda = filaEnemigos.itemAt(indice)
            if (celda) celda.golpear(Game.cifra(daño))
        }

        function onHeroeHerido(indice, daño) {
            const celda = filaHeroes.itemAt(indice)
            if (celda) celda.golpear("-" + Game.cifra(daño))
        }

        function onCurado(indice, cantidad) {
            const celda = filaHeroes.itemAt(indice)
            if (celda) celda.curar("+" + Game.cifra(cantidad))
        }

        function onHabilidadLanzada(indice) {
            const celda = filaHeroes.itemAt(indice)
            if (celda) celda.destellar()
        }
    }

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
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(Game.esJefe ? 0xF0BC2 : 0xF04E5)
                color: Game.esJefe ? Theme.red : Theme.muted
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: "Oleada " + Game.oleada
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Game.esJefe ? Theme.red : Theme.ink
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                visible: Game.esJefe
                text: "jefe"
                color: Theme.red
                font.pixelSize: 9
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    { g: 0xF0114, v: Game.cifra(Game.oro),    c: "#ffd60a" },
                    { g: 0xF04D6, v: Game.cofres + "",        c: "#c78fff" },
                    { g: 0xF0C0F, v: Game.mejorOleada + "",   c: Theme.muted }
                ]

                delegate: RowLayout {
                    required property var modelData
                    spacing: 4
                    Layout.alignment: Qt.AlignVCenter

                    IconGlyph {
                        text: String.fromCodePoint(parent.modelData.g)
                        color: parent.modelData.c
                        font.pixelSize: 12
                    }

                    IslandLabel {
                        text: parent.modelData.v
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── campo de batalla ──────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 126
            radius: 12
            color: Theme.surface
            clip: true

            // suelo
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 26
                color: Theme.surfaceHi
                opacity: 0.45
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                // ── el grupo
                Repeater {
                    id: filaHeroes
                    model: Game.grupo

                    delegate: Combatiente {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        sprite: "assets/heroes/" + Game.claseDe(modelData.clase).sprite + ".png"
                        vida: modelData.vida
                        vidaMax: Game.vidaMaxDe(modelData)
                        colorVida: Theme.green
                        nombre: Game.claseDe(modelData.clase).nombre
                        mirandoDerecha: true

                        // recarga de la habilidad, como aro bajo el sprite
                        recarga: Game.claseDe(modelData.clase).recarga
                        recargaRestante: modelData.recargaRestante
                        glifoHabilidad: Game.claseDe(modelData.clase).glifo
                        pulsable: Game.habilidadLista(index)
                        onLanzar: Game.lanzar(index)
                    }
                }

                IslandLabel {
                    text: "vs"
                    color: Theme.dim
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignVCenter
                }

                // ── la oleada
                Repeater {
                    id: filaEnemigos
                    model: Game.enemigos

                    delegate: Combatiente {
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        sprite: (modelData.jefe ? "assets/jefes/" : "assets/monstruos/")
                            + modelData.sprite + ".png"
                        vida: modelData.vida
                        vidaMax: modelData.vidaMax
                        colorVida: modelData.jefe ? Theme.red : "#ff9f0a"
                        mirandoDerecha: false
                        escala: modelData.jefe ? 1.15 : 1
                    }
                }
            }

            // ── fin de partida
            Rectangle {
                anchors.fill: parent
                color: "#e6000000"
                visible: !Game.viva && Game.finalizada.length > 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    IslandLabel {
                        text: Game.finalizada
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Theme.red
                        Layout.alignment: Qt.AlignHCenter
                    }

                    IslandLabel {
                        text: "récord: oleada " + Game.mejorOleada + " · "
                            + Game.partidas + (Game.partidas === 1 ? " partida" : " partidas")
                        color: Theme.muted
                        font.pixelSize: 10
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Rectangle {
                        Layout.preferredWidth: reiniciar.implicitWidth + 30
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        radius: 13
                        color: reinicioMouse.containsMouse ? Theme.blue : Theme.surfaceHi

                        Behavior on color { ColorAnimation { duration: 120 } }

                        IslandLabel {
                            id: reiniciar
                            anchors.centerIn: parent
                            text: "Nueva partida"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: reinicioMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Game.nuevaPartida()
                        }
                    }
                }
            }
        }

        // ── tienda de la partida ──────────────────────────────────
        Repeater {
            model: Game.mejorasDef

            delegate: Rectangle {
                id: fila
                required property var modelData
                readonly property bool asequible: Game.viva && Game.puedePagar(modelData.id)

                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 8
                color: compraMouse.containsMouse && asequible ? Theme.surfaceHi : Theme.surface
                border.width: asequible ? 1 : 0
                border.color: Theme.green

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    IconGlyph {
                        text: String.fromCodePoint(fila.modelData.glifo)
                        color: fila.asequible ? Theme.ink : Theme.dim
                        font.pixelSize: 14
                        Layout.preferredWidth: 18
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IslandLabel {
                        text: fila.modelData.nombre
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IslandLabel {
                        text: "nv " + Game.niveles[fila.modelData.id]
                        color: Theme.dim
                        font.pixelSize: 10
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IslandLabel {
                        text: fila.modelData.desc
                        color: Theme.muted
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IconGlyph {
                        text: String.fromCodePoint(0xF0114)
                        color: fila.asequible ? "#ffd60a" : Theme.dim
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IslandLabel {
                        text: Game.cifra(Game.coste(fila.modelData.id))
                        color: fila.asequible ? "#ffd60a" : Theme.dim
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                MouseArea {
                    id: compraMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: fila.asequible ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Game.comprar(fila.modelData.id)
                }
            }
        }
    }
}
