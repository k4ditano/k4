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
                        let u = (lienzo.segundos - a.t) / Math.max(0.001, b.t - a.t)
                        //  La misma smoothstep que mete python en el grafo:
                        //  u²(3−2u), por capa y no por clave.
                        if (modelData.suave)
                            u = u * u * (3 - 2 * u)
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

            //  Los efectos de entrada y salida, con la MISMA cuenta que hace
            //  python al renderizar: rampa lineal pegada a t0 o a t1, acotada
            //  a media ventana. Los dos tipos funden; «deslizar» además
            //  empuja desde abajo lo que le queda de rampa.
            function rampaEfecto(e, esEntrada) {
                if (!e || !e.tipo)
                    return 1
                const ventana = Math.max(0.1, modelData.t1 - modelData.t0)
                const d = Math.max(0.05, Math.min(ventana / 2,
                    Number(e.dur) > 0 ? Number(e.dur) : 0.4))
                const r = esEntrada
                    ? (lienzo.segundos - modelData.t0) / d
                    : (modelData.t1 - lienzo.segundos) / d
                const u = Math.max(0, Math.min(1, r))
                //  La curva, la misma que `curvar()` en python: la duración
                //  dice cuánto tarda y esto cómo reparte ese tiempo.
                if (e.curva === "suave")
                    return u * u * (3 - 2 * u)
                if (e.curva === "golpe")
                    return 1 - (1 - u) * (1 - u) * (1 - u)
                return u
            }

            //  Solo funden los que funden: «crecer» y «girar» llegan a tamaño
            //  y ángulo completos y ya se ven, igual que en el render.
            function rampaAlfa(e, esEntrada) {
                if (!e || !e.tipo || e.tipo === "crecer" || e.tipo === "girar")
                    return 1
                return rampaEfecto(e, esEntrada)
            }

            readonly property real alfaEfecto:
                rampaAlfa(modelData.entrada, true)
                * rampaAlfa(modelData.salida, false)

            //  Crecer y girar, con la misma cuenta que el render: de media
            //  medida a entera, y de veinte grados a ninguno.
            function porEfecto(tipo, valor) {
                let v = 1
                if (modelData.entrada && modelData.entrada.tipo === tipo)
                    v = Math.min(v, rampaEfecto(modelData.entrada, true))
                if (modelData.salida && modelData.salida.tipo === tipo)
                    v = Math.min(v, rampaEfecto(modelData.salida, false))
                return v
            }

            readonly property real escalaEfecto: 0.5 + 0.5 * porEfecto("crecer")
            readonly property real giroEfecto: 20 * (1 - porEfecto("girar"))

            readonly property real empujeEfecto:
                (modelData.entrada && modelData.entrada.tipo === "deslizar"
                    ? 0.08 * (1 - rampaEfecto(modelData.entrada, true)) : 0)
                + (modelData.salida && modelData.salida.tipo === "deslizar"
                    ? 0.08 * (1 - rampaEfecto(modelData.salida, false)) : 0)

            //  El Ken Burns de la previa: el mismo zoom por dentro que hace
            //  zoompan en el render, con su recorte centrado y su misma
            //  rampa. La capa no cambia de tamaño; respira su contenido.
            readonly property real zoomKenburns: {
                const kb = modelData.kenburns
                if (!kb)
                    return 1
                const z0 = Math.max(1, Math.min(3, Number(kb.desde) || 1))
                const z1 = Math.max(1, Math.min(3, Number(kb.hasta) || 1))
                let u = (lienzo.segundos - modelData.t0)
                    / Math.max(0.05, modelData.t1 - modelData.t0)
                u = Math.max(0, Math.min(1, u))
                if (modelData.suave)
                    u = u * u * (3 - 2 * u)
                return z0 + (z1 - z0) * u
            }

            //  ── el aspecto ────────────────────────────────────────
            //
            //  Filtro de color, forma y marco, con la misma cuenta que hace
            //  python: la máscara redondea sobre el cuadrado del centro —que es
            //  lo que hace `crop=min(iw,ih)` antes del `geq`— y el grosor del
            //  marco es una fracción del ancho de la capa.
            //
            //  Los colores son una aproximación y no la matriz exacta del
            //  render: `MultiEffect` tiñe, no multiplica matrices. Lo que sí es
            //  exacto —y es lo que se mira al colocar— son la forma, el marco y
            //  el encuadre.
            readonly property string filtro: String(modelData.filtro || "")
            readonly property string mascara: String(modelData.mascara || "")
            readonly property real marco: Number(modelData.marco || 0)
            readonly property real sombra: Number(modelData.sombra || 0)
            readonly property bool conAspecto: filtro.length > 0
                                            || mascara.length > 0
                                            || sombra > 0.001
            readonly property real ladoMenor: Math.min(width, height)
            readonly property real radioMascara: mascara === "circulo"
                ? ladoMenor / 2 : mascara === "redonda" ? ladoMenor * 0.12 : 0

            //  Lo que ocupa la capa una vez pintada: el círculo se queda con el
            //  cuadrado del centro y el marco añade su grosor por cada lado.
            //  Lo usan el recuadro de selección y sus tiradores, para que lo que
            //  se agarra sea lo que se ve.
            readonly property int grosorMarco: marco > 0.001
                ? Math.max(1, Math.round(width * marco)) : 0
            readonly property real anchoPintado:
                (mascara === "circulo" ? ladoMenor : width) + 2 * grosorMarco
            readonly property real altoPintado:
                (mascara === "circulo" ? ladoMenor : height) + 2 * grosorMarco

            readonly property bool esTexto: modelData.tipo === "texto"
            readonly property bool esPip: modelData.tipo === "video"
            readonly property bool esZona: modelData.tipo === "zona"
            readonly property bool esForma: modelData.tipo === "forma"
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
                                        || modelData.tipo === "forma"

            //  La proporción de la imagen la trae la propia imagen. ffmpeg
            //  escala con `-1` de alto, o sea conservándola, así que aquí hay
            //  que hacer lo mismo o la previa mentiría.
            //  Un pip trae su tamaño en el plan, medido al añadirlo: `scale=…:-1`
            //  conserva la proporción al renderizar, y si la previa la inventara
            //  enseñaría un recuadro que no es el que va a salir.
            //  Una forma es cuadrada por construcción: su PNG se dibuja en
            //  un lienzo de lado fijo.
            readonly property real relacion: esForma ? 1.0
                : esPip
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

            width: esTexto ? rotuloMedida.implicitWidth + relleno * 2
                 : esZona  ? Math.max(8, lienzo.width * vAn)
                           : Math.max(8, lienzo.width * eEscala)
            height: esTexto ? rotuloMedida.implicitHeight + relleno * 2
                  : esZona  ? Math.max(8, lienzo.height * eAl)
                            : width * relacion
            x: ex * lienzo.width - width / 2
            y: (ey + empujeEfecto) * lienzo.height - height / 2

            // El mismo `boxborderw` que le pasa el grafo a ffmpeg.
            readonly property real tamTexto: lienzo.height
                * animado("tam", 0.06)
            readonly property real relleno: esTexto && modelData.fondo > 0.001
                ? Math.max(2, Math.round(tamTexto * 0.28)) : 0

            opacity: animado("opacidad", 1) * alfaEfecto
            rotation: animado("rotacion", 0) + giroEfecto
            //  El «crecer» se hace aquí, sobre la capa entera y desde el
            //  centro: en el render es un zoompan sobre lienzo acolchado y el
            //  resultado es el mismo —la huella no cambia, el contenido sí—.
            scale: escalaEfecto
            transformOrigin: Item.Center

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
                    //  Con sonido si la capa lo trae, y callado si no: desde que
                    //  un vídeo incrustado puede sonar en el render, silenciarlo
                    //  aquí sería esconder la mitad de lo que va a salir.
                    audioOutput: AudioOutput {
                        muted: !capa.modelData.sonido
                        //  Qt no pasa de 1; el plan sí llega más arriba y ese
                        //  trozo solo lo puede dar el render.
                        volume: Math.min(1, capa.modelData.volumen !== undefined
                                            ? capa.modelData.volumen : 1)
                    }
                }

                // VideoOutput no permite asignar sourceRect. Se recorta con
                // un contenedor y se escala dentro para que la previsualización
                // use exactamente las mismas fracciones que el render.
                Item {
                    id: marcoPip
                    anchors.fill: parent
                    clip: true

                    transform: Scale {
                        origin.x: marcoPip.width / 2
                        xScale: capa.modelData.espejo ? -1 : 1
                    }

                    layer.enabled: capa.conAspecto
                    layer.effect: AspectoCapa {
                        capaDe: capa
                        molde: mascaraFuente
                    }

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

            //  Con marco recortado: el zoom del Ken Burns agranda la imagen
            //  por dentro y lo que se sale por los bordes no se ve, igual
            //  que hace zoompan con su ventana.
            //  La forma, con el mismo trazo que le pinta magick al render:
            //  el grosor es 1/13 del lado, la flecha apunta a la derecha.
            Canvas {
                id: forma
                anchors.fill: parent
                visible: capa.esForma

                readonly property string tono: capa.modelData.color || "#ff453a"
                readonly property string modo: capa.modelData.modo || "flecha"
                onTonoChanged: requestPaint()
                onModoChanged: requestPaint()
                onWidthChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    const g = Math.max(2, width / 13)
                    ctx.strokeStyle = tono
                    ctx.fillStyle = tono
                    ctx.lineWidth = g
                    if (modo === "circulo") {
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, width / 2 - g, 0,
                                2 * Math.PI)
                        ctx.stroke()
                    } else if (modo === "marco") {
                        ctx.strokeRect(g, g, width - 2 * g, height - 2 * g)
                    } else {
                        const y = height / 2
                        ctx.lineWidth = g * 1.2
                        ctx.beginPath()
                        ctx.moveTo(width / 16, y)
                        ctx.lineTo(width - width / 3, y)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(width - width / 16, y)
                        ctx.lineTo(width - width / 3 - 8 * width / 512,
                                   y - height / 5)
                        ctx.lineTo(width - width / 3 - 8 * width / 512,
                                   y + height / 5)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
            }

            //  El molde de la máscara y su textura. El molde no se dibuja
            //  —`hideSource` lo esconde— y solo existe para que el efecto
            //  tenga de dónde sacar la forma. Del tamaño de la capa entera,
            //  con el cuadrado dentro: si la textura fuera más pequeña, el
            //  efecto la estiraría y el círculo saldría ovalado.
            Item {
                id: molde
                anchors.fill: parent

                Rectangle {
                    anchors.centerIn: parent
                    width: capa.mascara === "circulo" ? capa.ladoMenor
                                                      : capa.width
                    height: capa.mascara === "circulo" ? capa.ladoMenor
                                                       : capa.height
                    radius: capa.radioMascara
                    color: "#ffffff"
                }
            }

            ShaderEffectSource {
                id: mascaraFuente
                anchors.fill: parent
                sourceItem: molde
                hideSource: true
                visible: false
                live: true
            }

            //  La sombra de una capa con máscara: la silueta ES el molde, así
            //  que se pinta el molde en negro, difuminado y caído. La de una
            //  capa sin máscara sale del alfa de su contenido y la hace el
            //  propio efecto, que ahí sí puede.
            Rectangle {
                z: -1
                visible: capa.sombra > 0.001 && capa.mascara.length > 0
                readonly property real sigma: Math.max(2, 0.045 * capa.width)

                anchors.centerIn: parent
                anchors.horizontalCenterOffset: sigma * (0.5 + capa.sombra)
                anchors.verticalCenterOffset: sigma * (0.5 + capa.sombra)
                width: capa.anchoPintado
                height: capa.altoPintado
                radius: capa.mascara === "circulo" ? width / 2
                                                   : capa.radioMascara
                color: Qt.rgba(0, 0, 0, 0.7 * capa.sombra)

                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: Math.min(1, 0.045 * capa.width / 32)
                    blurMax: 32
                }
            }

            //  El marco, por encima de todo lo que pinte la capa. Va POR FUERA
            //  —igual que el `pad` del render— y sigue la forma que tenga
            //  puesta: pintado hacia dentro se comía el borde de la imagen.
            //
            //  Con `z`, y no confiando en el orden de los hermanos: escrito
            //  aquí arriba lo tapaba la propia imagen y no se veía nada. Los
            //  tiradores de la selección van por 30 y 31, así que 20 lo deja
            //  encima de la capa y debajo de lo que se agarra con el ratón.
            Rectangle {
                z: 20
                visible: capa.marco > 0.001
                         && (capa.esPip || (!capa.esTexto && !capa.esZona
                                            && !capa.esForma))
                //  Por fuera de la capa, no por dentro: el borde de QML se pinta
                //  hacia adentro, así que el recuadro se hace más grande que la
                //  capa justo el grosor y el trazo cae en ese hueco. Es lo mismo
                //  que hace el `pad` del render.
                anchors.centerIn: parent
                width: capa.anchoPintado
                height: capa.altoPintado
                radius: capa.mascara === "circulo" ? width / 2
                      : capa.mascara === "redonda"
                        ? capa.radioMascara + capa.grosorMarco : 0
                color: "transparent"
                border.width: capa.grosorMarco
                border.color: capa.modelData.colorMarco || "#ffffff"
            }

            Item {
                anchors.fill: parent
                clip: true
                visible: !capa.esTexto && !capa.esPip && !capa.esZona
                    && !capa.esForma

                transform: Scale {
                    origin.x: capa.width / 2
                    xScale: capa.modelData.espejo ? -1 : 1
                }

                layer.enabled: capa.conAspecto
                layer.effect: AspectoCapa { capaDe: capa; molde: mascaraFuente }

                Image {
                    id: imagen
                    anchors.fill: parent
                    scale: capa.zoomKenburns
                    source: !capa.esTexto && !capa.esPip && !capa.esForma
                        && capa.modelData.ruta
                        ? "file://" + capa.modelData.ruta : ""
                    fillMode: Image.Stretch
                    // El PNG llega a menudo mucho más grande que el hueco; sin esto
                    // se guarda en memoria a tamaño completo por cada capa.
                    sourceSize.width: Math.max(64, width)
                    smooth: true
                    asynchronous: true
                }
            }

            // ── el rótulo ─────────────────────────────────────────
            //
            //  El estilo, con el mismo criterio que `estilo_texto()` en
            //  python: los planes de antes no llevan `estilo`, y si tenían
            //  caja se quedan con su caja. `colorFondo` es el color
            //  secundario del estilo, sea cual sea.
            readonly property string estiloTexto: {
                const e = modelData.estilo || ""
                if (e === "caja" || e === "contorno" || e === "sombra"
                    || e === "limpio")
                    return e
                return (modelData.fondo || 0) > 0.001 ? "caja" : "limpio"
            }
            //  Si el texto se está escribiendo AQUÍ, sobre el vídeo.
            property bool editandoTexto: false

            Rectangle {
                anchors.fill: parent
                visible: capa.esTexto && capa.estiloTexto === "caja"
                color: capa.modelData.colorFondo || "#000000"
                opacity: capa.modelData.fondo !== undefined
                    ? capa.modelData.fondo : 0.5
            }

            //  El rótulo entero, invisible: es quien MIDE. Con la máquina de
            //  escribir el visible enseña un prefijo, pero la capa tiene que
            //  medir lo que medirá al final o la caja bailaría.
            Text {
                id: rotuloMedida
                visible: false
                //  Mide lo mismo que se pinta, así que el formato también.
                textFormat: Text.PlainText
                text: capa.modelData.texto || ""
                font.family: fuenteRotulos.name
                font.pixelSize: Math.max(6, capa.tamTexto)
                renderType: Text.NativeRendering
            }

            //  Cuántas letras se ven ya, con la misma rampa del render.
            readonly property int letrasVisibles: {
                const e = modelData.entrada
                const texto = modelData.texto || ""
                if (!capa.esTexto || !e || e.tipo !== "maquina")
                    return texto.length
                const d = Math.max(0.05, Math.min(
                    Math.max(0.1, modelData.t1 - modelData.t0) / 2,
                    Number(e.dur) > 0 ? Number(e.dur) : 0.4))
                const u = Math.max(0, Math.min(1,
                    (lienzo.segundos - modelData.t0) / d))
                return Math.min(texto.length, Math.floor(texto.length * u) + 1)
            }

            Text {
                id: rotulo
                visible: capa.esTexto && !capa.editandoTexto
                //  El rótulo del usuario. El render lo quema con `drawtext`,
                //  que es literal: interpretarlo aquí enseñaría una cosa y
                //  produciría otra.
                textFormat: Text.PlainText
                x: capa.relleno
                y: capa.relleno
                text: (capa.modelData.texto || "")
                    .substring(0, capa.letrasVisibles)
                color: capa.modelData.color || "#ffffff"
                //  La misma tipografía que le pasa el grafo a ffmpeg, cargada del
                //  mismo fichero. Sin esto el ancho del rótulo en la previa no
                //  tendría por qué parecerse al del render.
                font.family: fuenteRotulos.name
                font.pixelSize: Math.max(6, capa.tamTexto)
                renderType: Text.NativeRendering
                //  Contorno y sombra, aproximados: el de Qt es de un píxel
                //  mientras el render escala con la letra. Sitio y color son
                //  exactos, que es lo que se ajusta a ojo; el resto lo dice
                //  la previa exacta.
                style: capa.estiloTexto === "contorno" ? Text.Outline
                     : capa.estiloTexto === "sombra" ? Text.Raised
                                                     : Text.Normal
                styleColor: capa.modelData.colorFondo || "#000000"
            }

            //  Escribir el rótulo AHÍ, sobre el vídeo, con doble clic. El
            //  mismo campo de la ficha sigue valiendo; este es el directo.
            //
            //  Se edita EN LOCAL y el plan se escribe al terminar, por lo
            //  mismo que los bloques de la línea de tiempo: escribir el
            //  modelo reasigna el array de capas, eso destruye y recrea los
            //  delegados, y el TextInput moría con la primera letra — el
            //  resto de la frase caía en los atajos del editor, que es de
            //  las peores cosas que pueden pasar tecleando.
            TextInput {
                id: rotuloVivo
                cursorDelegate: IslandCursor {}
                visible: capa.esTexto && capa.editandoTexto
                x: capa.relleno
                y: capa.relleno
                width: Math.max(40, implicitWidth + 20)
                color: capa.modelData.color || "#ffffff"
                font.family: fuenteRotulos.name
                font.pixelSize: Math.max(6, capa.tamTexto)
                selectByMouse: true
                selectionColor: Theme.blue

                function terminar(guardando) {
                    if (!capa.editandoTexto)
                        return
                    capa.editandoTexto = false
                    if (guardando)
                        Editor.fijarCapa(capa.modelData.id, { texto: text })
                }

                onEditingFinished: terminar(true)
                Keys.onEscapePressed: terminar(false)
                onVisibleChanged: if (visible) {
                    text = capa.modelData.texto || ""
                    forceActiveFocus()
                    selectAll()
                }
            }

            // ── el marco de selección ─────────────────────────────
            //
            //  Ciñe lo que de verdad se pinta, que no siempre es la caja de la
            //  capa: un círculo se queda con el cuadrado del centro y un marco
            //  la agranda su grosor por cada lado. Con la caja a secas, la
            //  bola pintada se salía del recuadro de selección.
            Rectangle {
                anchors.centerIn: parent
                width: capa.anchoPintado
                height: capa.altoPintado
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
                //  Mientras se escribe el rótulo ahí mismo, el área de mover
                //  se aparta: el clic es para colocar el cursor en el texto.
                enabled: !capa.editandoTexto
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                //  Doble clic en un rótulo: escribirlo ahí, sobre el vídeo.
                onDoubleClicked: {
                    if (capa.esTexto
                        && !Editor.capaBloqueada(capa.modelData)) {
                        capa.moviendo = false
                        capa.editandoTexto = true
                    }
                }

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
            //
            //  En la esquina de lo PINTADO, no en la de la caja: con un marco
            //  o una máscara las dos dejaron de ser la misma, y el tirador se
            //  quedaba metido para dentro, lejos de la esquina que se ve.
            MouseArea {
                width: 14
                height: 14
                x: (capa.width + capa.anchoPintado) / 2 - 12
                y: (capa.height + capa.altoPintado) / 2 - 12
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

    // ── el recorrido de la capa elegida ───────────────────────────
    //
    //  La polilínea de sus fotogramas clave, con un punto agarrable y
    //  numerado en cada uno. Vive fuera del modo de trazado a propósito: con
    //  la capa elegida, el recorrido se ve y se retoca siempre — arrastrar
    //  recoloca el punto y el clic derecho lo quita, igual que su rombo.
    Item {
        id: recorrido
        anchors.fill: parent
        visible: Editor.tipoSel === "capa" && Editor.capaSel !== null
            && ks.length > 0 && Editor.capaVisible(Editor.capaSel)

        readonly property var ks: Editor.tipoSel === "capa" && Editor.capaSel
            ? (Editor.capaSel.keyframes || []) : []

        onKsChanged: trazo.requestPaint()
        onWidthChanged: trazo.requestPaint()
        onHeightChanged: trazo.requestPaint()

        Canvas {
            id: trazo
            anchors.fill: parent
            opacity: 0.85
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const ks = recorrido.ks
                if (ks.length < 2)
                    return
                ctx.strokeStyle = String(Theme.blue)
                ctx.lineWidth = 1.5
                ctx.setLineDash([5, 4])
                ctx.beginPath()
                ctx.moveTo(Number(ks[0].x) * width, Number(ks[0].y) * height)
                for (let i = 1; i < ks.length; ++i)
                    ctx.lineTo(Number(ks[i].x) * width,
                               Number(ks[i].y) * height)
                ctx.stroke()
            }
        }

        Repeater {
            model: recorrido.ks

            delegate: Item {
                id: punto
                required property var modelData
                required property int index

                property bool moviendo: false
                property real vx: 0
                property real vy: 0

                readonly property real px: moviendo ? vx : Number(modelData.x)
                readonly property real py: moviendo ? vy : Number(modelData.y)

                width: 18
                height: 18
                x: px * recorrido.width - width / 2
                y: py * recorrido.height - height / 2

                Rectangle {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    radius: 5
                    color: puntoRaton.containsMouse || punto.moviendo
                        ? Theme.ink : Theme.blue
                    border.width: 1
                    border.color: "#ffffff"
                }

                //  El número dice el orden del recorrido, que la línea sola
                //  no cuenta cuando se cruza consigo misma.
                IslandLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    text: punto.index + 1
                    color: Theme.ink
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    style: Text.Outline
                    styleColor: "#000000"
                }

                MouseArea {
                    id: puntoRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.SizeAllCursor

                    function enLienzo(ev) { return mapToItem(lienzo, ev.x, ev.y) }

                    onPressed: function (ev) {
                        if (ev.button === Qt.RightButton) {
                            Editor.quitarKeyframe(Editor.idSel, punto.index)
                            return
                        }
                        punto.vx = punto.px
                        punto.vy = punto.py
                        punto.moviendo = true
                    }

                    onPositionChanged: function (ev) {
                        if (!pressed || !punto.moviendo)
                            return
                        const p = enLienzo(ev)
                        punto.vx = Math.max(0, Math.min(1,
                            p.x / Math.max(1, recorrido.width)))
                        punto.vy = Math.max(0, Math.min(1,
                            p.y / Math.max(1, recorrido.height)))
                    }

                    onReleased: {
                        if (!punto.moviendo)
                            return
                        punto.moviendo = false
                        Editor.moverPuntoRuta(Editor.idSel, punto.index,
                                              punto.vx, punto.vy)
                    }
                }
            }
        }
    }

    // ── trazar el movimiento pinchando ────────────────────────────
    //
    //  El modo que quita botones de en medio: activado desde la ficha, cada
    //  clic sobre el vídeo añade un punto del recorrido y la capa pasará por
    //  todos en orden. El tiempo se reparte solo —la velocidad la pone la
    //  distancia entre puntos— y el clic derecho termina. Declarado el
    //  último: mientras el modo está puesto, el lienzo es suyo.
    MouseArea {
        anchors.fill: parent
        visible: Editor.trazandoRuta && Editor.tipoSel === "capa"
        z: 50
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor

        onClicked: function (ev) {
            if (ev.button === Qt.RightButton) {
                Editor.trazandoRuta = false
                return
            }
            Editor.anadirPuntoRuta(Editor.idSel,
                                   ev.x / Math.max(1, width),
                                   ev.y / Math.max(1, height))
        }
    }
}
