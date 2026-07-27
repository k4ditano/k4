//  La pelea: el grupo contra la oleada, y la tienda de la partida.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: panel

    spacing: 8

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

    // ── campo de batalla ──────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 122
        radius: 12
        color: Theme.surface
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 24
            color: Theme.surfaceHi
            opacity: 0.45
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 6

            // El modelo es la CANTIDAD, no el array: el servicio reasigna
            // grupo y enemigos en cada tic, y un Repeater con modelo de array
            // JS destruye y recrea todos los delegados cada segundo —de ahí
            // que las barras parpadearan—. Con un entero estable los delegados
            // viven, y solo se rehacen si cambia el número de combatientes.
            Repeater {
                id: filaHeroes
                model: Game.grupo.length

                delegate: Combatiente {
                    required property int index
                    readonly property var datos: Game.grupo[index] || ({ clase: "tanque", vida: 0 })

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    sprite: "assets/heroes/" + Game.claseDe(datos.clase).sprite + ".png"
                    vida: datos.vida
                    vidaMax: Game.vidaMaxDe(datos)
                    colorVida: Theme.green
                    mirandoDerecha: true

                    recarga: Game.claseDe(datos.clase).recarga
                    recargaRestante: datos.recargaRestante
                    glifoHabilidad: Game.claseDe(datos.clase).glifo
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

            Repeater {
                id: filaEnemigos
                model: Game.enemigos.length

                delegate: Combatiente {
                    required property int index
                    readonly property var datos: Game.enemigos[index]
                        || ({ vida: 0, vidaMax: 1, sprite: "m00", jefe: false })

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    sprite: (datos.jefe ? "assets/jefes/" : "assets/monstruos/") + datos.sprite + ".png"
                    vida: datos.vida
                    vidaMax: datos.vidaMax
                    colorVida: datos.jefe ? Theme.red : "#ff9f0a"
                    mirandoDerecha: false
                    escala: datos.jefe ? 1.15 : 1
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
                spacing: 5

                IslandLabel {
                    text: Game.finalizada
                    font.pixelSize: 14
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

                IslandLabel {
                    text: "el equipo se conserva; el oro y las mejoras, no"
                    color: Theme.dim
                    font.pixelSize: 9
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.preferredWidth: reiniciar.implicitWidth + 28
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    radius: 12
                    color: reinicioMouse.containsMouse ? Theme.blue : Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: 120 } }

                    IslandLabel {
                        id: reiniciar
                        anchors.centerIn: parent
                        text: "Nueva partida"
                        font.pixelSize: 11
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

    // ── tienda de la partida ──────────────────────────────────────
    Repeater {
        model: Game.mejorasDef

        delegate: Rectangle {
            id: fila
            required property var modelData
            readonly property bool asequible: Game.viva && Game.puedePagar(modelData.id)

            Layout.fillWidth: true
            Layout.preferredHeight: 28
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
                    font.pixelSize: 13
                    Layout.preferredWidth: 16
                    Layout.alignment: Qt.AlignVCenter
                }

                IslandLabel {
                    text: fila.modelData.nombre
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignVCenter
                }

                IslandLabel {
                    text: "nv " + Game.niveles[fila.modelData.id]
                    color: Theme.dim
                    font.pixelSize: 9
                    Layout.alignment: Qt.AlignVCenter
                }

                IslandLabel {
                    text: fila.modelData.desc
                    color: Theme.muted
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                IslandLabel {
                    text: Game.cifra(Game.coste(fila.modelData.id))
                    color: fila.asequible ? "#ffd60a" : Theme.dim
                    font.pixelSize: 11
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
