//  La bolsa: abrir cofres, equipar y desguazar.
//
//  Clic izquierdo equipa en el héroe al que más le sirve; clic derecho
//  desguaza a cambio de reliquias.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: panel

    spacing: 6

    property var ultimo: null           // lo último que salió de un cofre

    // A quién le viene mejor una pieza: la clase que más gana con ella. Así
    // equipar es un clic y no un menú.
    function mejorDestino(objeto) {
        let mejor = Game.clases[0].id
        let ganancia = -Infinity

        for (let i = 0; i < Game.clases.length; ++i) {
            const clase = Game.clases[i].id
            const puesto = (Game.equipo[clase] || ({}))[objeto.hueco]
            const delta = Items.puntuacion(objeto) - Items.puntuacion(puesto)

            // el arma le luce más a quien más daño base tiene, y la armadura
            // a quien aguanta: se pondera por el papel de la clase
            const peso = objeto.hueco === "arma" ? Game.clases[i].daño / 10
                : objeto.hueco === "armadura" || objeto.hueco === "escudo"
                    ? Game.clases[i].vida / 150 : 1

            if (delta * peso > ganancia) {
                ganancia = delta * peso
                mejor = clase
            }
        }
        return mejor
    }

    // ── cofres ────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        // los layouts anidados traen fillHeight activado: sin esto la fila de
        // cofres se estira y se come el panel entero
        Layout.fillHeight: false
        Layout.preferredHeight: 34
        spacing: 6

        Repeater {
            model: Items.cofres

            delegate: Rectangle {
                id: cofre
                required property var modelData
                required property int index
                readonly property int cuantos: Game.cofresPorTipo[index]

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 9
                color: cofreMouse.containsMouse && cuantos > 0 ? Theme.surfaceHi : Theme.surface
                border.width: cuantos > 0 ? 1 : 0
                border.color: cofre.modelData.color
                opacity: cuantos > 0 ? 1 : 0.45

                Behavior on color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    spacing: 7

                    IconGlyph {
                        text: String.fromCodePoint(cofre.modelData.glifo)
                        color: cofre.modelData.color
                        font.pixelSize: 15
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        IslandLabel {
                            text: cofre.modelData.nombre
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        IslandLabel {
                            text: cofre.cuantos > 0 ? "pulsa para abrir" : "no tienes"
                            color: Theme.dim
                            font.pixelSize: 8
                        }
                    }

                    IslandLabel {
                        text: cofre.cuantos
                        color: cofre.cuantos > 0 ? Theme.ink : Theme.dim
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                MouseArea {
                    id: cofreMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: cofre.cuantos > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const salio = Game.abrirCofre(cofre.index)
                        if (salio)
                            panel.ultimo = salio
                    }
                }
            }
        }
    }

    // ── lo último que salió ───────────────────────────────────────
    ObjetoFila {
        Layout.fillWidth: true
        Layout.preferredHeight: panel.ultimo ? 28 : 0
        visible: panel.ultimo !== null
        objeto: panel.ultimo
        onPulsado: {
            if (panel.ultimo) {
                Game.equipar(panel.ultimo, panel.mejorDestino(panel.ultimo))
                panel.ultimo = null
            }
        }
    }

    // ── la bolsa ──────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 20
        spacing: 8

        IslandLabel {
            text: Game.bolsa.length + " / " + Game.topeBolsa + " piezas"
            color: Theme.muted
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter
        }

        IslandLabel {
            text: "izquierdo equipa · derecho desguaza"
            color: Theme.dim
            font.pixelSize: 9
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }

        Rectangle {
            Layout.preferredWidth: limpiar.implicitWidth + 20
            Layout.preferredHeight: 20
            radius: 10
            color: limpiarMouse.containsMouse ? Theme.red : Theme.surfaceHi
            visible: Game.bolsa.length > 0

            Behavior on color { ColorAnimation { duration: 120 } }

            IslandLabel {
                id: limpiar
                anchors.centerIn: parent
                text: "Desguazar sobrantes"
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }

            MouseArea {
                id: limpiarMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Game.desguazarSobrantes()
            }
        }
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds

        // las mejores arriba: con sesenta piezas, buscar a ojo es inviable
        model: Game.bolsa.slice().sort(function (a, b) {
            return Items.puntuacion(b) - Items.puntuacion(a)
        })

        delegate: ObjetoFila {
            id: pieza
            required property var modelData
            width: ListView.view.width
            objeto: modelData
            onPulsado: Game.equipar(modelData, panel.mejorDestino(modelData))
            onSecundario: Game.desguazar(modelData)
        }

        IslandLabel {
            anchors.centerIn: parent
            visible: Game.bolsa.length === 0
            text: Game.cofres > 0 ? "Abre un cofre ahí arriba" : "La bolsa está vacía"
            color: Theme.muted
            font.pixelSize: 11
        }
    }
}
