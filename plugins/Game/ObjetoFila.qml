//  Una pieza de equipo: icono, nombre teñido por rareza y lo que da.
//  Sirve en la bolsa y en los huecos del grupo.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

Rectangle {
    id: fila

    property var objeto: null
    property string vacio: "vacío"
    property bool activo: true
    signal pulsado()
    signal secundario()

    readonly property var rareza: objeto ? Items.rarezaDe(objeto.rareza) : null

    height: 30
    radius: 7
    color: raton.containsMouse && activo ? Theme.surfaceHi : Theme.surface
    border.width: objeto ? 1 : 0
    border.color: rareza ? rareza.color : "transparent"
    opacity: objeto ? 1 : 0.5

    Behavior on color { ColorAnimation { duration: 110 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 8
        spacing: 7

        Image {
            source: fila.objeto
                ? "assets/objetos/i" + String(fila.objeto.icono).padStart(2, "0") + ".png"
                : ""
            visible: fila.objeto !== null
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            fillMode: Image.PreserveAspectFit
            // Aquí se REDUCE (32 -> 20), y reduciendo con vecino más cercano
            // se pierden filas de píxeles enteras. Suavizar es lo correcto.
            smooth: true
            mipmap: true
        }

        IconGlyph {
            visible: fila.objeto === null
            text: String.fromCodePoint(0xF0156)
            color: Theme.dim
            font.pixelSize: 13
            Layout.preferredWidth: 20
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            IslandLabel {
                text: (fila.objeto && !Game.algunoPuede(fila.objeto) ? "🔒 " : "")
                    + (fila.objeto ? fila.objeto.nombre : fila.vacio)
                color: fila.rareza ? fila.rareza.color : Theme.dim
                font.pixelSize: 11
                font.weight: fila.objeto && fila.objeto.rareza >= 3 ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            IslandLabel {
                visible: fila.objeto !== null
                text: fila.objeto ? Items.resumen(fila.objeto) : ""
                color: Theme.muted
                font.pixelSize: 9
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        InsigniaRareza {
            visible: fila.objeto !== null
            rareza: fila.objeto ? fila.objeto.rareza : 0
            nivel: Items.nivelDe(fila.objeto)
            compacta: true
            Layout.alignment: Qt.AlignVCenter
        }

        IslandLabel {
            visible: fila.objeto !== null && raton.containsMouse
            text: Idioma.t("ol ") + (fila.objeto ? fila.objeto.oleada : 0)
            color: Theme.dim
            font.pixelSize: 9
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: raton
        anchors.fill: parent
        hoverEnabled: true
        enabled: fila.activo
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton)
                fila.secundario()
            else
                fila.pulsado()
        }
    }
}
