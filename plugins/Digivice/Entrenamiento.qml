//  El entrenamiento: tres tiros a un blanco que se mueve.
//
//  Era un botón que sumaba fuerza, o sea un trámite: pulsar cien veces sin
//  decidir nada. Los aparatos originales tenían aquí un minijuego, y es de
//  donde salía el esfuerzo —lo que luego separa una buena crianza de una
//  mala—. Con puntería de por medio, entrenar es algo que se te puede dar
//  mal, y eso es lo que lo convierte en juego.
//
//  El coste en hambre se paga igual se acierte o no; lo que cambia con la
//  puntería es lo que sacas.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    signal terminado(int aciertos)

    property var zumbador: null
    function _pitar(n) { if (zumbador) zumbador.sonar(n) }

    property int ronda: 0
    property int aciertos: 0
    property bool corriendo: true
    property string ultimo: ""

    //  El blanco se estrecha cada ronda: la tercera es la que de verdad
    //  distingue. Con ancho fijo, acertar tres veces era lo mismo que
    //  acertar una.
    readonly property real anchoBlanco: 0.26 - ronda * 0.06
    readonly property real centroBlanco: 0.5

    function tirar() {
        if (!corriendo)
            return
        const p = marcador.x / Math.max(1, pista.width - marcador.width)
        const dist = Math.abs(p - centroBlanco)
        const acerto = dist <= anchoBlanco / 2
        _pitar(acerto ? "acierto" : "fallo")
        if (acerto) {
            aciertos += 1
            ultimo = dist <= anchoBlanco / 6 ? Idioma.t("¡En el centro!")
                                             : Idioma.t("¡Dentro!")
        } else {
            ultimo = Idioma.t("Fuera")
        }
        ronda += 1
        if (ronda >= Digivice.rondasEntreno) {
            corriendo = false
            cierre.start()
        }
    }

    Timer {
        id: cierre
        interval: 900
        onTriggered: self.terminado(self.aciertos)
    }

    focus: true
    Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Space || e.key === Qt.Key_Return
            || e.key === Qt.Key_E) {
            self.tirar()
            e.accepted = true
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: self.tirar()
    }

    Column {
        anchors.centerIn: parent
        spacing: 16
        width: parent.width * 0.8

        K4.Etiqueta {
            anchors.horizontalCenter: parent.horizontalCenter
            text: self.corriendo
                ? Idioma.f(Idioma.t("Tiro %1 de %2"),
                           self.ronda + 1, Digivice.rondasEntreno)
                : Idioma.f(Idioma.t("%1 de %2 aciertos"),
                           self.aciertos, Digivice.rondasEntreno)
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        // ── la pista ──────────────────────────────────────────────
        Rectangle {
            id: pista
            width: parent.width
            height: 34
            radius: 17
            color: K4.Tema.superficie

            //  El blanco
            Rectangle {
                height: parent.height - 8
                width: parent.width * self.anchoBlanco
                x: parent.width * self.centroBlanco - width / 2
                y: 4
                radius: height / 2
                color: K4.Tema.verde
                opacity: 0.28

                Behavior on width { NumberAnimation { duration: 200 } }
            }

            //  El centro exacto, para que se vea a qué se apunta
            Rectangle {
                width: 2
                height: parent.height - 12
                x: parent.width * self.centroBlanco - 1
                y: 6
                color: K4.Tema.verde
                opacity: 0.7
            }

            //  El marcador
            Rectangle {
                id: marcador
                width: 6
                height: parent.height - 4
                y: 2
                radius: 3
                color: K4.Tema.tinta

                //  Va y viene; se acelera cada ronda para que la última
                //  cueste de verdad.
                SequentialAnimation on x {
                    running: self.corriendo
                    loops: Animation.Infinite

                    NumberAnimation {
                        from: 2; to: pista.width - marcador.width - 2
                        duration: 1300 - self.ronda * 300
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: pista.width - marcador.width - 2; to: 2
                        duration: 1300 - self.ronda * 300
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }

        K4.Etiqueta {
            anchors.horizontalCenter: parent.horizontalCenter
            text: self.ultimo || Idioma.t("Clic o espacio para golpear")
            font.pixelSize: 13
            color: self.ultimo === Idioma.t("Fuera") ? K4.Tema.rojo
                 : self.ultimo ? K4.Tema.verde : K4.Tema.apagado
        }
    }
}
