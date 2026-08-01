//  Los fundidos de la línea entera: al entrar, al salir y en los cortes.
//  Siempre visibles: no hay nada que seleccionar para llegar a ellos.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    Layout.fillWidth: true
    Layout.topMargin: 8
    spacing: 4

    IslandLabel {
        text: Idioma.t("Fundidos")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    Repeater {
        model: [
            { cual: "entrada", nombre: Idioma.t("Al entrar") },
            { cual: "salida",  nombre: Idioma.t("Al salir") },
            { cual: "entre",   nombre: Idioma.t("En los cortes") }
        ]

        delegate: RowLayout {
            id: filaFundido
            required property var modelData

            readonly property real valor:
                filaFundido.modelData.cual === "entrada"
                    ? Editor.fundidoEntrada
              : filaFundido.modelData.cual === "salida"
                    ? Editor.fundidoSalida
                    : Editor.fundidoEntre

            //  Hasta 2 s: más que eso en un corte es que se te
            //  ha ido la mano, y el trozo se queda en negro.
            readonly property real tope: 2.0

            Layout.fillWidth: true
            //  «En los cortes» no pinta nada con un solo trozo.
            visible: filaFundido.modelData.cual !== "entre"
                     || Editor.tramos.length > 1
            spacing: 6

            IslandLabel {
                Layout.preferredWidth: 58
                text: filaFundido.modelData.nombre
                color: Theme.muted
                font.pixelSize: 9
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: Theme.track

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1,
                        filaFundido.valor / filaFundido.tope))
                    height: parent.height
                    radius: parent.radius
                    color: Theme.green
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    cursorShape: Qt.PointingHandCursor

                    function poner(x) {
                        const u = Math.max(0, Math.min(1,
                            x / Math.max(1, width)))
                        Editor.ponerFundido(
                            filaFundido.modelData.cual,
                            Math.round(u * filaFundido.tope * 20) / 20)
                    }
                    onPressed: function (ev) { poner(ev.x) }
                    onPositionChanged: function (ev) {
                        if (pressed) poner(ev.x)
                    }
                }
            }

            IslandLabel {
                Layout.preferredWidth: 30
                horizontalAlignment: Text.AlignRight
                text: filaFundido.valor.toFixed(2) + " s"
                color: Theme.dim
                font.pixelSize: 9
            }
        }
    }
}
