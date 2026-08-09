//  Entrenar la VIDA: aguantar.
//
//  Mantienes pulsado mientras una barra sube, y tienes que soltarla dentro de
//  la franja buena. Pasarte revienta el intento —te has forzado de más— y
//  quedarte corto no cuenta. Es lo contrario de la puntería: allí eliges el
//  instante, aquí sostienes el esfuerzo.

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
    property real carga: 0
    property bool apretando: false
    property bool corriendo: true
    property string ultimo: ""

    //  La franja buena se estrecha y se aleja cada ronda.
    //  Medido: con la franja de 0,55–0,80 y la carga a 0,55/s la ventana de
    //  la primera ronda era de 450 ms, que es poco para algo que se juega de
    //  reojo en una barra. Ahora arranca en 710 ms y se estrecha con las
    //  rondas, que es donde debe estar la dificultad.
    readonly property real desde: 0.50 + ronda * 0.09
    readonly property real hasta: 0.82 + ronda * 0.05

    function empezar() {
        if (!corriendo || apretando) return
        apretando = true
        carga = 0
    }

    function soltar() {
        if (!apretando) return
        apretando = false
        const dentro = carga >= desde && carga <= hasta
        _pitar(dentro ? "acierto" : "fallo")
        if (dentro) { aciertos += 1; ultimo = Idioma.t("¡Aguantado!") }
        else if (carga > hasta) ultimo = Idioma.t("Te has pasado")
        else ultimo = Idioma.t("Muy poco")
        ronda += 1
        carga = 0
        if (ronda >= Digivice.rondasEntreno) {
            corriendo = false
            cierre.start()
        }
    }

    //  Lo llama la vista: pulsar empieza, volver a pulsar suelta.
    function tirar() { if (apretando) soltar(); else empezar() }

    Timer {
        interval: 40
        repeat: true
        running: self.apretando
        onTriggered: {
            self.carga += 0.018
            //  Reventar: pasarse mucho termina el intento solo, para que
            //  aguantar tenga un techo y no se pueda esperar sin más.
            if (self.carga >= 1.0) self.soltar()
        }
    }

    Timer { id: cierre; interval: 900; onTriggered: self.terminado(self.aciertos) }

    MouseArea {
        anchors.fill: parent
        onPressed: self.empezar()
        onReleased: self.soltar()
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 10

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: self.corriendo
                ? Idioma.f(Idioma.t("Aguante %1 de %2"),
                           self.ronda + 1, Digivice.rondasEntreno)
                : Idioma.f(Idioma.t("%1 de %2"), self.aciertos, Digivice.rondasEntreno)
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: "#d8f0de"
        }

        //  La barra, en vertical no: en horizontal se lee mejor a este tamaño.
        Rectangle {
            width: parent.width
            height: 26
            radius: 4
            color: "#0a1a10"
            border.width: 1
            border.color: "#2f5a3c"

            //  La franja buena.
            Rectangle {
                x: parent.width * self.desde
                width: parent.width * (self.hasta - self.desde)
                height: parent.height - 6
                y: 3
                color: "#2f6b40"
                opacity: 0.6
            }

            //  Lo aguantado.
            Rectangle {
                x: 3
                y: 3
                width: Math.max(0, (parent.width - 6) * self.carga)
                height: parent.height - 6
                color: self.carga > self.hasta ? "#e0806b" : "#7de08a"
            }
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: self.ultimo || Idioma.t("Mantén pulsado y suelta en la franja")
            font.pixelSize: 12
            color: self.ultimo === Idioma.t("¡Aguantado!") ? "#9fe8ac"
                 : self.ultimo ? "#e0806b" : "#8fbf9c"
        }
    }
}
