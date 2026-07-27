//  La pelea: el grupo contra la oleada, y la tienda de la partida.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: panel

    spacing: 8

    // desplazamiento y opacidad de los enemigos al aparecer
    property real entradaX: 0
    property real entradaOpacidad: 1

    ParallelAnimation {
        id: entrada
        NumberAnimation {
            target: panel; property: "entradaX"
            from: 90; to: 0; duration: 900; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: panel; property: "entradaOpacidad"
            from: 0; to: 1; duration: 700
        }
    }

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

        function onOleadaSuperada(numero) {
            escenario.caminar()
            entrada.restart()
        }
    }

    // ── campo de batalla ──────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 122
        radius: 12
        color: Theme.islandBg
        clip: true

        Fondo {
            id: escenario
            anchors.fill: parent
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

                    nivel: datos.nivel || 1
                    exp: datos.exp || 0
                    expNecesaria: Game.expParaNivel(datos.nivel || 1)
                    escudo: datos.escudo || 0
                    habilidades: Game.habilidadesDe(datos)
                    recargas: datos.recargas || ({})
                    heroe: index
                    onLanzar: function (id) { Game.lanzar(index, id) }
                }
            }

            IslandLabel {
                text: "vs"
                color: Theme.dim
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter
            }

            // la oleada entra deslizándose mientras el grupo camina
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

                    // Translate y no `x`: animar la x de un hijo de RowLayout
                    // pelea con el propio layout, y al acabar la animación los
                    // enemigos se quedaban clavados en el borde izquierdo,
                    // encima de los héroes.
                    transform: Translate { x: panel.entradaX }
                    opacity: panel.entradaOpacidad
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

                // ── dónde empezar la siguiente
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    spacing: 5
                    visible: Game.iniciosDisponibles.length > 1

                    IslandLabel {
                        text: "empezar en:"
                        color: Theme.dim
                        font.pixelSize: 9
                    }

                    Repeater {
                        model: Game.iniciosDisponibles

                        delegate: Rectangle {
                            id: punto
                            required property var modelData
                            readonly property bool elegido: Game.inicioElegido === modelData

                            Layout.preferredWidth: etiquetaPunto.implicitWidth + 14
                            Layout.preferredHeight: 18
                            radius: 9
                            color: elegido ? Theme.blue
                                : (puntoMouse.containsMouse ? Theme.surfaceHi : Theme.surface)

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IslandLabel {
                                id: etiquetaPunto
                                anchors.centerIn: parent
                                text: punto.modelData
                                font.pixelSize: 9
                                font.weight: punto.elegido ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                id: puntoMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Game.elegirInicio(punto.modelData)
                            }
                        }
                    }
                }

                IslandLabel {
                    visible: Game.relevoRestante > 0
                    text: "siguiente partida en " + Game.relevoRestante + " s"
                    color: "#ffd60a"
                    font.pixelSize: 10
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
                        text: Game.relevoRestante > 0 ? "Empezar ya" : "Nueva partida"
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

        // ── depósito vacío
        //  En modo vibecoding esto no es un error, es la mecánica: el grupo
        //  espera a que vuelvas a picar. Conviene que se entienda a la
        //  primera, así que se dice qué falta y no solo que está parado.
        Rectangle {
            anchors.fill: parent
            color: "#d9000000"
            visible: Settings.juegoPorTokens && !Tokens.hay
                && Game.viva && !Game.pausada

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 3

                IconGlyph {
                    text: String.fromCodePoint(0xF0241)
                    color: Theme.dim
                    font.pixelSize: 22
                    Layout.alignment: Qt.AlignHCenter
                }

                IslandLabel {
                    text: "El grupo espera"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignHCenter
                }

                IslandLabel {
                    text: "gasta tokens en Claude o Codex y seguirán peleando"
                    color: Theme.muted
                    font.pixelSize: 10
                    Layout.alignment: Qt.AlignHCenter
                }

                IslandLabel {
                    visible: Tokens.totalChispa > 0
                    text: Tokens.cifra(Tokens.totalChispa) + " de chispa quemada en total"
                    color: Theme.dim
                    font.pixelSize: 9
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // ── tienda de cofres ──────────────────────────────────────────
    // El oro ya no sube estadísticas: eso lo hace la experiencia. Aquí se
    // decide qué botín te llevas, que sí es una decisión.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 38
        spacing: 8

        Repeater {
            model: Game.tiendaDef

            delegate: IslandTile {
                id: oferta
                required property var modelData
                readonly property int precio: Game.costeCofre(modelData.tipo)
                readonly property bool asequible: Game.oro >= precio

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                activa: asequible
                colorActiva: Theme.surface
                onPulsada: Game.comprarCofre(oferta.modelData.tipo)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 7

                    IconGlyph {
                        text: String.fromCodePoint(oferta.modelData.glifo)
                        color: oferta.asequible ? Theme.ink : Theme.dim
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IslandLabel {
                        text: oferta.modelData.nombre
                        color: oferta.asequible ? Theme.ink : Theme.dim
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IconGlyph {
                        text: String.fromCodePoint(0xF0114)
                        color: oferta.asequible ? "#ffd60a" : Theme.dim
                        font.pixelSize: 10
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IslandLabel {
                        text: Game.cifra(oferta.precio)
                        color: oferta.asequible ? "#ffd60a" : Theme.dim
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }
}
