//  Apertura de cofre, con su ceremonia.
//
//  Abrir era pulsar y ver aparecer una línea en una lista. Aquí el cofre
//  tiembla, se resquebraja, revienta en luz y la pieza sale despedida con el
//  color de su rareza. Cuanto mejor es lo que hay dentro, más se hace esperar:
//  la tensión es la mitad de la gracia.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: apertura

    property int tipo: 0
    property var objeto: null
    signal terminado()

    // fotograma actual dentro de la fila del cofre (0..3)
    property int cuadro: 0
    property real fulgor: 0

    readonly property var rareza: objeto ? Items.rarezaDe(objeto.rareza) : null
    // los grados altos tiemblan más rato antes de abrirse
    readonly property int suspense: objeto ? 420 + Math.min(6, objeto.rareza) * 240 : 420

    function abrir() {
        cuadro = 0
        fulgor = 0
        ceremonia.restart()
    }

    SequentialAnimation {
        id: ceremonia

        // 1 · reposo breve
        PauseAnimation { duration: 260 }

        // 2 · temblor, tanto más largo cuanto mejor es el botín
        ScriptAction { script: apertura.cuadro = 1 }
        SequentialAnimation {
            loops: Math.max(2, Math.round(apertura.suspense / 130))
            NumberAnimation { target: sacudida; property: "x"; to: 4; duration: 60 }
            NumberAnimation { target: sacudida; property: "x"; to: -4; duration: 60 }
        }
        NumberAnimation { target: sacudida; property: "x"; to: 0; duration: 60 }

        // 3 · se resquebraja
        ScriptAction { script: apertura.cuadro = 2 }
        PauseAnimation { duration: 260 }

        // 4 · revienta
        ParallelAnimation {
            ScriptAction { script: apertura.cuadro = 3 }
            NumberAnimation {
                target: apertura; property: "fulgor"
                from: 0; to: 1; duration: 180; easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: tapa; property: "scale"
                from: 0.9; to: 1.12; duration: 220; easing.type: Easing.OutBack
            }
        }

        // 5 · la pieza sube y se queda
        ParallelAnimation {
            NumberAnimation {
                target: premio; property: "opacity"
                from: 0; to: 1; duration: 240
            }
            NumberAnimation {
                target: premio; property: "y"
                from: apertura.height * 0.34; to: apertura.height * 0.02
                duration: 520; easing.type: Easing.OutBack
            }
            NumberAnimation {
                target: apertura; property: "fulgor"
                to: 0.35; duration: 520
            }
        }

        // tiempo de sobra para leer qué ha salido
        PauseAnimation { duration: 3200 }
        ScriptAction { script: apertura.terminado() }
    }

    // ── resplandor detrás de todo
    // Centrado en `sacudida`, que es hermano suyo: anclarlo a `tapa`, que vive
    // dentro de otro item, no es válido y lo mandaba a la esquina superior
    // izquierda.
    Rectangle {
        anchors.centerIn: sacudida
        width: 260 * apertura.fulgor
        height: width
        radius: width / 2
        opacity: apertura.fulgor * 0.5
        color: apertura.rareza ? apertura.rareza.color : "#ffffff"
        visible: apertura.fulgor > 0
    }

    // ── chispas que salen al reventar
    Repeater {
        model: 10

        delegate: Rectangle {
            id: chispa
            required property int index
            readonly property real angulo: (index / 10) * Math.PI * 2

            width: 4
            height: 4
            radius: 2
            color: apertura.rareza ? apertura.rareza.color : "#ffd60a"
            opacity: apertura.fulgor
            visible: apertura.fulgor > 0
            x: sacudida.x + sacudida.width / 2 - 2 + Math.cos(angulo) * 90 * apertura.fulgor
            y: sacudida.y + sacudida.height / 2 - 2 + Math.sin(angulo) * 70 * apertura.fulgor
        }
    }

    // ── el cofre
    Item {
        id: sacudida
        width: 96
        height: 96
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.42

        Image {
            id: tapa
            anchors.fill: parent
            source: "assets/cofres/c" + String(apertura.tipo * 4 + apertura.cuadro)
                .padStart(2, "0") + ".png"
            fillMode: Image.PreserveAspectFit
            smooth: false
        }
    }

    // ── lo que salió
    ColumnLayout {
        id: premio
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.8
        opacity: 0
        spacing: 2

        // el icono de la pieza: ver qué ha salido, no solo leerlo
        Image {
            source: apertura.objeto
                ? "assets/objetos/i" + String(apertura.objeto.icono).padStart(2, "0") + ".png"
                : ""
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignHCenter
            fillMode: Image.PreserveAspectFit
            smooth: false
        }

        InsigniaRareza {
            rareza: apertura.objeto ? apertura.objeto.rareza : 0
            nivel: Items.nivelDe(apertura.objeto)
            Layout.alignment: Qt.AlignHCenter
        }

        IslandLabel {
            text: apertura.objeto ? apertura.objeto.nombre : ""
            font.pixelSize: 13
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        IslandLabel {
            text: apertura.objeto ? Items.resumen(apertura.objeto) : ""
            color: Theme.muted
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
    }

    // pulsar salta la ceremonia
    MouseArea {
        anchors.fill: parent
        onClicked: {
            ceremonia.stop()
            apertura.terminado()
        }
    }
}
