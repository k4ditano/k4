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
    property bool destacado: false      // élite o jefe: se le da color
    property bool envenenado: false
    property bool furioso: false        // envalentonado por un aullido
    property bool mirandoDerecha: true
    property real escala: 1

    // solo los héroes: nivel, experiencia, escudo y habilidades
    property int nivel: 0
    property real exp: 0
    property real expNecesaria: 1
    property real escudo: 0
    property var habilidades: []
    property var recargas: ({})
    property int heroe: -1
    property var rasgos: []        // ya resueltos: { nombre, color }
    signal lanzar(string id)
    signal pulsado()

    readonly property bool caido: vida <= 0
    readonly property real fraccion: vidaMax > 0 ? Math.max(0, Math.min(1, vida / vidaMax)) : 0
    readonly property bool tieneHabilidad: habilidades.length > 0

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
            height: combatiente.height - (combatiente.tieneHabilidad ? 34 : 14)

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

                // ── estados que duran
                //  El veneno y el envalentonamiento cambian el combate durante
                //  segundos, y sin marca no hay forma de saber que están ahí.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -2
                    width: 26
                    height: 6
                    radius: 3
                    visible: combatiente.envenenado || combatiente.furioso
                    color: combatiente.envenenado ? "#32d74b" : "#ff453a"
                    opacity: 0.55

                    SequentialAnimation on opacity {
                        running: combatiente.envenenado || combatiente.furioso
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 620 }
                        NumberAnimation { to: 0.6; duration: 620 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: 5
                    enabled: combatiente.heroe >= 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: combatiente.pulsado()
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
                // se van escalonando: si todos salen del mismo punto se tapan
                // unos a otros y no se lee ninguno
                property int turno: 0

                function lanzar(texto, curacion) {
                    if (plantilla.status !== Component.Ready)
                        return

                    turno = (turno + 1) % 4
                    plantilla.createObject(numeros, {
                        texto: texto,
                        critico: curacion === true,
                        x: numeros.width / 2 - 16 + (turno % 2 === 0 ? -13 : 13)
                            + (Math.random() * 8 - 4),
                        y: numeros.height * 0.34 - turno * 11
                    })
                }
            }
        }

        // ── quién es
        //  Estaba declarado y no se pintaba: los monstruos salían anónimos y
        //  daba igual pelear contra un limo que contra un murciélago.
        IslandLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: combatiente.nombre.length > 0 && !combatiente.caido
            text: combatiente.nombre
            color: combatiente.destacado ? "#ffd60a" : Theme.muted
            font.pixelSize: 8
            font.weight: combatiente.destacado ? Font.DemiBold : Font.Normal
        }

        // ── lo que trae este bicho
        //  Sin esto los rasgos son magia invisible: te matan y no sabes por
        //  qué. Con el nombre delante, la oleada 70 se lee de un vistazo.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            visible: combatiente.rasgos.length > 0 && !combatiente.caido

            Repeater {
                model: combatiente.rasgos

                delegate: IslandLabel {
                    required property var modelData

                    text: modelData.nombre
                    color: modelData.color
                    font.pixelSize: 7
                    font.weight: Font.DemiBold
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

            // el escudo se pinta encima, en cian: absorbe antes que la vida
            Rectangle {
                width: parent.width * Math.min(1, combatiente.escudo
                    / Math.max(1, combatiente.vidaMax))
                height: parent.height
                radius: parent.radius
                color: "#6ccce4"
                opacity: 0.9
                visible: combatiente.escudo > 0

                Behavior on width { NumberAnimation { duration: 200 } }
            }
        }

        // ── experiencia, una línea fina bajo la vida
        Rectangle {
            visible: combatiente.tieneHabilidad
            width: combatiente.width - 6
            height: 2
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.islandBg

            Rectangle {
                width: parent.width * Math.min(1, combatiente.exp
                    / Math.max(1, combatiente.expNecesaria))
                height: parent.height
                color: "#c78fff"
            }
        }

        // ── habilidades: una pastilla por cada una desbloqueada
        RowLayout {
            visible: combatiente.tieneHabilidad
            width: combatiente.width - 4
            height: 15
            spacing: 2

            Repeater {
                model: combatiente.habilidades

                delegate: Rectangle {
                    id: pastilla
                    required property var modelData
                    readonly property real restante: combatiente.recargas[modelData.id] || 0
                    readonly property bool lista: restante <= 0 && !combatiente.caido

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 4
                    color: lista ? (pastillaMouse.containsMouse ? Theme.blue : Theme.surfaceHi)
                        : Theme.islandBg
                    border.width: lista ? 1 : 0
                    border.color: "#ffd60a"

                    Behavior on color { ColorAnimation { duration: 140 } }

                    // lo recargado, como relleno
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * (1 - Math.max(0, pastilla.restante)
                            / Math.max(1, pastilla.modelData.recarga))
                        radius: parent.radius
                        color: Theme.surfaceHi
                        opacity: pastilla.lista ? 0 : 0.9
                    }

                    IconGlyph {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(pastilla.modelData.glifo)
                        color: pastilla.lista ? "#ffd60a" : Theme.dim
                        font.pixelSize: 9
                    }

                    SequentialAnimation on scale {
                        running: pastilla.lista
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.08; duration: 620; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                    }

                    MouseArea {
                        id: pastillaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: pastilla.lista
                        cursorShape: Qt.PointingHandCursor
                        onClicked: combatiente.lanzar(pastilla.modelData.id)
                    }
                }
            }
        }
    }
}
