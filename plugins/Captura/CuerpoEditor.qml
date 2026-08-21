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
    //
    //  En VENTANA se reserva menos, y no es un ajuste fino: ahí el vídeo es
    //  ancho, así que un poco menos de alto casi no se nota en la imagen y en
    //  cambio son dos o tres bandas más visibles sin tener que desplazar. En la
    //  island manda lo contrario —la previa ya es pequeña y encogerla más la
    //  deja inservible—, así que el número es distinto a propósito.
    readonly property int altoParaLinea: Math.max(
        linea.altoRegla + linea.altoClips + 10,
        view.height - (view.enVentana ? 210 : 300))

    readonly property var momento: Editor.momentoSel

    readonly property real segundos: reproductor.cabezal
    readonly property real total: Math.max(0.001, Editor.duracionLinea)

    Component.onCompleted: forceActiveFocus()

    // ── la locución ───────────────────────────────────────────────
    //
    //  El Editor tiene el micro; el reproductor está aquí. Así que allí se
    //  decide y aquí se obedece: cuando el micro ya está abierto —y no antes—
    //  se busca el punto y se da al play.
    Connections {
        target: Editor

        function onVozPreparada() {
            reproductor.irA(Editor.vozDesde)
            reproductor.reproducir()
        }

        function onVozParada() {
            reproductor.pausar()
        }
    }

    //  Y cuando el vídeo se mueve DE VERDAD, se avisa.
    //
    //  Pedirle que se reproduzca y que se reproduzca son dos instantes
    //  distintos: entre medias hay un medio que se coloca. Lo que vale como
    //  «ya está andando» es que el cabezal AVANCE, que es lo único observable
    //  desde fuera; el Editor solo se queda con la primera vez.
    Connections {
        target: reproductor
        enabled: Editor.grabandoVoz
        function onCabezalChanged() {
            Editor.vozEmpezoASonar(reproductor.cabezal)
        }

        //  Y si el vídeo se para —se acabó, o le has dado a pausa— la toma se
        //  acaba con él. Seguir con el micro abierto solo grabaría silencio, y
        //  encima con el editor delante sin decir que sigue escuchando.
        function onReproduciendoChanged() {
            if (!reproductor.reproduciendo)
                Editor.pararVoz()
        }
    }

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

    //  Quitar lo que esté elegido, sea de la fila que sea.
    //
    //  Sale de la tecla porque ahora lo usan dos: Suprimir y Ctrl+X. Con dos
    //  pistas y cuatro clases de bloque, «quitar» ya no puede querer decir solo
    //  «quitar el zoom».
    function borrarSeleccion() {
        //  Todo lo elegido, no solo lo principal: desde que se pueden coger
        //  varios con Ctrl, borrar uno de tres sería la mitad del gesto.
        if (Editor.tipoSel.length > 0) {
            Editor.quitarSeleccion()
            return
        }
        if (view.momento)
            Editor.quitarMomento(view.momento.id)
    }

    property bool conAyuda: false

    //  Lo que no se ve por ningún lado. Un renglón por gesto, sin adornos:
    //  esto es una chuleta, no documentación.
    readonly property var gestos: [
        [Idioma.t("Doble clic en un rótulo"), Idioma.t("escribirlo sobre el vídeo")],
        [Idioma.t("Arrastrar sobre el vídeo"), Idioma.t("dibujar un zoom")],
        [Idioma.t("Rueda sobre el vídeo"), Idioma.t("nivel del zoom")],
        [Idioma.t("Soltar un fichero en la línea"), Idioma.t("lo añade donde caiga")],
        [Idioma.t("Ctrl + rueda en la línea"), Idioma.t("acercar hasta ×60")],
        [Idioma.t("Ctrl + clic en un bloque"), Idioma.t("coger varios")],
        [Idioma.t("Esquina de un trozo"), Idioma.t("fundido · doble clic lo quita")],
        [Idioma.t("Clic derecho en un bloque"), Idioma.t("fotograma clave")],
        ["S", Idioma.t("cortar lo elegido por el cabezal")],
        ["M", Idioma.t("marcador")],
        ["← →", Idioma.t("un fotograma · con Ctrl, un segundo")],
        [Idioma.t("Espacio"), Idioma.t("reproducir")],
        ["Ctrl + C / V / X", Idioma.t("copiar, pegar, cortar")],
        ["Supr", Idioma.t("quitar lo elegido")],
        ["Esc", Idioma.t("soltar la herramienta o la selección")]
    ]

    //  Cuánto avanza una flecha.
    //
    //  UN FOTOGRAMA, que es como se afina en cualquier editor. Antes era un
    //  segundo entero: a 60 fps eso son sesenta fotogramas de golpe, o sea que
    //  no había forma de colocar un corte donde va — había que arrastrar el
    //  cabezal a ojo y conformarse.
    //
    //  Con Ctrl, un segundo, para recorrer de verdad. Es el reparto de siempre:
    //  el gesto pequeño de fábrica y el grande con modificador, no al revés.
    function paso(ev) {
        return (ev.modifiers & Qt.ControlModifier) ? 1 : Editor.unFotograma
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
            //
            //  Y corta lo que esté elegido: con una música o un rótulo cogidos,
            //  parte esos; sin nada, la pista de vídeo. Antes partía siempre el
            //  vídeo, así que las capas se quedaban cruzando el corte enteras.
            Editor.cortarEnCabezal(view.segundos)
        } else if (ev.key === Qt.Key_Left) {
            if ((ev.modifiers & Qt.ShiftModifier) && view.momento)
                Editor.moverMomento(view.momento.id, -0.2)
            else
                view.irA(view.segundos - view.paso(ev))
        } else if (ev.key === Qt.Key_Right) {
            if ((ev.modifiers & Qt.ShiftModifier) && view.momento)
                Editor.moverMomento(view.momento.id, 0.2)
            else
                view.irA(view.segundos + view.paso(ev))
        } else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab) {
            view.saltarMomento(1)
        } else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) {
            view.saltarMomento(-1)
        } else if (ev.key === Qt.Key_Plus || ev.key === Qt.Key_Equal) {
            if (view.momento) Editor.ajustarNivel(view.momento.id, 0.2)
        } else if (ev.key === Qt.Key_Escape && Editor.herramienta.length > 0) {
            //  Antes que soltar la selección: si has armado una herramienta sin
            //  querer, lo primero que quieres es desarmarla.
            Editor.desarmar()
        } else if (ev.key === Qt.Key_Escape && Editor.tipoSel.length > 0) {
            //  Soltar lo elegido, que es para lo que se pulsa Escape. Solo se
            //  queda el evento si HAY algo que soltar: sin selección, Escape
            //  tiene que seguir llegando a quien cierra el editor.
            Editor.seleccionar("", 0)
        } else if ((ev.modifiers & Qt.ControlModifier) && ev.key === Qt.Key_C) {
            //  Copiar lo que esté elegido, sea de la fila que sea.
            Editor.copiarSeleccion()
        } else if ((ev.modifiers & Qt.ControlModifier) && ev.key === Qt.Key_V) {
            //  Y pegarlo DONDE ESTÉ EL CABEZAL, no donde estaba el original:
            //  la línea de tiempo es el sitio, y el cabezal es dónde miras.
            Editor.pegar(view.segundos)
        } else if ((ev.modifiers & Qt.ControlModifier) && ev.key === Qt.Key_X) {
            //  Cortar es copiar y quitar. Va aquí y no en el Editor porque
            //  «quitar lo elegido» ya vive en esta tecla de abajo.
            if (Editor.copiarSeleccion())
                view.borrarSeleccion()
        } else if (ev.key === Qt.Key_Delete || ev.key === Qt.Key_Backspace) {
            view.borrarSeleccion()
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
            //  «Audio» a secas no dice cuál, y con tres capas de audio en el
            //  montaje —el sistema, el micro y una locución— la cabecera era
            //  la misma para las tres. El nombre de verdad lo sabe el Editor.
            if (Editor.capaSel.tipo === "audio")
                return Editor.nombreCapa(Editor.capaSel)
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
                : Editor.capaSel.tipo === "audio"
                  //  Debajo, el fichero: el nombre ya está arriba, y de dos
                  //  capas que se llaman igual esto es lo que las separa.
                  ? Editor.capaSel.ruta.split("/").pop()
                    + "   ·   " + Editor.capaSel.t0.toFixed(1) + " s"
                  : Editor.capaSel.ruta.split("/").pop()
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

            //  El nombre del montaje, y se pulsa para cambiarlo.
            //
            //  Aquí salía el nombre del fichero de vídeo, que no se podía tocar
            //  y encima repetía lo que ya se ve en el reproductor. Ahora es cómo
            //  se llama el PROYECTO, que es lo que hay que poder decidir para
            //  luego encontrarlo.
            //
            //  El campo de texto está siempre —no es un `Loader`— y solo cambia
            //  si acepta el ratón: un `TextInput` que nace en el momento de
            //  pulsarlo no llega a tiempo de recibir ese mismo clic, y había que
            //  pulsar dos veces sin entender por qué.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                implicitHeight: 14

                TextInput {
                    id: nombrePlan
                    anchors.fill: parent
                    anchors.rightMargin: confirmarNombre.visible ? 20 : 0
                    cursorDelegate: IslandCursor {}
                    verticalAlignment: TextInput.AlignVCenter

                    //  Si lo has tocado, manda lo que hayas escrito; si no,
                    //  manda el Editor.
                    //
                    //  Aquí estaba el fallo por el que renombrar no hacía nada:
                    //  al perder el foco se reponía el texto viejo, y la
                    //  confirmación —que llega en ese mismo momento— acababa
                    //  pidiendo renombrar al nombre que ya tenía. O sea que se
                    //  pedía, se comparaba consigo mismo y no se hacía nada.
                    property bool tocado: false
                    text: Editor.nombreProyecto
                    onTextEdited: tocado = true

                    readonly property bool cambiado: tocado
                        && text.trim().length > 0
                        && text.trim() !== Editor.nombreProyecto

                    function confirmar() {
                        if (!cambiado) { descartar(); return }
                        tocado = false
                        Editor.renombrarProyecto(text)
                    }

                    function descartar() {
                        tocado = false
                        text = Editor.nombreProyecto
                    }

                    color: activeFocus ? Theme.ink : Theme.dim
                    font.pixelSize: 10
                    font.family: Theme.uiFont
                    selectByMouse: true
                    selectionColor: Theme.blue
                    clip: true
                    enabled: Editor.estado === "editando"

                    onAccepted: confirmar()
                    Keys.onEscapePressed: { descartar(); focus = false }
                    onActiveFocusChanged: if (!activeFocus) confirmar()

                    //  Y cuando el nombre cambia por fuera —renombrado, otro
                    //  montaje— se repone, salvo que estés escribiendo. Con un
                    //  enlace no bastaba: teclear lo rompe y ya no vuelve.
                    Connections {
                        target: Editor
                        function onNombreProyectoChanged() {
                            if (!nombrePlan.tocado)
                                nombrePlan.text = Editor.nombreProyecto
                        }
                    }

                    ToolTip.visible: hovered.hovered && !activeFocus
                    ToolTip.text: Idioma.t("Pulsa para ponerle nombre al montaje")
                    HoverHandler { id: hovered }
                }

                //  Y un botón para confirmarlo, que aparece solo si has
                //  cambiado algo.
                //
                //  No es un adorno: en este editor casi cada letra es un atajo
                //  —M marca, S corta, Espacio reproduce— y fiarlo todo a Intro y
                //  al foco deja el renombrado a merced de quién se quede la
                //  tecla. Con un botón, pulsarlo es pulsarlo.
                MediaButton {
                    id: confirmarNombre
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: nombrePlan.cambiado
                    glyph: String.fromCodePoint(0xF012C)   // md-check
                    glyphSize: 12
                    glyphColor: Theme.green
                    onActivated: nombrePlan.confirmar()
                }
            }

            //  Los gestos, en un sitio.
            //
            //  Los modos con botón —recorte, trazado— se ven en su ficha. Lo que
            //  no se ve por ningún lado son los GESTOS: doble clic en un rótulo
            //  para escribirlo encima del vídeo, Ctrl+rueda para acercar la
            //  línea, Ctrl+clic para coger varios, soltar ficheros. Cada uno se
            //  descubre por accidente o no se descubre, y una función que nadie
            //  encuentra es una función que no existe.
            MediaButton {
                glyph: String.fromCodePoint(0xF0625)   // md-help_circle_outline
                glyphSize: 13
                glyphColor: view.conAyuda ? Theme.blue : Theme.dim
                onActivated: view.conAyuda = !view.conAyuda
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
                //
                //  Más alto en ventana, y no menos: ahí el vídeo mide el doble
                //  de ancho, así que 180 px de alto ya no son una previa sino
                //  una rendija. El sitio para las bandas sale de reservar menos
                //  arriba —ver `altoParaLinea`—, no de aplastar la imagen.
                Layout.minimumHeight: view.enVentana ? 260 : 180
                radius: 8
                color: "black"
                clip: true

                //  Pinchar donde no hay nada suelta lo elegido.
                //
                //  Sin esto, en cuanto tocabas un trozo o una capa la ficha se
                //  quedaba con SUS opciones para siempre: no había forma de
                //  volver a las generales salvo abrir otra cosa. Va la primera
                //  —o sea, debajo de todo— así que solo recibe el clic que no
                //  ha querido nadie: las capas, el encuadre y el trazado de
                //  recorrido lo cogen antes.
                MouseArea {
                    anchors.fill: parent
                    onClicked: Editor.seleccionar("", 0)
                }

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
                    //  Y si no hay ninguno donde está el cabezal, dibujar uno.
                    //
                    //  Antes esto estaba apagado fuera de un momento, así que
                    //  crear un zoom obligaba a arrastrar en la línea de tiempo
                    //  y solo DESPUÉS venir aquí a apuntar: el cuándo en un sitio
                    //  y el dónde en otro, para decir una sola cosa. Ahora el
                    //  rectángulo dice las dos —dónde y cuánto— y el cuándo
                    //  empieza donde esté el cabezal.
                    MouseArea {
                        id: gesto
                        anchors.fill: parent

                        //  Si el cabezal cae dentro de un momento se ARRASTRA
                        //  ese; si no, se DIBUJA uno nuevo. Un mismo gesto con
                        //  dos significados según dónde estés, que es lo que ya
                        //  hace la propia línea de tiempo.
                        //  Con la herramienta armada se DIBUJA siempre, aunque
                        //  el cabezal caiga dentro de un zoom que ya existe.
                        //  Es el sentido de armarla: has dicho que vas a hacer
                        //  uno nuevo, así que arrastrar no puede significar
                        //  «mueve el de debajo».
                        readonly property bool sobreMomento:
                            Editor.herramienta !== "zoom"
                            && view.momento !== null
                            && view.segundos >= view.momento.t0
                            && view.segundos <= view.momento.t1

                        cursorShape: sobreMomento
                            ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                            : Qt.CrossCursor

                        property real xIni: 0
                        property real yIni: 0
                        property real cxIni: 0
                        property real cyIni: 0

                        //  El rectángulo que se está dibujando, en píxeles de
                        //  este marco.
                        property bool marcando: false
                        property real mx0: 0
                        property real my0: 0
                        property real mx1: 0
                        property real my1: 0

                        //  De píxeles del marco a píxeles del VÍDEO.
                        //
                        //  Hay que contar el encuadre actual: si ya estás con
                        //  zoom puesto, el punto de arriba a la izquierda del
                        //  marco no es el 0,0 del vídeo sino la esquina de la
                        //  ventana visible, que es lo que dice `estadoCamara`.
                        function aVideo(px, py) {
                            const f = lente.factor * lente.escala
                            return [view.estadoCamara[1] + px / f,
                                    view.estadoCamara[2] + py / f]
                        }

                        onPressed: function (ev) {
                            if (sobreMomento) {
                                marcando = false
                                xIni = ev.x; yIni = ev.y
                                cxIni = view.momento.cx
                                cyIni = view.momento.cy
                                return
                            }
                            marcando = true
                            mx0 = ev.x; my0 = ev.y
                            mx1 = ev.x; my1 = ev.y
                        }

                        onPositionChanged: function (ev) {
                            if (!pressed)
                                return
                            if (marcando) {
                                mx1 = ev.x; my1 = ev.y
                                return
                            }
                            if (!view.momento)
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

                        onReleased: {
                            if (!marcando) {
                                view.camaraForzada = null
                                return
                            }
                            marcando = false
                            //  Un rectángulo diminuto es un clic con pulso, no
                            //  una intención. Sin este mínimo, pinchar el vídeo
                            //  para nada creaba un zoom de ×40 en un píxel.
                            const an = Math.abs(mx1 - mx0)
                            const al = Math.abs(my1 - my0)
                            if (an < 16 || al < 16)
                                return
                            //  Usada es desarmada: dejarla puesta convertiría el
                            //  siguiente arrastre en otro zoom sin querer.
                            Editor.desarmar()
                            const a = aVideo(Math.min(mx0, mx1), Math.min(my0, my1))
                            const b = aVideo(Math.max(mx0, mx1), Math.max(my0, my1))
                            Editor.crearZoomEn(view.segundos,
                                               (a[0] + b[0]) / 2,
                                               (a[1] + b[1]) / 2,
                                               Editor.anchoVideo
                                                   / Math.max(1, b[0] - a[0]))
                        }

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

                    //  Que la herramienta está armada, dicho encima del vídeo.
                    //
                    //  Un modo que solo se nota porque el cursor cambió de
                    //  forma es un modo escondido, y un modo escondido acaba en
                    //  «¿por qué no puedo mover el encuadre?». El borde marca la
                    //  zona donde el gesto significa otra cosa, y el rótulo dice
                    //  cuál y cómo salirse.
                    Rectangle {
                        anchors.fill: parent
                        visible: Editor.herramienta === "zoom"
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.blue
                        radius: 8

                        //  Con fondo: el rótulo cae sobre el vídeo, y sobre un
                        //  fotograma claro el texto blanco no se lee.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            width: pista.implicitWidth + 18
                            height: 22
                            radius: 11
                            color: Theme.blue

                            IslandLabel {
                                id: pista
                                anchors.centerIn: parent
                                text: Idioma.t("Arrastra el zoom sobre el vídeo · Esc")
                                color: Theme.ink
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    //  Lo que estás dibujando, mientras lo dibujas.
                    //
                    //  Sin esto el gesto es a ciegas: sueltas y ya ves dónde ha
                    //  quedado el zoom. Va DESPUÉS del área para quedar por
                    //  encima, y no acepta el ratón —no es un control, es lo que
                    //  se está diciendo—.
                    Rectangle {
                        visible: gesto.marcando
                        x: Math.min(gesto.mx0, gesto.mx1)
                        y: Math.min(gesto.my0, gesto.my1)
                        width: Math.abs(gesto.mx1 - gesto.mx0)
                        height: Math.abs(gesto.my1 - gesto.my0)
                        color: Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, 0.14)
                        border.width: 1
                        border.color: Theme.blue
                        radius: 2

                        //  Cuánto zoom va a salir de este rectángulo, con las
                        //  mismas cuentas y los mismos topes que al soltar: si
                        //  el número dijera una cosa y el resultado otra, más
                        //  valdría no enseñarlo.
                        IslandLabel {
                            anchors.centerIn: parent
                            visible: parent.width > 52 && parent.height > 20
                            text: "×" + Math.max(1.1, Math.min(4,
                                     Editor.anchoVideo
                                     / Math.max(1, parent.width
                                                   / (lente.factor * lente.escala))
                                  )).toFixed(2)
                            color: Theme.ink
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
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

                    //  Y el sonido de las capas de audio.
                    //
                    //  Estaba escrito y declarado en `qmldir` desde hace tiempo,
                    //  pero NADIE LO INSTANCIABA: código muerto. No se notaba
                    //  porque el reproductor principal seguía sacando la pista
                    //  del vídeo —la Mezcla, las dos sumadas— y eso tapaba el
                    //  agujero: al separar el audio oías lo mismo de antes, solo
                    //  que venía del sitio equivocado. En cuanto el reproductor
                    //  empezó a callarse al separar, como debe, no quedó nadie
                    //  sonando y el editor se quedó mudo. Aquí está quien suena.
                    AudioExtra {
                        segundos: view.segundos
                        sonando: reproductor.reproduciendo
                        silenciado: view.silenciado
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
                ScrollBar.vertical: IslandScrollBar {}

                ColumnLayout {
                    id: fichaCol
                    width: ficha.width - 10
                    spacing: 6

                    //  Qué hay elegido.
                    //
                    //  Con dos pistas la ficha ya no puede ser siempre la del zoom:
                    //  si acabas de pinchar un trozo, lo que quieres saber es de
                    //  dónde sale y qué le puedes hacer.
                    //  El título de lo elegido, y la salida.
                    //
                    //  Elegir algo sustituye el panel de AÑADIR por el de lo
                    //  elegido, y hasta ahora la única forma de volver era
                    //  pulsar un hueco vacío de una banda. Eso ni se ve ni
                    //  siempre existe: si la fila está llena de bloques no hay
                    //  hueco que pulsar, y te quedabas sin poder añadir nada
                    //  hasta dar con el sitio bueno por casualidad.
                    //
                    //  Ahora la salida está escrita al lado del título, que es
                    //  donde uno mira cuando quiere deshacer lo que acaba de
                    //  hacer. Y con Escape, que es lo que se pulsa sin pensar.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        IslandLabel {
                            text: view.tituloSel
                            color: Theme.ink
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        //  Cuántas cosas hay cogidas, cuando hay más de una.
                        //  Sin esto, elegir tres y borrar es una sorpresa.
                        Rectangle {
                            visible: Editor.todoLoElegido.length > 1
                            Layout.preferredWidth: Math.max(14,
                                cuantas.implicitWidth + 10)
                            Layout.preferredHeight: 14
                            radius: 7
                            color: Theme.blue

                            IslandLabel {
                                id: cuantas
                                anchors.centerIn: parent
                                text: String(Editor.todoLoElegido.length)
                                color: Theme.islandBg
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }
                        }

                        MediaButton {
                            visible: Editor.tipoSel.length > 0
                            glyph: String.fromCodePoint(0xF0156)  // md-close
                            glyphSize: 13
                            glyphColor: Theme.muted
                            onActivated: Editor.seleccionar("", 0)
                        }
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

                    //  ── lo general, solo cuando no hay nada elegido ──
                    //
                    //  Los fundidos son de la LÍNEA entera, la transcripción es
                    //  del vídeo y las pistas son del fichero: ninguna de las
                    //  tres tiene que ver con el trozo o la capa que acabas de
                    //  pinchar. Salían siempre debajo de las opciones de lo
                    //  elegido, y lo que hacían era alargar la ficha y confundir
                    //  sobre a qué se refiere cada cosa.
                    FichaFundidos { visible: Editor.tipoSel === "" }

                    FichaTranscripcion {
                        view: view
                        visible: Editor.tipoSel === ""
                    }

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
                    FichaPistas {
                        reproductor: reproductor
                        //  Las dos condiciones juntas: poner `visible` desde
                        //  aquí PISA la que la ficha trae dentro —«solo si hay
                        //  pistas»—, y sin ella se quedaba un hueco con título
                        //  y nada debajo cuando el vídeo no tiene sonido.
                        visible: Editor.tipoSel === "" && Editor.pistasAudio.length > 0
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
            ScrollBar.vertical: IslandScrollBar {}

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
                //  `m:ss.ff`, con el fotograma. Con décimas no se puede decir en
                //  qué fotograma estás, que es lo que hace falta saber justo
                //  cuando afinas un corte.
                text: Editor.reloj(view.segundos) + " / " + Editor.reloj(view.total)
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

    // ── al cerrar, si has tocado algo ─────────────────────────────
    //
    //  No es «¿guardar?» porque el editor guarda solo mientras trabajas: lo
    //  que se ofrece aquí es lo contrario, poder tirar la sesión entera y
    //  dejar el proyecto como estaba al abrirlo. Por eso lo dice tal cual, en
    //  vez de preguntar algo que ya está hecho.
    Rectangle {
        id: aviso
        z: 100
        visible: view.plugin.preguntandoCierre
        anchors.fill: parent
        color: "#cc000000"

        //  Se traga los clics: con el editor detrás, pulsar «renderizar» sin
        //  querer mientras hay una pregunta encima es de las cosas que peor
        //  sientan.
        MouseArea {
            anchors.fill: parent
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(360, parent.width - 40)
            height: cuerpoAviso.implicitHeight + 28
            radius: 12
            color: Theme.surface
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            ColumnLayout {
                id: cuerpoAviso
                anchors.centerIn: parent
                width: parent.width - 28
                spacing: 8

                IslandLabel {
                    text: Idioma.t("Cerrar el proyecto")
                    color: Theme.ink
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                IslandLabel {
                    Layout.fillWidth: true
                    text: Idioma.f(
                        Idioma.t("Lo editado se guarda solo en %1. Puedes cerrarlo así o deshacer todo lo de esta sesión."),
                        Editor.rutaPlan.split("/").pop())
                    color: Theme.muted
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }

                BotonAccion {
                    texto: Idioma.t("Guardar y cerrar")
                    icono: 0xF0193                      // md-content_save
                    activo: true
                    onPulsado: view.plugin.cerrarProyecto()
                }

                BotonAccion {
                    texto: Idioma.t("Deshacer los cambios de esta sesión")
                    icono: 0xF054C                      // md-undo
                    peligro: true
                    onPulsado: view.plugin.cerrarDescartando()
                }

                BotonAccion {
                    texto: Idioma.t("Seguir editando")
                    icono: 0xF0156                      // md-close
                    onPulsado: view.plugin.preguntandoCierre = false
                }
            }
        }
    }

    //  La chuleta, encima de todo.
    //
    //  Declarada la última para quedar por encima, y con su propio MouseArea que
    //  se lo come todo: mientras está abierta no se edita por debajo sin querer.
    //  Se cierra pulsando en cualquier sitio, que es lo que uno hace.
    Rectangle {
        anchors.fill: parent
        visible: view.conAyuda
        color: Qt.rgba(0, 0, 0, 0.82)
        radius: 10
        z: 100

        MouseArea {
            anchors.fill: parent
            onClicked: view.conAyuda = false
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 520)
            spacing: 3

            IslandLabel {
                Layout.bottomMargin: 6
                text: Idioma.t("Gestos y atajos")
                color: Theme.ink
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Repeater {
                model: view.gestos
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10

                    IslandLabel {
                        Layout.preferredWidth: 190
                        text: modelData[0]
                        color: Theme.yellow
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    IslandLabel {
                        Layout.fillWidth: true
                        text: modelData[1]
                        color: Theme.muted
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }

            IslandLabel {
                Layout.topMargin: 8
                text: Idioma.t("Pulsa en cualquier sitio para cerrar")
                color: Theme.dim
                font.pixelSize: 10
            }
        }
    }
}
