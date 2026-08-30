//  El estado del equipo de un vistazo.
//
//  Arriba las cuatro que importan —CPU, RAM, GPU y red— cada una con su
//  historia de los dos últimos minutos; abajo quién se lo está comiendo, con
//  su botón para cortarlo.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 11
        anchors.bottomMargin: 12
        spacing: 7

        // ── cabecera ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF035B)
                color: Theme.muted
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Idioma.t("Sistema")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            //  Las cifras que no cambian en dos minutos —disco, nvme, hilos—
            //  ya no viven aquí: se apretaban a 10 px contra la × en la
            //  esquina, que es donde va lo que no importa, y sí importan. Han
            //  bajado a su propia fila (ver «tres cifras que se miran de
            //  refilón»), y la cabecera se queda con el título y el cierre.
            Item { Layout.fillWidth: true }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── las cuatro medidas ────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            columns: 2
            columnSpacing: 8
            rowSpacing: 7

            Repeater {
                model: [
                    { id: "cpu", nombre: Idioma.t("CPU"), tono: "#0a84ff" },
                    { id: "ram", nombre: Idioma.t("Memoria"), tono: "#bf5af2" },
                    { id: "gpu", nombre: Idioma.t("GPU"), tono: "#30d158" },
                    { id: "red", nombre: Idioma.t("Red"), tono: "#ff9f0a" }
                ]

                delegate: Rectangle {
                    id: tarjeta
                    required property var modelData

                    readonly property bool esRed: modelData.id === "red"
                    readonly property bool esGpu: modelData.id === "gpu"

                    visible: !esGpu || Sistema.hayGpu

                    Layout.fillWidth: true
                    Layout.preferredHeight: 74
                    radius: 11
                    color: Theme.surface

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            IslandLabel {
                                text: tarjeta.modelData.nombre
                                color: Theme.muted
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            // el detalle de cada una: qué modelo, qué interfaz
                            IslandLabel {
                                text: tarjeta.esGpu ? Sistema.gpuNombre
                                    : tarjeta.esRed ? Sistema.redIface : ""
                                color: Theme.dim
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            IslandLabel {
                                text: {
                                    if (tarjeta.modelData.id === "cpu")
                                        return Sistema.grados(Sistema.cpuTemp)
                                    if (tarjeta.esGpu)
                                        return Sistema.grados(Sistema.gpuTemp)
                                    return ""
                                }
                                color: Theme.dim
                                font.pixelSize: 10
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            IslandLabel {
                                text: {
                                    if (tarjeta.modelData.id === "cpu")
                                        return Math.round(Sistema.cpuUso) + "%"
                                    if (tarjeta.modelData.id === "ram")
                                        return Math.round(Sistema.ramPct) + "%"
                                    if (tarjeta.esGpu)
                                        return Math.round(Sistema.gpuUso) + "%"
                                    return "↓ " + Sistema.tasa(Sistema.redRx)
                                }
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }

                            IslandLabel {
                                text: {
                                    //  El swap va CON la memoria, que es de
                                    //  lo que habla. Estaba en la tarjeta de
                                    //  la CPU —de relleno, porque era la única
                                    //  sin segundo dato— y ahí no significaba
                                    //  nada: quien mira «swap 1,7 GB» debajo
                                    //  de un 13 % de CPU lee dos cosas que no
                                    //  tienen que ver.
                                    if (tarjeta.modelData.id === "ram") {
                                        const base = Sistema.ramUsada.toFixed(1) + " / "
                                            + Sistema.ramTotal.toFixed(1) + Idioma.t(" GB")
                                        return Sistema.swapTotal > 0 && Sistema.swapUsada > 0.05
                                            ? base + Idioma.t(" · swap ")
                                              + Sistema.swapUsada.toFixed(1)
                                            : base
                                    }
                                    if (tarjeta.esGpu)
                                        return Math.round(Sistema.gpuMemUsada) + " / "
                                            + Math.round(Sistema.gpuMemTotal) + Idioma.t(" MB")
                                    if (tarjeta.esRed)
                                        return "↑ " + Sistema.tasa(Sistema.redTx)
                                    return ""
                                }
                                color: Theme.dim
                                font.pixelSize: 9
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 3
                            }

                            Item { Layout.fillWidth: true }
                        }

                        Grafica {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 20
                            tono: tarjeta.modelData.tono
                            // la red no tiene tope: se escala con lo que haya
                            techo: tarjeta.esRed ? 0 : 100
                            valores: {
                                if (tarjeta.modelData.id === "cpu") return Sistema.cpuHist
                                if (tarjeta.modelData.id === "ram") return Sistema.ramHist
                                if (tarjeta.esGpu) return Sistema.gpuHist
                                return Sistema.redHist
                            }
                        }
                    }
                }
            }
        }

        //  ── tres cifras que se miran de refilón ───────────────────
        //
        //  Disco, temperatura del disco y núcleos: lo que no se mueve en dos
        //  minutos y por eso no merece gráfica, pero sí merece leerse. Con la
        //  misma forma de tarjeta que las cuatro de arriba —rótulo tenue
        //  encima, cifra debajo— para que la pantalla tenga UNA gramática y no
        //  dos: lo de arriba se vigila, esto se consulta.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 1
            spacing: 8

            Repeater {
                model: [
                    { clave: "disco", nombre: Idioma.t("Disco"),
                      hay: Sistema.discoTotal > 0,
                      valor: Math.round(Sistema.discoUsado) + " / "
                             + Math.round(Sistema.discoTotal) + Idioma.t(" GB") },
                    { clave: "nvme", nombre: Idioma.t("Temperatura"),
                      hay: Sistema.tempNvme > 0,
                      valor: Sistema.grados(Sistema.tempNvme) },
                    { clave: "hilos", nombre: Idioma.t("Núcleos"),
                      hay: Sistema.cpuHilos > 0,
                      valor: String(Sistema.cpuHilos) }
                ]

                delegate: Rectangle {
                    required property var modelData
                    //  La que no tenga dato no deja un hueco: se va y las
                    //  otras se reparten el ancho. Un portátil sin nvme no
                    //  tiene por qué enseñar una tarjeta con un guion.
                    visible: modelData.hay
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 11
                    color: Theme.surface

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0

                        IslandLabel {
                            text: modelData.nombre
                            color: Theme.dim
                            font.pixelSize: 9
                            Layout.alignment: Qt.AlignHCenter
                        }

                        IslandLabel {
                            text: modelData.valor
                            color: Theme.ink
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }

        // ── quién se lo come ──────────────────────────────────────
        //  Los márgenes y anchos son los mismos que los de las filas: si no
        //  cuadran al píxel, un rótulo de columna desalineado confunde más que
        //  no ponerlo.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 9
            Layout.rightMargin: 6
            Layout.topMargin: 2
            spacing: 8

            IslandLabel {
                text: Idioma.t("Lo que más consume")
                color: Theme.muted
                font.pixelSize: 10
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }

            IslandLabel {
                text: Idioma.t("PID")
                color: Theme.dim
                font.pixelSize: 9
                Layout.preferredWidth: 54
                horizontalAlignment: Text.AlignRight
            }

            IslandLabel {
                text: Idioma.t("CPU")
                color: Theme.dim
                font.pixelSize: 9
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
            }

            IslandLabel {
                text: Idioma.t("Memoria")
                color: Theme.dim
                font.pixelSize: 9
                Layout.preferredWidth: 58
                horizontalAlignment: Text.AlignRight
            }

            // el hueco del botón de matar, que en las filas siempre ocupa
            Item { Layout.preferredWidth: 28 }
        }

        ListView {
            //  La barra de la casa: sale sola si hay más de lo que cabe.
            ScrollBar.vertical: IslandScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: Sistema.procesos
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: fila
                required property var modelData

                width: ListView.view.width
                height: 26
                radius: 7
                color: filaMouse.containsMouse ? Theme.surface : "transparent"

                Behavior on color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 6
                    spacing: 8

                    IslandLabel {
                        text: fila.modelData.nombre
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    IslandLabel {
                        text: fila.modelData.pid
                        color: Theme.dim
                        font.pixelSize: 9
                        Layout.preferredWidth: 54
                        horizontalAlignment: Text.AlignRight
                    }

                    IslandLabel {
                        text: fila.modelData.cpu.toFixed(1) + "%"
                        color: fila.modelData.cpu > 50 ? Theme.red : Theme.ink
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Layout.preferredWidth: 44
                        horizontalAlignment: Text.AlignRight
                    }

                    IslandLabel {
                        text: fila.modelData.ram >= 1024
                            ? (fila.modelData.ram / 1024).toFixed(1) + Idioma.t(" GB")
                            : fila.modelData.ram + Idioma.t(" MB")
                        color: Theme.muted
                        font.pixelSize: 10
                        Layout.preferredWidth: 58
                        horizontalAlignment: Text.AlignRight
                    }

                    MediaButton {
                        glyph: Theme.ico.close
                        glyphSize: 12
                        glyphColor: Theme.red
                        opacity: filaMouse.containsMouse ? 1 : 0
                        onActivated: Sistema.matar(fila.modelData.pid)

                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                }

                MouseArea {
                    id: filaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    z: -1
                }
            }
        }

        IslandLabel {
            Layout.fillWidth: true
            visible: !Sistema.cargado
            text: Idioma.t("Midiendo…")
            color: Theme.dim
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
