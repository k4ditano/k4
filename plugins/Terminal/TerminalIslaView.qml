//  La terminal dentro de la island.
//
//  Aquí no se emula nada: lo que se pinta es la rejilla que manda
//  k4term-isla, ya resuelta por el VT de ghostty, y lo que se teclea se le
//  devuelve tal cual. La vista es una ventana a una sesión que vive fuera —
//  por eso cerrarla no para nada y volver a abrirla te deja donde estabas.
//
//  Del teclado: mientras está abierta se lo queda entero, como el lanzador o
//  la pregunta a la IA. ESC cierra, que es la convención de la casa; si algún
//  día hace falta mandar un ESC de verdad a la sesión, será con otra tecla.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: vista

    required property var plugin

    readonly property var marco: plugin.marco

    //  La misma fuente que la terminal de ventana: es monoespaciada de
    //  verdad, así que el ancho de celda sale de medir una eme.
    readonly property int cuerpo: 13
    readonly property real anchoCelda: metricas.advanceWidth("M")
    readonly property real altoLinea: Math.ceil(metricas.height)
    readonly property int margen: 14

    FontMetrics {
        id: metricas
        font.family: Theme.iconFont
        font.pixelSize: vista.cuerpo
    }

    //  Cuántas columnas y filas caben de verdad. Se le dice a la sesión, que
    //  es quien redimensiona el PTY: la shell tiene que saber su ancho o
    //  parte las líneas donde no toca.
    readonly property int cols: Math.max(20, Math.floor((width - margen * 2) / anchoCelda))
    readonly property int filas: Math.max(4, Math.floor((height - margen * 2) / altoLinea))

    onColsChanged: medir.restart()
    onFilasChanged: medir.restart()
    Component.onCompleted: {
        plugin.mandar({ que: "medida", cols: cols, filas: filas })
        plugin.mandar({ que: "pinta" })
        forzarFoco.start()
    }

    Timer {
        id: medir
        interval: 60
        onTriggered: vista.plugin.mandar({ que: "medida", cols: vista.cols,
                                           filas: vista.filas })
    }

    //  El foco llega un pelo después de que la island se abra; sin esta
    //  espera las primeras teclas se pierden.
    Timer {
        id: forzarFoco
        interval: 60
        onTriggered: campo.forceActiveFocus()
    }

    Column {
        id: rejilla
        x: vista.margen
        y: vista.margen
        spacing: 0

        Repeater {
            model: vista.marco ? vista.marco.filas : []

            delegate: Row {
                required property var modelData
                height: vista.altoLinea
                spacing: 0

                Repeater {
                    model: parent.modelData

                    delegate: Item {
                        required property var modelData
                        implicitWidth: letras.implicitWidth
                        implicitHeight: vista.altoLinea

                        Rectangle {
                            anchors.fill: parent
                            color: modelData.b
                            visible: modelData.b !== String(Theme.islandBg)
                        }

                        Text {
                            id: letras
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.t
                            color: modelData.f
                            font.family: Theme.iconFont
                            font.pixelSize: vista.cuerpo
                            //  El bit 0x02 del VT es la negrita.
                            font.weight: (modelData.n & 0x02) ? Font.Bold : Font.Normal
                            font.italic: (modelData.n & 0x04) !== 0
                            font.underline: (modelData.n & 0x08) !== 0
                            font.strikeout: (modelData.n & 0x40) !== 0
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }
    }

    //  El cursor va aparte de las filas: es de la sesión, no del texto.
    Rectangle {
        visible: vista.marco !== null
        x: vista.margen + (vista.marco ? (vista.marco.cursor[0] - 1) : 0) * vista.anchoCelda
        y: vista.margen + (vista.marco ? (vista.marco.cursor[1] - 1) : 0) * vista.altoLinea
        width: 2
        height: vista.altoLinea
        color: Theme.ink
        opacity: 0.9
    }

    //  Un receptor de teclas sin pintar nada: la traducción de tecla a bytes
    //  la hace la sesión, que para eso lleva el codificador de ghostty
    //  dentro. Aquí solo se decide si es texto o si tiene nombre.
    //  La rueda mueve el historial de la sesión, que es quien lo guarda. Tres
    //  líneas por muesca, como en todas partes.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function (rueda) {
            const pasos = rueda.angleDelta.y > 0 ? 3 : -3
            vista.plugin.mandar({ que: "rueda", lineas: -pasos })
            rueda.accepted = true
        }
    }

    Item {
        id: campo
        focus: true
        anchors.fill: parent

        readonly property var nombres: ({})

        Keys.onPressed: function (e) {
            const mods = {
                shift: (e.modifiers & Qt.ShiftModifier) !== 0,
                control: (e.modifiers & Qt.ControlModifier) !== 0,
                alt: (e.modifiers & Qt.AltModifier) !== 0
            }

            const conNombre = function (nombre) {
                vista.plugin.mandar(Object.assign({ que: "tecla", nombre: nombre }, mods))
                e.accepted = true
            }

            switch (e.key) {
            case Qt.Key_Escape:       vista.plugin.cerrar(); e.accepted = true; return
            case Qt.Key_Return:
            case Qt.Key_Enter:        return conNombre("enter")
            case Qt.Key_Backspace:    return conNombre("backspace")
            case Qt.Key_Tab:          return conNombre("tab")
            case Qt.Key_Backtab:      return conNombre("tab")
            case Qt.Key_Up:           return conNombre("up")
            case Qt.Key_Down:         return conNombre("down")
            case Qt.Key_Left:         return conNombre("left")
            case Qt.Key_Right:        return conNombre("right")
            case Qt.Key_Home:         return conNombre("home")
            case Qt.Key_End:          return conNombre("end")
            case Qt.Key_PageUp:       return conNombre("pageup")
            case Qt.Key_PageDown:     return conNombre("pagedown")
            case Qt.Key_Delete:       return conNombre("delete")
            case Qt.Key_Insert:       return conNombre("insert")
            }

            if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F12)
                return conNombre("f" + (e.key - Qt.Key_F1 + 1))

            //  Lo demás va como texto. Qt ya entrega el carácter de control
            //  cuando se pulsa Ctrl+algo, así que un Ctrl+C llega hecho.
            if (e.text.length > 0) {
                vista.plugin.mandar({ que: "texto", valor: e.text })
                e.accepted = true
            }
        }
    }

    //  Pie discreto: qué es esto y cómo se sale. Con el mismo margen que la
    //  rejilla, que la island tiene las esquinas redondeadas y lo que se pega
    //  al borde se sale por debajo del recorte.
    IslandLabel {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: vista.margen
        anchors.bottomMargin: 6
        text: Idioma.t("ESC cierra · la sesión sigue viva")
        color: Theme.dim
        font.pixelSize: 10
    }
}
