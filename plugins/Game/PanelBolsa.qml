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

    property var plugin: null
    // pieza bajo el ratón, para el emergente
    property var mirando: null
    property real mirandoX: 0
    property real mirandoY: 0
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
                    onClicked: panel.plugin.abrirConCeremonia(cofre.index)
                }
            }
        }
    }

    // ── emergente con la ficha de la pieza ────────────────────────
    // En la rejilla solo caben icono e insignia; el nombre y lo que da hay que
    // poder verlos sin equiparla para averiguarlo.
    Rectangle {
        id: emergente
        parent: panel
        z: 30
        visible: panel.mirando !== null
        width: Math.min(230, panel.width - 12)
        height: contenidoFicha.implicitHeight + 14
        radius: 9
        color: "#f2101014"
        border.width: 1
        border.color: panel.mirando
            ? Items.rarezaDe(panel.mirando.rareza).color : Theme.surfaceHi

        // se coloca encima de la celda, y se aparta del borde si no cabe
        x: Math.max(4, Math.min(panel.width - width - 4, panel.mirandoX - width / 2))
        y: Math.max(4, panel.mirandoY - height - 6)

        ColumnLayout {
            id: contenidoFicha
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 7
            spacing: 3

            IslandLabel {
                text: panel.mirando ? panel.mirando.nombre : ""
                font.pixelSize: 11
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                spacing: 5

                InsigniaRareza {
                    rareza: panel.mirando ? panel.mirando.rareza : 0
                    nivel: Items.nivelDe(panel.mirando)
                }

                IslandLabel {
                    text: panel.mirando ? Items.huecoDe(panel.mirando.hueco).nombre : ""
                    color: Theme.muted
                    font.pixelSize: 9
                }
            }

            IslandLabel {
                text: panel.mirando ? Items.resumen(panel.mirando) : ""
                color: Theme.ink
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            IslandLabel {
                visible: panel.mirando !== null && !Game.algunoPuede(panel.mirando)
                text: "necesita nivel " + Items.nivelRequerido(panel.mirando)
                color: Theme.red
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }

            IslandLabel {
                text: panel.mirando ? "desguace: " + Game.cifra(Items.valorDesguace(panel.mirando))
                    + " reliquias" : ""
                color: Theme.dim
                font.pixelSize: 9
            }
        }
    }

    // ── ceremonia de apertura, por encima de todo lo demás
    AperturaCofre {
        id: ceremonia
        parent: panel
        anchors.fill: parent
        z: 20
        visible: panel.plugin.abriendo !== null
        tipo: panel.plugin.tipoAbriendo
        objeto: panel.plugin.abriendo
        onTerminado: {
            panel.ultimo = panel.plugin.abriendo
            panel.plugin.abriendo = null
        }

        // Arranca al anunciarse un cofre y también al montarse: abrir desde
        // fuera cambia de pestaña, así que la señal salta antes de que exista
        // este panel y la ceremonia se quedaba congelada en el primer cuadro.
        Component.onCompleted: if (panel.plugin && panel.plugin.abriendo) abrir()

        Connections {
            target: panel.plugin
            function onAbriendoChanged() {
                if (panel.plugin.abriendo)
                    ceremonia.abrir()
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
            text: "izquierdo equipa · derecho desguaza · arrastra para ordenar"
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

    // ── la bolsa, en rejilla ──────────────────────────────────────
    // Antes era una lista ordenada por puntuación: no se veía de un vistazo y
    // no se podía colocar nada. Aquí el orden es tuyo y se arrastra.
    GridView {
        id: rejilla
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        cellWidth: Math.floor(width / 10)
        cellHeight: cellWidth
        model: Game.bolsa.length
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            required property int index
            width: rejilla.cellWidth
            height: rejilla.cellHeight

            CeldaObjeto {
                anchors.fill: parent
                anchors.margins: 3
                objeto: Game.bolsa[parent.index]
                posicion: parent.index
                onPulsado: {
                    const it = Game.bolsa[parent.index]
                    if (it) Game.equipar(it, panel.mejorDestino(it))
                }
                onSecundario: {
                    const it = Game.bolsa[parent.index]
                    if (it) Game.desguazar(it)
                }
                onSoltadoEn: function (desde) { Game.moverEnBolsa(desde, parent.index) }

                onEncimaChanged: {
                    if (encima) {
                        panel.mirando = objeto
                        const pos = mapToItem(panel, width / 2, 0)
                        panel.mirandoX = pos.x
                        panel.mirandoY = pos.y
                    } else if (panel.mirando === objeto) {
                        panel.mirando = null
                    }
                }
            }
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
