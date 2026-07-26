//  Un combatiente en el campo: sprite, barra de vida y —si es de los tuyos—
//  el botón de su habilidad con la recarga.
//
//  Sirve igual para héroes y enemigos: lo único que cambia es hacia dónde
//  mira, el color de la barra y si tiene habilidad.

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../../core"

Item {
    id: combatiente

    property string sprite: ""
    property real vida: 0
    property real vidaMax: 1
    property color colorVida: "#30d158"
    property string nombre: ""
    property bool mirandoDerecha: true
    property real escala: 1

    // solo los héroes tienen habilidad
    property real recarga: 0
    property real recargaRestante: 0
    property int glifoHabilidad: 0
    property bool pulsable: false
    signal lanzar()

    readonly property bool caido: vida <= 0
    readonly property real fraccion: vidaMax > 0 ? Math.max(0, Math.min(1, vida / vidaMax)) : 0
    readonly property bool tieneHabilidad: recarga > 0

    function golpear(texto) {
        sacudida.restart()
        destello.restart()
        numeros.lanzar(texto, false)
    }

    function curar(texto) { numeros.lanzar(texto, true) }
    function destellar() { aura.restart() }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        spacing: 3

        // ── sprite
        Item {
            width: combatiente.width
            height: combatiente.height - (combatiente.tieneHabilidad ? 26 : 14)

            Item {
                id: soporte
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: 44 * combatiente.escala
                height: width

                property real empuje: 0
                transform: Translate { x: soporte.empuje }
                opacity: combatiente.caido ? 0.25 : 1
                Behavior on opacity { NumberAnimation { duration: 250 } }

                // flotación de reposo, desfasada por combatiente para que no
                // suban y bajen todos a la vez como un coro
                SequentialAnimation on anchors.bottomMargin {
                    running: !combatiente.caido
                    loops: Animation.Infinite
                    NumberAnimation { to: 4; duration: 1100 + (combatiente.x % 7) * 60
                        easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 1100 + (combatiente.x % 7) * 60
                        easing.type: Easing.InOutSine }
                }

                Image {
                    id: retrato
                    anchors.fill: parent
                    source: combatiente.sprite
                    fillMode: Image.PreserveAspectFit
                    smooth: false                  // pixel art: sin interpolar
                    mirror: !combatiente.mirandoDerecha
                    rotation: combatiente.caido ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                // destello del golpe, con la forma del sprite y no del cuadro
                MultiEffect {
                    id: tinte
                    anchors.fill: parent
                    source: retrato
                    brightness: 0
                    saturation: -1
                    visible: brightness > 0
                }

                // resplandor al lanzar la habilidad
                MultiEffect {
                    id: brillo
                    anchors.fill: parent
                    source: retrato
                    brightness: 0
                    colorization: 1
                    colorizationColor: "#ffd60a"
                    visible: brightness > 0
                }

                NumberAnimation {
                    id: destello
                    target: tinte; property: "brightness"
                    from: 0.85; to: 0; duration: 150
                }

                NumberAnimation {
                    id: aura
                    target: brillo; property: "brightness"
                    from: 1; to: 0; duration: 420
                }

                SequentialAnimation {
                    id: sacudida
                    NumberAnimation { target: soporte; property: "empuje"
                        to: combatiente.mirandoDerecha ? -4 : 4; duration: 45 }
                    NumberAnimation { target: soporte; property: "empuje"
                        to: 0; duration: 110; easing.type: Easing.OutCubic }
                }
            }

            // números de daño y curación
            Item {
                id: numeros
                anchors.fill: parent

                property var plantilla: Qt.createComponent("NumeroFlotante.qml")

                function lanzar(texto, curacion) {
                    if (plantilla.status !== Component.Ready)
                        return
                    plantilla.createObject(numeros, {
                        texto: texto,
                        critico: curacion === true,
                        x: numeros.width / 2 - 14 + (Math.random() * 16 - 8),
                        y: numeros.height * 0.35
                    })
                }
            }
        }

        // ── barra de vida
        Rectangle {
            width: combatiente.width - 6
            height: 5
            anchors.horizontalCenter: parent.horizontalCenter
            radius: 2.5
            color: Theme.islandBg

            Rectangle {
                width: parent.width * combatiente.fraccion
                height: parent.height
                radius: parent.radius
                color: combatiente.fraccion < 0.3 ? Theme.red : combatiente.colorVida

                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
        }

        // ── habilidad, solo en los héroes
        Rectangle {
            visible: combatiente.tieneHabilidad
            width: combatiente.width - 6
            height: 16
            anchors.horizontalCenter: parent.horizontalCenter
            radius: 8
            color: combatiente.pulsable
                ? (habilidadMouse.containsMouse ? Theme.blue : Theme.surfaceHi)
                : Theme.islandBg
            border.width: combatiente.pulsable ? 1 : 0
            border.color: "#ffd60a"

            Behavior on color { ColorAnimation { duration: 140 } }

            // lo que queda de recarga, como relleno
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * (combatiente.recarga > 0
                    ? 1 - Math.max(0, combatiente.recargaRestante) / combatiente.recarga : 0)
                radius: parent.radius
                color: Theme.surfaceHi
                opacity: combatiente.pulsable ? 0 : 0.9
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 3

                IconGlyph {
                    text: combatiente.glifoHabilidad > 0
                        ? String.fromCodePoint(combatiente.glifoHabilidad) : ""
                    color: combatiente.pulsable ? "#ffd60a" : Theme.dim
                    font.pixelSize: 10
                }

                IslandLabel {
                    text: combatiente.pulsable ? "¡ya!" : Math.ceil(combatiente.recargaRestante) + "s"
                    color: combatiente.pulsable ? Theme.ink : Theme.dim
                    font.pixelSize: 9
                    font.weight: combatiente.pulsable ? Font.DemiBold : Font.Normal
                }
            }

            // late cuando está lista, para que se vea sin mirarla fijo
            SequentialAnimation on scale {
                running: combatiente.pulsable
                loops: Animation.Infinite
                NumberAnimation { to: 1.05; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
            }

            MouseArea {
                id: habilidadMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: combatiente.pulsable
                cursorShape: Qt.PointingHandCursor
                onClicked: combatiente.lanzar()
            }
        }
    }
}
