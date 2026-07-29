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
import QtQuick.Layouts
import "../../core"
import "../../services"

RowLayout {
    id: linea

    property real total: 1
    property real cabezal: 0

    signal saltar(real t)
    // Añadir algo en una banda nueva encima de todo.
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
        for (let b = Editor.cuantasBandas; b >= 1; --b)
            r.push({ banda: b, capas: Editor.capasDeBanda(b) })
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


        //  Añadir una capa: algo nuevo, encima de todo.
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

        CabeceraPista {
            Layout.fillWidth: true
            Layout.preferredHeight: linea.altoClips
            alto: linea.altoClips
            texto: Idioma.t("Vídeo")
            glifo: 0x000F0567          // md-video
            tono: Theme.blue
        }

        CabeceraPista {
            Layout.fillWidth: true
            Layout.preferredHeight: linea.altoPista
            alto: linea.altoPista
            texto: Idioma.t("Zoom")
            glifo: 0x000F1276          // md-magnify_scan
            tono: Theme.blue
        }

        Repeater {
            model: linea.bandasVista

            delegate: CabeceraPista {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.preferredHeight: linea.altoPista
                alto: linea.altoPista

                //  Cómo se llama una banda: por lo que lleva si lleva una cosa,
                //  y por cuántas si lleva varias. Vacía, por su número — decía
                //  «0 cosas», que es verdad y no sirve para nada.
                texto: modelData.capas.length === 1
                    ? Editor.nombreCapa(modelData.capas[0])
                    : (modelData.capas.length === 0
                       ? Idioma.t("Capa ") + modelData.banda
                       : Idioma.f(Idioma.t("%1 cosas"),
                                  String(modelData.capas.length)))
                //  El icono dice de qué es la banda cuando lleva una sola cosa.
                glifo: modelData.capas.length === 1
                    ? Editor.glifoCapa(modelData.capas[0])
                    : 0x000F02E9      // md-image
                tono: Theme.green
                elegida: Editor.capaSel !== null
                    && Editor.bandaDe(Editor.capaSel) === modelData.banda

                arrastrable: linea.bandasVista.length > 1

                onPulsada: if (modelData.capas.length > 0)
                               Editor.seleccionar("capa", modelData.capas[0].id)

                //  Bajar en la LISTA es bajar de banda en el plan, y la lista va
                //  del revés. La vuelta se da aquí y en un solo sitio.
                //
                //  `index` va de arriba abajo, así que el puesto en la lista al
                //  que se ha llevado la fila es `index + filas`, y el número de
                //  banda que le toca es el complementario.
                onReordenada: function (filas) {
                    const puesto = Math.max(0, Math.min(
                        linea.bandasVista.length - 1, index + filas))
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
            }

            // ── los trozos de vídeo ───────────────────────────────
            PistaClips {
                Layout.fillWidth: true
                Layout.preferredHeight: linea.altoClips

                total: linea.total
                cabezal: linea.cabezal
                onSaltar: function (t) { linea.saltar(t) }
                onRascaInicio: linea.rascaInicio()
                onRascaFin: linea.rascaFin()
            }

            // ── el zoom ───────────────────────────────────────────
            Pista {
                Layout.fillWidth: true
                Layout.preferredHeight: linea.altoPista

                modelo: Editor.momentos
                total: linea.total
                cabezal: linea.cabezal
                elegido: {
                    //  `Pista` elige por índice y la selección va por id, porque
                    //  con varias pistas el índice no dice de qué es. Aquí se
                    //  traduce.
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
                onEditar: function (id, a, b) {
                    Editor.fijarMomento(id, { t0: a, t1: b })
                }
                onCrear: function (a, b) {
                    Editor.seleccionar("momento", Editor.crearMomento(a, b))
                }
            }

            // ── una fila por banda ────────────────────────────────
            //
            //  Cada banda puede llevar varias cosas, normalmente en instantes
            //  distintos. Lo que se apila es la banda, así que subir algo de
            //  banda es lo que cambia qué tapa a qué.
            Repeater {
                model: linea.bandasVista

                delegate: Pista {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: linea.altoPista

                    modelo: modelData.capas
                    total: linea.total
                    cabezal: linea.cabezal
                    tono: Theme.green
                    // Una capa necesita un fichero detrás, y eso se elige, no se
                    // dibuja arrastrando en un hueco.
                    creable: false
                    elegido: {
                        for (let i = 0; i < modelData.capas.length; ++i)
                            if (Editor.tipoSel === "capa"
                                    && modelData.capas[i].id === Editor.idSel)
                                return i
                        return -1
                    }

                    onSaltar: function (t) { linea.saltar(t) }
                    onElegir: function (i) {
                        if (i < 0 || i >= modelData.capas.length)
                            return
                        const c = modelData.capas[i]
                        Editor.seleccionar("capa", c.id)
                        //  Y si el cabezal está fuera de su tramo, llevarlo
                        //  dentro: una capa solo se puede mover y escalar
                        //  mientras se ve, así que elegirla sin poder tocarla no
                        //  sirve de nada.
                        if (linea.cabezal < c.t0 || linea.cabezal > c.t1)
                            linea.saltar(c.t0 + Math.min(0.3, (c.t1 - c.t0) / 2))
                    }
                    onEditar: function (id, a, b) {
                        Editor.fijarCapa(id, { t0: a, t1: b })
                    }

                    //  Sacar una cosa de su capa y llevarla a otra.
                    //
                    //  Bajar en la LISTA es bajar de banda en el plan, y la lista
                    //  va del revés, de ahí el signo menos. Arrastrar por encima
                    //  de la primera fila da banda `cuantasBandas + 1`, que
                    //  `ponerCapaEnBanda` acepta creando una capa nueva.
                    porFilas: true
                    pasoFila: linea.altoPista + linea.hueco
                    onMoverFila: function (id, filas) {
                        Editor.ponerCapaEnBanda(id, modelData.banda - filas)
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
