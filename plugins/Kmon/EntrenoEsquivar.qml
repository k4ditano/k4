//  Velocidad — esquivar: caen bloques por tres carriles y hay que apartarse
//  clicando el carril al que huir. Diez bloques, cada esquive cuenta.

import QtQuick
import "../../core"
import "../../services"

Item {
    id: juego

    property color tinta: "#2e332a"
    property int carril: 1          // donde está la criatura: 0 · 1 · 2
    property int caidos: 0
    property int esquivados: 0
    signal terminado(int puntos)

    readonly property int totalBloques: 10
    readonly property real anchoCarril: width / 3

    anchors.fill: parent

    IslandLabel {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 14
        text: Idioma.t("¡Esquiva!") + "  " + juego.caidos + "/" + juego.totalBloques
        color: juego.tinta
        font.pixelSize: 11
        font.weight: Font.Bold
        z: 3
    }

    //  Las líneas de los carriles.
    Repeater {
        model: 2
        Rectangle {
            required property int index
            x: (index + 1) * juego.anchoCarril
            y: 30
            width: 1
            height: parent.height - 60
            color: juego.tinta
            opacity: 0.25
        }
    }

    //  El bloque que cae.
    Rectangle {
        id: bloque
        width: 26; height: 26
        color: juego.tinta
        visible: false

        property int enCarril: 0

        NumberAnimation on y {
            id: caida
            running: false
            from: 22
            to: juego.height - 58
            duration: 1300
            onFinished: {
                bloque.visible = false
                if (bloque.enCarril !== juego.carril)
                    juego.esquivados += 1
                else
                    golpe.restart()
                juego.caidos += 1
                if (juego.caidos >= juego.totalBloques)
                    fin.start()
                else
                    siguiente.restart()
            }
        }
    }

    //  La criatura, abajo, en su carril.
    Image {
        id: corredor
        x: juego.carril * juego.anchoCarril + (juego.anchoCarril - width) / 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        width: 44; height: 44
        fillMode: Image.PreserveAspectFit
        smooth: false
        source: Qt.resolvedUrl("assets/" + Kmon.spriteLcd(juego.caidos % 2 === 0))

        Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }

        SequentialAnimation {
            id: golpe
            NumberAnimation { target: corredor; property: "rotation"; to: 24; duration: 90 }
            NumberAnimation { target: corredor; property: "rotation"; to: 0; duration: 180 }
        }
    }

    //  Clicar un tercio de la pantalla es correr a ese carril.
    MouseArea {
        anchors.fill: parent
        z: 2
        onClicked: function (ev) {
            juego.carril = Math.max(0, Math.min(2,
                Math.floor(ev.x / juego.anchoCarril)))
        }
    }

    Timer {
        id: siguiente
        interval: 420
        running: true
        onTriggered: {
            bloque.enCarril = Math.floor(Math.random() * 3)
            bloque.x = bloque.enCarril * juego.anchoCarril
                + (juego.anchoCarril - bloque.width) / 2
            bloque.visible = true
            caida.restart()
        }
    }

    Timer {
        id: fin
        interval: 500
        onTriggered: juego.terminado(Math.round(juego.esquivados * 10 / juego.totalBloques))
    }
}
