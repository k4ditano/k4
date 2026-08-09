//  Entrenar la DEFENSA: bloquear.
//
//  Llegan golpes con un ritmo y hay que pararlos justo cuando tocan. No es
//  puntería sobre un blanco quieto: es reaccionar a algo que viene, que es lo
//  que entrena defenderse.

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
    //  0 = lejos, 1 = encima. La zona de bloqueo está al final.
    property real avance: 0
    property bool volando: false

    readonly property real zona: 0.82

    function lanzar() {
        if (!corriendo) return
        avance = 0
        volando = true
    }

    //  Lo llama la vista con B.
    function tirar() {
        if (!volando) return
        const dist = Math.abs(avance - zona)
        const bien = dist <= 0.09
        volando = false
        _pitar(bien ? "acierto" : "fallo")
        if (bien) { aciertos += 1; ultimo = Idioma.t("¡Bloqueado!") }
        else ultimo = avance < zona ? Idioma.t("Muy pronto") : Idioma.t("Muy tarde")
        _siguiente()
    }

    function _siguiente() {
        ronda += 1
        if (ronda >= Digivice.rondasEntreno) {
            corriendo = false
            cierre.start()
        } else {
            respiro.restart()
        }
    }

    Timer { id: respiro; interval: 700; onTriggered: self.lanzar() }
    Timer { id: arranque; interval: 600; running: true; onTriggered: self.lanzar() }
    Timer { id: cierre; interval: 900; onTriggered: self.terminado(self.aciertos) }

    //  El golpe se acerca, y más deprisa cada ronda.
    Timer {
        interval: 30
        repeat: true
        running: self.volando
        onTriggered: {
            self.avance += 0.016 + self.ronda * 0.006
            if (self.avance >= 1.0) {
                //  Se te ha echado encima sin bloquear.
                self.volando = false
                self.ultimo = Idioma.t("Te ha dado")
                self._pitar("fallo")
                self._siguiente()
            }
        }
    }

    MouseArea { anchors.fill: parent; onClicked: self.tirar() }

    Column {
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 10

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: self.corriendo
                ? Idioma.f(Idioma.t("Golpe %1 de %2"),
                           self.ronda + 1, Digivice.rondasEntreno)
                : Idioma.f(Idioma.t("%1 de %2"), self.aciertos, Digivice.rondasEntreno)
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: "#d8f0de"
        }

        Item {
            width: parent.width
            height: 40

            //  El bicho, al final del carril.
            Retrato {
                x: parent.width * self.zona - 16
                anchors.verticalCenter: parent.verticalCenter
                especie: Digivice.especie
                lado: 34
            }

            //  La ventana de bloqueo.
            Rectangle {
                x: parent.width * (self.zona - 0.09)
                width: parent.width * 0.18
                height: parent.height
                color: "#2f6b40"
                opacity: 0.35
                radius: 3
            }

            //  El golpe que viene.
            Rectangle {
                visible: self.volando
                x: parent.width * self.avance - 6
                anchors.verticalCenter: parent.verticalCenter
                width: 12; height: 12; radius: 6
                color: "#e0806b"
                border.width: 1
                border.color: "#ffd0c4"
            }
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: self.ultimo || Idioma.t("B cuando el golpe te alcance")
            font.pixelSize: 12
            color: self.ultimo === Idioma.t("¡Bloqueado!") ? "#9fe8ac"
                 : self.ultimo ? "#e0806b" : "#8fbf9c"
        }
    }
}
