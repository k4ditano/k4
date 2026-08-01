//  Cerebro — memoria: cuatro teclas de fósforo repiten una secuencia que
//  crece. Ver, repetir, y no perderse: seis rondas para la matrícula.

import QtQuick
import "../../core"
import "../../services"

Item {
    id: juego

    property color tinta: "#2e332a"
    property var secuencia: []
    property int paso: 0            // qué posición está repitiendo el jugador
    property bool enseñando: false
    property int iluminada: -1
    property int rondas: 0
    signal terminado(int puntos)

    readonly property int totalRondas: 6
    readonly property var glifos: ["⚡", "◆", "●", "▲"]

    anchors.fill: parent

    Component.onCompleted: nuevaRonda.start()

    function empezarRonda() {
        secuencia = secuencia.concat([Math.floor(Math.random() * 4)])
        paso = 0
        enseñando = true
        _indice = 0
        muestra.start()
    }

    property int _indice: 0

    Timer {
        id: muestra
        interval: 520
        repeat: true
        onTriggered: {
            if (juego._indice % 2 === 0) {
                juego.iluminada = juego.secuencia[juego._indice / 2]
            } else {
                juego.iluminada = -1
                if ((juego._indice + 1) / 2 >= juego.secuencia.length) {
                    stop()
                    juego.enseñando = false
                }
            }
            juego._indice += 1
        }
    }

    Timer { id: nuevaRonda; interval: 700; onTriggered: juego.empezarRonda() }
    Timer { id: fin; interval: 600; onTriggered: juego.terminado(Math.round(juego.rondas * 10 / juego.totalRondas)) }

    IslandLabel {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 14
        text: (juego.enseñando ? Idioma.t("Mira…") : Idioma.t("¡Repite!"))
              + "  " + juego.rondas + "/" + juego.totalRondas
        color: juego.tinta
        font.pixelSize: 11
        font.weight: Font.Bold
    }

    Grid {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 8
        columns: 2
        spacing: 14

        Repeater {
            model: 4

            delegate: Rectangle {
                id: tecla
                required property int index
                width: 62; height: 52
                radius: 9
                color: juego.iluminada === index ? juego.tinta : "transparent"
                border.width: 2
                border.color: juego.tinta

                Behavior on color { ColorAnimation { duration: 90 } }

                IslandLabel {
                    anchors.centerIn: parent
                    text: juego.glifos[tecla.index]
                    color: juego.iluminada === tecla.index
                        ? "#a9b39c" : juego.tinta
                    font.pixelSize: 20
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !juego.enseñando
                    onClicked: {
                        juego.iluminada = tecla.index
                        apagar.restart()
                        if (tecla.index === juego.secuencia[juego.paso]) {
                            juego.paso += 1
                            if (juego.paso >= juego.secuencia.length) {
                                juego.rondas += 1
                                if (juego.rondas >= juego.totalRondas)
                                    fin.start()
                                else
                                    nuevaRonda.restart()
                            }
                        } else {
                            fin.start()   // fallo: se acabó, con lo logrado
                        }
                    }
                }
            }
        }
    }

    Timer { id: apagar; interval: 180; onTriggered: juego.iluminada = -1 }
}
