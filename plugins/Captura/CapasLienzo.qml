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
import QtQuick.Effects
import QtMultimedia
import "../../core"
import "../../services"

Item {
    id: lienzo

    // El instante de la línea, para saber qué capas tocan ahora.
    property real segundos: 0
    // Si la reproducción va en marcha, para que los vídeos de dentro la sigan.
    property bool sonando: false

    //  De dónde sacar la imagen para desenfocarla o pixelarla.
    //
    //  Es `lente`, o sea el vídeo YA con el zoom aplicado, que es exactamente
    //  lo que le llega a la zona en el grafo: las zonas van después del
    //  `zoompan`, igual que las demás capas. Sin esto habría que desenfocar el
    //  vídeo sin zoom y la previa enseñaría otra cosa.
    property Item fuenteVideo: null

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

    //  Los destellos de los clics.
    //
    //  Van los PRIMEROS, o sea debajo de las capas, igual que en el grafo: si
    //  tapas una zona con un desenfoque, lo que pasara ahí debajo no tiene que
    //  asomar por encima ni siquiera un destello.
    //
    //  La lista la calcula python —hay que leer el rastro y pasarlo por el mapa
    //  de clips—, así que aquí solo se pintan. Las coordenadas vienen en píxeles
    //  del vídeo de salida: la regla de tres con el marco es la de siempre.
    Repeater {
        model: Editor.clicsActivos ? Editor.clics : []

        delegate: Item {
            id: destello
            required property var modelData

            readonly property real t: modelData[0]
            readonly property real px: modelData[1]
            readonly property real py: modelData[2]
            //  El mismo 0,35 s que `CLIC_DUR` en tools/editar.py, y el mismo
            //  0,055 del ancho que `CLIC_DIAMETRO`.
            readonly property real lado: lienzo.width * 0.055
            readonly property real factor: lienzo.width
                / Math.max(1, Editor.anchoVideo)

            visible: lienzo.segundos >= t && lienzo.segundos < t + 0.35
            width: lado
            height: lado
            x: px * factor - lado / 2
            y: py * factor - lado / 2

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: Math.max(2, Math.round(parent.lado / 12))
                border.color: Editor.colorClics
            }

            //  0,42 es el RADIO del círculo de dentro en `dibujar_anillo`, así
            //  que aquí el diámetro es 0,42 del lado y no 0,84.
            Rectangle {
                anchors.centerIn: parent
                width: parent.lado * 0.42
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1, Math.round(parent.lado / 24))
                border.color: Editor.colorClics
            }
        }
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
            visible: Editor.capaVisible(modelData)
                && visual && (dentro || moviendo || escalando)

            // ── el gesto en curso, en local ───────────────────────
            property bool moviendo: false
            property bool escalando: false
            property real vX: 0
            property real vY: 0
            property real vEscala: 0
            // Una zona se estira por los dos lados, así que lleva su propio alto.
            property real vAl: 0

            function animado(campo, defecto) {
                const ks = modelData.keyframes || []
                if (ks.length === 0 || modelData.tipo === "zona")
                    return modelData[campo] !== undefined
                        ? Number(modelData[campo]) : defecto
                if (lienzo.segundos <= Number(ks[0].t))
                    return ks[0][campo] !== undefined ? Number(ks[0][campo]) : defecto
                for (let i = 1; i < ks.length; ++i) {
                    if (lienzo.segundos <= Number(ks[i].t)) {
                        const a = ks[i - 1], b = ks[i]
                        const u = (lienzo.segundos - a.t) / Math.max(0.001, b.t - a.t)
                        const av = a[campo] !== undefined ? Number(a[campo]) : defecto
                        const bv = b[campo] !== undefined ? Number(b[campo]) : av
                        return av + (bv - av) * u
                    }
                }
                const ultimo = ks[ks.length - 1]
                return ultimo[campo] !== undefined ? Number(ultimo[campo]) : defecto
            }

            readonly property real ex: moviendo ? vX : animado("x", 0.5)
            readonly property real ey: moviendo ? vY : animado("y", 0.5)
            readonly property real eEscala: escalando ? vEscala
                : animado("escala", 0.3)

            readonly property bool esTexto: modelData.tipo === "texto"
            readonly property bool esPip: modelData.tipo === "video"
            readonly property bool esZona: modelData.tipo === "zona"
            readonly property string modoZona: modelData.modo || "desenfoque"
            readonly property var recorteFuente: modelData.recorteFuente
                && modelData.recorteFuente.length === 4
                ? modelData.recorteFuente : [0, 0, 1, 1]
            readonly property bool recortando: elegida && Editor.recortandoCapa
                && esPip
            //  El audio no se pinta: no tiene sitio en el fotograma. Su bloque
            //  vive en la línea de tiempo y su volumen en la ficha.
            readonly property bool visual: modelData.tipo === "texto"
                                        || modelData.tipo === "imagen"
                                        || modelData.tipo === "video"
                                        || modelData.tipo === "zona"

            //  La proporción de la imagen la trae la propia imagen. ffmpeg
            //  escala con `-1` de alto, o sea conservándola, así que aquí hay
            //  que hacer lo mismo o la previa mentiría.
            //  Un pip trae su tamaño en el plan, medido al añadirlo: `scale=…:-1`
            //  conserva la proporción al renderizar, y si la previa la inventara
            //  enseñaría un recuadro que no es el que va a salir.
            readonly property real relacion: esPip
                ? (modelData.w > 0
                   ? modelData.h * recorteFuente[3]
                     / Math.max(1, modelData.w * recorteFuente[2])
                   : 0.5625)
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
            //  Una zona lleva ancho y alto por separado, y no `escala` con la
            //  proporción de la imagen: tapar una barra de direcciones pide un
            //  rectángulo ancho y bajo, y con un solo número no se dice eso.
            readonly property real vAn: escalando ? vEscala : (modelData.an || 0.3)
            readonly property real eAl: escalando ? vAl : (modelData.al || 0.25)

            width: esTexto ? rotulo.implicitWidth + relleno * 2
                 : esZona  ? Math.max(8, lienzo.width * vAn)
                           : Math.max(8, lienzo.width * eEscala)
            height: esTexto ? rotulo.implicitHeight + relleno * 2
                  : esZona  ? Math.max(8, lienzo.height * eAl)
                            : width * relacion
            x: ex * lienzo.width - width / 2
            y: ey * lienzo.height - height / 2

            // El mismo `boxborderw` que le pasa el grafo a ffmpeg.
            readonly property real tamTexto: lienzo.height
                * animado("tam", 0.06)
            readonly property real relleno: esTexto && modelData.fondo > 0.001
                ? Math.max(2, Math.round(tamTexto * 0.28)) : 0

            opacity: animado("opacidad", 1)
            rotation: animado("rotacion", 0)

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

                // VideoOutput no permite asignar sourceRect. Se recorta con
                // un contenedor y se escala dentro para que la previsualización
                // use exactamente las mismas fracciones que el render.
                Item {
                    id: marcoPip
                    anchors.fill: parent
                    clip: true

                    Item {
                        x: -capa.recorteFuente[0] / capa.recorteFuente[2]
                           * marcoPip.width
                        y: -capa.recorteFuente[1] / capa.recorteFuente[3]
                           * marcoPip.height
                        width: marcoPip.width / capa.recorteFuente[2]
                        height: marcoPip.height / capa.recorteFuente[3]

                        VideoOutput {
                            id: salidaPip
                            anchors.fill: parent
                            fillMode: VideoOutput.Stretch
                        }
                    }
                }
            }

            // ── la zona ───────────────────────────────────────────
            //
            //  Se saca el trozo del vídeo que hay debajo y se vuelve a pintar
            //  aquí estropeado. Es una aproximación: el desenfoque de Qt no es
            //  el `gblur` de ffmpeg ni el pixelado es su `pixelize`, así que el
            //  fichero manda y para eso está «previa exacta». Lo que sí es
            //  exacto —y es lo que importa al colocarla— son el sitio, el
            //  tamaño y la ventana de tiempo.
            //
            //  `sourceRect` va en coordenadas de `lente`, que lleva el zoom
            //  encima; `mapFromItem` se encarga de esa vuelta.
            ShaderEffectSource {
                id: trozoVideo
                //  Con tamaño, aunque no se dibuje: sin ancho y alto la textura
                //  sale de 0×0 y la zona no se ve. Quien la pinta es el
                //  MultiEffect de debajo, así que esto va invisible.
                width: Math.max(1, capa.width)
                height: Math.max(1, capa.height)
                visible: false
                sourceItem: capa.esZona && capa.modoZona !== "foco"
                    ? lienzo.fuenteVideo : null
                live: true
                hideSource: false

                readonly property real escalaLente: lienzo.fuenteVideo
                    ? Math.max(0.001, lienzo.fuenteVideo.scale) : 1
                readonly property point esquina: lienzo.fuenteVideo
                    ? lienzo.fuenteVideo.mapFromItem(lienzo, capa.x, capa.y)
                    : Qt.point(0, 0)

                sourceRect: Qt.rect(esquina.x, esquina.y,
                                    capa.width / escalaLente,
                                    capa.height / escalaLente)

                //  El pixelado se hace aquí y no con un filtro: se pide la
                //  textura pequeña y se deja que la amplíe sin suavizar, que es
                //  literalmente lo que hace `pixelize`. La fuerza del plan es
                //  0-1 y se traduce igual que en python: bloques de 4 a 64 px.
                readonly property int bloque: Math.max(
                    4, Math.round(4 + (capa.modelData.fuerza !== undefined
                                       ? capa.modelData.fuerza : 0.5) * 60))
                textureSize: capa.modoZona === "pixelado"
                    ? Qt.size(Math.max(1, Math.round(capa.width / bloque)),
                              Math.max(1, Math.round(capa.height / bloque)))
                    : Qt.size(0, 0)
                smooth: capa.modoZona !== "pixelado"
            }

            MultiEffect {
                anchors.fill: parent
                visible: capa.esZona && capa.modoZona !== "foco"
                source: trozoVideo

                //  La fuerza del plan va tal cual, y `blurMax` lo más alto que
                //  todavía sirve de algo.
                //
                //  El desenfoque de Qt NO se puede casar con la sigma de
                //  `gblur`: aquí el mando es un 0-1 sobre `blurMax`, no un radio
                //  en píxeles. Intenté traducirlo por la sigma y salió peor.
                //  Medido contra el render sobre las barras SMPTE —comparando la
                //  caja de píxeles que cambian— ffmpeg empieza a cambiar en
                //  x=84; la previa a tope llega a x=120 con blurMax 64 y a x=106
                //  con 128, y con 256 deja de hacer efecto.
                //
                //  O sea: **la previa difumina menos que el render**, y desde
                //  aquí no hay forma de arreglarlo. Lo que sí es exacto es el
                //  dónde y el cuándo, que es lo que se ajusta a ojo; para la
                //  intensidad está «previa exacta».
                blurEnabled: capa.modoZona === "desenfoque"
                blur: capa.modelData.fuerza !== undefined
                    ? capa.modelData.fuerza : 0.5
                blurMax: 128
                autoPaddingEnabled: false
            }

            //  El foco es al revés: lo que se estropea es TODO menos la zona.
            //  Cuatro rectángulos alrededor, que es más barato y más exacto que
            //  una máscara, y da el mismo resultado con un rectángulo.
            //  `parent: lienzo` porque tienen que salirse de la capa: la capa ES
            //  la zona nítida, y esto es lo de fuera. Y `z: -1` para quedar por
            //  debajo del marco de selección y de las asas.
            Repeater {
                model: capa.esZona && capa.modoZona === "foco"
                    ? [ { i: 0 }, { i: 1 }, { i: 2 }, { i: 3 } ] : []

                delegate: Rectangle {
                    id: sombra
                    required property var modelData
                    readonly property int lado: modelData.i   // 0 izq 1 der 2 arr 3 abj

                    parent: lienzo
                    z: -1
                    visible: capa.visible
                    color: "#000000"
                    opacity: 0.15 + (capa.modelData.fuerza !== undefined
                                     ? capa.modelData.fuerza : 0.5) * 0.65

                    x: lado === 0 ? 0
                     : lado === 1 ? capa.x + capa.width
                                  : capa.x
                    y: lado <= 1 ? 0
                     : lado === 2 ? 0
                                  : capa.y + capa.height
                    width: lado === 0 ? Math.max(0, capa.x)
                         : lado === 1 ? Math.max(0, lienzo.width - capa.x - capa.width)
                                      : capa.width
                    height: lado <= 1 ? lienzo.height
                          : lado === 2 ? Math.max(0, capa.y)
                                       : Math.max(0, lienzo.height - capa.y - capa.height)
                }
            }

            Image {
                id: imagen
                anchors.fill: parent
                visible: !capa.esTexto && !capa.esPip && !capa.esZona
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

            // ── recorte espacial de un vídeo superpuesto ─────────
            property real recorteX0: 0
            property real recorteY0: 0
            property real recorteX1: 0
            property real recorteY1: 0

            onRecortandoChanged: if (recortando) {
                recorteX0 = 0
                recorteY0 = 0
                recorteX1 = width
                recorteY1 = height
            }

            Rectangle {
                z: 30
                visible: capa.recortando && Math.abs(capa.recorteX1
                                                       - capa.recorteX0) > 2
                    && Math.abs(capa.recorteY1 - capa.recorteY0) > 2
                x: Math.min(capa.recorteX0, capa.recorteX1)
                y: Math.min(capa.recorteY0, capa.recorteY1)
                width: Math.abs(capa.recorteX1 - capa.recorteX0)
                height: Math.abs(capa.recorteY1 - capa.recorteY0)
                color: Qt.rgba(0.2, 0.8, 0.4, 0.16)
                border.width: 2
                border.color: Theme.green
            }

            MouseArea {
                z: 31
                anchors.fill: parent
                visible: capa.recortando && !Editor.capaBloqueada(capa.modelData)
                preventStealing: true
                enabled: !Editor.capaBloqueada(capa.modelData)
                cursorShape: Qt.CrossCursor

                onPressed: function (ev) {
                    capa.recorteX0 = Math.max(0, Math.min(capa.width, ev.x))
                    capa.recorteY0 = Math.max(0, Math.min(capa.height, ev.y))
                    capa.recorteX1 = capa.recorteX0
                    capa.recorteY1 = capa.recorteY0
                }

                onPositionChanged: function (ev) {
                    if (!pressed)
                        return
                    capa.recorteX1 = Math.max(0, Math.min(capa.width, ev.x))
                    capa.recorteY1 = Math.max(0, Math.min(capa.height, ev.y))
                }

                onReleased: {
                    const x = Math.min(capa.recorteX0, capa.recorteX1)
                    const y = Math.min(capa.recorteY0, capa.recorteY1)
                    const w = Math.abs(capa.recorteX1 - capa.recorteX0)
                    const h = Math.abs(capa.recorteY1 - capa.recorteY0)
                    if (w > 4 && h > 4)
                        Editor.fijarRecorteFuente(capa.modelData.id,
                            [x / Math.max(1, capa.width),
                             y / Math.max(1, capa.height),
                             w / Math.max(1, capa.width),
                             h / Math.max(1, capa.height)])
                    Editor.recortandoCapa = false
                }
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
                    let nx = Math.max(0, Math.min(1, capa.modelData.x
                        + (p.x - xIni) / Math.max(1, lienzo.width)))
                    let ny = Math.max(0, Math.min(1, capa.modelData.y
                        + (p.y - yIni) / Math.max(1, lienzo.height)))
                    // Ajuste magnético al centro y a los bordes del lienzo.
                    const puntosX = [0.05, 0.5, 0.95]
                    const puntosY = [0.05, 0.5, 0.95]
                    for (let k = 0; k < puntosX.length; ++k)
                        if (Math.abs(nx - puntosX[k]) < 0.018) nx = puntosX[k]
                    for (let k = 0; k < puntosY.length; ++k)
                        if (Math.abs(ny - puntosY[k]) < 0.018) ny = puntosY[k]
                    capa.vX = nx
                    capa.vY = ny
                }

                onReleased: {
                    Editor.ponerTransformacion(capa.modelData.id,
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
                    && !Editor.capaBloqueada(capa.modelData)
                preventStealing: true
                cursorShape: Qt.SizeFDiagCursor

                property real xIni: 0
                property real yIni: 0

                function enLienzo(ev) { return mapToItem(lienzo, ev.x, ev.y) }

                //  Una imagen se escala por el ancho y un rótulo por el cuerpo de
                //  letra. Es el mismo gesto, pero lo que cambia no es lo mismo:
                //  `escala` va en fracción del ANCHO del fotograma y `tam` en
                //  fracción del ALTO, porque así lo trata cada filtro. Y una zona
                //  se estira por los dos lados a la vez, que para eso lleva ancho
                //  y alto por separado.
                readonly property real actual: capa.esTexto ? capa.modelData.tam
                    : capa.esZona ? (capa.modelData.an || 0.3)
                                  : capa.modelData.escala
                readonly property real actualAl: capa.modelData.al || 0.25
                readonly property real referencia: capa.esTexto
                    ? lienzo.height : lienzo.width

                onPressed: function (ev) {
                    const p = enLienzo(ev)
                    xIni = p.x
                    yIni = p.y
                    capa.vEscala = actual
                    capa.vAl = actualAl
                    capa.escalando = true
                }

                onPositionChanged: function (ev) {
                    if (!pressed)
                        return
                    //  Se escala desde el centro, que es donde está anclada la
                    //  capa: por eso el doble. Arrastrar la esquina un píxel
                    //  aleja el borde un píxel, y el de enfrente otro.
                    const p = enLienzo(ev)
                    const d = (p.x - xIni) * 2
                    capa.vEscala = Math.max(0.01, Math.min(2,
                        actual + d / Math.max(1, referencia)))
                    if (capa.esZona)
                        capa.vAl = Math.max(0.01, Math.min(1, actualAl
                            + (p.y - yIni) * 2 / Math.max(1, lienzo.height)))
                }

                onReleased: {
                    Editor.fijarCapa(capa.modelData.id,
                        capa.esTexto ? { tam: capa.vEscala }
                      : capa.esZona  ? { an: Math.min(1, capa.vEscala),
                                         al: capa.vAl }
                                     : { escala: capa.vEscala })
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
