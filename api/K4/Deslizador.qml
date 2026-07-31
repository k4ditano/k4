//  Deslizador con su etiqueta y su valor, el del volumen y el brillo.
//
//  Trabaja en enteros o con decimales según `paso`, y avisa por `movido` solo
//  cuando el valor cambia de verdad — arrastrar dentro del mismo escalón no
//  dispara nada, que si no un plugin que escriba a disco al moverlo escribe
//  sesenta veces por segundo.

import QtQuick
import QtQuick.Layouts

Item {
    id: control

    property string etiqueta: ""
    property real valor: 0
    property real desde: 0
    property real hasta: 100
    property real paso: 1
    property string sufijo: ""

    signal movido(real valor)

    implicitHeight: 38

    readonly property real fraccion: hasta > desde
        ? Math.max(0, Math.min(1, (valor - desde) / (hasta - desde))) : 0

    function cuantizar(f) {
        const crudo = desde + Math.max(0, Math.min(1, f)) * (hasta - desde)
        const pegado = Math.round(crudo / paso) * paso
        //  Paso decimal → se redondea a esa precisión; si no, arrastra el
        //  0.30000000000000004 de siempre y sale en pantalla.
        const decimales = paso < 1 ? String(paso).split(".")[1].length : 0
        return parseFloat(pegado.toFixed(decimales))
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Etiqueta {
                text: control.etiqueta
                color: Tema.apagado
                font.pixelSize: 11
                Layout.fillWidth: true
            }

            Etiqueta {
                text: control.valor + control.sufijo
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 16

            Rectangle {
                id: carril
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: raton.containsMouse || raton.pressed ? 6 : 4
                radius: height / 2
                color: Tema.carril

                Behavior on height {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    width: carril.width * control.fraccion
                    height: parent.height
                    radius: parent.radius
                    color: Tema.tinta

                    Behavior on width {
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }
                }
            }

            Rectangle {
                x: carril.width * control.fraccion - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: raton.pressed ? 14 : 12
                height: width
                radius: width / 2
                color: Tema.tinta

                Behavior on width {
                    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                }
                Behavior on x {
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                id: raton
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function aplicar(x) {
                    const siguiente = control.cuantizar(x / carril.width)
                    if (siguiente !== control.valor)
                        control.movido(siguiente)
                }

                onPressed: function (ev) { aplicar(ev.x) }
                onPositionChanged: function (ev) { if (pressed) aplicar(ev.x) }
            }
        }
    }
}
