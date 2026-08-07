//  La pista base: los trozos de vídeo, en el orden en que se ven.
//
//  No reusa `Pista`/`BloqueTiempo` aunque se parezcan, y no es por pereza: allí
//  un bloque tiene un t0 y un t1 propios y puede estar donde quiera, y aquí los
//  trozos van pegados y sin huecos. Arrastrar no significa «ponlo en el segundo
//  siete» sino «ponlo el tercero», y las asas no mueven el bloque en la línea
//  sino que cambian por dónde entra y por dónde sale del FICHERO. Es otro gesto
//  con la misma pinta, y mezclarlos habría salido caro.
//
//  Como en los bloques de zoom, el gesto se edita en local y el modelo se
//  escribe al soltar: escribir `clips` reasigna el array, el Repeater destruye
//  los delegados y con ellos el MouseArea que tenía el agarre.

import QtQuick
import "../../core"
import "../../services"

Rectangle {
    id: pista

    property real total: 1
    property real cabezal: 0

    signal saltar(real t)
    // Buscar un instante con el ratón: el reproductor se pausa mientras dura.
    signal rascaInicio()
    signal rascaFin()

    radius: 6
    color: Theme.surface
    clip: true

    function t2px(t) { return width * (t / Math.max(0.001, total)) }
    function px2t(px) { return px / Math.max(1, width) * total }

    // ── el fondo: saltar a un instante ────────────────────────────
    //
    //  Declarado primero a propósito: en QML gana el último, así que los trozos
    //  quedan por encima y se llevan el gesto cuando toca.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: function (ev) {
            //  Pinchar el hueco es decir «ninguno de estos»: suelta lo elegido
            //  y la ficha vuelve a las opciones generales.
            Editor.seleccionar("", 0)
            pista.rascaInicio()
            pista.saltar(pista.px2t(ev.x))
        }
        onPositionChanged: function (ev) {
            if (pressed) pista.saltar(pista.px2t(ev.x))
        }
        onReleased: pista.rascaFin()
        onCanceled: pista.rascaFin()
    }

    Repeater {
        model: Editor.tramos

        delegate: Rectangle {
            id: trozo
            required property var modelData
            required property int index

            readonly property bool elegido: Editor.tipoSel === "clip"
                && Editor.idSel === modelData.clip

            // ── el gesto en curso, en local ───────────────────────
            property bool arrastrando: false
            property real deltaX: 0
            property bool recortando: false
            property real vDesde: 0
            property real vHasta: 0

            readonly property real dur: recortando
                ? Math.max(0.1, vHasta - vDesde)
                : modelData.fin - modelData.inicio

            x: pista.t2px(modelData.inicio) + deltaX
            width: Math.max(6, pista.t2px(dur))
            y: 3
            height: pista.height - 6
            radius: 5

            //  El que se arrastra va por encima de los demás y con sombra: sin
            //  eso, al pasar sobre el vecino desaparecía debajo y parecía que se
            //  había soltado.
            z: arrastrando ? 10 : 0

            //  Un trozo marcado como silencio va en rojo, y por eso se marcan y
            //  no se borran: así se ve de un vistazo qué se va a quitar antes de
            //  quitarlo. El clip lleva la marca; aquí solo se pinta.
            readonly property bool mudo: {
                const i = Editor.indiceDeClip(modelData.clip)
                return i >= 0 && !!Editor.clips[i].silencio
            }

            color: elegido ? Theme.blue
                : mudo ? (raton.containsMouse ? Qt.rgba(0.65, 0.28, 0.30, 0.9)
                                              : Qt.rgba(0.52, 0.22, 0.24, 0.85))
                : (raton.containsMouse ? Qt.rgba(0.35, 0.45, 0.6, 0.85)
                                       : Qt.rgba(0.28, 0.34, 0.45, 0.8))
            opacity: arrastrando ? 0.85 : 1

            Behavior on color { ColorAnimation { duration: 110 } }
            Behavior on x {
                enabled: !trozo.arrastrando
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            border.width: elegido ? 0 : 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            // ── los fundidos, uno por esquina ─────────────────────
            //
            //  El tirador vive ARRIBA y las asas de recorte a los lados y abajo,
            //  que es como se reparten en cualquier editor: dos gestos distintos
            //  en el mismo borde tienen que separarse por sitio o se pelean.
            //
            //  Se dibuja el triángulo que va a salir. Un fundido es una rampa, y
            //  una rampa dibujada dice cuánto dura sin leer ningún número.
            Repeater {
                model: 2
                delegate: Item {
                    id: rampa
                    required property int index
                    readonly property bool entrando: index === 0
                    readonly property real segundos:
                        Editor.fundidoDe(trozo.modelData, entrando)
                    //  En píxeles: el fundido va en tiempo de LÍNEA, igual que
                    //  el ancho del bloque.
                    readonly property real ancho:
                        Math.min(trozo.width / 2, pista.t2px(segundos))

                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    x: entrando ? 0 : trozo.width - ancho
                    width: Math.max(0, ancho)
                    visible: ancho > 1

                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            const c = getContext("2d")
                            c.reset()
                            if (width <= 0 || height <= 0)
                                return
                            c.fillStyle = Qt.rgba(0, 0, 0, 0.55)
                            c.beginPath()
                            //  El triángulo apunta a donde el vídeo está oscuro:
                            //  entrando, la esquina de arriba a la izquierda.
                            if (rampa.entrando) {
                                c.moveTo(0, 0); c.lineTo(width, 0); c.lineTo(0, height)
                            } else {
                                c.moveTo(width, 0); c.lineTo(0, 0); c.lineTo(width, height)
                            }
                            c.closePath()
                            c.fill()
                        }
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                    }
                }
            }

            //  Y el agarre, arriba en cada esquina. Siempre presente aunque el
            //  fundido valga cero: si solo saliera cuando ya hay fundido, no
            //  habría forma de crear el primero.
            Repeater {
                model: 2
                delegate: MouseArea {
                    id: asaFunde
                    required property int index
                    readonly property bool entrando: index === 0

                    readonly property real actual:
                        Editor.fundidoDe(trozo.modelData, entrando)

                    width: 13
                    height: 13
                    y: 1
                    x: entrando
                       ? Math.min(trozo.width - 14, pista.t2px(actual) - 6)
                       : Math.max(1, trozo.width - pista.t2px(actual) - 7)
                    visible: trozo.width > 40 && !trozo.arrastrando
                    preventStealing: true
                    hoverEnabled: true
                    cursorShape: Qt.SizeHorCursor

                    property real xIni: 0
                    property real vIni: 0

                    onPressed: function (ev) {
                        Editor.seleccionar("clip", trozo.modelData.id)
                        xIni = mapToItem(pista, ev.x, 0).x
                        vIni = actual
                    }
                    onPositionChanged: function (ev) {
                        if (!pressed)
                            return
                        const d = pista.px2t(mapToItem(pista, ev.x, 0).x - xIni)
                        Editor.fijarFundido(trozo.modelData.id, entrando,
                                            vIni + (entrando ? d : -d))
                    }
                    //  Doble clic lo quita: llevarlo a cero arrastrando hasta el
                    //  borde exacto es pedir puntería para decir «ninguno».
                    onDoubleClicked: Editor.fijarFundido(
                        trozo.modelData.id, entrando, 0)

                    Rectangle {
                        anchors.centerIn: parent
                        width: 9
                        height: 9
                        radius: 2
                        rotation: 45
                        color: parent.containsMouse || parent.pressed
                            ? Theme.yellow : Qt.rgba(1, 1, 1, 0.55)
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.4)
                    }
                }
            }

            // ── qué trozo es ──────────────────────────────────────
            Column {
                anchors.left: parent.left
                anchors.leftMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                visible: trozo.width > 54

                IslandLabel {
                    text: trozo.dur.toFixed(1) + " s"
                    color: Theme.ink
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                // De dónde sale, en tiempo del fichero. Es lo que distingue dos
                // trozos del mismo vídeo, que si no son idénticos por fuera.
                IslandLabel {
                    visible: trozo.width > 92
                    text: (trozo.recortando ? trozo.vDesde : trozo.modelData.desde)
                          .toFixed(1) + " → "
                          + (trozo.recortando ? trozo.vHasta : trozo.modelData.hasta)
                          .toFixed(1)
                    color: trozo.elegido ? Qt.rgba(1, 1, 1, 0.75) : Theme.muted
                    font.pixelSize: 9
                }
            }

            // ── mover: cambia el ORDEN, no el instante ────────────
            MouseArea {
                id: raton
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SizeAllCursor

                property real xIni: 0
                property bool movido: false

                //  En coordenadas de la PISTA, no del trozo.
                //
                //  Es la trampa que ya costó el arrastre de los bloques de zoom
                //  y la de la mazmorra antes: `ev.x` va en coordenadas del
                //  elemento, y este elemento se recoloca en cuanto cambia
                //  `deltaX`. El puntero se quedaba siempre en el mismo punto
                //  relativo y el desplazamiento se anulaba a sí mismo. La
                //  posición absoluta es la única que no se mueve bajo los pies.
                function enPista(ev) { return mapToItem(pista, ev.x, 0).x }

                onPressed: function (ev) {
                    Editor.seleccionar("clip", trozo.modelData.clip)
                    xIni = enPista(ev)
                    movido = false
                }

                onPositionChanged: function (ev) {
                    if (!pressed)
                        return
                    const d = enPista(ev) - xIni
                    if (!movido && Math.abs(d) < 6)
                        return
                    movido = true
                    trozo.arrastrando = true
                    trozo.deltaX = d
                }

                onReleased: {
                    if (!movido) {
                        //  Un clic sin arrastre lleva el cabezal a DONDE has
                        //  pinchado.
                        //
                        //  Antes lo llevaba al principio del trozo, y estaba mal:
                        //  la pista de los trozos es la superficie grande de la
                        //  línea de tiempo, así que es donde uno pincha para
                        //  buscar un instante, y saltar al principio del trozo
                        //  convertía cada intento en un viaje de vuelta.
                        pista.saltar(pista.px2t(xIni))
                        return
                    }
                    // A qué hueco ha ido a parar el centro del trozo.
                    const centro = trozo.x + trozo.width / 2
                    Editor.moverClip(trozo.modelData.clip,
                                     pista.huecoEn(centro, trozo.index))
                    trozo.arrastrando = false
                    trozo.deltaX = 0
                }
            }

            // ── recortar: cambia por dónde entra y sale del fichero ─
            Component {
                id: asa

                MouseArea {
                    property bool esIzquierda: true

                    // Nueve píxeles y no cuatro: acertar en una franja de cuatro
                    // arrastrando es pedir una puntería que nadie tiene.
                    width: 9
                    height: trozo.height
                    x: esIzquierda ? 0 : trozo.width - 9
                    preventStealing: true
                    hoverEnabled: true
                    cursorShape: Qt.SizeHorCursor

                    property real xIni: 0

                    // En coordenadas de la pista, por lo mismo que el cuerpo:
                    // el asa va pegada a un borde que este gesto mueve.
                    function enPista(ev) { return mapToItem(pista, ev.x, 0).x }

                    onPressed: function (ev) {
                        Editor.seleccionar("clip", trozo.modelData.clip)
                        trozo.vDesde = trozo.modelData.desde
                        trozo.vHasta = trozo.modelData.hasta
                        trozo.recortando = true
                        xIni = enPista(ev)
                    }

                    onPositionChanged: function (ev) {
                        if (!pressed)
                            return
                        // Lo arrastrado, en segundos. Del fichero y de la línea
                        // a la vez: el trozo no cambia de velocidad.
                        const d = pista.px2t(enPista(ev) - xIni)
                        if (esIzquierda)
                            trozo.vDesde = Math.min(trozo.modelData.desde + d,
                                                    trozo.vHasta - 0.1)
                        else
                            trozo.vHasta = Math.max(trozo.modelData.hasta + d,
                                                    trozo.vDesde + 0.1)
                    }

                    onReleased: {
                        Editor.recortarClip(trozo.modelData.clip,
                                            trozo.vDesde, trozo.vHasta)
                        trozo.recortando = false
                    }

                    Rectangle {
                        visible: trozo.elegido || parent.containsMouse
                        anchors.centerIn: parent
                        width: 2
                        height: parent.height * 0.45
                        radius: 1
                        color: Theme.ink
                        opacity: parent.containsMouse ? 1 : 0.5
                    }
                }
            }

            Loader { sourceComponent: asa; onLoaded: item.esIzquierda = true }
            Loader { sourceComponent: asa; onLoaded: item.esIzquierda = false }
        }
    }

    //  En qué posición del orden cae una x dada.
    //
    //  Se cuenta cuántos trozos tienen su centro a la izquierda, saltándose el
    //  que se está moviendo: contarlo a sí mismo haría que quedarse quieto
    //  contara como avanzar un puesto.
    function huecoEn(x, propio) {
        let n = 0
        for (let i = 0; i < Editor.tramos.length; ++i) {
            if (i === propio)
                continue
            const t = Editor.tramos[i]
            if (t2px((t.inicio + t.fin) / 2) < x)
                ++n
        }
        return n
    }

    // ── el zoom, encima de los trozos ─────────────────────────────
    //
    //  El zoom no es una capa: es algo que se le HACE al vídeo, y por eso vive
    //  en la fila del vídeo y no en una propia. Antes gastaba una fila entera
    //  para unas pocas marcas, y con dos capas eso eran cuatro filas.
    //
    //  Va en una tira de siete píxeles pegada al borde de abajo, con su propia
    //  zona de ratón: arrastrar un trozo y estirar un zoom son dos gestos en el
    //  mismo sitio, y separarlos por altura es lo que evita que se peleen. Es lo
    //  mismo que ya hacen las asas de recorte.
    //  ── cuánto ocupa la tira del zoom ─────────────────────────────
    //
    //  Siete píxeles fijos eran una tira en la que no se acierta: la misma
    //  lección que ya pagaron las asas de los trozos unas líneas más abajo
    //  —«nueve píxeles y no cuatro: acertar en una franja de cuatro es pedir
    //  una puntería que nadie tiene»— y que a estas marcas no se les aplicó.
    //
    //  Y ahora la pista ENTERA, como cualquier otro bloque de la línea.
    //
    //  Primero fueron siete píxeles, luego el 40% de abajo, y las dos veces por
    //  el mismo motivo: dejar sitio al trozo de debajo, porque comparten fila.
    //  Pero media altura es media altura, y un bloque que se arrastra, se estira
    //  y se elige pide el mismo cuerpo que los demás.
    //
    //  Lo que cuesta, dicho claro: donde hay un zoom, el trozo de debajo queda
    //  tapado y ahí no se puede agarrar ni recortar. Se aparta el zoom y vuelve
    //  a estar. La alternativa era darle fila propia al zoom, que es lo que hace
    //  cualquier editor grande, pero en la island cada fila se paga cara.
    readonly property int altoZoom: height

    Repeater {
        model: Editor.momentos

        delegate: Rectangle {
            id: marca
            required property var modelData

            readonly property bool elegido: Editor.tipoSel === "momento"
                && Editor.idSel === modelData.id

            //  Lo que se está estirando, en local: escribir el modelo reasigna
            //  el array y el Repeater se lleva por delante el delegado que tiene
            //  el agarre. Es la misma trampa que ya pagó la pista de clips.
            property bool estirando: false
            property real vA: 0
            property real vB: 0

            readonly property real a: estirando ? vA : modelData.t0
            readonly property real b: estirando ? vB : modelData.t1

            x: pista.t2px(a)
            //  Veintiséis de mínimo y no cuatro. Un zoom corto salía de cuatro
            //  píxeles de ancho, y sobre cuatro píxeles no hay nada que pulsar:
            //  entre las dos asas se lo repartían entero y la zona de elegir
            //  quedaba en NEGATIVO. Veintiséis es lo que hace falta para que
            //  quepan dos asas de nueve —el ancho que este fichero ya declaró
            //  necesario para las de los trozos— y quede centro entre ellas.
            width: Math.max(26, pista.t2px(b - a))
            y: 0
            height: pista.altoZoom
            radius: 4
            //  Semitransparente aposta: ocupa la fila entera, así que si fuera
            //  opaco no se vería que hay un trozo debajo ni dónde acaba.
            opacity: 0.85
            color: elegido ? Theme.blue : Qt.rgba(10 / 255, 132 / 255, 1, 0.55)
            border.width: elegido ? 1 : 0
            border.color: Theme.ink

            //  Lo que ocupa cada asa por punta. Nueve, que es lo que este mismo
            //  fichero declaró necesario para las asas de los trozos —«acertar
            //  en una franja de cuatro arrastrando es pedir una puntería que
            //  nadie tiene»— y que a estas nunca se les dio: con seis no salían
            //  para estirar.
            //
            //  Proporcional y con tope, no fijo: con un número fijo por punta,
            //  una marca más estrecha que dos asas se queda sin centro —margen
            //  mayor que el ancho es una zona de lado negativo, o sea ninguna
            //  zona— y no se podía ni elegir. Así el centro existe siempre.
            readonly property real asa: Math.min(9, width / 3)

            //  El centro elige Y MUEVE el bloque entero.
            //
            //  Antes solo elegía: podías estirarlo por las puntas y no llevarlo
            //  a otro sitio, así que mover un zoom dos segundos a la derecha era
            //  estirar por un lado y encoger por el otro hasta cuadrarlo. Un
            //  bloque de una línea de tiempo se arrastra, y punto.
            //
            //  En local mientras dura el gesto, como todo lo de este fichero:
            //  escribir el modelo reasigna el array y el Repeater destruye al
            //  delegado que tiene el agarre.
            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: marca.asa
                anchors.rightMargin: marca.asa
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true

                property real xIni: 0
                property real dur: 0

                onPressed: function (ev) {
                    Editor.seleccionar("momento", marca.modelData.id)
                    xIni = mapToItem(pista, ev.x, 0).x
                    marca.vA = marca.modelData.t0
                    marca.vB = marca.modelData.t1
                    dur = marca.vB - marca.vA
                    marca.estirando = true
                }

                onPositionChanged: function (ev) {
                    if (!pressed)
                        return
                    const d = pista.px2t(mapToItem(pista, ev.x, 0).x - xIni)
                    //  Se mueve entero: la duración no cambia al llevarlo de un
                    //  sitio a otro, y en los topes se para en vez de encogerse.
                    //  Y con imán, como cualquier otro bloque: un zoom que
                    //  empieza justo donde acaba un trozo se pega solo.
                    const crudo = Math.max(0, Math.min(pista.total - dur,
                                                       marca.modelData.t0 + d))
                    const a = Math.min(pista.total - dur,
                        Editor.ajustarTiempo(crudo, marca.modelData.id))
                    marca.vA = a
                    marca.vB = a + dur
                }

                onReleased: {
                    Editor.fijarMomento(marca.modelData.id,
                                        { t0: marca.vA, t1: marca.vB })
                    marca.estirando = false
                    Editor.soltarIman()
                }
                onCanceled: { marca.estirando = false; Editor.soltarIman() }
            }

            Repeater {
                model: 2
                delegate: MouseArea {
                    required property int index
                    readonly property bool izquierda: index === 0

                    width: marca.asa + 2
                    height: parent.height
                    x: izquierda ? -1 : parent.width - marca.asa - 1
                    cursorShape: Qt.SizeHorCursor
                    preventStealing: true

                    property real xIni: 0

                    onPressed: function (ev) {
                        xIni = mapToItem(pista, ev.x, 0).x
                        marca.vA = marca.modelData.t0
                        marca.vB = marca.modelData.t1
                        marca.estirando = true
                        Editor.seleccionar("momento", marca.modelData.id)
                    }
                    onPositionChanged: function (ev) {
                        if (!pressed)
                            return
                        const d = pista.px2t(
                            mapToItem(pista, ev.x, 0).x - xIni)
                        if (izquierda)
                            marca.vA = Math.max(0, Math.min(
                                marca.modelData.t1 - 0.2,
                                marca.modelData.t0 + d))
                        else
                            marca.vB = Math.min(pista.total, Math.max(
                                marca.modelData.t0 + 0.2,
                                marca.modelData.t1 + d))
                    }
                    onReleased: {
                        Editor.fijarMomento(marca.modelData.id,
                                            { t0: marca.vA, t1: marca.vB })
                        marca.estirando = false
                    }
                    onCanceled: marca.estirando = false
                }
            }
        }
    }

    // ── dónde va la reproducción ──────────────────────────────────
    Rectangle {
        x: pista.t2px(pista.cabezal) - 1
        width: 2
        height: pista.height
        color: Theme.ink
    }
}
