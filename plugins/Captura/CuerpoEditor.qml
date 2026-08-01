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
//
//  Las secciones de la ficha lateral viven en sus propias piezas —FichaAnadir,
//  FichaCapa, FichaClip, FichaFundidos, FichaTranscripcion, FichaPistas—:
//  aquí queda el reparto, el vídeo con su lente y la línea de tiempo.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
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

    //  Cuánto alto le queda a la línea de tiempo.
    //
    //  La island crece con las bandas hasta su tope, y a partir de ahí la línea
    //  se recorre en vertical en vez de desbordarse. El número sale de lo que
    //  mide todo lo demás del editor —cabecera, vídeo y pie— y por eso vive
    //  aquí y no en el plugin: aquí es donde están esas piezas.
    //  Los 300 son lo que ocupa todo lo demás: cabecera, pie, márgenes y el
    //  mínimo del vídeo. Con menos, el pie acababa por debajo del borde de la
    //  island — que es lo que pasaba con 470 mal contados.
    readonly property int altoParaLinea: Math.max(
        linea.altoRegla + linea.altoClips + 10,
        view.height - 300)

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
        if ((ev.modifiers & Qt.ControlModifier) && ev.key === Qt.Key_Z) {
            if (ev.modifiers & Qt.ShiftModifier) Editor.rehacer()
            else Editor.deshacer()
        } else if ((ev.modifiers & Qt.ControlModifier) && ev.key === Qt.Key_Y) {
            Editor.rehacer()
        } else if (ev.key === Qt.Key_M) {
            Editor.crearMarcador(view.segundos)
        } else if (ev.key === Qt.Key_Space) {
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
        if (Editor.capaSel) {
            if (Editor.capaSel.tipo === "texto")  return Idioma.t("Rótulo")
            if (Editor.capaSel.tipo === "audio")  return Idioma.t("Audio")
            if (Editor.capaSel.tipo === "video")  return Idioma.t("Vídeo encima")
            if (Editor.capaSel.tipo === "zona")   return Editor.nombreCapa(Editor.capaSel)
            if (Editor.capaSel.tipo === "forma")  return Editor.nombreCapa(Editor.capaSel)
            return Idioma.t("Imagen")
        }
        if (momento)
            return Idioma.t("Momento ") + momento.id
        return Idioma.t("Sin selección")
    }

    readonly property string detalleSel: {
        if (Editor.clipSel)
            return Editor.clipSel.desde.toFixed(1) + " → "
                   + Editor.clipSel.hasta.toFixed(1) + " s "
                   + Idioma.t("del original")
        if (Editor.capaSel) {
            //  Una zona no tiene fichero que enseñar: lo suyo es su ventana.
            if (Editor.capaSel.tipo === "zona")
                return Editor.capaSel.t0.toFixed(1) + " – "
                       + Editor.capaSel.t1.toFixed(1) + " s"
            return Editor.capaSel.tipo === "texto"
                ? Editor.capaSel.t0.toFixed(1) + " – "
                  + Editor.capaSel.t1.toFixed(1) + " s"
                : Editor.capaSel.ruta.split("/").pop()
                  + (Editor.capaSel.tipo === "audio"
                     ? "   ·   " + Editor.capaSel.t0.toFixed(1) + " s" : "")
        }
        if (momento)
            return momento.t0.toFixed(1) + " – " + momento.t1.toFixed(1) + " s"
                   + "   ·   ×" + momento.z.toFixed(1)
        return ""
    }

    ColumnLayout {
        id: reparto
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

            MediaButton {
                glyph: String.fromCodePoint(0xF054C) // undo
                glyphSize: 13
                glyphColor: Editor.puedeDeshacer ? Theme.ink : Theme.dim
                enabledAction: Editor.puedeDeshacer
                onActivated: Editor.deshacer()
            }

            MediaButton {
                glyph: String.fromCodePoint(0xF054D) // redo
                glyphSize: 13
                glyphColor: Editor.puedeRehacer ? Theme.ink : Theme.dim
                enabledAction: Editor.puedeRehacer
                onActivated: Editor.rehacer()
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
                //  Pero no por debajo de esto: con muchas capas, la línea de
                //  tiempo se comía el vídeo hasta dejarlo en una raya.
                Layout.minimumHeight: 180
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
                        sonando: reproductor.reproduciendo
                        //  Para desenfocar hace falta la imagen de debajo, y la
                        //  de debajo es la que YA lleva el zoom: las zonas van
                        //  después del `zoompan` como las demás capas.
                        fuenteVideo: lente
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

                    // ── la previa del Short ───────────────────────
                    //
                    //  Con la salida 9:16 puesta, dos cortinas oscurecen lo
                    //  que el recorte vertical va a tirar y un borde marca la
                    //  banda que sobrevive — la MISMA banda centrada que
                    //  recorta el render—. Cortinas y no recorte duro a
                    //  propósito: viendo lo que se pierde se decide mejor
                    //  dónde poner cada cosa, y todo se sigue pudiendo
                    //  arrastrar, también lo que queda en penumbra.
                    readonly property real bandaShorts:
                        height * 9.0 / 16.0
                    readonly property real cortinaShorts:
                        Math.max(0, (width - bandaShorts) / 2)

                    Rectangle {
                        visible: Editor.salidaVertical
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: marco.cortinaShorts
                        color: "#aa000000"
                    }

                    Rectangle {
                        visible: Editor.salidaVertical
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: marco.cortinaShorts
                        color: "#aa000000"
                    }

                    Rectangle {
                        visible: Editor.salidaVertical
                        x: marco.cortinaShorts
                        width: marco.bandaShorts
                        height: parent.height
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.yellow

                        IslandLabel {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.topMargin: 4
                            text: "9:16"
                            color: Theme.yellow
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            //  Con desplazamiento propio, y no es un capricho: desde que la
            //  rejilla de acciones vive aquí, el contenido de la ficha pasa de
            //  los quinientos píxeles, y su alto implícito arrastraba a toda la
            //  fila y empujaba el pie por debajo del borde de la island. Medido:
            //  861 px de contenido en 814 disponibles.
            //
            //  `fillWidth: false` explícito: un layout anidado lo pone a true
            //  por su cuenta, y con eso este panel se quedaba TODO el ancho
            //  dejando el vídeo en una tira.
            Flickable {
                id: ficha
                Layout.fillWidth: false
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: fichaCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                ScrollBar.vertical: ScrollBar {
                    policy: ficha.contentHeight > ficha.height
                        ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: fichaCol
                    width: ficha.width - 10
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

                    // ── qué se le puede añadir ────────────────────────
                    FichaAnadir { view: view }

                    // ── lo que se le hace a una capa ──────────────────
                    FichaCapa { view: view }

                    // ── lo que se le hace a un trozo ──────────────────
                    FichaClip { view: view }

                    // ── los fundidos ──────────────────────────────────
                    FichaFundidos { }

                    // ── lo que se dice en el vídeo ────────────────────
                    FichaTranscripcion { view: view }

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

                    //  Las pistas de audio, con su volumen y su monitor.
                    FichaPistas { reproductor: reproductor }

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
        }

        // ── la línea de tiempo ────────────────────────────────────
        //  La línea, dentro de algo que se pueda recorrer en vertical.
        //
        //  El alto de la island crece con las bandas pero tiene un tope, y en
        //  cuanto se llega a él las filas de abajo se salían por debajo del
        //  borde sin más aviso. Es el mismo problema que tuvieron los ajustes y
        //  se arregla igual: un `Flickable` con barra.
        //
        //  Se desplaza la línea ENTERA —cabeceras, regla y pistas— y no solo las
        //  filas: las dos columnas tienen que moverse a la vez o la cabecera
        //  dejaría de decir de qué es cada pista, que es lo único para lo que
        //  está.
        Flickable {
            id: rodilloV
            Layout.fillWidth: true
            //  Lo que pida la línea, hasta donde quepa.
            //
            //  Y no `fillHeight`: con eso la línea y el vídeo se repartían el
            //  hueco a medias y la línea se quedaba en dos filas teniendo nueve.
            //  Aquí la línea coge lo suyo y el vídeo se queda con el resto, que
            //  es el orden en que importan: las filas o están o no están, y el
            //  vídeo se ve igual de bien un poco más pequeño.
            Layout.preferredHeight: Math.min(linea.implicitHeight,
                                             view.altoParaLinea)
            contentWidth: width
            contentHeight: linea.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            //  Solo en vertical: el horizontal ya lo lleva la línea por dentro,
            //  y dos desplazamientos peleándose por el mismo arrastre es lo que
            //  hace que ninguno de los dos vaya bien.
            flickableDirection: Flickable.VerticalFlick
            ScrollBar.vertical: ScrollBar {
                policy: rodilloV.contentHeight > rodilloV.height
                    ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }

            LineaTiempo {
                id: linea
                width: rodilloV.width

                total: view.total
                cabezal: view.segundos

                onSaltar: function (t) { view.irA(t) }
                // «Capa» no es sinónimo de «imagen»: primero deja elegir qué
                // tipo de capa se quiere añadir en la sección «Añadir».
                onNuevaCapa: Editor.crearBanda()
                onRascaInicio: reproductor.empezarRasca()
                onRascaFin: reproductor.terminarRasca()
            }
        }

        // ── pie ───────────────────────────────────────────────────
        RowLayout {
            id: pie
            Layout.fillWidth: true
            spacing: 8

            MediaButton {
                glyph: reproductor.reproduciendo ? Theme.ico.pause : Theme.ico.play
                glyphSize: 16
                glyphColor: Theme.ink
                onActivated: reproductor.alternar()
            }

            //  Un vídeo dentro del vídeo.
            //
            //  Sin etiqueta: cinco botones con texto no caben, y de los cinco
            //  este es el que menos falta hace explicar —el icono de un recuadro
            //  dentro de otro se entiende—. Los cuatro frecuentes conservan su
            //  nombre.
            MediaButton {
                glyph: String.fromCodePoint(0xF0E57)   // md-picture_in_picture_bottom_right
                glyphSize: 15
                glyphColor: Theme.ink
                onActivated: view.plugin.pedirPip(view.segundos)
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

            //  La chuleta de teclas, solo en la ventana grande.
            //
            //  En la island no cabe: con los botones de añadir zoom, imagen,
            //  texto y audio, el pie se pasaba del ancho y «Renderizar» se salía
            //  por el borde. Y de las dos cosas, la que hace falta es el botón.
            IslandLabel {
                visible: view.enVentana && Editor.estado !== "renderizando"
                Layout.fillWidth: true
                elide: Text.ElideRight
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

            //  En qué formato sale.
            //
            //  Aquí y no en Ajustes: el mismo vídeo se saca en mp4 para
            //  archivarlo y en gif para pegarlo en una incidencia, así que no es
            //  una preferencia sino una decisión de cada vez.
            RowLayout {
                visible: Editor.estado !== "renderizando"
                spacing: 2

                Repeater {
                    model: ["mp4", "webm", "gif"]

                    delegate: Rectangle {
                        id: chipFmt
                        required property var modelData

                        readonly property bool puesto:
                            Editor.formatoSalida === chipFmt.modelData

                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 22
                        radius: 11
                        color: chipFmt.puesto ? Theme.surfaceHi : "transparent"
                        border.width: 1
                        border.color: chipFmt.puesto ? Qt.rgba(1, 1, 1, 0.2)
                                                     : Qt.rgba(1, 1, 1, 0.08)

                        IslandLabel {
                            anchors.centerIn: parent
                            text: chipFmt.modelData
                            color: chipFmt.puesto ? Theme.ink : Theme.dim
                            font.pixelSize: 9
                            font.weight: chipFmt.puesto ? Font.DemiBold
                                                        : Font.Normal
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Editor.formatoSalida = chipFmt.modelData
                        }
                    }
                }
            }

            //  La salida vertical para Shorts, al lado de los formatos: es
            //  la misma clase de decisión —de cada render, no un ajuste—.
            Rectangle {
                readonly property bool puesto: Editor.salidaVertical
                visible: Editor.estado !== "renderizando"
                Layout.preferredWidth: 40
                Layout.preferredHeight: 22
                radius: 11
                color: puesto ? Theme.surfaceHi : "transparent"
                border.width: 1
                border.color: puesto ? Qt.rgba(1, 1, 1, 0.2)
                                     : Qt.rgba(1, 1, 1, 0.08)

                IslandLabel {
                    anchors.centerIn: parent
                    text: "9:16"
                    color: parent.puesto ? Theme.ink : Theme.dim
                    font.pixelSize: 9
                    font.weight: parent.puesto ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Editor.salidaVertical = !Editor.salidaVertical
                }
            }

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
