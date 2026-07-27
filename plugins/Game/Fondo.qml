//  Escenario de la mazmorra, con parallax.
//
//  Dos capas a distinta velocidad: el paisaje al fondo se arrastra despacio y
//  el suelo pasa deprisa, que es lo que da sensación de profundidad. Entre
//  oleada y oleada el grupo "camina" unos segundos: el desplazamiento se
//  acelera y la siguiente oleada entra por la derecha.

import QtQuick
import "../../core"
import "../../services"

Item {
    id: escenario

    property real avance: 0            // píxeles recorridos en total
    property bool caminando: false

    // Deriva lenta en reposo, para que la escena nunca esté del todo quieta.
    NumberAnimation on avance {
        running: !escenario.caminando
        loops: Animation.Infinite
        from: escenario.avance
        to: escenario.avance + 10000
        duration: 500000               // ~50 s por cada 1000 px
    }

    function caminar() {
        caminando = true
        tranco.restart()
    }

    SequentialAnimation {
        id: tranco
        NumberAnimation {
            target: escenario
            property: "avance"
            to: escenario.avance + 420
            duration: 1400
            easing.type: Easing.InOutQuad
        }
        ScriptAction { script: escenario.caminando = false }
    }

    clip: true

    // Ancho de cada copia del paisaje: los fondos son 512x128, o sea 4:1, así
    // que sale de la altura. Calcularlo aquí y no leer el ancho del delegado,
    // que vive dentro del Repeater y desde fuera no existe.
    readonly property real anchoPaisaje: height * 4

    // ── paisaje, la capa lenta
    Row {
        y: 0
        height: parent.height
        x: -((escenario.avance * 0.35) % escenario.anchoPaisaje)

        Repeater {
            model: 3

            delegate: Image {
                height: escenario.height
                width: escenario.anchoPaisaje
                source: "assets/fondos/" + Game.fondo + ".png"
                fillMode: Image.PreserveAspectFit
                smooth: false
                opacity: 0.55            // atenuado: va detrás de los sprites

                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
        }
    }

    // oscurecido inferior, para que los sprites recorten contra el fondo
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.55
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.72) }
        }
    }

    // ── suelo, la capa rápida
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 24
        clip: true

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceHi
            opacity: 0.5
        }

        // marcas del suelo: son las que hacen visible el movimiento
        Row {
            spacing: 26
            x: -((escenario.avance) % 26)
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: Math.ceil(escenario.width / 26) + 2

                delegate: Rectangle {
                    width: 9
                    height: 2
                    radius: 1
                    color: Theme.ink
                    opacity: 0.16
                }
            }
        }
    }
}
