//  Lo que se le hace a una capa: la sección más larga de la ficha del editor,
//  ahora con nombre propio.
//
//  Mover y escalar se hacen encima del vídeo con el ratón, y su tramo se
//  estira en la línea de tiempo. Aquí queda lo que no tiene un gesto natural:
//  el recorte, el croma, el modo de una zona, el inspector numérico, el texto
//  de un rótulo y la barra que gradúa lo suyo de cada tipo.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: fichaCapa

    required property var view

    //  La barra vale para varias cosas y cada una tiene su tope: la opacidad y
    //  el fondo llegan a 1 y el volumen a 2, porque subir la música al doble
    //  es lo que hace falta cuando viene baja.
    readonly property real topeBarra: Editor.capaSel
        && Editor.capaSel.tipo === "audio" ? 2 : 1

    readonly property real valorBarra: {
        const c = Editor.capaSel
        if (!c) return 1
        if (c.tipo === "texto") return c.fondo !== undefined ? c.fondo : 0.5
        if (c.tipo === "audio") return c.volumen !== undefined ? c.volumen : 0.8
        //  La fuerza es 0-1 en el plan y cada modo la traduce a lo suyo en
        //  python: sigma para el desenfoque, tamaño de bloque para el pixelado
        //  y cuánto oscurece para el foco. Así el panel enseña UN control y
        //  cambiar de modo no obliga a volver a ajustarlo.
        if (c.tipo === "zona") return c.fuerza !== undefined ? c.fuerza : 0.6
        return c.opacidad !== undefined ? c.opacidad : 1
    }

    visible: Editor.capaSel !== null
    Layout.fillWidth: true
    Layout.topMargin: 6
    spacing: 4

    Rectangle {
        visible: Editor.capaSel
            && Editor.capaSel.tipo === "video"
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: 13
        color: Editor.recortandoCapa ? Theme.blue
             : recorteRaton.containsMouse
               ? Theme.surfaceHi : Theme.surface
        border.width: 1
        border.color: Editor.recortandoCapa
            ? Theme.blue : Qt.rgba(1, 1, 1, 0.1)

        RowLayout {
            anchors.centerIn: parent
            spacing: 5

            IconGlyph {
                text: String.fromCodePoint(0xF019E) // md-crop
                color: Editor.recortandoCapa ? "#ffffff"
                                              : Theme.muted
                font.pixelSize: 12
            }

            IslandLabel {
                text: Editor.recortandoCapa
                    ? Idioma.t("Dibuja el recorte en el vídeo")
                    : Idioma.t("Recortar vídeo")
                color: Editor.recortandoCapa ? "#ffffff"
                                              : Theme.muted
                font.pixelSize: 10
            }
        }

        MouseArea {
            id: recorteRaton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Editor.alternarRecorte()
        }
    }

    //  Quitar el fondo verde de un vídeo encima.
    //
    //  La previa no lo enseña: `VideoOutput` no sabe hacer un
    //  croma. Lo dice el propio botón y para verlo está
    //  «previa exacta».
    Rectangle {
        readonly property bool puesto: Editor.capaSel
            && Editor.capaSel.croma
            && Editor.capaSel.croma.color

        visible: Editor.capaSel && Editor.capaSel.tipo === "video"
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 26 : 0
        radius: 13
        color: puesto ? Theme.green
             : cromaRaton.containsMouse ? Theme.surfaceHi
                                        : Theme.surface

        RowLayout {
            anchors.centerIn: parent
            spacing: 5

            IconGlyph {
                text: String.fromCodePoint(0xF00E3)   // md-brush
                color: parent.parent.puesto ? "#ffffff" : Theme.muted
                font.pixelSize: 12
            }

            IslandLabel {
                text: parent.parent.puesto
                    ? Idioma.t("Fondo verde quitado (al renderizar)")
                    : Idioma.t("Quitar el fondo verde")
                color: parent.parent.puesto ? "#ffffff" : Theme.muted
                font.pixelSize: 10
            }
        }

        MouseArea {
            id: cromaRaton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Editor.alternarCroma(Editor.idSel)
        }
    }

    //  Qué le hace la zona a lo que hay debajo.
    //
    //  Los tres modos son la misma capa: cambiar de uno a otro
    //  conserva el sitio, el tamaño y la ventana de tiempo, que
    //  es lo que cuesta colocar.
    IslandLabel {
        visible: Editor.capaSel && Editor.capaSel.tipo === "zona"
        text: Idioma.t("Qué hace")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    RowLayout {
        visible: Editor.capaSel && Editor.capaSel.tipo === "zona"
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: [
                { id: "desenfoque", nombre: Idioma.t("Difuminar"),
                  icono: 0xF00B5 },                    // md-blur
                { id: "pixelado", nombre: Idioma.t("Pixelar"),
                  icono: 0xF00B6 },                    // md-blur_linear
                { id: "foco", nombre: Idioma.t("Foco"),
                  icono: 0xF04C9 }                     // md-spotlight_beam
            ]

            delegate: Rectangle {
                id: chipModo
                required property var modelData

                readonly property bool puesto: Editor.capaSel
                    && (Editor.capaSel.modo || "desenfoque")
                       === chipModo.modelData.id

                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: 13
                color: chipModo.puesto ? Theme.blue
                     : modoRaton.containsMouse ? Theme.surfaceHi
                                               : Theme.surface

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0

                    IconGlyph {
                        Layout.alignment: Qt.AlignHCenter
                        text: String.fromCodePoint(
                            chipModo.modelData.icono)
                        color: chipModo.puesto ? "#ffffff"
                                               : Theme.muted
                        font.pixelSize: 13
                    }
                }

                MouseArea {
                    id: modoRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Editor.fijarCapa(Editor.idSel,
                        { modo: chipModo.modelData.id })
                }
            }
        }
    }

    //  Con qué entra y con qué sale la capa.
    //
    //  Solo lo que se ve: el sonido tendrá sus propios fundidos y una zona
    //  no «entra», tapa. Los dos tipos funden; «deslizar» además llega
    //  subiendo desde abajo, que es lo que hace un tercio inferior.
    Repeater {
        model: Editor.capaSel && (Editor.capaSel.tipo === "imagen"
                                  || Editor.capaSel.tipo === "texto"
                                  || Editor.capaSel.tipo === "video")
            ? [{ cual: "entrada", nombre: Idioma.t("Entrada"),
                 aparecer: Idioma.t("Aparecer") },
               { cual: "salida", nombre: Idioma.t("Salida"),
                 aparecer: Idioma.t("Desvanecer") }]
            : []

        delegate: ColumnLayout {
            id: filaEfecto
            required property var modelData

            readonly property var puesto: Editor.capaSel
                ? Editor.capaSel[filaEfecto.modelData.cual] : null
            readonly property string tipoPuesto:
                puesto && puesto.tipo ? puesto.tipo : ""

            Layout.fillWidth: true
            spacing: 3

            IslandLabel {
                text: filaEfecto.modelData.nombre
                color: Theme.dim
                font.pixelSize: 9
                font.capitalization: Font.AllUppercase
                font.weight: Font.DemiBold
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 3

                Repeater {
                    model: [
                        { id: "", nombre: Idioma.t("Nada") },
                        { id: "desvanecer",
                          nombre: filaEfecto.modelData.aparecer },
                        { id: "deslizar", nombre: Idioma.t("Deslizar") }
                    ]

                    delegate: Rectangle {
                        id: chipEfecto
                        required property var modelData

                        readonly property bool puesta:
                            filaEfecto.tipoPuesto === chipEfecto.modelData.id

                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        radius: 12
                        color: chipEfecto.puesta ? Theme.blue
                             : efectoRaton.containsMouse ? Theme.surfaceHi
                                                         : Theme.surface

                        IslandLabel {
                            anchors.centerIn: parent
                            text: chipEfecto.modelData.nombre
                            color: chipEfecto.puesta ? "#ffffff" : Theme.muted
                            font.pixelSize: 10
                            font.weight: chipEfecto.puesta ? Font.DemiBold
                                                           : Font.Normal
                        }

                        MouseArea {
                            id: efectoRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Editor.fijarEfecto(Editor.idSel,
                                filaEfecto.modelData.cual,
                                chipEfecto.modelData.id,
                                filaEfecto.puesto ? filaEfecto.puesto.dur : 0.4)
                        }
                    }
                }
            }

            //  Cuánto dura la rampa. El tope de verdad lo pone la ventana de
            //  la capa —media, como en el render—; la barra ofrece hasta 1,5 s.
            RowLayout {
                visible: filaEfecto.tipoPuesto.length > 0
                Layout.fillWidth: true
                spacing: 6

                readonly property real valor: filaEfecto.puesto
                    ? Number(filaEfecto.puesto.dur) || 0.4 : 0.4

                IslandLabel {
                    Layout.preferredWidth: 58
                    text: Idioma.t("Duración")
                    color: Theme.muted
                    font.pixelSize: 9
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    radius: 2
                    color: Theme.track

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1,
                            (parent.parent.valor - 0.1) / 1.4))
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
                            const u = Math.max(0, Math.min(1,
                                x / Math.max(1, width)))
                            Editor.fijarEfecto(Editor.idSel,
                                filaEfecto.modelData.cual,
                                filaEfecto.tipoPuesto,
                                Math.round((0.1 + u * 1.4) * 20) / 20)
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
                    text: parent.valor.toFixed(2) + " s"
                    color: Theme.dim
                    font.pixelSize: 9
                }
            }
        }
    }

    //  La música que se agacha: cuando hay voz en el vídeo, esta capa baja
    //  sola y vuelve con calma. Solo para capas de audio, y solo se oye al
    //  renderizar: el reproductor de la previa no comprime.
    BotonAccion {
        visible: Editor.capaSel && Editor.capaSel.tipo === "audio"
        texto: Editor.capaSel && Editor.capaSel.agachar
            ? Idioma.t("Se agacha con la voz (al renderizar)")
            : Idioma.t("Agacharse con la voz")
        icono: 0xF0792                        // md-arrow_collapse_down
        activo: Editor.capaSel && !!Editor.capaSel.agachar
        onPulsado: Editor.fijarCapa(Editor.idSel,
            { agachar: !Editor.capaSel.agachar })
    }

    //  El Ken Burns: la foto quieta que respira. Zoom por dentro de la
    //  huella —la capa no cambia de tamaño— a lo largo de su ventana.
    IslandLabel {
        visible: Editor.capaSel && Editor.capaSel.tipo === "imagen"
        text: Idioma.t("Ken Burns")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    RowLayout {
        visible: Editor.capaSel && Editor.capaSel.tipo === "imagen"
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: [
                { id: "",        nombre: Idioma.t("Nada") },
                { id: "acercar", nombre: Idioma.t("Acercar") },
                { id: "alejar",  nombre: Idioma.t("Alejar") }
            ]

            delegate: Rectangle {
                id: chipKb
                required property var modelData

                readonly property var kb: Editor.capaSel
                    ? Editor.capaSel.kenburns : null
                readonly property string puestoId: !kb ? ""
                    : (Number(kb.hasta) > Number(kb.desde) ? "acercar"
                                                           : "alejar")
                readonly property bool puesta: puestoId === chipKb.modelData.id

                Layout.fillWidth: true
                Layout.preferredHeight: 24
                radius: 12
                color: chipKb.puesta ? Theme.blue
                     : kbRaton.containsMouse ? Theme.surfaceHi : Theme.surface

                IslandLabel {
                    anchors.centerIn: parent
                    text: chipKb.modelData.nombre
                    color: chipKb.puesta ? "#ffffff" : Theme.muted
                    font.pixelSize: 10
                    font.weight: chipKb.puesta ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: kbRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Editor.fijarCapa(Editor.idSel, {
                        kenburns: chipKb.modelData.id === "" ? null
                            : chipKb.modelData.id === "acercar"
                            ? { desde: 1.0, hasta: 1.25 }
                            : { desde: 1.25, hasta: 1.0 }
                    })
                }
            }
        }
    }

    //  Qué forma señala: los tres modos comparten sitio, tamaño, giro y
    //  ventana, así que cambiar de uno a otro no descoloca nada.
    IslandLabel {
        visible: Editor.capaSel && Editor.capaSel.tipo === "forma"
        text: Idioma.t("Qué forma")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    RowLayout {
        visible: Editor.capaSel && Editor.capaSel.tipo === "forma"
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: [
                { id: "flecha",  icono: 0xF09C6 },  // md-arrow_top_right_thick
                { id: "circulo", icono: 0xF0130 },  // md-checkbox_blank_circle_outline
                { id: "marco",   icono: 0xF01A2 }   // md-crop_square
            ]

            delegate: Rectangle {
                id: chipForma
                required property var modelData

                readonly property bool puesta: Editor.capaSel
                    && (Editor.capaSel.modo || "flecha")
                       === chipForma.modelData.id

                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: 13
                color: chipForma.puesta ? Theme.blue
                     : formaRaton.containsMouse ? Theme.surfaceHi
                                                : Theme.surface

                IconGlyph {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(chipForma.modelData.icono)
                    color: chipForma.puesta ? "#ffffff" : Theme.muted
                    font.pixelSize: 13
                }

                MouseArea {
                    id: formaRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Editor.fijarCapa(Editor.idSel,
                        { modo: chipForma.modelData.id })
                }
            }
        }
    }

    // Inspector numérico: permite repetir posiciones y
    // tamaños con precisión, sin depender del ratón.
    GridLayout {
        visible: Editor.capaSel !== null
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 4
        rowSpacing: 3

        Repeater {
            model: [
                { k: "x", n: "X", suf: "", dec: 3 },
                { k: "y", n: "Y", suf: "", dec: 3 },
                { k: "tamano", n: "Tamaño", suf: "", dec: 3 },
                { k: "rotacion", n: "Giro", suf: "°", dec: 1 },
                { k: "opacidad", n: "Opac.", suf: "", dec: 2 },
                { k: "t0", n: "Inicio", suf: " s", dec: 2 },
                { k: "t1", n: "Fin", suf: " s", dec: 2 }
            ]

            delegate: RowLayout {
                required property var modelData
                visible: Editor.capaSel !== null
                    && (Editor.capaSel.tipo !== "audio"
                        || modelData.k === "t0"
                        || modelData.k === "t1")
                Layout.fillWidth: true
                spacing: 3

                IslandLabel {
                    Layout.preferredWidth: 42
                    text: parent.modelData.n
                    color: Theme.muted
                    font.pixelSize: 9
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 25
                    radius: 6
                    color: Theme.surface
                    border.width: 1
                    border.color: inspectorCampo.activeFocus
                        ? Theme.blue : Qt.rgba(1, 1, 1, 0.1)

                    TextInput {
                        id: inspectorCampo
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 4
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.ink
                        font.pixelSize: 10
                        font.family: Theme.uiFont
                        selectByMouse: true
                        clip: true
                        //  Con el tipo delante, y no solo el id: un trozo y una
                        //  capa pueden compartir número, y al saltar de uno a
                        //  otra el campo se quedaba con los valores viejos.
                        property string deQuien: Editor.tipoSel + Editor.idSel
                        //  Por id y no por `capaSel`: este valor se lee DENTRO
                        //  de la cascada del cambio de selección, y ahí
                        //  `capaSel` puede devolver todavía su caché de antes
                        //  —el manejador corre antes de que la notificación
                        //  llegue al binding—. Con el id se va a la lista
                        //  directamente y siempre sale la capa recién elegida.
                        function valor() {
                            const c = Editor.tipoSel === "capa"
                                ? Editor.capaPorId(Editor.idSel) : null
                            if (!c) return 0
                            if (modelData.k === "tamano")
                                return c.tipo === "texto" ? c.tam
                                    : c.tipo === "zona" ? c.an
                                    : c.escala
                            return c[modelData.k] !== undefined
                                ? c[modelData.k] : 0
                        }
                        onDeQuienChanged: text = valor().toFixed(
                            modelData.dec)
                        Component.onCompleted: text = valor().toFixed(
                            modelData.dec)
                        onEditingFinished: {
                            if (!Editor.capaSel) return
                            let v = Number(text.replace(",", "."))
                            if (!isFinite(v)) { text = valor().toFixed(modelData.dec); return }
                            let campos = {}
                            if (modelData.k === "tamano") {
                                if (Editor.capaSel.tipo === "texto") campos.tam = Math.max(0.005, Math.min(0.4, v))
                                else if (Editor.capaSel.tipo === "zona") campos.an = Math.max(0.01, Math.min(1, v))
                                else campos.escala = Math.max(0.01, Math.min(2, v))
                            } else if (modelData.k === "rotacion") {
                                campos.rotacion = v
                            } else if (modelData.k === "t0" || modelData.k === "t1") {
                                const c = Editor.capaSel
                                const a = modelData.k === "t0" ? Math.max(0, Math.min(c.t1 - 0.05, v)) : c.t0
                                const b = modelData.k === "t1" ? Math.max(c.t0 + 0.05, Math.min(Editor.duracionLinea, v)) : c.t1
                                campos.t0 = a; campos.t1 = b
                            } else {
                                campos[modelData.k] = Math.max(0, Math.min(1, v))
                            }
                            Editor.ponerTransformacion(Editor.idSel, campos)
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        visible: Editor.capaSel !== null
        Layout.fillWidth: true
        spacing: 3
        BotonAccion {
            texto: Editor.capaSel && Editor.capaSel.visible === false
                ? Idioma.t("Mostrar") : Idioma.t("Ocultar")
            icono: Editor.capaSel && Editor.capaSel.visible === false
                ? 0xF0208 : 0xF0209
            onPulsado: Editor.alternarVisibilidadCapa(Editor.idSel)
        }
        BotonAccion {
            texto: Editor.capaSel && Editor.capaSel.bloqueada
                ? Idioma.t("Desbloquear") : Idioma.t("Bloquear")
            icono: Editor.capaSel && Editor.capaSel.bloqueada
                ? 0xF033E : 0xF033F
            onPulsado: Editor.alternarBloqueoCapa(Editor.idSel)
        }
    }

    BotonAccion {
        visible: Editor.capaSel !== null
            && Editor.capaSel.tipo !== "audio"
        texto: Idioma.t("Restablecer transformación")
        icono: 0xF0450
        onPulsado: {
            const c = Editor.capaSel
            const p = { x: 0.5, y: 0.5, rotacion: 0 }
            if (c.tipo === "texto") p.tam = 0.06
            else if (c.tipo === "zona") { p.an = 0.3; p.al = 0.25 }
            else p.escala = 0.3
            Editor.ponerTransformacion(Editor.idSel, p)
        }
    }

    //  El camino directo: pinchar el recorrido sobre el propio vídeo. Los
    //  tiempos se reparten solos —la velocidad la pone la distancia entre
    //  puntos— y se afinan con los rombos. Menos botones, más lienzo.
    BotonAccion {
        visible: Editor.capaSel !== null
            && (Editor.capaSel.tipo === "imagen"
                || Editor.capaSel.tipo === "texto"
                || Editor.capaSel.tipo === "video")
        texto: Editor.trazandoRuta
            ? Idioma.t("Pincha el recorrido · clic derecho termina")
            : Idioma.t("Trazar movimiento")
        icono: 0xF0561                        // md-vector_polyline
        activo: Editor.trazandoRuta
        onPulsado: Editor.alternarRuta()
    }

    BotonAccion {
        visible: Editor.capaSel !== null
            && Editor.capaSel.tipo !== "audio"
        texto: Idioma.t("Crear fotograma clave")
        icono: 0xF05A1
        onPulsado: Editor.crearKeyframe(Editor.idSel,
                                         fichaCapa.view.segundos)
    }

    //  Solo cuando hay claves: un interruptor de easing sin animación que
    //  suavizar es ruido. El movimiento suave es la smoothstep de siempre,
    //  por capa entera: mezclar estilos entre rombos no se puede leer.
    BotonAccion {
        readonly property bool hay: Editor.capaSel
            && (Editor.capaSel.keyframes || []).length > 1
        visible: hay
        texto: Editor.capaSel && Editor.capaSel.suave
            ? Idioma.t("Movimiento suave") : Idioma.t("Movimiento recto")
        //  Comprobado contra la propia fuente con fontTools, como manda la
        //  casa: 0xF0170 era md-code_not_equal.
        icono: 0xF0C50                        // md-chart_bell_curve
        activo: Editor.capaSel && !!Editor.capaSel.suave
        onPulsado: Editor.fijarCapa(Editor.idSel,
            { suave: !Editor.capaSel.suave })
    }

    IslandLabel {
        visible: Editor.capaSel
            && (Editor.capaSel.keyframes || []).length > 0
        Layout.fillWidth: true
        text: Idioma.t("los puntos del vídeo y los rombos del bloque se arrastran · clic derecho quita")
        color: Theme.dim
        font.pixelSize: 9
        wrapMode: Text.WordWrap
    }

    //  Lo que dice el rótulo.
    //
    //  Aquí y no editando encima del vídeo: sobre el vídeo el
    //  texto puede ser diminuto o quedar sobre algo del mismo
    //  color, y escribir a ciegas en un sitio así no es escribir.
    IslandLabel {
        visible: Editor.capaSel && Editor.capaSel.tipo === "texto"
        text: Idioma.t("Texto")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    Rectangle {
        visible: Editor.capaSel && Editor.capaSel.tipo === "texto"
        Layout.fillWidth: true
        Layout.preferredHeight: 30
        radius: 8
        color: Theme.surface
        border.width: 1
        border.color: campoTexto.activeFocus
            ? Theme.blue : Qt.rgba(1, 1, 1, 0.1)

        TextInput {
            id: campoTexto
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.ink
            font.pixelSize: 12
            font.family: Theme.uiFont
            selectByMouse: true
            selectionColor: Theme.blue
            clip: true

            //  El texto se lee del plan y se escribe al plan, sin
            //  copia intermedia: `text` se ata a la capa elegida
            //  y cada tecla la guarda con el rebote de siempre.
            //  Reasignarlo desde fuera mientras escribes movería
            //  el cursor al final, así que solo se relee cuando
            //  cambia de capa. El tipo va delante por lo mismo que
            //  en el inspector: un trozo puede compartir id. Y por
            //  id y no por `capaSel`, que dentro de la cascada del
            //  cambio aún puede traer la capa de antes.
            property string deQuien: Editor.tipoSel + Editor.idSel
            function releer() {
                const c = Editor.tipoSel === "capa"
                    ? Editor.capaPorId(Editor.idSel) : null
                text = c ? (c.texto || "") : ""
            }
            onDeQuienChanged: releer()
            Component.onCompleted: releer()

            onTextEdited: Editor.fijarCapa(Editor.idSel,
                                           { texto: text })
        }
    }

    //  El estilo del rótulo: la caja de siempre, contorno, sombra o limpio.
    //  `colorFondo` es el color secundario del estilo que toque, y por eso la
    //  segunda fila de colores vale para los tres.
    IslandLabel {
        visible: Editor.capaSel && Editor.capaSel.tipo === "texto"
        text: Idioma.t("Estilo")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    RowLayout {
        visible: Editor.capaSel && Editor.capaSel.tipo === "texto"
        Layout.fillWidth: true
        spacing: 3

        readonly property string puesto: {
            const c = Editor.capaSel
            if (!c) return ""
            const e = c.estilo || ""
            if (e.length > 0) return e
            return (c.fondo || 0) > 0.001 ? "caja" : "limpio"
        }

        Repeater {
            model: [
                { id: "caja",     nombre: Idioma.t("Caja") },
                { id: "contorno", nombre: Idioma.t("Contorno") },
                { id: "sombra",   nombre: Idioma.t("Sombra") },
                { id: "limpio",   nombre: Idioma.t("Limpio") }
            ]

            delegate: Rectangle {
                id: chipEstilo
                required property var modelData

                readonly property bool puesta:
                    parent.puesto === chipEstilo.modelData.id

                Layout.fillWidth: true
                Layout.preferredHeight: 24
                radius: 12
                color: chipEstilo.puesta ? Theme.blue
                     : estiloRaton.containsMouse ? Theme.surfaceHi
                                                 : Theme.surface

                IslandLabel {
                    anchors.centerIn: parent
                    text: chipEstilo.modelData.nombre
                    color: chipEstilo.puesta ? "#ffffff" : Theme.muted
                    font.pixelSize: 9
                    font.weight: chipEstilo.puesta ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: estiloRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Editor.fijarCapa(Editor.idSel,
                        { estilo: chipEstilo.modelData.id })
                }
            }
        }
    }

    //  Los colores, en dos filas de muestras: el del texto y el del estilo
    //  —la caja, el trazo o la sombra—. Pocas y buenas: para un rótulo de
    //  vídeo, seis colores bien elegidos rinden más que una rueda entera.
    Repeater {
        model: Editor.capaSel && Editor.capaSel.tipo === "texto"
            ? [{ campo: "color", nombre: Idioma.t("Color del texto") },
               { campo: "colorFondo", nombre: Idioma.t("Color del estilo") }]
            : Editor.capaSel && Editor.capaSel.tipo === "forma"
            ? [{ campo: "color", nombre: Idioma.t("Color") }]
            : []

        delegate: ColumnLayout {
            id: filaColorTexto
            required property var modelData

            Layout.fillWidth: true
            spacing: 3

            IslandLabel {
                text: filaColorTexto.modelData.nombre
                color: Theme.dim
                font.pixelSize: 9
                font.capitalization: Font.AllUppercase
                font.weight: Font.DemiBold
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: ["#ffffff", "#000000", "#ffd60a",
                            "#ff453a", "#32d74b", "#0a84ff"]

                    delegate: Rectangle {
                        id: muestra
                        required property var modelData

                        readonly property bool puesta: Editor.capaSel
                            && String(Editor.capaSel[filaColorTexto.modelData.campo]
                                      || (filaColorTexto.modelData.campo === "color"
                                          ? "#ffffff" : "#000000")).toLowerCase()
                               === muestra.modelData

                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        radius: 11
                        color: muestra.modelData
                        border.width: puesta ? 2 : 1
                        border.color: puesta ? Theme.blue
                                             : Qt.rgba(1, 1, 1, 0.25)

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const campos = {}
                                campos[filaColorTexto.modelData.campo] =
                                    muestra.modelData
                                Editor.fijarCapa(Editor.idSel, campos)
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    IslandLabel {
        text: {
            if (!Editor.capaSel) return Idioma.t("Opacidad")
            if (Editor.capaSel.tipo === "texto") return Idioma.t("Fondo")
            if (Editor.capaSel.tipo === "audio") return Idioma.t("Volumen")
            if (Editor.capaSel.tipo === "zona") return Idioma.t("Fuerza")
            return Idioma.t("Opacidad")
        }
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
                //  El volumen llega a 2 y las opacidades a 1, así
                //  que la barra se normaliza por su tope: subir el
                //  doble es lo que hace falta cuando la música
                //  viene baja.
                width: parent.width * Math.min(1,
                    fichaCapa.valorBarra / fichaCapa.topeBarra)
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
                    const v = Math.max(0, Math.min(fichaCapa.topeBarra,
                        x / Math.max(1, width) * fichaCapa.topeBarra))
                    const q = Math.round(v * 20) / 20
                    //  En un rótulo lo que se gradúa es la caja
                    //  de detrás: el texto en sí translúcido no
                    //  se lee, y bajarle la opacidad es lo que
                    //  uno quiere para que no tape el vídeo.
                    if (!Editor.capaSel) return
                    if (Editor.capaSel.tipo === "texto")
                        Editor.fijarCapa(Editor.idSel, { fondo: q })
                    else if (Editor.capaSel.tipo === "audio")
                        Editor.fijarCapa(Editor.idSel, { volumen: q })
                    else if (Editor.capaSel.tipo === "zona")
                        Editor.fijarCapa(Editor.idSel, { fuerza: q })
                    else
                        Editor.fijarCapa(Editor.idSel, { opacidad: q })
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
            text: Math.round(fichaCapa.valorBarra * 100) + "%"
            color: Theme.dim
            font.pixelSize: 9
        }
    }

    //  Sin botones de subir y bajar.
    //
    //  Los había, y sobraban en cuanto el bloque de la línea de
    //  tiempo se pudo arrastrar de una fila a otra: el gesto de
    //  coger algo y llevarlo a la capa de arriba se entiende sin
    //  leer nada, y dos formas de hacer lo mismo son una de más.
    //
    //  Lo que sí hace falta es SABER en qué capa está, porque
    //  arrastrando no siempre se ve dónde ha caído.
    IslandLabel {
        Layout.topMargin: 4
        visible: Editor.capaSel !== null
        text: Idioma.f(Idioma.t("Capa %1 de %2"),
                       String(Editor.capaSel
                              ? Editor.bandaDe(Editor.capaSel) : 1),
                       String(Editor.cuantasBandas))
             + "  ·  " + Idioma.t("arrastra el bloque para cambiarla")
        color: Theme.dim
        font.pixelSize: 9
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
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
                text: {
                    if (!Editor.capaSel) return Idioma.t("Quitar")
                    if (Editor.capaSel.tipo === "texto")
                        return Idioma.t("Quitar el rótulo")
                    if (Editor.capaSel.tipo === "audio")
                        return Idioma.t("Quitar el audio")
                    if (Editor.capaSel.tipo === "video")
                        return Idioma.t("Quitar el vídeo")
                    if (Editor.capaSel.tipo === "forma")
                        return Idioma.t("Quitar la forma")
                    return Idioma.t("Quitar la imagen")
                }
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
