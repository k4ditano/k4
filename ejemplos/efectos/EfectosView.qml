//  Una fila de botones por cada efecto. Lo interesante no está aquí sino en
//  lo que provocan: K4.Tema.tintar, K4.Isla.efecto y la Mano de al lado.

import QtQuick
import K4 as K4

Item {
    id: vista

    required property var plugin

    Column {
        anchors.centerIn: parent
        spacing: 10

        K4.Etiqueta {
            anchors.horizontalCenter: parent.horizontalCenter
            text: vista.plugin.tr("La island como escenario")
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        //  El tinte: el ambiente de toda la barra durante unos segundos.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Repeater {
                model: [
                    { texto: vista.plugin.tr("Bosque"), color: "#2e5c3a" },
                    { texto: vista.plugin.tr("Brasa"), color: "#5c2e2e" },
                    { texto: vista.plugin.tr("Abismo"), color: "#26324f" },
                    { texto: vista.plugin.tr("Destintar"), color: "" }
                ]

                delegate: K4.Baldosa {
                    id: chipTinte
                    required property var modelData
                    width: etiquetaTinte.implicitWidth + 26
                    height: 30

                    K4.Etiqueta {
                        id: etiquetaTinte
                        anchors.centerIn: parent
                        text: chipTinte.modelData.texto
                        font.pixelSize: 11
                    }

                    onPulsada: {
                        if (chipTinte.modelData.color === "")
                            K4.Tema.destintar("efectos")
                        else
                            K4.Tema.tintar("efectos", chipTinte.modelData.color,
                                           0.35, 4000)
                    }
                }
            }
        }

        //  Los gestos: la island como objeto físico.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Repeater {
                model: [
                    { texto: vista.plugin.tr("Sacudida"), gesto: "sacudida" },
                    { texto: vista.plugin.tr("Empujón"), gesto: "empujon" },
                    { texto: vista.plugin.tr("Tirón"), gesto: "tiron" }
                ]

                delegate: K4.Baldosa {
                    id: chipGesto
                    required property var modelData
                    width: etiquetaGesto.implicitWidth + 26
                    height: 30

                    K4.Etiqueta {
                        id: etiquetaGesto
                        anchors.centerIn: parent
                        text: chipGesto.modelData.texto
                        font.pixelSize: 11
                    }

                    onPulsada: K4.Isla.efecto("efectos", chipGesto.modelData.gesto)
                }
            }
        }

        //  Lo de fuera y lo de moverse: la mano que asoma, y la island que
        //  se va de paseo por su borde y vuelve sola.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            K4.Baldosa {
                width: etiquetaMano.implicitWidth + 26
                height: 30
                activa: vista.plugin.manoFuera

                K4.Etiqueta {
                    id: etiquetaMano
                    anchors.centerIn: parent
                    text: vista.plugin.manoFuera
                        ? vista.plugin.tr("Esconder la mano")
                        : vista.plugin.tr("Sacar la mano")
                    font.pixelSize: 11
                }

                onPulsada: vista.plugin.manoFuera = !vista.plugin.manoFuera
            }

            K4.Baldosa {
                width: etiquetaPaseo.implicitWidth + 26
                height: 30

                K4.Etiqueta {
                    id: etiquetaPaseo
                    anchors.centerIn: parent
                    text: vista.plugin.tr("De paseo")
                    font.pixelSize: 11
                }

                //  Al 15% del borde tres segundos, y de vuelta sola.
                onPulsada: K4.Isla.colocar("efectos", 0.15, 3000)
            }
        }
    }
}
