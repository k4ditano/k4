//  La línea de tiempo: cabeceras a la izquierda y pistas a la derecha.
//
//  Todas las pistas comparten eje —el tiempo de LÍNEA— y por eso comparten
//  anchura, desplazamiento y cabezal. Lo que cambia es qué significa arrastrar
//  en cada una: en la de arriba, en qué orden van los trozos; en las de abajo,
//  dónde se ve cada cosa.
//
//  Y se puede recorrer. Antes toda la duración se aplastaba en el ancho visible
//  pasara lo que pasara, así que en un vídeo de diez minutos cada segundo eran
//  dos píxeles y no había forma de colocar nada. Ahora la rueda recorre y
//  ctrl+rueda acerca, como en cualquier editor.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

RowLayout {
    id: linea

    property real total: 1
    property real cabezal: 0

    signal saltar(real t)
    // Preparar una capa nueva en una banda encima de todo.
    signal nuevaCapa()

    //  Empezar y terminar de buscar un instante con el ratón. El reproductor se
    //  pausa mientras dura y se reanuda al soltar si estaba sonando.
    signal rascaInicio()
    signal rascaFin()

    spacing: 6

    // ── cuánto se ve ──────────────────────────────────────────────
    //
    //  1 = la línea entera cabe en el ancho; 4 = hace falta recorrer cuatro
    //  pantallas para verla. Se acerca desde ahí, nunca por debajo: alejar más
    //  allá de «todo cabe» no enseña nada.
    property real acercamiento: 1
    readonly property real acercamientoMax: 60

    //  El imán mide su radio en píxeles de pantalla, y cuántos segundos son eso
    //  depende de lo acercada que esté la línea. Solo se sabe aquí, así que se
    //  lo contamos.
    onAcercamientoChanged: Editor.acercamientoLinea = acercamiento
    Component.onCompleted: Editor.acercamientoLinea = acercamiento

    function acercar(factor, anclaX) {
        const antes = rodillo.contentWidth
        //  Lo que hay bajo el puntero se queda bajo el puntero. Sin esto,
        //  acercar te lleva siempre al principio y hay que volver a buscar
        //  dónde estabas.
        const bajoElPuntero = (rodillo.contentX + anclaX) / Math.max(1, antes)
        acercamiento = Math.max(1, Math.min(acercamientoMax,
                                            acercamiento * factor))
        rodillo.contentX = Math.max(0, Math.min(
            rodillo.contentWidth - rodillo.width,
            bajoElPuntero * rodillo.contentWidth - anclaX))
    }

    //  Que el cabezal no se pierda de vista mientras corre.
    //
    //  Solo cuando se sale, y colocándolo a un tercio: seguirlo en el centro
    //  todo el rato marea, y esperar a que toque el borde deja medio segundo
    //  sin contexto de lo que viene.
    function seguirCabezal() {
        if (acercamiento <= 1.001)
            return
        const x = rodillo.contentWidth * (cabezal / Math.max(0.001, total))
        if (x < rodillo.contentX + 20 || x > rodillo.contentX + rodillo.width - 20)
            rodillo.contentX = Math.max(0, Math.min(
                rodillo.contentWidth - rodillo.width, x - rodillo.width / 3))
    }

    onCabezalChanged: seguirCabezal()

    //  Las bandas, de arriba abajo tal como se ven encima del vídeo.
    //
    //  En el plan la banda 1 es la de abajo, porque es la primera que se apila.
    //  Aquí se dan la vuelta: en una lista, lo de arriba es lo que está delante,
    //  y nadie espera lo contrario. La vuelta se da SOLO aquí.
    readonly property var bandasVista: {
        const r = []
        for (let b = Editor.cuantasBandas; b >= 2; --b)
            r.push({ banda: b, capas: Editor.capasDeBanda(b), clips: false })
        //  Y abajo del todo, el vídeo: es la banda 1 y va en la misma lista que
        //  las demás. Antes tenía su propia fila fija, y el zoom otra, y eso
        //  eran cuatro filas para dos capas.
        r.push({ banda: 1, capas: [], clips: true })
        return r
    }

    //  La regla mide 20 y no los 13 que ocupan sus marcas: es la fila que en la
    //  columna de la izquierda lleva el botón de añadir capa, y las dos tienen
    //  que medir lo mismo o la columna se desalinea de las pistas fila a fila.
    readonly property int altoRegla: 20
    readonly property int altoClips: 34
    readonly property int altoPista: 26
    readonly property int hueco: 3

    // ── las cabeceras ─────────────────────────────────────────────
    ColumnLayout {
        Layout.preferredWidth: 92
        Layout.fillWidth: false
        Layout.alignment: Qt.AlignTop
        spacing: linea.hueco


        //  Añadir una capa: primero se elige su tipo en el panel «Añadir».
        //
        //  Va aquí arriba y no en el pie porque es donde se busca —la columna de
        //  capas— y porque «encima de todo» se entiende mirando dónde está el
        //  botón. El de abajo sigue existiendo y coloca donde haya hueco.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: linea.altoRegla
            radius: 6
            color: nuevaRaton.containsMouse ? Theme.surfaceHi : "transparent"
            border.width: 1
            border.color: nuevaRaton.containsMouse
                ? Qt.rgba(52 / 255, 199 / 255, 89 / 255, 0.5)
                : Qt.rgba(1, 1, 1, 0.08)

            Row {
                anchors.centerIn: parent
                spacing: 4

                IconGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0x000F0415)   // md-plus
                    color: Theme.green
                    font.pixelSize: 11
                }

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Idioma.t("Capa")
                    color: Theme.muted
                    font.pixelSize: 9
                }
            }

            MouseArea {
                id: nuevaRaton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: linea.nuevaCapa()
            }
        }

        Repeater {
            model: linea.bandasVista

            delegate: CabeceraPista {
                required property var modelData
                required property int index

                readonly property var info: Editor.infoBanda(modelData.banda)

                Layout.fillWidth: true
                Layout.preferredHeight: esVideo ? linea.altoClips
                                                : linea.altoPista
                alto: esVideo ? linea.altoClips : linea.altoPista
                esVideo: modelData.clips === true
                visiblePista: esVideo ? true : Editor.bandaVisible(modelData.banda)
                bloqueada: esVideo ? false : Editor.bandaBloqueada(modelData.banda)
                solo: esVideo ? false : !!(info && info.solo)

                //  Cómo se llama una banda: por lo que lleva si lleva una cosa,
                //  y por cuántas si lleva varias. Vacía, por su número — decía
                //  «0 cosas», que es verdad y no sirve para nada. Y la 1 es el
                //  vídeo, que se llama así aunque lleve veinte trozos.
                texto: esVideo ? Idioma.t("Vídeo")
                    : modelData.capas.length === 1
                    ? Editor.nombreCapa(modelData.capas[0])
                    : (modelData.capas.length === 0
                       ? Editor.nombreBanda(modelData.banda)
                       : Idioma.f(Idioma.t("%1 cosas"),
                                  String(modelData.capas.length)))
                //  El icono dice de qué es la banda cuando lleva una sola cosa.
                glifo: esVideo ? 0x000F0567          // md-video
                    : modelData.capas.length === 1
                    ? Editor.glifoCapa(modelData.capas[0])
                    : 0x000F02E9      // md-image
                tono: esVideo ? Theme.blue : Theme.green
                elegida: esVideo
                    ? Editor.clipSel !== null
                    : Editor.bandaSeleccionada === modelData.banda

                //  El vídeo no se arrastra: es la base y se queda abajo. Un
                //  vídeo encima de todo taparía el resto y no querría decir nada.
                arrastrable: !esVideo && linea.bandasVista.length > 2

                onPulsada: if (!esVideo) {
                    if (modelData.capas.length > 0)
                        Editor.seleccionar("capa", modelData.capas[0].id)
                    else
                        Editor.seleccionarBanda(modelData.banda)
                }

                onAlternarVisible: if (!esVideo)
                    Editor.alternarVisibilidadBanda(modelData.banda)
                onAlternarBloqueo: if (!esVideo)
                    Editor.alternarBloqueoBanda(modelData.banda)
                onAlternarSolo: if (!esVideo)
                    Editor.alternarSoloBanda(modelData.banda)

                //  Bajar en la LISTA es bajar de banda en el plan, y la lista va
                //  del revés. La vuelta se da aquí y en un solo sitio.
                //
                //  `index` va de arriba abajo, así que el puesto en la lista al
                //  que se ha llevado la fila es `index + filas`, y el número de
                //  banda que le toca es el complementario.
                //  La última fila de la lista es el vídeo y no se baraja, así
                //  que el sitio más bajo al que puede ir una capa es el
                //  penúltimo: `length - 2`.
                onReordenada: function (filas) {
                    if (esVideo || Editor.bandaBloqueada(modelData.banda))
                        return
                    const puesto = Math.max(0, Math.min(
                        linea.bandasVista.length - 2, index + filas))
                    Editor.ponerBandaEn(modelData.banda,
                                        linea.bandasVista.length - puesto)
                }
            }
        }
    }

    // ── las pistas ────────────────────────────────────────────────
    Flickable {
        id: rodillo

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Layout.preferredHeight: contenido.implicitHeight

        contentWidth: width * linea.acercamiento
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        //  Con barra: ampliada la línea, sin nada que lo diga no se sabe ni
        //  que hay más ni por dónde vas de un proyecto largo.
        ScrollBar.horizontal: IslandScrollBar {}

        //  Y siguiendo al cabezal, como cualquier editor: si la reproducción
        //  se acerca al borde de lo visible, la vista se recoloca para
        //  dejarla con aire por delante. Solo cuando nadie tiene la línea
        //  agarrada — con la mano encima, manda la mano.
        Connections {
            target: linea
            function onCabezalChanged() {
                if (linea.acercamiento <= 1.001 || rodillo.moving
                        || rodillo.dragging)
                    return
                const px = rodillo.contentWidth
                    * (linea.cabezal / Math.max(0.001, linea.total))
                const margen = rodillo.width * 0.12
                if (px < rodillo.contentX + margen
                        || px > rodillo.contentX + rodillo.width - margen)
                    rodillo.contentX = Math.max(0, Math.min(
                        rodillo.contentWidth - rodillo.width,
                        px - rodillo.width * 0.3))
            }
        }

        //  Soltar ficheros encima de la línea.
        //
        //  Antes meter una imagen eran tres pasos: abrir la ficha de añadir,
        //  pulsar el botón, y buscarla en el diálogo del sistema. Y encima el
        //  instante lo ponía el cabezal, así que había que colocarlo ANTES. Lo
        //  natural es arrastrar el fichero y soltarlo donde va, que es lo que
        //  hace cualquier editor.
        //
        //  El tipo sale de la extensión y cada uno va por su puerta: una imagen
        //  se crea directa, un vídeo o un audio hay que medirlos primero. Esas
        //  puertas ya existían —son las que usan los botones— así que esto no
        //  añade ninguna forma nueva de crear capas, solo una forma nueva de
        //  llegar a ellas.
        DropArea {
            id: sueltalo
            anchors.fill: parent
            z: 40
            keys: ["text/uri-list"]

            //  Dónde caería, en segundos. Cuenta el desplazamiento del rodillo:
            //  con la línea acercada, el 0 de la vista no es el 0 del montaje.
            function instanteEn(x) {
                return Math.max(0, Math.min(linea.total,
                    (rodillo.contentX + x) / Math.max(1, rodillo.contentWidth)
                    * linea.total))
            }

            property real caeEn: -1
            onPositionChanged: function (ev) { caeEn = instanteEn(ev.x) }
            onExited: caeEn = -1

            onDropped: function (ev) {
                const donde = instanteEn(ev.x)
                caeEn = -1
                const urls = ev.urls || []
                for (let i = 0; i < urls.length; ++i) {
                    const ruta = String(urls[i]).replace(/^file:\/\//, "")
                    const ext = ruta.split(".").pop().toLowerCase()
                    if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "avif",
                         "tiff"].indexOf(ext) >= 0)
                        Editor.crearImagen(decodeURIComponent(ruta), donde)
                    else if (["mp4", "mkv", "mov", "webm", "avi",
                              "m4v"].indexOf(ext) >= 0)
                        Editor.crearPip(decodeURIComponent(ruta), donde)
                    else if (["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]
                             .indexOf(ext) >= 0)
                        Editor.crearAudio(decodeURIComponent(ruta), donde)
                    else
                        Editor.fallo("no-se-puede-soltar")
                }
            }
        }

        //  Y dónde va a caer, mientras lo traes.
        Rectangle {
            z: 49
            visible: sueltalo.containsDrag && sueltalo.caeEn >= 0
            x: rodillo.contentWidth
               * (sueltalo.caeEn / Math.max(0.001, linea.total)) - 1
            width: 2
            height: contenido.implicitHeight
            color: Theme.green
        }

        //  La guía del imán: dónde te acabas de pegar.
        //
        //  Va aquí dentro del rodillo y por encima de todo, cruzando las filas
        //  enteras, porque de eso se trata: ver que el borde que arrastras ha
        //  quedado a plomo con el cabezal, con el final de un trozo o con el
        //  principio de otra capa. Sin la línea, el imán es magia negra: se te
        //  pega y no sabes a qué.
        //
        //  No acepta ratón ni ocupa sitio en el layout: es un dibujo.
        Rectangle {
            z: 50
            visible: Editor.imanEn >= 0
            x: rodillo.contentWidth
               * (Editor.imanEn / Math.max(0.001, linea.total)) - 1
            y: 0
            width: 2
            height: contenido.implicitHeight
            color: Theme.yellow
            opacity: 0.9
        }

        ColumnLayout {
            id: contenido
            width: rodillo.contentWidth
            spacing: linea.hueco

            // ── la regla ──────────────────────────────────────────
            Item {
                id: regla
                Layout.fillWidth: true
                Layout.preferredHeight: linea.altoRegla

                //  Una marca cada tanto, con el número puesto. El paso se elige
                //  para que no se amontonen: en un clip de diez segundos cada
                //  segundo, y en uno de diez minutos cada minuto.
                readonly property var escalones: [0.5, 1, 2, 5, 10, 15, 30, 60,
                                                  120, 300, 600, 1800]
                readonly property real paso: {
                    const objetivo = linea.total / Math.max(1, width / 78)
                    for (let i = 0; i < escalones.length; ++i)
                        if (escalones[i] >= objetivo)
                            return escalones[i]
                    return escalones[escalones.length - 1]
                }

                //  Pinchar y arrastrar en la regla lleva el cabezal.
                //
                //  Es donde lo intenta cualquiera, y no estaba: solo se podía
                //  desde la pista de los trozos, que además está llena de bloques
                //  que se quedan el gesto para lo suyo. Aquí no hay nada más, así
                //  que es la superficie fiable para buscar un instante.
                //
                //  Declarado ANTES de las marcas para que ellas queden encima; no
                //  aceptan ratón, así que no se lo van a quitar.
                MouseArea {
                    anchors.fill: parent
                    // Un poco más alto de lo que mide: acertar en veinte píxeles
                    // pidiendo puntería vertical no hace falta.
                    anchors.bottomMargin: -4
                    cursorShape: Qt.PointingHandCursor

                    function llevar(x) {
                        linea.saltar(Math.max(0, Math.min(linea.total,
                            x / Math.max(1, regla.width) * linea.total)))
                    }
                    onPressed: function (ev) {
                        linea.rascaInicio()
                        llevar(ev.x)
                    }
                    onPositionChanged: function (ev) {
                        if (pressed) llevar(ev.x)
                    }
                    onReleased: linea.rascaFin()
                    onCanceled: linea.rascaFin()
                }

                Repeater {
                    //  Todo referido a `regla` por su id y no por `parent`:
                    //  dentro de un delegado hay dos niveles de padre y coger el
                    //  que no es devuelve `undefined`, que en una cuenta sale
                    //  como NaN y coloca la marca en ninguna parte.
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

                // Marcadores editables: guías rápidas para cortes, rótulos y
                // cambios de plano. Se crean con M o desde el botón de la ficha.
                Repeater {
                    model: Editor.marcadores
                    delegate: Item {
                        id: marcador
                        required property var modelData

                        readonly property bool elegido:
                            Editor.tipoSel === "marcador"
                            && Editor.idSel === modelData.id

                        x: regla.width * (Number(modelData.t)
                            / Math.max(0.001, linea.total))
                        width: 1
                        height: regla.height + 260
                        z: 4

                        Rectangle {
                            width: marcador.elegido ? 3 : 2
                            height: parent.height
                            color: Theme.orange
                            opacity: marcador.elegido ? 1 : 0.7
                        }
                        IslandLabel {
                            x: 3
                            y: 0
                            text: marcador.modelData.nombre || "M"
                            color: Theme.orange
                            font.pixelSize: 8
                            font.weight: marcador.elegido
                                ? Font.DemiBold : Font.Normal
                        }

                        //  Pulsar ELIGE; para borrarlo, Suprimir.
                        //
                        //  Antes pulsar lo borraba, sin más. Era la única cosa
                        //  de la línea de tiempo que se destruía al tocarla
                        //  —todo lo demás se elige y se borra con Suprimir— y no
                        //  había forma de señalar uno para copiarlo, que es de
                        //  lo que salió esto.
                        MouseArea {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: regla.height
                            anchors.leftMargin: -6
                            anchors.rightMargin: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Editor.seleccionar("marcador",
                                                          marcador.modelData.id)
                        }
                    }
                }
            }

            // ── una fila por banda, y la 1 es el vídeo ────────────
            //
            //  Cada banda puede llevar varias cosas, normalmente en instantes
            //  distintos. Lo que se apila es la banda, así que subir algo de
            //  banda es lo que cambia qué tapa a qué.
            //
            //  La banda 1 son los trozos, con el zoom dibujado encima. Antes
            //  eran dos filas fijas más una por banda; ahora es una sola pila y
            //  el zoom no gasta fila, porque el zoom no es una capa: es algo que
            //  se le hace al vídeo.
            Repeater {
                model: linea.bandasVista

                delegate: Loader {
                    required property var modelData

                    //  El puente para PistaBanda: su propiedad se llama
                    //  `linea`, y dentro de su binding ese nombre resuelve
                    //  PRIMERO contra sus propias propiedades — o sea contra
                    //  sí misma, que aún es undefined. Con `linea: linea` la
                    //  fila se quedaba sin total ni cabezal y los bloques se
                    //  salían del borde derecho: por eso las bandas de capas
                    //  llevaban tiempo saliendo vacías. Desde el Loader, que
                    //  no tiene ninguna `linea`, el nombre sí llega al id.
                    readonly property var lineaDeArriba: linea

                    Layout.fillWidth: true
                    Layout.preferredHeight: modelData.clips
                        ? linea.altoClips : linea.altoPista

                    sourceComponent: modelData.clips ? pistaVideo : pistaCapas

                    Component {
                        id: pistaVideo
                        PistaClips {
                            total: linea.total
                            cabezal: linea.cabezal
                            onSaltar: function (t) { linea.saltar(t) }
                            onRascaInicio: linea.rascaInicio()
                            onRascaFin: linea.rascaFin()
                        }
                    }

                    Component {
                        id: pistaCapas
                        PistaBanda {
                            banda: modelData
                            linea: lineaDeArriba
                        }
                    }
                }
            }
        }

        //  La rueda, en un área que solo escucha la rueda.
        //
        //  Con `acceptedButtons: Qt.NoButton` no acepta pulsaciones, así que los
        //  clics y los arrastres siguen bajando hasta los bloques; pero sí recibe
        //  la rueda. Es la única forma limpia: un `MouseArea` acepta el evento de
        //  rueda tenga o no manejador, así que las pistas se lo quedaban y un
        //  `WheelHandler` del Flickable no llegaba a verlo nunca. La alternativa
        //  era reenviarlo a mano desde las tres clases de bloque.
        //
        //  Y va declarada al final, que en QML es lo de arriba.
        MouseArea {
            anchors.fill: contenido
            acceptedButtons: Qt.NoButton

            onWheel: function (ev) {
                if (ev.modifiers & Qt.ControlModifier) {
                    linea.acercar(ev.angleDelta.y > 0 ? 1.25 : 1 / 1.25, ev.x)
                } else {
                    //  Rueda vertical y horizontal valen igual: en un ratón
                    //  normal solo hay una, y aquí el único eje es el tiempo.
                    const d = ev.angleDelta.y !== 0 ? ev.angleDelta.y
                                                    : ev.angleDelta.x
                    rodillo.contentX = Math.max(0, Math.min(
                        Math.max(0, rodillo.contentWidth - rodillo.width),
                        rodillo.contentX - d * 0.6))
                }
                ev.accepted = true
            }
        }
    }
}
