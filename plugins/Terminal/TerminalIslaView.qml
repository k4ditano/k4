//  La terminal dentro de la island.
//
//  Aquí no se emula nada: lo que se pinta es la rejilla que manda
//  k4term-isla, ya resuelta por el VT de ghostty, y lo que se teclea se le
//  devuelve tal cual. La vista es una ventana a una sesión que vive fuera —
//  por eso cerrarla no para nada y volver a abrirla te deja donde estabas.
//
//  Del teclado: mientras está abierta se lo queda entero, como el lanzador o
//  la pregunta a la IA. Pero ESC NO cierra —va a la terminal—, y ahí se rompe
//  la convención de la casa a propósito: ESC es la tecla de cancelar de
//  claude, de codex y de vim, y quedárnosla dejaba a esos programas sin
//  ninguna forma de recibirla. Para esconder la vista está el botón de la
//  cabecera y la misma tecla que la abrió.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: vista

    //  Recortado, que ahora hace falta: el contenido va al tamaño de destino
    //  desde el primer momento y la caja llega detrás, así que mientras crece
    //  hay filas de más que no deben salirse por abajo.
    clip: true

    required property var plugin

    readonly property var marco: plugin.marco

    //  La misma fuente que la terminal de ventana: es monoespaciada de
    //  verdad, así que el ancho de celda sale de medir una eme.
    //
    //  Medida la mide el plugin, no esta vista, aunque la use ella para todo:
    //  con ella decide él el alto de la island y con ella se calcula aquí
    //  cuántas filas caben, y esos dos números TIENEN que salir del mismo
    //  sitio. Cuando no lo hacían —18 allí, 17 aquí— la island pedía una fila
    //  más de las que tenía y no volvía a crecer nunca.
    readonly property int cuerpo: plugin.cuerpo
    readonly property real anchoCelda: plugin.anchoCelda
    readonly property real altoLinea: plugin.altoLinea
    readonly property int margen: 14

    //  La casa con virgulilla y sin más de tres tramos: en un pie de diez
    //  píxeles, una ruta entera no se lee, se estorba.
    function corto(ruta) {
        const casa = String(ruta).replace(/^\/home\/[^/]+/, "~")
        const partes = casa.split("/").filter(function (x) { return x.length > 0 })
        if (partes.length <= 3)
            return casa
        return (casa.charAt(0) === "~" ? "" : "…/") + partes.slice(-3).join("/")
    }

    //  Cuántas columnas y filas se le piden a la sesión, que es quien
    //  redimensiona el PTY: la shell tiene que saber su ancho o parte las
    //  líneas donde no toca.
    //
    //  Las filas son el DESTINO de la island, no las que caben en el alto de
    //  ahora mismo. La diferencia se veía: como el alto va animado, pedirlas
    //  según el alto actual hacía que el PTY se redimensionara a cachos
    //  persiguiendo a la animación, y el texto llegaba tarde y a trompicones —
    //  primero se movía la caja y después el contenido, o al revés. Pidiendo
    //  el destino desde el primer instante, el contenido ya está donde va a
    //  estar y la caja se limita a descubrirlo.
    readonly property int cols: Math.max(20, Math.floor((width - margen * 2) / anchoCelda))
    readonly property int filas: Math.max(4, plugin.filasDeseadas)

    //  Dónde estás dentro del historial, tal cual lo cuenta la sesión: la fila
    //  por la que empieza lo que se ve y cuántas hay en total.
    readonly property int arriba: marco ? marco.scroll[0] : 0
    readonly property int historial: marco ? Math.max(1, marco.scroll[1]) : 1
    readonly property real recorrido: Math.min(1, (marco ? marco.filas_n : filas) / historial)
    readonly property real asomado: arriba / historial

    //  ── de píxeles a celdas ───────────────────────────────────────
    //
    //  Todo lo que hace el ratón pasa por aquí, y por eso está en un sitio: la
    //  rejilla se pinta anclando cada tramo a `(columna - 1) * anchoCelda`, así
    //  que leerla al revés tiene que hacer la misma cuenta o el clic caería una
    //  celda a la izquierda de donde se ve.
    function colDe(x) {
        return Math.max(1, Math.min(cols, Math.floor((x - margen) / anchoCelda) + 1))
    }

    function filaDe(y) {
        const n = marco ? marco.filas_n : filas
        return Math.max(1, Math.min(n, Math.floor((y - margen - altoCabecera) / altoLinea) + 1))
    }

    //  La fila del HISTORIAL a la que corresponde una de la rejilla. Todo lo
    //  que se guarda —la selección, las marcas— va en estas coordenadas: son
    //  las únicas que no se mueven cuando sigue saliendo salida.
    //
    //  Y no es una resta: con salidas recogidas, la rejilla ya no es un calco
    //  del hueco visible —una fila puede valer por cincuenta—, así que la
    //  correspondencia la manda la sesión, que es quien pliega.
    function absoluta(filaVista) {
        if (marco && marco.filas_abs && filaVista >= 1 && filaVista <= marco.filas_abs.length)
            return marco.filas_abs[filaVista - 1]
        return arriba + filaVista - 1
    }

    //  Al revés: en qué fila de la rejilla ha caído una del historial, o -1 si
    //  ahora mismo no se ve (está recogida, o fuera de la pantalla).
    function enRejilla(filaAbs) {
        if (!marco || !marco.filas_abs)
            return filaAbs - arriba
        for (let i = 0; i < marco.filas_abs.length; ++i)
            if (marco.filas_abs[i] === filaAbs)
                return i
        return -1
    }

    //  ¿Esa fila de la rejilla es la línea de una salida recogida?
    function esResumen(i) {
        return !!(marco && marco.resumidas && marco.resumidas.indexOf(i) >= 0)
    }

    //  Recoger o desplegar la salida de un mandato. Se nombra por la fila del
    //  historial donde empieza: los índices de la rejilla cambian en cuanto
    //  sale una línea más.
    function plegar(filaAbs) {
        if (filaAbs !== undefined && filaAbs >= 0)
            plugin.mandar({ que: "plegar", fila: filaAbs })
    }

    function plegarUltimo() {
        if (ultimoBloque && ultimoBloque.fin > ultimoBloque.fila)
            plegar(ultimoBloque.fila)
    }

    //  Una fila de la rejilla como texto, rellenando con espacios los huecos
    //  entre tramos: los tramos vienen con su columna, y sin el relleno las
    //  posiciones no cuadrarían con lo que se ve.
    function textoFila(i) {
        if (!marco || i < 0 || i >= marco.filas.length)
            return ""
        const tramos = marco.filas[i]
        let linea = ""
        for (let k = 0; k < tramos.length; ++k) {
            while (linea.length < tramos[k].c - 1)
                linea += " "
            linea += tramos[k].t
        }
        return linea
    }

    //  ── la selección ──────────────────────────────────────────────
    //
    //  Dos puntas en coordenadas del historial. Se guardan tal cual se
    //  pinchan, sin ordenar: hacia dónde vas es asunto de quien arrastra, y
    //  ordenarlas al vuelo es más barato que mantenerlas ordenadas.
    property var selA: null
    property var selB: null
    readonly property bool haySeleccion: selA !== null && selB !== null

    function ordenada() {
        if (!haySeleccion)
            return null
        const antes = selA.fila < selB.fila
                   || (selA.fila === selB.fila && selA.col <= selB.col)
        return antes ? { desde: selA, hasta: selB } : { desde: selB, hasta: selA }
    }

    function limpiarSeleccion() { selA = null; selB = null }

    //  Qué trozo de la fila `i` de la rejilla está seleccionado, o nada.
    function tramoSeleccion(i) {
        const s = ordenada()
        if (!s)
            return null
        const abs = absoluta(i + 1)
        if (abs < s.desde.fila || abs > s.hasta.fila)
            return null
        const a = abs === s.desde.fila ? s.desde.col : 1
        const b = abs === s.hasta.fila ? s.hasta.col : cols
        return b >= a ? { a: a, b: b } : null
    }

    //  El texto lo compone la SESIÓN, que es quien tiene el historial: la
    //  rejilla solo sabe de lo que se ve, y una selección puede empezar más
    //  arriba de lo que hay en pantalla.
    function copiarSeleccion(motivo) {
        const s = ordenada()
        if (!s)
            return false
        plugin.mandar({ que: "texto_de",
                        desde: s.desde.fila, hasta: s.hasta.fila,
                        col_desde: s.desde.col, col_hasta: s.hasta.col,
                        motivo: motivo || "copiar" })
        return true
    }

    function seleccionarTodo() {
        selA = { fila: absoluta(1), col: 1 }
        selB = { fila: absoluta(marco ? marco.filas_n : filas), col: cols }
    }

    //  Doble clic: la palabra de debajo. «Palabra» es lo que no es espacio ni
    //  comilla — en una terminal lo que uno quiere coger casi siempre es una
    //  ruta, un hash o una URL, y partirlos por los puntos o las barras sería
    //  justo lo contrario de lo que se busca.
    function palabraEn(filaVista, col) {
        const linea = textoFila(filaVista - 1)
        if (col > linea.length)
            return null
        const corte = /[\s"'`]/
        if (corte.test(linea.charAt(col - 1)))
            return null
        let a = col, b = col
        while (a > 1 && !corte.test(linea.charAt(a - 2)))
            --a
        while (b < linea.length && !corte.test(linea.charAt(b)))
            ++b
        return { a: a, b: b }
    }

    //  Un enlace bajo esa celda, si lo hay.
    //
    //  Primero el de verdad: el de OSC 8, que la aplicación escondió detrás
    //  del texto y viaja en el tramo. Si no lo hay, se adivina mirando si algo
    //  parece una dirección, que es lo que salva a `ls` y a los mensajes de
    //  error de toda la vida.
    function urlEn(filaVista, col) {
        const tramos = marco && marco.filas[filaVista - 1] ? marco.filas[filaVista - 1] : []
        for (let k = 0; k < tramos.length; ++k) {
            const tr = tramos[k]
            if (tr.u && col >= tr.c && col < tr.c + tr.t.length)
                return tr.u
        }

        const linea = textoFila(filaVista - 1)
        const patron = /(https?:\/\/|www\.)[^\s"'`<>()\[\]]+/g
        let m
        while ((m = patron.exec(linea)) !== null) {
            const a = m.index + 1
            const b = m.index + m[0].length
            if (col >= a && col <= b)
                return m[0]
        }
        return ""
    }

    //  ── buscar ────────────────────────────────────────────────────
    //
    //  El reparto: rebuscar en el historial es de la sesión, que es quien lo
    //  guarda; pintar de amarillo lo que se ve es de aquí, que ya tiene el
    //  texto delante y no necesita preguntar nada.
    property bool buscando: false

    function abrirBusqueda() {
        buscando = true
        campoBusqueda.forceActiveFocus()
        campoBusqueda.selectAll()
    }

    function cerrarBusqueda() {
        buscando = false
        plugin.aguja = ""
        plugin.sinRastro = false
        plugin.filaHallada = -1
        campo.forceActiveFocus()
    }

    //  Por qué columnas aparece lo buscado en la fila `i` de la rejilla.
    function hallazgosEn(i) {
        const aguja = String(plugin.aguja).toLowerCase()
        if (!buscando || aguja.length === 0)
            return []
        const linea = textoFila(i).toLowerCase()
        const sitios = []
        let donde = linea.indexOf(aguja)
        while (donde >= 0) {
            sitios.push(donde + 1)
            donde = linea.indexOf(aguja, donde + aguja.length)
        }
        return sitios
    }

    //  ── los bloques ───────────────────────────────────────────────
    //
    //  Lo que la sesión ya sabía y no se veía: dónde empieza cada mandato y
    //  cómo acabó. El filete del margen es eso, y nada más — nada hasta que
    //  significa algo.
    readonly property var ultimoBloque: marco && marco.ultimo ? marco.ultimo : null

    //  Ctrl+Shift+N para ir a la terminal N. Con Shift, la fila de números da
    //  otro símbolo según la distribución —en la española `!"·$%&/()`, en la
    //  americana `!@#$%^&*(`— y Qt entrega ESE símbolo, no el dígito: mirar
    //  solo los dígitos dejaría el atajo muerto en medio mundo.
    readonly property var simbolosNumero: [
        [Qt.Key_Exclam, Qt.Key_QuoteDbl, 0xb7, Qt.Key_Dollar, Qt.Key_Percent,
         Qt.Key_Ampersand, Qt.Key_Slash, Qt.Key_ParenLeft, Qt.Key_ParenRight],
        [Qt.Key_Exclam, Qt.Key_At, Qt.Key_NumberSign, Qt.Key_Dollar, Qt.Key_Percent,
         Qt.Key_AsciiCircum, Qt.Key_Ampersand, Qt.Key_Asterisk, Qt.Key_ParenLeft]
    ]

    function numeroDe(tecla) {
        if (tecla >= Qt.Key_1 && tecla <= Qt.Key_9)
            return tecla - Qt.Key_1 + 1
        for (let d = 0; d < simbolosNumero.length; ++d) {
            const donde = simbolosNumero[d].indexOf(tecla)
            if (donde >= 0)
                return donde + 1
        }
        return 0
    }

    function copiarUltimaSalida() {
        if (!ultimoBloque)
            return
        //  La marca de arranque cae en la PRIMERA fila de la salida, y la de
        //  final en la de después de la última —ahí es donde el shell va a
        //  pintar su siguiente prompt—, así que la última buena es `fin - 1`.
        //  Mientras el mandato corre no hay final: se copia hasta donde llegue.
        plugin.mandar({ que: "texto_de",
                        desde: ultimoBloque.fila,
                        hasta: ultimoBloque.fin > ultimoBloque.fila
                             ? ultimoBloque.fin - 1 : 0,
                        motivo: "copiar" })
    }

    onColsChanged: medir.restart()
    onFilasChanged: medir.restart()
    Component.onCompleted: {
        plugin.mandar({ que: "medida", cols: cols, filas: filas })
        plugin.mandar({ que: "pinta" })
        forzarFoco.start()
        pintadoX = destinoX
        pintadoY = destinoY
    }


    Timer {
        id: medir
        //  Corto a propósito: solo está para juntar el cambio de filas con el
        //  de columnas si llegan a la vez, no para esperar a nada.
        interval: 16
        onTriggered: vista.plugin.mandar({ que: "medida", cols: vista.cols,
                                           filas: vista.filas })
    }

    //  El foco llega un pelo después de que la island se abra; sin esta
    //  espera las primeras teclas se pierden.
    Timer {
        id: forzarFoco
        interval: 60
        onTriggered: campo.forceActiveFocus()
    }

    //  ── la cabecera: qué terminales hay y cómo esconderlas ────────────
    //
    //  Una tira siempre, aunque solo haya una sesión: con una hace de título
    //  —dice qué corre dentro y dónde— y con varias es el selector. Que
    //  aparezca y desaparezca según cuántas haya movería la rejilla entera de
    //  sitio cada vez que abres una terminal nueva.
    readonly property int altoCabecera: 22

    Item {
        id: cabecera
        x: vista.margen
        y: 6
        width: vista.width - vista.margen * 2
        height: vista.altoCabecera

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: vista.plugin.vivas

                delegate: Rectangle {
                    id: pestana
                    required property var modelData
                    required property int index

                    readonly property bool esta: index === vista.plugin.actual

                    //  Lo que corre aquí dentro y si te está llamando. Se leen
                    //  los MAPAS del plugin, no una función que los mire por
                    //  dentro: un enlace de QML solo se reevalúa cuando cambia
                    //  una PROPIEDAD que haya leído, y con `trabajos` metido
                    //  dentro de una llamada la pestaña se quedaría con lo que
                    //  hubiera al nacer. Es la trampa de `advanceWidth`.
                    readonly property string clave: "isla." + modelData.numero
                    readonly property var trabajo: vista.plugin.trabajos[clave]
                    readonly property bool llamando:
                        vista.plugin.esperas[clave] !== undefined

                    //  La campana primero: que un agente haya acabado su turno
                    //  y te espere urge más que saber que sigue pensando. Sin
                    //  una cosa ni la otra, la pestaña va limpia.
                    readonly property var insignia: llamando
                        ? ({ glifo: Theme.ico.bell.codePointAt(0),
                             color: Theme.yellow })
                        : (trabajo ? vista.plugin.insigniaDe(trabajo.mandato)
                                   : null)

                    //  DÓNDE estás y QUÉ corre, las dos cosas. Antes era una o
                    //  la otra, y con dos agentes en dos repos el título solo
                    //  no distingue nada: lo que las separa es el directorio,
                    //  y lo que dice en qué anda cada una es el mandato.
                    readonly property string donde: modelData.cwd
                        ? vista.corto(modelData.cwd)
                        : Idioma.t("terminal") + " " + (index + 1)

                    //  Qué corre, a secas: el programa, sin ruta ni argumentos,
                    //  que en dos dedos de pestaña es lo único que se lee. Lo
                    //  pone el reloj de los trabajos, que solo cuenta lo que
                    //  lleva unos segundos vivo: por eso esto no parpadea con
                    //  cada `ls`, y por eso una pestaña en reposo no dice nada
                    //  de más.
                    //
                    //  El título de la aplicación NO entra aquí, aunque fuera
                    //  la tentación. Un shell en reposo lo pone en
                    //  `abel@abel:~`, que es el directorio otra vez y con peor
                    //  letra; y lo que sí tiene título propio —vim, btop— es
                    //  justo lo que el reloj ya está contando.
                    readonly property string que: trabajo
                        ? vista.plugin.programaDe(trabajo.mandato) : ""

                    readonly property string nombre:
                        que ? donde + "  ·  " + que : donde

                    height: vista.altoCabecera - 4
                    //  El hueco de la aspa va SIEMPRE reservado aunque el aspa
                    //  no se vea: si apareciera al pasar el ratón, la pestaña
                    //  crecería y empujaría a las demás justo cuando vas a
                    //  pulsarlas.
                    width: fila.width + 18 + 14
                    radius: height / 2
                    color: esta ? Theme.surfaceHi : "transparent"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        id: fila
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        //  El mismo glifo que lleva su píldora, y por la misma
                        //  razón: saber CUÁL de las cuatro tiene al agente
                        //  esperándote sin ir tabulando por ellas. Una fila
                        //  se salta sola lo que no se ve, así que sin insignia
                        //  no queda ni el hueco.
                        IconGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pestana.insignia !== null
                            text: visible
                                ? String.fromCodePoint(pestana.insignia.glifo)
                                : ""
                            color: visible ? pestana.insignia.color : Theme.dim
                            font.pixelSize: 11
                        }

                        IslandLabel {
                            id: etiqueta
                            anchors.verticalCenter: parent.verticalCenter
                            text: (pestana.index + 1) + "  " + pestana.nombre
                            color: pestana.esta ? Theme.ink : Theme.muted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            //  Un nombre largo no puede empujar al resto fuera.
                            width: Math.min(implicitWidth, 190)
                        }
                    }

                    MouseArea {
                        id: pestanaRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: function (raton) {
                            //  El botón de en medio cierra, como en cualquier
                            //  pestaña; el izquierdo va a ella.
                            if (raton.button === Qt.MiddleButton)
                                vista.plugin.cerrarSesion(parent.index)
                            else
                                vista.plugin.irA(parent.index)
                        }
                    }

                    //  Cerrar esta terminal. Solo al acercarse: en reposo la
                    //  cabecera dice qué hay, no ofrece botones.
                    IslandLabel {
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"
                        font.pixelSize: 10
                        color: aspaRaton.containsMouse ? Theme.ink : Theme.muted
                        opacity: pestanaRaton.containsMouse || aspaRaton.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        MouseArea {
                            id: aspaRaton
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: vista.plugin.cerrarSesion(parent.parent.index)
                        }
                    }
                }
            }

            //  Una más.
            IconGlyph {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF0415)
                color: masRaton.containsMouse ? Theme.ink : Theme.dim
                font.pixelSize: 13

                MouseArea {
                    id: masRaton
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vista.plugin.nueva()
                }
            }
        }

        //  Esconderla sin tocar lo que corre dentro. Existe porque ESC ya no
        //  cierra: se la lleva la terminal.
        IconGlyph {
            id: menos
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0374)
            color: menosRaton.containsMouse ? Theme.ink : Theme.dim
            font.pixelSize: 14

            MouseArea {
                id: menosRaton
                anchors.fill: parent
                anchors.margins: -5
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: vista.plugin.cerrar()
            }
        }
    }

    //  ── la rejilla ────────────────────────────────────────────────────
    //
    //  Un terminal NO es texto encadenado: es una cuadrícula de celdas
    //  iguales, y cada tramo va en la columna que le toca. Que se pinte por
    //  columna y no por ancho natural no es una manía —es la única forma de
    //  que cuadre—: en cuanto aparece un glifo que no mide lo mismo que los
    //  demás (los marcos de las cajas de claude, un icono de la Nerd Font, un
    //  espacio duro), encadenar avances desplaza la línea a la derecha
    //  mientras el cursor, que sí va por columna, se queda donde debe. El
    //  resultado era exactamente eso: el cursor «se iba» respecto del texto.
    //
    //  Así que el ancho del glifo se usa para elegir el dibujo y la REJILLA
    //  decide dónde va. Cada fila es un lienzo y cada tramo se ancla en
    //  `(columna - 1) * anchoCelda`, así que un tramo torcido no arrastra a
    //  los de después.
    //  Lo seleccionado, POR DEBAJO del texto: va declarado antes que la
    //  rejilla a propósito, que en QML lo último que se declara es lo que
    //  queda encima y una selección que tapa las letras no sirve de nada.
    Repeater {
        model: vista.marco ? vista.marco.filas.length : 0

        delegate: Rectangle {
            required property int index
            readonly property var tramo: vista.tramoSeleccion(index)

            visible: tramo !== null
            x: vista.margen + ((tramo ? tramo.a : 1) - 1) * vista.anchoCelda
            y: vista.margen + vista.altoCabecera + index * vista.altoLinea
            width: tramo ? (tramo.b - tramo.a + 1) * vista.anchoCelda : 0
            height: vista.altoLinea
            color: Theme.blue
            opacity: 0.3
        }
    }

    //  Lo buscado, resaltado en todas las filas donde asome: la activa en
    //  sólido y las demás insinuadas. Va también por debajo del texto.
    Repeater {
        model: vista.buscando && vista.marco ? vista.marco.filas.length : 0

        delegate: Item {
            id: filaBuscada
            required property int index
            readonly property bool esLaBuena: vista.absoluta(index + 1) === vista.plugin.filaHallada

            Repeater {
                model: vista.hallazgosEn(filaBuscada.index)

                delegate: Rectangle {
                    required property var modelData

                    x: vista.margen + (modelData - 1) * vista.anchoCelda
                    y: vista.margen + vista.altoCabecera
                       + filaBuscada.index * vista.altoLinea
                    width: String(vista.plugin.aguja).length * vista.anchoCelda
                    height: vista.altoLinea
                    color: Theme.yellow
                    opacity: filaBuscada.esLaBuena ? 0.5 : 0.25
                }
            }
        }
    }

    //  El filete de cada mandato: dos píxeles en el margen, verde si salió
    //  bien y rojo si no. Es el aspecto de los bloques hecho a la manera de la
    //  casa — no ocupa sitio, no pide nada y solo aparece cuando hay algo que
    //  decir.
    Repeater {
        model: vista.marco && vista.marco.bloques ? vista.marco.bloques : []

        delegate: Item {
            required property var modelData
            readonly property int enFila: vista.enRejilla(modelData.fila)

            visible: enFila >= 0
            x: vista.margen - 12
            y: vista.margen + vista.altoCabecera + enFila * vista.altoLinea
            width: 10
            height: vista.altoLinea

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 4
                width: 2
                height: parent.height
                radius: 1
                color: parent.modelData.estado === "bien" ? Theme.green
                     : (parent.modelData.estado === "mal" ? Theme.red : Theme.muted)
                opacity: parent.modelData.estado === "corre" ? 0.6
                       : (filete.containsMouse ? 1 : 0.9)
            }

            //  Pulsar el filete recoge la salida de ese mandato. Es el sitio
            //  natural —marca justo el bloque— pero dos píxeles no se aciertan
            //  con el ratón, así que la zona sensible es más ancha que la raya.
            MouseArea {
                id: filete
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: parent.modelData.fin > parent.modelData.fila
                onClicked: vista.plegar(parent.modelData.fila)
            }
        }
    }

    Column {
        id: rejilla
        x: vista.margen
        y: vista.margen + vista.altoCabecera
        spacing: 0

        Repeater {
            model: vista.marco ? vista.marco.filas : []

            delegate: Item {
                required property var modelData
                required property int index
                width: vista.width - vista.margen * 2
                height: vista.altoLinea

                //  La línea de una salida recogida se distingue: un fondo
                //  suave que dice «aquí hay algo doblado», y el ratón en mano
                //  al pasar por encima.
                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: parent.width * 0.55
                    visible: vista.esResumen(parent.index)
                    color: Theme.surfaceHi
                    opacity: 0.35
                    radius: 4
                }

                //  Modo tranquilo: lo anterior al último mandato se atenúa. En
                //  una sesión larga con un agente dentro, saber dónde empieza
                //  lo nuevo vale más que cualquier color.
                opacity: vista.plugin.tranquilo && vista.ultimoBloque
                         && vista.absoluta(index + 1) < vista.ultimoBloque.fila ? 0.5 : 1
                Behavior on opacity { NumberAnimation { duration: 140 } }

                Repeater {
                    model: parent.modelData

                    delegate: Item {
                        required property var modelData
                        //  Su sitio en la rejilla, no donde acabara el vecino.
                        x: (modelData.c - 1) * vista.anchoCelda
                        width: modelData.t.length * vista.anchoCelda
                        height: vista.altoLinea

                        Rectangle {
                            anchors.fill: parent
                            color: modelData.b
                            visible: modelData.b !== String(Theme.islandBg)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            //  **Lo más importante de todo el fichero.**
                            //
                            //  Esto es la salida de tus mandatos: bytes que
                            //  vienen de donde vengan. Sin `PlainText`, un
                            //  `cat` a un fichero con `<img src="http://…">`
                            //  dentro haría que la barra saliera a pedir esa
                            //  imagen. El VT ya trae su propia negrita por
                            //  bits; el marcado no pinta nada aquí.
                            textFormat: Text.PlainText
                            text: modelData.t
                            color: modelData.f
                            font.family: plugin.fuente
                            font.pixelSize: vista.cuerpo
                            //  El bit 0x02 del VT es la negrita.
                            font.weight: (modelData.n & 0x02) ? Font.Bold : Font.Normal
                            font.italic: (modelData.n & 0x04) !== 0
                            font.underline: (modelData.n & 0x08) !== 0
                            font.strikeout: (modelData.n & 0x40) !== 0
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }
    }

    //  ── el cursor y su estela ─────────────────────────────────────────
    //
    //  El cursor va aparte de las filas: es de la sesión, no del texto. Y no
    //  se teletransporta, se desliza dejando rastro — la misma estela que la
    //  ventana, con la misma curva, porque son la misma terminal y no se
    //  entendería que una tuviera el efecto y la otra no.
    //
    //  Cuántos fantasmas lo dice la sesión, que lee los ajustes de k4term:
    //  aquí no se decide nada, solo se pinta.
    //
    //  Nada de `Behavior on x`: lo que se quiere enseñar es el camino REAL,
    //  con su aceleración, así que se guarda por dónde ha pasado en vez de
    //  interpolarlo al pintar. Por eso hay un latido en vez de una animación.
    readonly property real destinoX: margen + (marco ? (marco.cursor[0] - 1) : 0) * anchoCelda
    readonly property real destinoY: margen + altoCabecera + (marco ? (marco.cursor[1] - 1) : 0) * altoLinea

    //  Se inicializan a mano y no con un enlace a `destino`: un enlace haría
    //  que el cursor se plantara en el destino ANTES del primer latido, y ese
    //  primer movimiento —el único que se ve al abrir— saldría sin estela.
    property real pintadoX: 0
    property real pintadoY: 0
    property var fantasmas: []

    onDestinoXChanged: latido.start()
    onDestinoYChanged: latido.start()

    Timer {
        id: latido
        interval: 16
        repeat: true
        onTriggered: {
            const dx = Math.abs(vista.destinoX - vista.pintadoX)
            const dy = Math.abs(vista.destinoY - vista.pintadoY)
            const anterior = { x: vista.pintadoX, y: vista.pintadoY }

            //  Cuanto más lejos, más rápido: así un salto de línea no se
            //  arrastra y mover una letra sigue siendo suave. Y un salto
            //  enorme es una pantalla nueva, no un movimiento: ahí se planta.
            const lejos = (dx + dy) / Math.max(1, vista.altoLinea)
            const paso = Math.min(0.35 + lejos * 0.06, 0.75)
            const enorme = dy > vista.altoLinea * 12

            if (enorme) {
                vista.pintadoX = vista.destinoX
                vista.pintadoY = vista.destinoY
            } else {
                vista.pintadoX += (vista.destinoX - vista.pintadoX) * paso
                vista.pintadoY += (vista.destinoY - vista.pintadoY) * paso
            }

            //  A menos de medio píxel ya está en su sitio. Dejar de latir
            //  aquí es lo que evita quemar un temporizador para siempre.
            const quieto = Math.abs(vista.pintadoX - vista.destinoX) < 0.5
                        && Math.abs(vista.pintadoY - vista.destinoY) < 0.5
            if (quieto) {
                vista.pintadoX = vista.destinoX
                vista.pintadoY = vista.destinoY
            }

            let rastro = vista.fantasmas.slice()
            if (vista.plugin.estela > 0) {
                if (quieto) {
                    //  Parado, la estela se recoge sola: uno menos por latido
                    //  hasta vaciarse. Nada de seguir apuntando la posición
                    //  quieta —eso deja el rastro pegado al cursor para
                    //  siempre y el latido no para nunca.
                    rastro.shift()
                } else {
                    rastro.push(anterior)
                    if (rastro.length > vista.plugin.estela)
                        rastro = rastro.slice(rastro.length - vista.plugin.estela)
                }
            } else {
                rastro = []
            }
            vista.fantasmas = rastro

            if (quieto && rastro.length === 0)
                latido.stop()
        }
    }

    //  Los fantasmas, del más viejo al más nuevo y cada vez más presentes.
    //  Van antes que el cursor para que él quede encima.
    Repeater {
        model: vista.fantasmas

        delegate: Rectangle {
            required property var modelData
            required property int index
            x: modelData.x
            y: modelData.y + (vista.figuraCursor === "subrayado"
                              ? vista.altoLinea - vista.altoCursor : 0)
            width: vista.anchoCursor
            height: vista.altoCursor
            color: Theme.ink
            opacity: (index + 1) / Math.max(1, vista.fantasmas.length) * 0.35
        }
    }

    //  La figura que pida el programa (DECSCUSR): barra mientras escribes,
    //  bloque en el modo normal de vim, subrayado si lo pide. Y si pide que
    //  parpadee, parpadea — pero solo él: los fantasmas de la estela no, que
    //  serían una discoteca.
    readonly property string figuraCursor: marco && marco.cursor_figura
        ? marco.cursor_figura : "barra"
    readonly property real anchoCursor: figuraCursor === "bloque" ? anchoCelda : 2
    readonly property real altoCursor: figuraCursor === "subrayado" ? 2 : altoLinea

    Rectangle {
        id: cursor

        visible: vista.marco !== null
        x: vista.pintadoX
        y: vista.pintadoY + (vista.figuraCursor === "subrayado"
                             ? vista.altoLinea - vista.altoCursor : 0)
        width: vista.anchoCursor
        height: vista.altoCursor
        color: Theme.ink
        //  El bloque va translúcido a propósito: tapa la letra de debajo y
        //  así se lee igual, que es lo que hace una terminal al invertirla.
        opacity: vista.figuraCursor === "bloque" ? 0.45 : 0.9

        Behavior on width { NumberAnimation { duration: 90 } }
        Behavior on height { NumberAnimation { duration: 90 } }

        SequentialAnimation on opacity {
            running: vista.marco !== null && vista.marco.cursor_parpadea === true
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.05; duration: 530; easing.type: Easing.InOutQuad }
            NumberAnimation {
                to: vista.figuraCursor === "bloque" ? 0.45 : 0.9
                duration: 530
                easing.type: Easing.InOutQuad
            }
        }
    }

    //  ── el ratón ──────────────────────────────────────────────────
    //
    //  Dos dueños posibles y una sola regla para decidir: si la aplicación de
    //  dentro ha pedido el ratón (htop, vim, la interfaz de claude), los clics
    //  son SUYOS y aquí no se selecciona nada; si no, son de la vista, que los
    //  usa para seleccionar y copiar. Shift fuerza siempre el segundo caso —
    //  es la salida de emergencia de toda la vida para poder copiar dentro de
    //  un programa que se queda el ratón.
    //
    //  Va declarado antes que la barra de desplazamiento para que arrastrarla
    //  siga siendo cosa de ella, y con el margen de arriba justo por debajo de
    //  la cabecera, que las pestañas tienen sus propios clics.
    MouseArea {
        id: raton

        //  Lo que este receptor está más abajo que la vista. Los sucesos de
        //  ratón vienen en coordenadas SUYAS, no de la vista, así que sin
        //  sumarlo la cuenta de la fila sale casi dos líneas desplazada — se
        //  vio a la primera: un arrastre sobre una línea seleccionaba tres.
        readonly property int desfase: vista.altoCabecera + 4

        anchors.fill: parent
        anchors.topMargin: desfase
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: (enlace || sobreResumen) ? Qt.PointingHandCursor : Qt.IBeamCursor
        //  Encima de una salida recogida, la mano: ahí se pulsa, no se
        //  selecciona.
        property bool sobreResumen: false

        //  Un arrastre que aún no ha movido nada no es una selección: si lo
        //  fuera, cada clic suelto copiaría una letra a la primaria.
        property bool arrastrando: false
        property bool movido: false
        property bool reportando: false
        property string enlace: ""

        function nombreBoton(b) {
            if (b === Qt.MiddleButton)
                return "medio"
            return b === Qt.RightButton ? "derecho" : "izquierdo"
        }

        function conMods(orden, m) {
            return Object.assign(orden, {
                shift: (m & Qt.ShiftModifier) !== 0,
                control: (m & Qt.ControlModifier) !== 0,
                alt: (m & Qt.AltModifier) !== 0
            })
        }

        function esSuyo(m) {
            return vista.marco && vista.marco.raton && (m & Qt.ShiftModifier) === 0
        }

        function contar(tipo, boton, x, y, m) {
            vista.plugin.mandar(conMods({ que: "raton", tipo: tipo, boton: boton,
                                          col: vista.colDe(x), fila: vista.filaDe(y + desfase) }, m))
        }

        onPressed: function (e) {
            campo.forceActiveFocus()

            if (esSuyo(e.modifiers)) {
                reportando = true
                contar("pulsar", nombreBoton(e.button), e.x, e.y, e.modifiers)
                return
            }
            reportando = false

            //  El de en medio pega la selección primaria, como en cualquier
            //  terminal de siempre.
            if (e.button === Qt.MiddleButton) {
                vista.plugin.pegar(true)
                return
            }
            if (e.button !== Qt.LeftButton)
                return

            //  Ctrl+clic abre el enlace de debajo, y entonces no hay selección
            //  que empezar.
            const url = (e.modifiers & Qt.ControlModifier)
                ? vista.urlEn(vista.filaDe(e.y + desfase), vista.colDe(e.x)) : ""
            if (url) {
                vista.plugin.abrirEnlace(url)
                return
            }

            //  Pulsar una salida recogida la despliega. Va antes que la
            //  selección: quien pincha en esa línea quiere abrirla, no coger
            //  su texto.
            const filaPulsada = vista.filaDe(e.y + desfase)
            if (vista.esResumen(filaPulsada - 1)) {
                vista.plegar(vista.absoluta(filaPulsada))
                return
            }

            vista.limpiarSeleccion()
            arrastrando = true
            movido = false
            const punto = { fila: vista.absoluta(vista.filaDe(e.y + desfase)),
                            col: vista.colDe(e.x) }
            vista.selA = punto
            vista.selB = punto
        }

        onPositionChanged: function (e) {
            if (reportando) {
                contar("mover", nombreBoton(pressedButtons & Qt.MiddleButton ? Qt.MiddleButton
                                          : (pressedButtons & Qt.RightButton ? Qt.RightButton
                                                                             : Qt.LeftButton)),
                       e.x, e.y, e.modifiers)
                return
            }

            if (arrastrando) {
                const punto = { fila: vista.absoluta(vista.filaDe(e.y + desfase)),
                                col: vista.colDe(e.x) }
                if (punto.fila !== vista.selA.fila || punto.col !== vista.selA.col)
                    movido = true
                vista.selB = punto
                return
            }

            //  Sin botón: solo se mira si hay enlace debajo, y solo con Ctrl,
            //  que es lo que lo abre. Subrayar todo lo que parece una URL
            //  mientras paseas el ratón sería ruido.
            const filaBajoElRaton = vista.filaDe(e.y + desfase)
            sobreResumen = vista.esResumen(filaBajoElRaton - 1)
            enlace = (e.modifiers & Qt.ControlModifier)
                ? vista.urlEn(filaBajoElRaton, vista.colDe(e.x)) : ""
        }

        onReleased: function (e) {
            if (reportando) {
                contar("soltar", nombreBoton(e.button), e.x, e.y, e.modifiers)
                reportando = false
                return
            }
            if (!arrastrando)
                return
            arrastrando = false

            //  Al soltar, lo seleccionado va a la primaria: es lo que espera
            //  quien luego pega con el botón de en medio.
            if (movido)
                vista.copiarSeleccion("primaria")
            else
                vista.limpiarSeleccion()
        }

        onDoubleClicked: function (e) {
            if (esSuyo(e.modifiers))
                return
            const fila = vista.filaDe(e.y + desfase)
            const tramo = vista.palabraEn(fila, vista.colDe(e.x))
            if (!tramo)
                return
            vista.selA = { fila: vista.absoluta(fila), col: tramo.a }
            vista.selB = { fila: vista.absoluta(fila), col: tramo.b }
            vista.copiarSeleccion("primaria")
        }

        //  La rueda: tres líneas por muesca, como en todas partes. Quien
        //  decide si mueve el historial o se la lleva la aplicación es la
        //  sesión, que es la que sabe qué modos hay puestos; con shift se le
        //  dice que el historial es nuestro pase lo que pase.
        onWheel: function (rueda) {
            const pasos = rueda.angleDelta.y > 0 ? 3 : -3
            vista.plugin.mandar({ que: "rueda", lineas: -pasos,
                                  col: vista.colDe(rueda.x),
                                  fila: vista.filaDe(rueda.y + desfase),
                                  historial: (rueda.modifiers & Qt.ShiftModifier) !== 0 })
            rueda.accepted = true
        }
    }

    //  Y la barrita de la casa, la misma pieza que el resto de la island: aquí
    //  no se le puede colgar de un Flickable —la rejilla no lo es, el historial
    //  vive en la sesión— así que se le dan `size` y `position` a mano con lo
    //  que dice el marco. Sale sola cuando hay algo que recorrer y se desvanece
    //  al parar, como en todas partes.
    IslandScrollBar {
        id: barra

        orientation: Qt.Vertical
        anchors.right: parent.right
        anchors.rightMargin: 4
        y: vista.margen
        height: vista.height - vista.margen * 2

        size: vista.recorrido
        position: vista.asomado

        //  Arrastrarla también mueve la sesión. Al agarrarla, Qt escribe en
        //  `position` y de paso rompe el enlace con el marco; por eso se vuelve
        //  a atar al soltar, que si no la barra se queda muerta a partir del
        //  primer arrastre y no lo avisa nadie.
        onPressedChanged: {
            if (pressed) {
                arrastre.start()
            } else {
                arrastre.stop()
                position = Qt.binding(function () { return vista.asomado })
            }
        }

        //  A tirones y no en cada píxel: la sesión solo sabe moverse en
        //  relativo, así que cada latido recalcula lo que falta desde donde
        //  está de verdad. Con eso el error no se acumula aunque los marcos
        //  lleguen tarde.
        Timer {
            id: arrastre
            interval: 50
            repeat: true
            onTriggered: {
                const destino = Math.round(barra.position * vista.historial)
                const salto = destino - vista.arriba
                if (salto !== 0)
                    vista.plugin.mandar({ que: "rueda", lineas: salto })
            }
        }
    }

    Item {
        id: campo
        focus: true
        anchors.fill: parent

        readonly property var nombres: ({})

        Keys.onPressed: function (e) {
            const mods = {
                shift: (e.modifiers & Qt.ShiftModifier) !== 0,
                control: (e.modifiers & Qt.ControlModifier) !== 0,
                alt: (e.modifiers & Qt.AltModifier) !== 0
            }

            const conNombre = function (nombre) {
                vista.plugin.mandar(Object.assign({ que: "tecla", nombre: nombre }, mods))
                e.accepted = true
            }

            //  ── lo que es de la terminal y no de lo que corre dentro ──
            //
            //  Todo con Ctrl+Shift, igual que en la ventana y que en cualquier
            //  terminal moderna. Antes esto iba con Alt y el precio era caro:
            //  los programas de dentro se quedaban sin alt+flechas —que es
            //  como se anda por palabras en media consola— y sin alt+letra
            //  para sus propios menús. Ahora Alt vuelve a ser suyo entero.
            if (mods.control && mods.shift) {
                switch (e.key) {
                case Qt.Key_V: vista.plugin.pegar(false); e.accepted = true; return
                case Qt.Key_C: vista.copiarSeleccion("copiar"); e.accepted = true; return
                case Qt.Key_A: vista.seleccionarTodo(); e.accepted = true; return
                //  La salida del último mandato, sin tener que seleccionarla.
                case Qt.Key_E: vista.copiarUltimaSalida(); e.accepted = true; return
                case Qt.Key_Q: vista.plugin.alternarTranquilo(); e.accepted = true; return
                //  Recoger la salida del último mandato. Un `make` de
                //  trescientas líneas pasa a ser una, y la isla se encoge con
                //  ella; se despliega pulsándola o repitiendo la tecla.
                case Qt.Key_Z: vista.plegarUltimo(); e.accepted = true; return
                case Qt.Key_F:
                    if (vista.buscando)
                        vista.cerrarBusqueda()
                    else
                        vista.abrirBusqueda()
                    e.accepted = true
                    return
                //  A la nota del día: el último mandato con su salida, o la
                //  sesión entera. Sin Edinot abierto, la sesión lo dice.
                case Qt.Key_N: vista.plugin.anotar(false); e.accepted = true; return
                case Qt.Key_M: vista.plugin.anotar(true); e.accepted = true; return
                case Qt.Key_T: vista.plugin.nueva(); e.accepted = true; return
                //  Cerrar la de delante. Con `exit` también se va —la sesión
                //  muere y la pestaña con ella—, pero eso pide que la shell
                //  esté libre; esto vale aunque tengas algo corriendo.
                case Qt.Key_W:
                    vista.plugin.cerrarSesion(vista.plugin.actual)
                    e.accepted = true
                    return
                case Qt.Key_Right: vista.plugin.siguiente(); e.accepted = true; return
                case Qt.Key_Left:  vista.plugin.anterior();  e.accepted = true; return
                //  De un prompt al anterior o al siguiente: en una sesión
                //  larga es la diferencia entre buscar y encontrar.
                case Qt.Key_Up:
                    vista.plugin.mandar({ que: "saltar", hacia: -1 })
                    e.accepted = true
                    return
                case Qt.Key_Down:
                    vista.plugin.mandar({ que: "saltar", hacia: 1 })
                    e.accepted = true
                    return
                case Qt.Key_Plus:
                case Qt.Key_Equal:
                    vista.plugin.acercar(1)
                    e.accepted = true
                    return
                }

                const cual = vista.numeroDe(e.key)
                if (cual > 0) {
                    vista.plugin.irA(cual - 1)
                    e.accepted = true
                    return
                }
            }

            //  El historial con el teclado, con shift y las teclas de página
            //  como en cualquier terminal. Sin esto solo se podía subir con la
            //  rueda o arrastrando la barrita.
            if (mods.shift && !mods.control) {
                const salto = Math.max(1, (vista.marco ? vista.marco.filas_n : vista.filas) - 1)
                if (e.key === Qt.Key_PageUp || e.key === Qt.Key_PageDown) {
                    vista.plugin.mandar({ que: "rueda", historial: true,
                                          lineas: e.key === Qt.Key_PageUp ? -salto : salto })
                    e.accepted = true
                    return
                }
                if (e.key === Qt.Key_Home || e.key === Qt.Key_End) {
                    vista.plugin.mandar({ que: "tope", arriba: e.key === Qt.Key_Home })
                    e.accepted = true
                    return
                }
            }

            //  El tamaño de la letra, aquí y ahora. No toca los ajustes: quien
            //  agranda para leer un rato no está cambiando su preferencia.
            if (mods.control && !mods.shift) {
                if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) {
                    vista.plugin.acercar(1)
                    e.accepted = true
                    return
                }
                if (e.key === Qt.Key_Minus) {
                    vista.plugin.acercar(-1)
                    e.accepted = true
                    return
                }
                if (e.key === Qt.Key_0) {
                    vista.plugin.zoomNormal()
                    e.accepted = true
                    return
                }
            }

            switch (e.key) {
            //  ESC va A LA TERMINAL, que es donde hace falta: es la tecla de
            //  cancelar de claude, de codex y de vim, y mientras la island se
            //  la quedaba no había forma de mandársela. Para esconder la vista
            //  está el botón de arriba y la misma tecla que la abrió.
            case Qt.Key_Return:
            case Qt.Key_Enter:        return conNombre("enter")
            case Qt.Key_Backspace:    return conNombre("backspace")
            case Qt.Key_Tab:          return conNombre("tab")
            case Qt.Key_Backtab:      return conNombre("tab")
            case Qt.Key_Up:           return conNombre("up")
            case Qt.Key_Down:         return conNombre("down")
            case Qt.Key_Left:         return conNombre("left")
            case Qt.Key_Right:        return conNombre("right")
            case Qt.Key_Home:         return conNombre("home")
            case Qt.Key_End:          return conNombre("end")
            case Qt.Key_PageUp:       return conNombre("pageup")
            case Qt.Key_PageDown:     return conNombre("pagedown")
            case Qt.Key_Delete:       return conNombre("delete")
            case Qt.Key_Insert:       return conNombre("insert")
            }

            if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F12)
                return conNombre("f" + (e.key - Qt.Key_F1 + 1))

            //  Lo demás va como texto. Qt ya entrega el carácter de control
            //  cuando se pulsa Ctrl+algo, así que un Ctrl+C llega hecho.
            if (e.text.length > 0) {
                //  Al escribir se deshace la selección: lo seleccionado dejó
                //  de tener sentido en cuanto la pantalla cambia debajo.
                vista.limpiarSeleccion()
                //  Alt+letra es ESCAPE y luego la letra —lo que en las
                //  terminales se llama «meta manda escape»—, que es como lo
                //  esperan emacs, la línea de zsh y los menús de media consola.
                //  Qt entrega solo la letra: sin poner el escape delante, un
                //  alt+B llegaba como una «b» a secas.
                vista.plugin.mandar({ que: "texto",
                                      valor: (mods.alt ? String.fromCharCode(0x1b) : "")
                                             + e.text })
                e.accepted = true
            }
        }
    }

    //  ── la caja de buscar ─────────────────────────────────────────
    //
    //  Vestida como los overlays de la isla y no como una caja de texto gris:
    //  superficie de la casa, radio de ala partido por dos, y entra
    //  deslizándose. Se pone arriba a la derecha porque abajo está el pie con
    //  el directorio, y tapar dónde estás mientras buscas es una faena.
    Rectangle {
        id: cajaBusqueda

        visible: opacity > 0
        anchors.right: parent.right
        anchors.rightMargin: vista.margen + 10
        y: vista.margen + vista.altoCabecera - 3 + (vista.buscando ? 0 : -14)
        width: 250
        height: 26
        radius: 8
        color: Theme.surface
        border.width: 1
        border.color: vista.plugin.sinRastro ? Theme.red : Theme.surfaceHi
        opacity: vista.buscando ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        IconGlyph {
            id: lupa
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0349)
            color: Theme.muted
            font.pixelSize: 12
        }

        IslandLabel {
            anchors.left: lupa.right
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            visible: campoBusqueda.text.length === 0
            text: Idioma.t("buscar")
            color: Theme.dim
            font.pixelSize: 11
        }

        TextInput {
            id: campoBusqueda

            anchors.left: lupa.right
            anchors.leftMargin: 7
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: TextInput.AlignVCenter
            cursorDelegate: IslandCursor {}
            color: Theme.ink
            font.family: Theme.uiFont
            font.pixelSize: 11
            clip: true
            selectByMouse: true
            selectionColor: Theme.blue

            onTextEdited: {
                vista.plugin.aguja = text
                vista.plugin.sinRastro = false
            }

            Keys.onPressed: function (e) {
                if (e.key === Qt.Key_Escape) {
                    vista.cerrarBusqueda()
                    e.accepted = true
                    return
                }
                //  Intro busca HACIA ATRÁS. En una terminal lo que se busca
                //  casi siempre acaba de pasar y está por encima; con shift,
                //  hacia delante.
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    vista.plugin.buscar((e.modifiers & Qt.ShiftModifier) ? 1 : -1)
                    e.accepted = true
                }
            }
        }
    }

    //  ── el camino de una conexión ─────────────────────────────────
    //
    //  Mientras `ssh` negocia no se ve NADA —ni un punto— y tres segundos de
    //  pantalla quieta parecen una terminal colgada. Esto dice «voy»: de aquí,
    //  por la llave, hasta allí. Lo enciende el plugin de servidores y lo apaga
    //  la primera salida que llegue.
    Item {
        anchors.fill: parent
        visible: Consola.conectando !== ""
        z: 10

        //  Opaco, no translúcido: por debajo pasan el mandato, el saludo de
        //  la máquina y los avisos de ssh, y verlos correr detrás de la
        //  animación es lo contrario de lo que la animación viene a decir.
        //  Es la misma decisión que en la ventana.
        //
        //  Y con las esquinas de abajo redondeadas como las de la island: un
        //  rectángulo a secas la dejaba cuadrada por el pie mientras duraba la
        //  conexión, que es de las cosas que se ven aunque no se miren. El
        //  mismo radio que usa la silueta —32, o la mitad del alto si es
        //  bajita—, y arriba a cero porque ahí no hay esquina que tapar: está
        //  la cabecera de las pestañas.
        Rectangle {
            anchors.fill: parent
            color: Theme.islandBg
            bottomLeftRadius: Math.min(32, vista.height / 2)
            bottomRightRadius: Math.min(32, vista.height / 2)
        }

        Column {
            anchors.centerIn: parent
            spacing: 10

            Item {
                width: 220
                height: 26
                anchors.horizontalCenter: parent.horizontalCenter

                //  La línea, y encima la chispa que la recorre.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 2
                    color: Theme.blue
                    opacity: 0.25
                }

                Rectangle {
                    id: chispa
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 2
                    color: Theme.blue

                    //  De un lado al otro y vuelta a empezar. Va con el motor
                    //  de animación y no con un Timer, como todo lo que se
                    //  mueve en esta casa.
                    NumberAnimation on x {
                        running: Consola.conectando !== ""
                        loops: Animation.Infinite
                        from: 0
                        to: 210
                        duration: 1500
                        easing.type: Easing.InOutSine
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 8
                    color: Theme.blue
                }

                //  La llave: un ojo de cerradura dibujado, no un glifo — una
                //  letra se apoya en su línea base y dentro de un círculo
                //  siempre queda descentrada.
                Rectangle {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    radius: 13
                    color: Theme.blue

                    SequentialAnimation on opacity {
                        running: Consola.conectando !== ""
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutQuad }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 7
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.islandBg
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 13
                        width: 3
                        height: 6
                        radius: 1
                        color: Theme.islandBg
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width - 16
                    width: 16
                    height: 16
                    radius: 8
                    color: Theme.blue
                    opacity: chispa.x > 180 ? 1 : 0.25

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }

            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Idioma.t("conectando a ") + Consola.conectando + "…"
                color: Theme.muted
                font.pixelSize: 12
            }
        }
    }

    //  Pie discreto: dónde estás, que es lo que uno mira, y el recordatorio
    //  de salida en pequeño a la derecha. Con el mismo margen que la rejilla,
    //  que la island tiene las esquinas redondeadas y lo que se pega al borde
    //  se sale por debajo del recorte.
    IslandLabel {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: vista.margen
        anchors.bottomMargin: 6
        text: vista.marco && vista.marco.cwd ? vista.corto(vista.marco.cwd) : ""
        color: Theme.muted
        font.pixelSize: 10
    }

    IslandLabel {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: vista.margen
        anchors.bottomMargin: 6
        text: Idioma.t("ctrl+shift: ←→ cambia · T nueva · V pega · C copia · F busca")
        color: Theme.dim
        font.pixelSize: 10
    }
}
