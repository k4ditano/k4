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
import QtMultimedia
import "../../core"
import "../../services"

Item {
    id: lienzo

    // El instante de la línea, para saber qué capas tocan ahora.
    property real segundos: 0
    // Si la reproducción va en marcha, para que los vídeos de dentro la sigan.
    property bool sonando: false

    //  La tipografía de los rótulos, del mismo fichero que usa ffmpeg.
    //
    //  Cargada por ruta y no por nombre de familia: pedir «Adwaita Sans» al
    //  sistema puede devolver otra versión o una sustituta, y entonces el ancho
    //  del rótulo en la previa no sería el del render. El fichero es el mismo que
    //  nombra `FUENTE` en tools/editar.py.
    FontLoader {
        id: fuenteRotulos
        source: "file:///usr/share/fonts/Adwaita/AdwaitaSans-Regular.ttf"
    }

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
            visible: visual && (dentro || moviendo || escalando)

            // ── el gesto en curso, en local ───────────────────────
            property bool moviendo: false
            property bool escalando: false
            property real vX: 0
            property real vY: 0
            property real vEscala: 0

            readonly property real ex: moviendo ? vX : modelData.x
            readonly property real ey: moviendo ? vY : modelData.y
            readonly property real eEscala: escalando ? vEscala : modelData.escala

            readonly property bool esTexto: modelData.tipo === "texto"
            readonly property bool esPip: modelData.tipo === "video"
            //  El audio no se pinta: no tiene sitio en el fotograma. Su bloque
            //  vive en la línea de tiempo y su volumen en la ficha.
            readonly property bool visual: modelData.tipo === "texto"
                                        || modelData.tipo === "imagen"
                                        || modelData.tipo === "video"

            //  La proporción de la imagen la trae la propia imagen. ffmpeg
            //  escala con `-1` de alto, o sea conservándola, así que aquí hay
            //  que hacer lo mismo o la previa mentiría.
            //  Un pip trae su tamaño en el plan, medido al añadirlo: `scale=…:-1`
            //  conserva la proporción al renderizar, y si la previa la inventara
            //  enseñaría un recuadro que no es el que va a salir.
            readonly property real relacion: esPip
                ? (modelData.w > 0 ? modelData.h / modelData.w : 0.5625)
                : (imagen.implicitWidth > 0
                   ? imagen.implicitHeight / imagen.implicitWidth : 0.5625)

            //  Un rótulo mide lo que mida el texto; una imagen, lo que se le diga.
            //
            //  Y se coloca con la MISMA fórmula que `drawtext`: el centro pedido
            //  menos medio alto del texto. Ojo, «medio alto del texto» es alto de
            //  línea —subida más bajada—, no la caja de los trazos visibles, así
            //  que el rótulo se ve un poco por encima del centro pedido. Es un
            //  detalle raro, pero copiarlo es lo que hace que la previa coincida:
            //  medido, ffmpeg deja el centro visible en 0,837 cuando se le pide
            //  0,85, y aquí sale lo mismo por construcción.
            width: esTexto ? rotulo.implicitWidth + relleno * 2
                           : Math.max(8, lienzo.width * eEscala)
            height: esTexto ? rotulo.implicitHeight + relleno * 2
                            : width * relacion
            x: ex * lienzo.width - width / 2
            y: ey * lienzo.height - height / 2

            // El mismo `boxborderw` que le pasa el grafo a ffmpeg.
            readonly property real tamTexto: lienzo.height
                * (modelData.tam !== undefined ? modelData.tam : 0.06)
            readonly property real relleno: esTexto && modelData.fondo > 0.001
                ? Math.max(2, Math.round(tamTexto * 0.28)) : 0

            opacity: modelData.opacidad !== undefined ? modelData.opacidad : 1

            //  El vídeo de dentro, reproduciéndose.
            //
            //  Se coloca al entrar en su tramo y no en cada fotograma: pedirle un
            //  `seek` treinta veces por segundo es no dejarle reproducir nada. Es
            //  el mismo trato que a las pistas de audio añadidas, y con el mismo
            //  precio: al cabo de minutos habrá décimas de desfase. Lo que sale
            //  del render lo compone ffmpeg al fotograma.
            Item {
                anchors.fill: parent
                visible: capa.esPip

                readonly property bool debeSonar: capa.dentro && lienzo.sonando

                onDebeSonarChanged: {
                    if (debeSonar) {
                        const dentroDelClip = capa.modelData.recorte
                            ? capa.modelData.recorte[0] : 0
                        mp.position = Math.max(0, dentroDelClip
                            + lienzo.segundos - capa.modelData.t0) * 1000
                        mp.play()
                    } else {
                        mp.pause()
                    }
                }

                MediaPlayer {
                    id: mp
                    source: capa.esPip && capa.modelData.ruta
                        ? "file://" + capa.modelData.ruta : ""
                    videoOutput: salidaPip
                    //  Sin sonido: el audio de un pip no entra en el render —eso
                    //  lo hace una capa de audio— así que oírlo aquí engañaría.
                    audioOutput: AudioOutput { muted: true }
                }

                VideoOutput {
                    id: salidaPip
                    anchors.fill: parent
                    fillMode: VideoOutput.Stretch
                }
            }

            Image {
                id: imagen
                anchors.fill: parent
                visible: !capa.esTexto && !capa.esPip
                source: !capa.esTexto && !capa.esPip && capa.modelData.ruta
                    ? "file://" + capa.modelData.ruta : ""
                fillMode: Image.Stretch
                // El PNG llega a menudo mucho más grande que el hueco; sin esto
                // se guarda en memoria a tamaño completo por cada capa.
                sourceSize.width: Math.max(64, width)
                smooth: true
                asynchronous: true
            }

            // ── el rótulo ─────────────────────────────────────────
            Rectangle {
                anchors.fill: parent
                visible: capa.esTexto && capa.modelData.fondo > 0.001
                color: capa.modelData.colorFondo || "#000000"
                opacity: capa.modelData.fondo !== undefined
                    ? capa.modelData.fondo : 0.5
            }

            Text {
                id: rotulo
                visible: capa.esTexto
                x: capa.relleno
                y: capa.relleno
                text: capa.modelData.texto || ""
                color: capa.modelData.color || "#ffffff"
                //  La misma tipografía que le pasa el grafo a ffmpeg, cargada del
                //  mismo fichero. Sin esto el ancho del rótulo en la previa no
                //  tendría por qué parecerse al del render.
                font.family: fuenteRotulos.name
                font.pixelSize: Math.max(6, capa.tamTexto)
                renderType: Text.NativeRendering
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

                //  Una imagen se escala por el ancho y un rótulo por el cuerpo de
                //  letra. Es el mismo gesto, pero lo que cambia no es lo mismo:
                //  `escala` va en fracción del ANCHO del fotograma y `tam` en
                //  fracción del ALTO, porque así lo trata cada filtro.
                readonly property real actual: capa.esTexto
                    ? capa.modelData.tam : capa.modelData.escala
                readonly property real referencia: capa.esTexto
                    ? lienzo.height : lienzo.width

                onPressed: function (ev) {
                    xIni = enLienzo(ev)
                    capa.vEscala = actual
                    capa.escalando = true
                }

                onPositionChanged: function (ev) {
                    if (!pressed)
                        return
                    //  Se escala desde el centro, que es donde está anclada la
                    //  capa: por eso el doble. Arrastrar la esquina un píxel
                    //  aleja el borde un píxel, y el de enfrente otro.
                    const d = (enLienzo(ev) - xIni) * 2
                    capa.vEscala = Math.max(0.01, Math.min(2,
                        actual + d / Math.max(1, referencia)))
                }

                onReleased: {
                    Editor.fijarCapa(capa.modelData.id, capa.esTexto
                        ? { tam: capa.vEscala } : { escala: capa.vEscala })
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
