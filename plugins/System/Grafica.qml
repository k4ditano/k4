//  Una gráfica de barras con las últimas muestras.
//
//  Barras y no una línea a propósito: con cuarenta y cinco valores en doscientos
//  píxeles una polilínea es un garabato, y las barras se leen igual de lejos.
//  La última va encendida, que es la que dice cómo está la cosa ahora.

import QtQuick
import "../../core"

Item {
    id: grafica

    property var valores: []
    property real techo: 100            // 0 si hay que calcularlo de los datos
    property color tono: Theme.blue

    // Cuando el techo es dinámico —la red no tiene máximo— se toma el mayor de
    // la ventana, con un suelo para que el ruido de fondo no llene la gráfica.
    readonly property real limite: {
        if (techo > 0)
            return techo
        let m = 1
        for (let i = 0; i < valores.length; ++i)
            m = Math.max(m, valores[i])
        return m
    }

    readonly property int cuantas: 45
    readonly property real anchoBarra: Math.max(1, (width - (cuantas - 1) * 1) / cuantas)

    Row {
        anchors.fill: parent
        spacing: 1

        Repeater {
            model: grafica.cuantas

            delegate: Item {
                id: hueco
                required property int index

                // Las muestras se pintan pegadas a la derecha: la historia
                // entra por la izquierda según se llena.
                readonly property int desde: grafica.cuantas - grafica.valores.length
                readonly property real valor: index >= desde
                    ? grafica.valores[index - desde] : -1

                width: grafica.anchoBarra
                height: grafica.height

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: hueco.valor < 0 ? 0
                        : Math.max(1, parent.height
                            * Math.min(1, hueco.valor / grafica.limite))
                    radius: width > 2 ? 1 : 0
                    color: grafica.tono
                    opacity: hueco.index === grafica.cuantas - 1 ? 1 : 0.45

                    Behavior on height { NumberAnimation { duration: 220 } }
                }
            }
        }
    }
}
