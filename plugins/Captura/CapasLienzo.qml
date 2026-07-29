//  Las capas, encima del vídeo.
//
//  Van FUERA de `lente` y hermanas suyas, que es exactamente el orden que tiene
//  el grafo de ffmpeg: primero el zoom sobre el vídeo y las capas después. Por
//  eso lo que se ve aquí es lo que va a salir, por construcción y no por
//  casualidad —si estuvieran dentro, el zoom las ampliaría y arrastrarlas se
//  sentiría más rápido cuanto más ampliado estuviera el encuadre—.
//
//  Las coordenadas del plan son fracciones del fotograma y apuntan al centro,
//  así que colocarlas aquí es una regla de tres con el ancho del marco. Y como
//  el marco tiene la proporción del vídeo de salida, la regla de tres vale.

import QtQuick
import "../../core"
import "../../services"

Item {
    id: lienzo

    // El instante de la línea, para saber qué capas tocan ahora.
    property real segundos: 0

    Repeater {
        //  En el orden de APILADO, no en el de la lista.
        //
        //  En QML el último hijo se pinta encima, así que este orden es el que
        //  decide qué tapa a qué. Con `Editor.capas` a secas iba por el orden
        //  crudo y no por banda: subir una capa cambiaba el fichero renderizado
        //  pero no la previa, o sea que la vista mentía.
        model: Editor.capasApiladas

        delegate: Item {
            id: capa
            required property var modelData

            readonly property bool elegida: Editor.tipoSel === "capa"
                && Editor.idSel === modelData.id

            //  Se ve en su tramo, y también mientras la tienes agarrada: soltar
            //  el ratón justo al salirse del tramo la haría desaparecer a media
            //  faena.
            readonly property bool dentro: lienzo.segundos >= modelData.t0
                && lienzo.segundos <= modelData.t1
            visible: dentro || moviendo || escalando

            // ── el gesto en curso, en local ───────────────────────
            property bool moviendo: false
            property bool escalando: false
            property real vX: 0
            property real vY: 0
            property real vEscala: 0

            readonly property real ex: moviendo ? vX : modelData.x
            readonly property real ey: moviendo ? vY : modelData.y
            readonly property real eEscala: escalando ? vEscala : modelData.escala

            //  La proporción de la imagen la trae la propia imagen. ffmpeg
            //  escala con `-1` de alto, o sea conservándola, así que aquí hay
            //  que hacer lo mismo o la previa mentiría.
            readonly property real relacion: imagen.implicitWidth > 0
                ? imagen.implicitHeight / imagen.implicitWidth : 0.5625

            width: Math.max(8, lienzo.width * eEscala)
            height: width * relacion
            x: ex * lienzo.width - width / 2
            y: ey * lienzo.height - height / 2

            opacity: modelData.opacidad !== undefined ? modelData.opacidad : 1

            Image {
                id: imagen
                anchors.fill: parent
                source: capa.modelData.ruta.length > 0
                    ? "file://" + capa.modelData.ruta : ""
                fillMode: Image.Stretch
                // El PNG llega a menudo mucho más grande que el hueco; sin esto
                // se guarda en memoria a tamaño completo por cada capa.
                sourceSize.width: Math.max(64, width)
                smooth: true
                asynchronous: true
            }

            // ── el marco de selección ─────────────────────────────
            Rectangle {
                anchors.fill: parent
                visible: capa.elegida
                color: "transparent"
                border.width: 1
                border.color: Theme.blue
            }

            // ── mover ─────────────────────────────────────────────
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: 12
                anchors.bottomMargin: 12
                hoverEnabled: true
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                property real xIni: 0
                property real yIni: 0

                //  En coordenadas del LIENZO, no de la capa: la capa se recoloca
                //  con el propio arrastre, y en sus coordenadas el puntero se
                //  quedaría siempre en el mismo sitio. Es la trampa de siempre.
                function enLienzo(ev) { return mapToItem(lienzo, ev.x, ev.y) }

                onPressed: function (ev) {
                    Editor.seleccionar("capa", capa.modelData.id)
                    const p = enLienzo(ev)
                    xIni = p.x
                    yIni = p.y
                    capa.vX = capa.modelData.x
                    capa.vY = capa.modelData.y
                    capa.moviendo = true
                }

                onPositionChanged: function (ev) {
                    if (!pressed)
                        return
                    const p = enLienzo(ev)
                    capa.vX = Math.max(0, Math.min(1, capa.modelData.x
                        + (p.x - xIni) / Math.max(1, lienzo.width)))
                    capa.vY = Math.max(0, Math.min(1, capa.modelData.y
                        + (p.y - yIni) / Math.max(1, lienzo.height)))
                }

                onReleased: {
                    Editor.fijarCapa(capa.modelData.id,
                                     { x: capa.vX, y: capa.vY })
                    capa.moviendo = false
                }
            }

            // ── escalar, por la esquina ───────────────────────────
            MouseArea {
                width: 14
                height: 14
                x: capa.width - 12
                y: capa.height - 12
                visible: capa.elegida
                preventStealing: true
                cursorShape: Qt.SizeFDiagCursor

                property real xIni: 0

                function enLienzo(ev) { return mapToItem(lienzo, ev.x, ev.y).x }

                onPressed: function (ev) {
                    xIni = enLienzo(ev)
                    capa.vEscala = capa.modelData.escala
                    capa.escalando = true
                }

                onPositionChanged: function (ev) {
                    if (!pressed)
                        return
                    //  Se escala desde el centro, que es donde está anclada la
                    //  capa: por eso el doble. Arrastrar la esquina un píxel
                    //  aleja el borde un píxel, y el de enfrente otro.
                    const d = (enLienzo(ev) - xIni) * 2
                    capa.vEscala = Math.max(0.02, Math.min(2,
                        capa.modelData.escala + d / Math.max(1, lienzo.width)))
                }

                onReleased: {
                    Editor.fijarCapa(capa.modelData.id, { escala: capa.vEscala })
                    capa.escalando = false
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 9
                    height: 9
                    radius: 2
                    color: Theme.blue
                    border.width: 1
                    border.color: Theme.ink
                }
            }
        }
    }
}
