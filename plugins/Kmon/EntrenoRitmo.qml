//  Fuerza — el saco: una aguja barre la barra y hay que golpear cuando pasa
//  por la zona verde del centro. Ocho golpes; el compás no perdona el spam.

import QtQuick
import "../../core"
import "../../services"

Item {
    id: juego

    property color tinta: "#2e332a"
    property int golpes: 0
    property int aciertos: 0
    signal terminado(int puntos)

    readonly property int totalGolpes: 8

    anchors.fill: parent

    IslandLabel {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16
        text: Idioma.t("¡Golpea en la zona!") + "  " + juego.golpes + "/" + juego.totalGolpes
        color: juego.tinta
        font.pixelSize: 11
        font.weight: Font.Bold
    }

    //  El saco, temblando con cada acierto.
    Rectangle {
        id: saco
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -14
        width: 54; height: 68; radius: 10
        color: "transparent"
        border.width: 3
        border.color: juego.tinta

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            width: 8; height: 10
            color: juego.tinta
        }

        SequentialAnimation {
            id: temblor
            NumberAnimation { target: saco; property: "rotation"; to: 9; duration: 60 }
            NumberAnimation { target: saco; property: "rotation"; to: -7; duration: 90 }
            NumberAnimation { target: saco; property: "rotation"; to: 0; duration: 120 }
        }
    }

    //  La barra del compás.
    Rectangle {
        id: pista
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 34
        width: parent.width - 60
        height: 14
        radius: 7
        color: "transparent"
        border.width: 2
        border.color: juego.tinta

        //  La zona buena.
        Rectangle {
            id: zona
            anchors.centerIn: parent
            width: parent.width * 0.22
            height: parent.height
            color: juego.tinta
            opacity: 0.25
        }

        //  La aguja, de lado a lado.
        Rectangle {
            id: aguja
            width: 4
            height: parent.height + 8
            y: -4
            color: juego.tinta

            SequentialAnimation on x {
                running: juego.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: pista.width - 4; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 900; easing.type: Easing.InOutSine }
            }
        }
    }

    IslandLabel {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        text: Idioma.f(Idioma.t("aciertos: %1"), juego.aciertos)
        color: juego.tinta
        font.pixelSize: 10
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (juego.golpes >= juego.totalGolpes)
                return
            juego.golpes += 1
            const centro = aguja.x + 2
            const dentro = centro >= zona.x && centro <= zona.x + zona.width
            if (dentro) {
                juego.aciertos += 1
                temblor.restart()
            }
            if (juego.golpes >= juego.totalGolpes)
                fin.start()
        }
    }

    Timer {
        id: fin
        interval: 600
        onTriggered: juego.terminado(Math.round(juego.aciertos * 10 / juego.totalGolpes))
    }
}
