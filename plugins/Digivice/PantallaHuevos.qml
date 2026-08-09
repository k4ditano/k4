//  La incubadora.
//
//  Aquí es donde la colección deja de ser una estantería y pasa a ser una
//  decisión: eliges qué línea quieres criar de entre las que has capturado
//  peleando. Antes el huevo salía al azar y no elegías nada.
//
//  Con un huevo dentro, la pantalla es el huevo y su cuenta de pasos. Sin
//  huevo, se recorren con A los disponibles y B pone uno.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    property int cursor: 0

    readonly property var lista: Digivice.huevosDisponibles
    readonly property int total: lista.length
    readonly property int indice: total > 0
                                ? ((cursor % total) + total) % total : 0
    readonly property string elegido: total > 0 ? lista[indice] : ""

    //  Lo llama el botón B de la vista.
    function elegir() {
        if (Digivice.huevoListo) { Digivice.eclosionar(); return }
        if (Digivice.hayIncubacion) return
        if (self.elegido !== "") Digivice.incubar(self.elegido)
    }

    // ── con un huevo dentro ───────────────────────────────────────
    Column {
        anchors.centerIn: parent
        width: parent.width - 12
        spacing: 6
        visible: Digivice.hayIncubacion

        //  El huevo: un óvalo que se menea más cuanto más cerca está de
        //  romperse. Es el único aviso que sabe dar un huevo.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44
            height: 54
            radius: width / 2
            color: "#d8e8c8"
            border.width: 2
            border.color: "#8fbf9c"

            readonly property real avance: Math.min(1,
                Digivice.pasosIncubados / Math.max(1, Digivice.pasosParaEclosionar))

            SequentialAnimation on rotation {
                running: Digivice.hayIncubacion
                loops: Animation.Infinite
                NumberAnimation { to: 7; duration: 420 }
                NumberAnimation { to: -7; duration: 420 }
            }

            //  Las grietas, que aparecen al final.
            Rectangle {
                visible: parent.avance > 0.6
                x: 12; y: 18; width: 18; height: 2
                color: "#6b7a5c"; rotation: 20
            }
            Rectangle {
                visible: parent.avance > 0.85
                x: 16; y: 30; width: 14; height: 2
                color: "#6b7a5c"; rotation: -25
            }
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Digivice.huevoListo ? Idioma.t("¡Está rompiendo!")
                : Idioma.f(Idioma.t("%1 de %2 pasos"),
                           Digivice.pasosIncubados, Digivice.pasosParaEclosionar)
            font.pixelSize: 13
            font.weight: Digivice.huevoListo ? Font.Bold : Font.Normal
            color: Digivice.huevoListo ? "#e8b45a" : "#8fbf9c"
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Digivice.huevoListo ? Idioma.t("B lo saca")
                                      : Idioma.t("Se incuba andando")
            font.pixelSize: 12
            color: "#5f8f6c"
        }
    }

    // ── eligiendo huevo ───────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        width: parent.width - 12
        spacing: 4
        visible: !Digivice.hayIncubacion && self.total > 0

        Retrato {
            anchors.horizontalCenter: parent.horizontalCenter
            especie: self.elegido
            lado: 56
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Digivice.nombreDe(self.elegido)
            font.pixelSize: 13
            font.weight: Font.Bold
            color: "#d8f0de"
            elide: Text.ElideRight
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: (self.indice + 1) + " / " + self.total + "   ·   "
                + Idioma.t("B lo incuba")
            font.pixelSize: 12
            color: "#5f8f6c"
        }
    }

    K4.Etiqueta {
        anchors.centerIn: parent
        width: parent.width - 20
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: !Digivice.hayIncubacion && self.total === 0
        text: Idioma.t("Sin huevos.\nGana combates para capturar datos: cada línea capturada desbloquea su huevo.")
        font.pixelSize: 12
        color: "#8fbf9c"
    }
}
