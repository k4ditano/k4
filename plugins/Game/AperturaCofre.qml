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

    // Encadenando cofres no se puede parar seis segundos en cada uno: se
    // recorta el suspense y se acorta la pausa final, que es lo que más pesa.
    property bool rapido: false
    // Y cuanto más larga sea la cola, más corre: con una tanda de veinte se
    // puede saborear cada cofre, con ochocientos no. A 0,18 salen algo menos
    // de un segundo por cofre.
    readonly property real ritmo: !rapido ? 1 : (quedan > 20 ? 0.18 : 0.4)

    // Cuántos quedan de la tanda y cómo cortarla. Hace falta aquí dentro: la
    // ceremonia tapa el panel entero con su propio ratón, así que el botón de
    // la tarjeta queda debajo y era imposible parar una vez empezada.
    property bool encadenando: false
    property int quedan: 0
    signal parar()

    function abrir() {
        cuadro = 0
        fulgor = 0
        ceremonia.restart()
    }

    SequentialAnimation {
        id: ceremonia

        // 1 · reposo breve
        PauseAnimation { duration: 260 * apertura.ritmo }

        // 2 · temblor, tanto más largo cuanto mejor es el botín
        ScriptAction { script: apertura.cuadro = 1 }
        SequentialAnimation {
            loops: Math.max(2, Math.round(apertura.suspense * apertura.ritmo / 130))
            NumberAnimation { target: sacudida; property: "x"; to: 4; duration: 60 }
            NumberAnimation { target: sacudida; property: "x"; to: -4; duration: 60 }
        }
        NumberAnimation { target: sacudida; property: "x"; to: 0; duration: 60 }

        // 3 · se resquebraja
        ScriptAction { script: apertura.cuadro = 2 }
        PauseAnimation { duration: 260 * apertura.ritmo }

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

        // tiempo de sobra para leer qué ha salido, salvo en cadena
        PauseAnimation { duration: 3200 * apertura.ritmo }
        ScriptAction { script: apertura.terminado() }
    }

    // ── el velo
    //  Sin esto la ceremonia salía flotando sobre la rejilla del inventario y
    //  el cofre competía con veinte iconos de fondo. Tapando, se mira lo que
    //  ha salido y nada más.
    Rectangle {
        anchors.fill: parent
        color: "#ee0b0b0e"
        opacity: velo
        radius: 10

        property real velo: 0
        NumberAnimation on velo {
            running: apertura.visible
            from: 0; to: 1; duration: 180
        }
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
            // 64 = dos veces el sprite; a 40 quedaba a 1,25 y se ensuciaba
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
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

        // Con la bolsa llena la pieza no llega: se desguaza sola. Callarlo era
        // enseñar un premio que en realidad no tienes.
        IslandLabel {
            visible: apertura.objeto !== null && apertura.objeto.desguazado > 0
            text: apertura.objeto
                ? Idioma.t("bolsa llena · desguazado por ")
                  + apertura.objeto.desguazado + Idioma.t(" reliquias")
                : ""
            color: "#ff9f0a"
            font.pixelSize: 9
            font.weight: Font.DemiBold
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

    // ── parar la tanda ────────────────────────────────────────────
    //  Va por encima del ratón de arriba, que si no se queda con el clic.
    Rectangle {
        visible: apertura.encadenando
        z: 10
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        width: filaParar.implicitWidth + 20
        height: 26
        radius: 13
        color: pararRaton.containsMouse ? Theme.red : "#66000000"
        border.width: 1
        border.color: Theme.red

        Behavior on color { ColorAnimation { duration: 120 } }

        RowLayout {
            id: filaParar
            anchors.centerIn: parent
            spacing: 6

            IconGlyph {
                text: String.fromCodePoint(0xF04DB)
                color: Theme.ink
                font.pixelSize: 12
            }

            IslandLabel {
                text: apertura.quedan > 0
                    ? Idioma.t("Parar") + " · " + apertura.quedan
                    : Idioma.t("Parar")
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: pararRaton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: apertura.parar()
        }
    }
}
