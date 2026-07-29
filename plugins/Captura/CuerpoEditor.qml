//  El editor: se ve el vídeo, con el zoom aplicado, mientras corre.
//
//  Lo que se reproduce es el fichero ORIGINAL, sin tocar. El zoom se aplica
//  aquí, con una transformación sobre la imagen, siguiendo la trayectoria que
//  ha calculado tools/editar.py. Y son exactamente los mismos puntos que se
//  convierten en la expresión de ffmpeg —entre ellos se interpola en recta,
//  igual que hace el filtro—, así que lo que ves aquí es lo que va a salir en
//  el fichero. Sin renderizar nada y sin dos implementaciones que se separen.
//
//  De ahí que se pueda mover un momento y ver el efecto al instante: solo hay
//  que rehacer la trayectoria, que es aritmética.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: view

    required property var plugin

    //  Qué botones enseña la cabecera. En la island se aparta y se descarta;
    //  en la ventana grande se vuelve a la island y se descarta.
    property bool enVentana: false
    signal encoger()
    signal agrandar()

    focus: true

    readonly property var momento: Editor.momentoSel

    readonly property real segundos: reproductor.cabezal
    readonly property real total: Math.max(0.001, Editor.duracionLinea)

    Component.onCompleted: forceActiveFocus()

    // ── dónde está la cámara ahora ────────────────────────────────
    //
    //  Búsqueda binaria sobre los puntos y recta entre los dos vecinos. Con
    //  ciento y pico puntos daría igual recorrerlos, pero esto se evalúa en
    //  cada fotograma y no cuesta nada hacerlo bien.
    function camaraEn(t) {
        const c = Editor.camara
        if (!c || c.length === 0)
            return [1, 0, 0]
        if (t <= c[0][0])
            return [c[0][1], c[0][2], c[0][3]]
        if (t >= c[c.length - 1][0]) {
            const u = c[c.length - 1]
            return [u[1], u[2], u[3]]
        }
        let lo = 0, hi = c.length - 1
        while (hi - lo > 1) {
            const m = (lo + hi) >> 1
            if (c[m][0] <= t) lo = m; else hi = m
        }
        const a = c[lo], b = c[hi]
        const d = b[0] - a[0]
        const f = d > 0 ? (t - a[0]) / d : 0
        return [a[1] + (b[1] - a[1]) * f,
                a[2] + (b[2] - a[2]) * f,
                a[3] + (b[3] - a[3]) * f]
    }

    //  Mientras arrastras el encuadre manda esto, y al soltar se vuelve a la
    //  trayectoria que calcula python. Es lo que separa un arrastre que
    //  responde de uno que va a saltos.
    property var camaraForzada: null

    // El recorte que corresponde a un centro dado, con el zoom de ahora.
    function encuadreEn(cx, cy) {
        const z = estadoCamara ? estadoCamara[0] : 1
        const w = Editor.anchoVideo / z
        const h = Editor.altoVideo / z
        return [z,
                Math.max(0, Math.min(Editor.anchoVideo - w, cx - w / 2)),
                Math.max(0, Math.min(Editor.altoVideo - h, cy - h / 2))]
    }

    readonly property var estadoCamara: camaraForzada
        ? camaraForzada : camaraEn(segundos)
    readonly property bool conZoom: estadoCamara[0] > 1.001

    function irA(t) { reproductor.irA(t) }

    //  Elegir el momento anterior o el siguiente, sea cual sea la selección de
    //  ahora. Con las flechas se recorre la lista, que es lo que se espera.
    function saltarMomento(d) {
        const n = Editor.momentos.length
        if (n === 0)
            return
        let i = 0
        for (let k = 0; k < n; ++k)
            if (Editor.momentos[k].id === Editor.idSel)
                i = k
        const j = ((i + d) % n + n) % n
        Editor.seleccionar("momento", Editor.momentos[j].id)
        view.irA(Editor.momentos[j].t0)
    }

    Keys.onPressed: function (ev) {
        if (ev.key === Qt.Key_Space) {
            reproductor.alternar()
        } else if (ev.key === Qt.Key_S) {
            //  Cortar por donde vaya el cabezal. Es la tecla de cortar en
            //  cualquier editor de vídeo, y aquí no había otra cosa usándola.
            Editor.cortar(view.segundos)
        } else if (ev.key === Qt.Key_Left) {
            if ((ev.modifiers & Qt.ShiftModifier) && view.momento)
                Editor.moverMomento(view.momento.id, -0.2)
            else
                view.irA(view.segundos - 1)
        } else if (ev.key === Qt.Key_Right) {
            if ((ev.modifiers & Qt.ShiftModifier) && view.momento)
                Editor.moverMomento(view.momento.id, 0.2)
            else
                view.irA(view.segundos + 1)
        } else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab) {
            view.saltarMomento(1)
        } else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) {
            view.saltarMomento(-1)
        } else if (ev.key === Qt.Key_Plus || ev.key === Qt.Key_Equal) {
            if (view.momento) Editor.ajustarNivel(view.momento.id, 0.2)
        } else if (ev.key === Qt.Key_Delete || ev.key === Qt.Key_Backspace) {
            //  Borra lo que esté elegido, sea de la pista que sea. Con dos
            //  pistas, «quitar» ya no puede querer decir solo «quitar el zoom».
            if (Editor.tipoSel === "clip")
                Editor.quitarClip(Editor.idSel)
            else if (Editor.tipoSel === "capa")
                Editor.quitarCapa(Editor.idSel)
            else if (view.momento)
                Editor.quitarMomento(view.momento.id)
        } else if (ev.key === Qt.Key_Minus) {
            if (view.momento) Editor.ajustarNivel(view.momento.id, -0.2)
        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
            Editor.renderizar()
        } else {
            return
        }
        ev.accepted = true
    }

    property bool silenciado: false

    //  Qué dice la ficha de la derecha.
    //
    //  Con tres cosas que se pueden elegir —un trozo, un zoom, una capa— el
    //  encadenado de ternarios dentro del `text` dejaba de leerse. Aquí cada
    //  caso ocupa su línea y se ve de un vistazo lo que falta cuando llegue el
    //  cuarto.
    readonly property string tituloSel: {
        if (Editor.clipSel)
            return Idioma.t("Trozo ") + (Editor.tramoDe(Editor.idSel) + 1)
                   + "/" + Editor.tramos.length
        if (Editor.capaSel)
            return Idioma.t("Imagen")
        if (momento)
            return Idioma.t("Momento ") + momento.id
        return Idioma.t("Sin selección")
    }

    readonly property string detalleSel: {
        if (Editor.clipSel)
            return Editor.clipSel.desde.toFixed(1) + " → "
                   + Editor.clipSel.hasta.toFixed(1) + " s "
                   + Idioma.t("del original")
        if (Editor.capaSel)
            return Editor.capaSel.ruta.split("/").pop()
        if (momento)
            return momento.t0.toFixed(1) + " – " + momento.t1.toFixed(1) + " s"
                   + "   ·   ×" + momento.z.toFixed(1)
        return ""
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        // ── cabecera ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF1276)      // md-magnify_scan
                color: Theme.blue
                font.pixelSize: 16
            }

            IslandLabel {
                text: Editor.momentos.length === 0
                    ? Idioma.t("Editor")
                    : Idioma.f(Idioma.t("%1 momentos de zoom"),
                               String(Editor.momentos.length))
                color: Theme.ink
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            IslandLabel {
                text: Editor.rutaVideo.split("/").pop()
                color: Theme.dim
                font.pixelSize: 10
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            // Agrandar o encoger, según dónde esté.
            MediaButton {
                glyph: String.fromCodePoint(view.enVentana ? 0xF0294 : 0xF0293)
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: view.enVentana ? view.encoger() : view.agrandar()
            }

            // Apartar: sigue ahí, en la píldora, para retomarlo luego.
            MediaButton {
                glyph: String.fromCodePoint(0xF0374)     // md-minus
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
            }

            // Descartar: se tira el plan. El vídeo sin tocar sigue guardado.
            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: view.plugin.descartar()
            }
        }

        // ── el vídeo, con el zoom puesto ──────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Rectangle {
                id: celda
                //  Se estira: en la island son unos 600 px y en la ventana
                //  grande casi el doble, y el mismo cuerpo sirve para las dos.
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: "black"
                clip: true

                //  El lienzo, con la proporción del vídeo que va a salir.
                //
                //  Antes el vídeo se estiraba para llenar la celda, y como la
                //  celda tiene la forma que le deje el reparto, la previa salía
                //  aplastada. Con el zoom solo era feo; en cuanto haya capas
                //  encima deja de ser lo mismo que se va a renderizar, que es la
                //  única promesa que hace esta vista.
                Item {
                    id: marco
                    anchors.centerIn: parent

                    readonly property real aspecto:
                        Editor.anchoVideo / Math.max(1, Editor.altoVideo)

                    width: Math.min(celda.width, celda.height * aspecto)
                    height: width / Math.max(0.001, aspecto)
                    clip: true

                    //  La imagen llena el marco, y encima va la transformación que
                    //  hace el zoom. Escalar y desplazar sobre lo ya pintado es
                    //  justo lo que hace `zoompan` con su recorte, solo que aquí
                    //  sale gratis.
                    Item {
                        id: lente

                        //  Sin `anchors.fill`, y no es un capricho: **un elemento
                        //  anclado no se puede mover con x e y**. El ancla manda, y
                        //  con ella puestas el `scale` sí se aplicaba pero el
                        //  desplazamiento no, así que el zoom salía siempre pegado
                        //  a la esquina superior izquierda pasara lo que pasara con
                        //  el encuadre.
                        //
                        //  Es exactamente la misma trampa que costó el arrastre de
                        //  la mazmorra, documentada en CeldaObjeto.qml. Volver a
                        //  caer en ella dice bastante de lo bien que se esconde.
                        width: marco.width
                        height: marco.height

                        readonly property real escala: view.estadoCamara[0]
                        // de píxeles del vídeo a píxeles de este marco
                        readonly property real factor: marco.width / Math.max(1, Editor.anchoVideo)

                        transformOrigin: Item.TopLeft
                        scale: escala
                        x: -view.estadoCamara[1] * factor * escala
                        y: -view.estadoCamara[2] * factor * escala

                        //  El reproductor sabe qué trozo de qué fichero toca en
                        //  cada instante de la línea; aquí solo se le da sitio.
                        Reproductor {
                            id: reproductor
                            anchors.fill: parent
                            silenciado: view.silenciado
                        }
                    }

                    //  Arrastrar el encuadre.
                    //
                    //  Va POR ENCIMA de `lente` y no dentro, porque dentro la
                    //  escala del zoom se aplicaría también a las coordenadas del
                    //  ratón y el encuadre se movería más deprisa cuanto más
                    //  ampliado estuviera.
                    //
                    //  Se agarra el contenido, no la cámara: llevas la imagen
                    //  hacia donde quieres mirar, que es como funciona un mapa.
                    MouseArea {
                        anchors.fill: parent
                        enabled: view.momento !== null
                            && view.segundos >= view.momento.t0
                            && view.segundos <= view.momento.t1
                        cursorShape: enabled
                            ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                            : Qt.ArrowCursor

                        property real xIni: 0
                        property real yIni: 0
                        property real cxIni: 0
                        property real cyIni: 0

                        onPressed: function (ev) {
                            xIni = ev.x; yIni = ev.y
                            cxIni = view.momento.cx
                            cyIni = view.momento.cy
                        }

                        onPositionChanged: function (ev) {
                            if (!pressed || !view.momento)
                                return
                            const f = lente.factor * lente.escala
                            const cx = cxIni - (ev.x - xIni) / f
                            const cy = cyIni - (ev.y - yIni) / f
                            // Se pinta ya, sin esperar a que python rehaga la
                            // trayectoria: si no, el arrastre se sentiría a cuatro
                            // fotogramas por segundo.
                            view.camaraForzada = view.encuadreEn(cx, cy)
                            Editor.moverCentro(view.momento.id, cx, cy)
                        }

                        onReleased: view.camaraForzada = null

                        //  La rueda cambia el nivel del momento que esté sonando.
                        //  En el propio MouseArea: un WheelHandler hijo no recibe
                        //  el evento, se lo queda el área.
                        onWheel: function (ev) {
                            if (view.momento)
                                Editor.ajustarNivel(view.momento.id,
                                                     ev.angleDelta.y > 0 ? 0.1 : -0.1)
                            ev.accepted = true
                        }
                    }

                    //  Las capas: fuera de `lente`, que es donde las pone
                    //  también el grafo de ffmpeg —después del zoom—, y por eso
                    //  la previa coincide con el render por construcción.
                    //
                    //  Declaradas DESPUÉS del área de arrastrar el encuadre: en
                    //  QML manda el último, y pinchar encima de una capa tiene
                    //  que agarrar la capa y no mover la cámara.
                    CapasLienzo {
                        anchors.fill: parent
                        segundos: view.segundos
                    }

                    // Que lo que ves lleva zoom, para no confundirlo con el vídeo
                    // tal cual.
                    Rectangle {
                        visible: view.conZoom
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        width: marcaZoom.implicitWidth + 12
                        height: 18
                        radius: 9
                        color: "#cc0a84ff"

                        IslandLabel {
                            id: marcaZoom
                            anchors.centerIn: parent
                            text: "×" + view.estadoCamara[0].toFixed(2)
                            color: Theme.ink
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            // ── la ficha del momento ──────────────────────────────
            ColumnLayout {
                //  `fillWidth: false` explícito: un layout anidado lo pone a
                //  true por su cuenta, y con eso este panel se quedaba TODO el
                //  ancho —su contenido implícito es grande— dejando el vídeo en
                //  una tira de ocho píxeles. En la island colaba porque no
                //  sobraba sitio; en la ventana grande se veía a la primera.
                Layout.fillWidth: false
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                spacing: 6

                //  Qué hay elegido.
                //
                //  Con dos pistas la ficha ya no puede ser siempre la del zoom:
                //  si acabas de pinchar un trozo, lo que quieres saber es de
                //  dónde sale y qué le puedes hacer.
                IslandLabel {
                    text: view.tituloSel
                    color: Theme.ink
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                IslandLabel {
                    visible: text.length > 0
                    text: view.detalleSel
                    color: Theme.muted
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }

                // ── lo que se le hace a una capa ──────────────────
                //
                //  Mover y escalar se hacen encima del vídeo con el ratón, y su
                //  tramo se estira en la línea de tiempo. Aquí queda lo que no
                //  tiene un gesto natural.
                ColumnLayout {
                    visible: Editor.capaSel !== null
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 4

                    IslandLabel {
                        text: Idioma.t("Opacidad")
                        color: Theme.dim
                        font.pixelSize: 9
                        font.capitalization: Font.AllUppercase
                        font.weight: Font.DemiBold
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: Theme.track

                            Rectangle {
                                width: parent.width * (Editor.capaSel
                                    ? Editor.capaSel.opacidad : 1)
                                height: parent.height
                                radius: parent.radius
                                color: Theme.green
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.topMargin: -8
                                anchors.bottomMargin: -8
                                cursorShape: Qt.PointingHandCursor

                                function poner(x) {
                                    const v = Math.max(0, Math.min(1,
                                        x / Math.max(1, width)))
                                    Editor.fijarCapa(Editor.idSel,
                                        { opacidad: Math.round(v * 20) / 20 })
                                }
                                onPressed: function (ev) { poner(ev.x) }
                                onPositionChanged: function (ev) {
                                    if (pressed) poner(ev.x)
                                }
                            }
                        }

                        IslandLabel {
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignRight
                            text: Math.round((Editor.capaSel
                                ? Editor.capaSel.opacidad : 1) * 100) + "%"
                            color: Theme.dim
                            font.pixelSize: 9
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.preferredHeight: 26
                        radius: 13
                        color: quitarCapaRaton.containsMouse ? "#3a1416"
                                                             : Theme.surface
                        border.width: 1
                        border.color: Qt.rgba(1, 0.27, 0.23, 0.3)

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5

                            IconGlyph {
                                text: String.fromCodePoint(0xF01B4)  // md-delete
                                color: Theme.red
                                font.pixelSize: 12
                            }

                            IslandLabel {
                                text: Idioma.t("Quitar la imagen")
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: quitarCapaRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Editor.quitarCapa(Editor.idSel)
                        }
                    }
                }

                // ── lo que se le hace a un trozo ──────────────────
                ColumnLayout {
                    visible: Editor.clipSel !== null
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 6

                    Repeater {
                        model: [
                            { texto: Idioma.t("Cortar aquí"), icono: 0xF0190,             // md-content_cut
                              accion: "cortar" },
                            { texto: Idioma.t("Quitar el trozo"), icono: 0xF01B4,
                              accion: "quitar" }
                        ]

                        delegate: Rectangle {
                            id: botonClip
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            radius: 13
                            color: clipRaton.containsMouse ? Theme.surfaceHi
                                                           : Theme.surface
                            // Quitar el último trozo dejaría la línea vacía.
                            opacity: botonClip.modelData.accion === "quitar"
                                     && Editor.tramos.length <= 1 ? 0.4 : 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5

                                IconGlyph {
                                    text: String.fromCodePoint(botonClip.modelData.icono)
                                    color: botonClip.modelData.accion === "quitar"
                                        ? Theme.red : Theme.muted
                                    font.pixelSize: 12
                                }

                                IslandLabel {
                                    text: botonClip.modelData.texto
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                id: clipRaton
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (botonClip.modelData.accion === "cortar")
                                        Editor.cortar(view.segundos)
                                    else
                                        Editor.quitarClip(Editor.idSel)
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                GridLayout {
                    // Los botones del zoom solo pintan algo con un zoom elegido.
                    visible: Editor.clipSel === null && Editor.capaSel === null
                    columns: 2
                    columnSpacing: 6
                    rowSpacing: 6
                    Layout.fillWidth: true

                    Repeater {
                        model: [
                            { texto: Idioma.t("Antes"),   icono: 0xF0141, accion: "antes" },
                            { texto: Idioma.t("Después"), icono: 0xF0142, accion: "despues" },
                            { texto: Idioma.t("Menos"),   icono: 0xF034A, accion: "menos" },
                            { texto: Idioma.t("Más"),     icono: 0xF034B, accion: "mas" }
                        ]

                        delegate: Rectangle {
                            id: boton
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            radius: 13
                            color: botonRaton.containsMouse ? Theme.surfaceHi : Theme.surface
                            opacity: view.momento ? 1 : 0.4

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5

                                IconGlyph {
                                    text: String.fromCodePoint(boton.modelData.icono)
                                    color: Theme.muted
                                    font.pixelSize: 12
                                }

                                IslandLabel {
                                    text: boton.modelData.texto
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                id: botonRaton
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: view.momento !== null
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const a = boton.modelData.accion
                                    if (a === "antes")        Editor.moverMomento(view.momento.id, -0.2)
                                    else if (a === "despues") Editor.moverMomento(view.momento.id, 0.2)
                                    else if (a === "menos")   Editor.ajustarNivel(view.momento.id, -0.2)
                                    else if (a === "mas")     Editor.ajustarNivel(view.momento.id, 0.2)
                                }
                            }
                        }
                    }
                }

                //  Las pistas de audio.
                //
                //  Se graban por separado —sistema y micro— para poder
                //  equilibrarlas después: mezclarlas al grabar sería
                //  irreversible. Lo que se toque aquí se aplica al renderizar.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                    spacing: 3
                    visible: Editor.pistasAudio.length > 0

                    IslandLabel {
                        text: Idioma.t("Audio")
                        color: Theme.dim
                        font.pixelSize: 9
                        font.capitalization: Font.AllUppercase
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: Editor.pistasAudio

                        delegate: RowLayout {
                            id: filaPista
                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 6

                            //  Silenciar, y de paso decir cuál estás oyendo:
                            //  el reproductor solo puede sacar una pista a la
                            //  vez, así que pulsar el nombre cambia de monitor.
                            MediaButton {
                                glyph: String.fromCodePoint(
                                    filaPista.modelData.mudo ? 0xF0581 : 0xF057E)
                                glyphSize: 13
                                glyphColor: filaPista.modelData.mudo
                                    ? Theme.dim : Theme.ink
                                onActivated: Editor.fijarPista(
                                    filaPista.modelData.i,
                                    { mudo: !filaPista.modelData.mudo })
                            }

                            IslandLabel {
                                Layout.preferredWidth: 62
                                text: filaPista.modelData.titulo.length > 0
                                    ? filaPista.modelData.titulo
                                    : Idioma.t("Pista ") + (filaPista.modelData.i + 1)
                                color: reproductor.pistaAudio === filaPista.modelData.i
                                    ? Theme.ink : Theme.muted
                                font.pixelSize: 10
                                elide: Text.ElideRight

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: reproductor.fijarPistaAudio(filaPista.modelData.i)
                                }
                            }

                            // El volumen, de 0 a 2: subir el doble es lo que
                            // hace falta cuando el micro quedó bajo.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4
                                radius: 2
                                color: Theme.track
                                opacity: filaPista.modelData.mudo ? 0.4 : 1

                                Rectangle {
                                    width: parent.width
                                        * Math.min(1, filaPista.modelData.volumen / 2)
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.blue
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.topMargin: -8
                                    anchors.bottomMargin: -8
                                    cursorShape: Qt.PointingHandCursor

                                    function poner(x) {
                                        const v = Math.max(0, Math.min(2,
                                            x / Math.max(1, width) * 2))
                                        Editor.fijarPista(filaPista.modelData.i,
                                                           { volumen: Math.round(v * 20) / 20 })
                                    }
                                    onPressed: function (ev) { poner(ev.x) }
                                    onPositionChanged: function (ev) {
                                        if (pressed) poner(ev.x)
                                    }
                                }
                            }

                            IslandLabel {
                                Layout.preferredWidth: 30
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(filaPista.modelData.volumen * 100) + "%"
                                color: Theme.dim
                                font.pixelSize: 9
                            }
                        }
                    }
                }

                Rectangle {
                    // El trozo y la capa tienen su propio «quitar» arriba.
                    visible: Editor.clipSel === null && Editor.capaSel === null
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    radius: 13
                    color: quitarRaton.containsMouse ? "#3a1416" : Theme.surface
                    border.width: 1
                    border.color: Qt.rgba(1, 0.27, 0.23, 0.3)
                    opacity: view.momento ? 1 : 0.4

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 5

                        IconGlyph {
                            text: String.fromCodePoint(0xF01B4)     // md-delete
                            color: Theme.red
                            font.pixelSize: 12
                        }

                        IslandLabel {
                            text: Idioma.t("Quitar")
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: quitarRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: view.momento !== null
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Editor.quitarMomento(view.momento.id)
                    }
                }
            }
        }

        // ── la línea de tiempo ────────────────────────────────────
        LineaTiempo {
            id: linea
            Layout.fillWidth: true

            total: view.total
            cabezal: view.segundos

            onSaltar: function (t) { view.irA(t) }
        }

        // ── pie ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MediaButton {
                glyph: reproductor.reproduciendo ? Theme.ico.pause : Theme.ico.play
                glyphSize: 16
                glyphColor: Theme.ink
                onActivated: reproductor.alternar()
            }

            //  Crear un zoom donde esté el cabezal.
            //
            //  Se podía crear arrastrando en un hueco de la línea de tiempo,
            //  pero eso no lo adivina nadie: sin un botón, la única forma de
            //  añadir un momento era que lo propusiera el rastro del cursor.
            Rectangle {
                Layout.preferredWidth: nuevoTexto.implicitWidth + 26
                Layout.preferredHeight: 26
                radius: 13
                color: nuevoRaton.containsMouse ? Theme.surfaceHi : Theme.surface
                border.width: 1
                border.color: Qt.rgba(10 / 255, 132 / 255, 1, 0.35)

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    IconGlyph {
                        text: String.fromCodePoint(0xF1276)   // md-magnify_scan
                        color: Theme.blue
                        font.pixelSize: 13
                    }

                    IslandLabel {
                        id: nuevoTexto
                        text: Idioma.t("Añadir zoom")
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: nuevoRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // Dos segundos desde donde estés, o lo que quepa si
                        // estás cerca del final.
                        const a = Math.min(view.segundos, Math.max(0, view.total - 2))
                        const b = Math.min(view.total, a + 2)
                        Editor.seleccionar("momento", Editor.crearMomento(a, b))
                    }
                }
            }

            //  Traer una imagen de fuera.
            //
            //  Por zenity y no por un selector propio: una imagen se busca
            //  mirándola, no escribiendo su nombre, y el diálogo del sistema
            //  trae vista previa. Debajo habla con el portal, así que es el
            //  mismo que sale en cualquier otra aplicación.
            Rectangle {
                Layout.preferredWidth: imagenTexto.implicitWidth + 26
                Layout.preferredHeight: 26
                radius: 13
                color: imagenRaton.containsMouse ? Theme.surfaceHi : Theme.surface
                border.width: 1
                border.color: Qt.rgba(52 / 255, 199 / 255, 89 / 255, 0.35)

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    IconGlyph {
                        text: String.fromCodePoint(0xF087C)   // md-image_plus
                        color: Theme.green
                        font.pixelSize: 13
                    }

                    IslandLabel {
                        id: imagenTexto
                        text: Idioma.t("Añadir imagen")
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: imagenRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.plugin.pedirImagen(view.segundos)
                }
            }

            MediaButton {
                glyph: String.fromCodePoint(view.silenciado ? 0xF0581 : 0xF057E)
                glyphSize: 15
                glyphColor: view.silenciado ? Theme.dim : Theme.ink
                onActivated: view.silenciado = !view.silenciado
            }

            IslandLabel {
                text: view.segundos.toFixed(1) + " / " + view.total.toFixed(1) + " s"
                color: Theme.muted
                font.pixelSize: 10
            }

            //  Acercar y alejar la línea de tiempo.
            //
            //  También va con ctrl+rueda, que es lo que uno prueba, pero eso no
            //  se descubre solo: sin un botón, en un vídeo largo no habría forma
            //  de enterarse de que la línea se puede acercar.
            MediaButton {
                glyph: String.fromCodePoint(0xF034A)     // md-magnify_minus
                glyphSize: 13
                glyphColor: linea.acercamiento > 1 ? Theme.ink : Theme.dim
                onActivated: linea.acercar(1 / 1.6, linea.width / 2)
            }

            //  Con hueco reservado siempre.
            //
            //  Estaba oculta mientras la línea cabía entera, y al aparecer
            //  empujaba el botón de acercar: el segundo clic de una serie caía
            //  al lado. Un botón que se mueve porque lo has pulsado es de las
            //  cosas más molestas que puede hacer una interfaz.
            IslandLabel {
                Layout.preferredWidth: 26
                horizontalAlignment: Text.AlignHCenter
                text: linea.acercamiento > 1.001
                    ? "×" + linea.acercamiento.toFixed(1) : ""
                color: Theme.dim
                font.pixelSize: 9
            }

            MediaButton {
                glyph: String.fromCodePoint(0xF034B)     // md-magnify_plus
                glyphSize: 13
                glyphColor: Theme.ink
                onActivated: linea.acercar(1.6, linea.width / 2)
            }

            IslandLabel {
                visible: Editor.estado !== "renderizando"
                text: Idioma.t("espacio reproduce · ←→ salta · ↑↓ momento · mayús+←→ lo mueve · +− nivel")
                color: Theme.dim
                font.pixelSize: 9
                Layout.leftMargin: 6
            }

            Rectangle {
                visible: Editor.estado === "renderizando"
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: Theme.track

                Rectangle {
                    width: parent.width * Editor.progreso
                    height: parent.height
                    radius: parent.radius
                    color: Theme.blue
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }

            IslandLabel {
                visible: Editor.estado === "renderizando"
                text: Math.round(Editor.progreso * 100) + " %"
                color: Theme.muted
                font.pixelSize: 10
            }

            Item { Layout.fillWidth: true; visible: Editor.estado !== "renderizando" }

            Rectangle {
                visible: Editor.estado !== "renderizando"
                Layout.preferredWidth: renderTexto.implicitWidth + 24
                Layout.preferredHeight: 26
                radius: 13
                color: renderRaton.containsMouse
                    ? Qt.lighter(Theme.blue, 1.15) : Theme.blue

                IslandLabel {
                    id: renderTexto
                    anchors.centerIn: parent
                    text: Idioma.t("Renderizar")
                    color: Theme.ink
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: renderRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Editor.renderizar()
                }
            }
        }
    }
}
