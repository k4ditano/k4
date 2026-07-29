//  La línea de tiempo: la pista de trozos y la del zoom, con su regla.
//
//  Las dos comparten eje —el tiempo de LÍNEA— y por eso comparten anchura y
//  cabezal. Lo que cambia es qué significa arrastrar en cada una: abajo, dónde
//  quieres que se vea el zoom; arriba, en qué orden van los trozos.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: linea

    property real total: 1
    property real cabezal: 0

    signal saltar(real t)

    spacing: 3

    // ── la regla ──────────────────────────────────────────────────
    Item {
        id: regla
        Layout.fillWidth: true
        Layout.preferredHeight: 13

        //  Una marca cada tanto, con el número puesto. El paso se elige para
        //  que no se amontonen: en un clip de diez segundos cada segundo, y en
        //  uno de diez minutos cada minuto.
        readonly property var escalones: [0.5, 1, 2, 5, 10, 15, 30, 60, 120,
                                          300, 600, 1800]
        readonly property real paso: {
            const objetivo = linea.total / Math.max(1, width / 78)
            for (let i = 0; i < escalones.length; ++i)
                if (escalones[i] >= objetivo)
                    return escalones[i]
            return escalones[escalones.length - 1]
        }

        Repeater {
            //  Todo referido a `regla` por su id y no por `parent`: dentro de un
            //  delegado hay dos niveles de padre y coger el que no es devuelve
            //  `undefined`, que en una cuenta sale como NaN y coloca la marca en
            //  ninguna parte. Con el nombre delante no hay forma de equivocarse.
            model: Math.max(0, Math.floor(linea.total / regla.paso) + 1)

            delegate: Item {
                required property int index
                readonly property real t: index * regla.paso

                x: regla.width * (t / Math.max(0.001, linea.total))
                height: regla.height

                Rectangle {
                    width: 1
                    height: 4
                    color: Theme.dim
                    opacity: 0.6
                }

                IslandLabel {
                    x: 3
                    y: 1
                    text: parent.t >= 60
                        ? Math.floor(parent.t / 60) + ":"
                          + (parent.t % 60 < 10 ? "0" : "")
                          + Math.round(parent.t % 60)
                        : parent.t + " s"
                    color: Theme.dim
                    font.pixelSize: 8
                }
            }
        }
    }

    // ── los trozos de vídeo ───────────────────────────────────────
    PistaClips {
        Layout.fillWidth: true
        Layout.preferredHeight: 34

        total: linea.total
        cabezal: linea.cabezal
        onSaltar: function (t) { linea.saltar(t) }
    }

    // ── el zoom ───────────────────────────────────────────────────
    Pista {
        Layout.fillWidth: true
        Layout.preferredHeight: 26

        modelo: Editor.momentos
        total: linea.total
        cabezal: linea.cabezal
        elegido: {
            //  `Pista` elige por índice y la selección va por id, porque con
            //  varias pistas el índice no dice de qué es. Aquí se traduce.
            for (let i = 0; i < Editor.momentos.length; ++i)
                if (Editor.tipoSel === "momento"
                        && Editor.momentos[i].id === Editor.idSel)
                    return i
            return -1
        }

        onSaltar: function (t) { linea.saltar(t) }
        onElegir: function (i) {
            if (i >= 0 && i < Editor.momentos.length)
                Editor.seleccionar("momento", Editor.momentos[i].id)
        }
        onEditar: function (id, a, b) { Editor.fijarMomento(id, { t0: a, t1: b }) }
        onCrear: function (a, b) {
            Editor.seleccionar("momento", Editor.crearMomento(a, b))
        }
        onNivel: function (id, d) { Editor.ajustarNivel(id, d > 0 ? 0.1 : -0.1) }
    }
}
