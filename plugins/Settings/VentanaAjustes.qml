//  Ajustes, en una ventana con barra lateral.
//
//  Los ajustes vivían en un panel de la island: una columna única con TODO
//  dentro. Funcionaba con tres grupos; hoy hay ocho propios y otros tantos que
//  aportan los plugins —cerca de cincuenta opciones— y la única forma de
//  encontrar algo era bajar leyendo. Cada plugin que instalas lo empeora, así
//  que no era cuestión de apretar más: el sitio se había quedado pequeño.
//
//  Aquí las secciones son una lista a la izquierda y solo se pinta la que
//  estás mirando. Es el mismo movimiento que hizo la tienda de plugins cuando
//  salió de Ajustes, y por la misma razón.
//
//  ── de dónde salen los datos ─────────────────────────────────────
//
//  De `Settings.definicion`, que ya trae los grupos propios concatenados con
//  los que registran los plugins por `K4.Ajustes`. Esta ventana no declara ni
//  una opción: si mañana un plugin añade una sección, aparece aquí sola.
//
//  Y las filas son `FilaOpcion`, las mismas que pinta el panel de la island.
//  Dos implementaciones de un interruptor divergen a la primera corrección.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"

K4.Ventana {
    id: ventana

    required property var plugin

    nombre: "k4-ajustes"

    //  El teclado solo mientras el ratón esté aquí, y no en exclusiva para
    //  toda la sesión. Con `conTeclado` esta ventana abierta en un monitor
    //  dejaba el OTRO sin ratón ni teclado —un agarre exclusivo de Wayland no
    //  es por pantalla, y Hyprland lo trata como modal—. Así se puede tener
    //  Ajustes en la segunda pantalla y seguir trabajando en la primera.
    tecladoAlPasar: true

    //  Quién dice que el ratón está dentro: el fondo y la tarjeta, cada uno
    //  con su `HoverHandler`.
    //
    //  Handlers y no `MouseArea`: un MouseArea con `hoverEnabled` se come el
    //  roce y no lo deja bajar, así que al pasar por CUALQUIER botón de dentro
    //  —y esta ventana es toda botones— el de debajo se apagaría y soltaríamos
    //  el teclado a media escritura. Un `HoverHandler` es pasivo: se entera
    //  aunque el puntero esté sobre un hijo suyo.
    //
    //  Dos y no uno porque la tarjeta es HERMANA del fondo, no hija: el
    //  handler del fondo no ve lo que pasa sobre ella.
    ratonDentro: roceFondo.hovered || roceTarjeta.hovered

    //  Qué sección se está mirando, y qué se ha escrito en el buscador. Vive
    //  aquí y no en el plugin: al cerrar y volver a abrir se quiere empezar
    //  arriba y sin filtro, no donde lo dejaste hace tres días.
    property int seccion: 0
    property string busqueda: ""

    readonly property var todas: Settings.definicion

    //  Lo que sale en la lateral. Las secciones que aportan los plugins NO:
    //  viven dentro de la fila de su plugin, en la sección Plugins, al lado
    //  del interruptor que las enciende. Siguen en `todas`, y eso importa —el
    //  buscador recorre la lista entera y las encuentra igual.
    readonly property var lateral: ventana.todas.filter(function (g) {
        return g.enLateral !== false
    })

    //  Lo que se pinta a la derecha.
    //
    //  Sin buscar, la sección elegida y ya. Buscando, las coincidencias de
    //  TODAS las secciones, cada una bajo su título: quien escribe «captura»
    //  no sabe en qué cajón está lo que busca — si lo supiera no escribiría.
    readonly property var contenido: {
        const q = String(ventana.busqueda).trim().toLowerCase()
        if (q.length === 0)
            return ventana.seccion < ventana.lateral.length
                ? [ventana.lateral[ventana.seccion]] : []

        const fuera = []
        for (let i = 0; i < ventana.todas.length; ++i) {
            const g = ventana.todas[i]
            const casaGrupo = String(g.grupo).toLowerCase().indexOf(q) >= 0
            const ops = (g.opciones || []).filter(function (o) {
                return casaGrupo
                    || String(o.nombre || "").toLowerCase().indexOf(q) >= 0
                    || String(o.desc || "").toLowerCase().indexOf(q) >= 0
            })
            if (ops.length > 0)
                fuera.push({ grupo: g.grupo, glifo: g.glifo, desc: g.desc,
                             vista: g.vista, opciones: ops })
        }
        return fuera
    }

    readonly property int cuantasCasan: {
        let n = 0
        for (let i = 0; i < ventana.contenido.length; ++i)
            n += ventana.contenido[i].opciones.length
        return n
    }

    function elegir(i) {
        ventana.seccion = i
        ventana.busqueda = ""
        campo.text = ""
    }

    // ── el fondo ──────────────────────────────────────────────────
    //
    //  Oscurece lo que hay detrás y recoge el clic que cierra. Es la salida
    //  que todo el mundo prueba antes de buscar un aspa.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        HoverHandler { id: roceFondo }

        MouseArea {
            anchors.fill: parent
            onClicked: ventana.plugin.cerrarVentana()
        }
    }

    //  El teclado: escribir busca, ESC deshace y luego cierra. El foco se pide
    //  con reintento porque la capa tarda en concederlo — el mismo baile que
    //  hacen el lanzador y la tienda.
    property int intentos: 0

    Component.onCompleted: {
        campo.forceActiveFocus()
        foco.start()
    }

    //  Al volver el ratón, el campo recupera el foco. Al soltar el teclado se
    //  pierde, y sin esto habría que pinchar el buscador cada vez que vuelves
    //  de la otra pantalla: cambiar una molestia por otra.
    onRatonDentroChanged: if (ratonDentro) campo.forceActiveFocus()

    Timer {
        id: foco
        interval: 140
        onTriggered: {
            campo.forceActiveFocus()
            if (!campo.activeFocus && ventana.intentos < 6) {
                ventana.intentos += 1
                restart()
            }
        }
    }

    // ── la tarjeta ────────────────────────────────────────────────
    Rectangle {
        id: tarjeta

        anchors.centerIn: parent
        width: Math.min(1040, parent.width - 120)
        height: Math.min(700, parent.height - 120)
        radius: 22
        color: Theme.islandBg
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)

        HoverHandler { id: roceTarjeta }

        //  Que el clic dentro NO llegue al fondo, o cerrar sería imposible sin
        //  acertar en el hueco entre controles.
        MouseArea { anchors.fill: parent }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // ── la barra lateral ──────────────────────────────────
            Rectangle {
                Layout.preferredWidth: 248
                Layout.fillHeight: true
                topLeftRadius: 21
                bottomLeftRadius: 21
                color: Qt.rgba(1, 1, 1, 0.03)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    //  El buscador. Con cerca de cincuenta opciones repartidas
                    //  en dieciséis cajones, esto es lo que de verdad arregla
                    //  el «no encuentro nada».
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 17
                        color: Theme.surface
                        border.width: 1
                        border.color: campo.activeFocus
                            ? Theme.blue : "transparent"

                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 8

                            IconGlyph {
                                text: Theme.ico.search
                                color: campo.activeFocus ? Theme.muted : Theme.dim
                                font.pixelSize: 13
                                renderType: Text.NativeRendering
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                IslandLabel {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: campo.text.length === 0
                                    text: Idioma.t("Buscar en los ajustes")
                                    color: Theme.dim
                                    font.pixelSize: 12
                                }

                                TextInput {
                                    id: campo
                                    anchors.fill: parent
                                    cursorDelegate: IslandCursor {}
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.ink
                                    font.family: Theme.uiFont
                                    font.pixelSize: 12
                                    clip: true
                                    selectByMouse: true
                                    selectionColor: Theme.blue
                                    text: ventana.busqueda
                                    onTextEdited: ventana.busqueda = text

                                    //  ESC deshace primero lo de dentro y solo
                                    //  cierra cuando ya no queda nada que
                                    //  deshacer. Si se dejara subir siempre,
                                    //  borrar una búsqueda costaría cerrar la
                                    //  ventana entera.
                                    Keys.onPressed: function (ev) {
                                        if (ev.key !== Qt.Key_Escape)
                                            return
                                        if (campo.text.length > 0) {
                                            campo.text = ""
                                            ventana.busqueda = ""
                                        } else {
                                            ventana.plugin.cerrarVentana()
                                        }
                                        ev.accepted = true
                                    }
                                }
                            }
                        }
                    }

                    // ── las secciones ─────────────────────────────
                    K4.Rodillo {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: ventana.lateral

                                //  Rectángulo pelado y no `K4.Baldosa`: la
                                //  Baldosa dibuja un borde interior SIEMPRE, y
                                //  con dieciséis seguidas la lateral se
                                //  convierte en una rejilla de cajas. Aquí lo
                                //  que tiene que destacar es UNA: la que estás
                                //  mirando.
                                delegate: Rectangle {
                                    id: entrada
                                    required property var modelData
                                    required property int index

                                    readonly property bool activa:
                                        ventana.busqueda.length === 0
                                        && ventana.seccion === entrada.index

                                    width: parent.width
                                    height: 38
                                    radius: 10
                                    color: entrada.activa
                                        ? Qt.rgba(Theme.blue.r, Theme.blue.g,
                                                  Theme.blue.b, 0.18)
                                        : (raton.containsMouse
                                           ? Qt.rgba(1, 1, 1, 0.05) : "transparent")

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    MouseArea {
                                        id: raton
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ventana.elegir(entrada.index)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 11
                                        anchors.rightMargin: 11
                                        spacing: 10

                                        IconGlyph {
                                            Layout.alignment: Qt.AlignVCenter
                                            //  Sin icono propio —una sección de
                                            //  plugin que no lo declaró— se usa
                                            //  la pieza de puzle, que es como
                                            //  la barra dibuja «esto es un
                                            //  plugin» en todas partes.
                                            text: String.fromCodePoint(
                                                entrada.modelData.glifo
                                                    ? entrada.modelData.glifo : 0xF0431)
                                            color: entrada.activa
                                                ? Theme.blue : Theme.muted
                                            font.pixelSize: 14
                                            renderType: Text.NativeRendering
                                        }

                                        IslandLabel {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            text: entrada.modelData.grupo
                                            textFormat: Text.PlainText
                                            color: entrada.activa
                                                ? Theme.ink : Theme.muted
                                            font.pixelSize: 12
                                            font.weight: entrada.activa
                                                ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── el contenido ──────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // La cabecera: qué sección es y de qué va.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 26
                        anchors.rightMargin: 16
                        spacing: 14

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: 22
                            color: Qt.rgba(Theme.blue.r, Theme.blue.g,
                                           Theme.blue.b, 0.16)

                            IconGlyph {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(
                                    ventana.busqueda.length > 0 ? 0xF0349
                                    : (ventana.contenido.length > 0
                                       && ventana.contenido[0].glifo
                                       ? ventana.contenido[0].glifo : 0xF0431))
                                color: Theme.blue
                                font.pixelSize: 20
                                renderType: Text.NativeRendering
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 3

                            IslandLabel {
                                Layout.fillWidth: true
                                text: ventana.busqueda.length > 0
                                    ? Idioma.f(Idioma.t("%1 coinciden con «%2»"),
                                               ventana.cuantasCasan, ventana.busqueda)
                                    : (ventana.contenido.length > 0
                                       ? ventana.contenido[0].grupo : "")
                                textFormat: Text.PlainText
                                font.pixelSize: 19
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            IslandLabel {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: ventana.busqueda.length > 0
                                    ? Idioma.t("De todas las secciones a la vez")
                                    : (ventana.contenido.length > 0
                                       ? (ventana.contenido[0].desc || "") : "")
                                textFormat: Text.PlainText
                                color: Theme.dim
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                            }
                        }

                        //  En qué commit está la barra. Chiquito y apagado:
                        //  contesta «¿qué versión tengo?», que no se preguntaba
                        //  en ninguna otra parte, sin competir con el título.
                        IslandLabel {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 18
                            text: ventana.plugin.version.commit
                            textFormat: Text.PlainText
                            color: Theme.dim
                            font.pixelSize: 9
                        }

                        //  Y la novedad SÍ es una noticia, así que se pone azul
                        //  y se pulsa.
                        //
                        //  Con cambios sin guardar no se ofrece el botón:
                        //  `./instalar` no toca el código con el árbol sucio
                        //  —a propósito— así que sería un botón que no hace lo
                        //  que dice. Se dice lo que pasa y decide quien lea,
                        //  que el trabajo sin guardar es suyo.
                        Rectangle {
                            id: novedad
                            visible: ventana.plugin.version.hayNovedad
                            Layout.preferredWidth: textoNovedad.implicitWidth + 22
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 12
                            radius: 12

                            readonly property bool ofrece: !ventana.plugin.version.sucio

                            color: !ofrece ? Theme.track
                                : (ratonNovedad.containsMouse ? "#4a9eff" : Theme.blue)

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IslandLabel {
                                id: textoNovedad
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: novedad.ofrece
                                    ? Idioma.f(Idioma.t("%1 nuevos · Actualizar"),
                                               ventana.plugin.version.detras)
                                    : Idioma.f(Idioma.t("%1 nuevos · guarda tus cambios"),
                                               ventana.plugin.version.detras)
                                color: novedad.ofrece ? Theme.ink : Theme.muted
                                font.pixelSize: 10
                                font.weight: novedad.ofrece ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                id: ratonNovedad
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: novedad.ofrece
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    ventana.plugin.version.actualizar()
                                    ventana.plugin.cerrarVentana()
                                }
                            }
                        }

                        //  El aspa. Se cierra con ESC y tocando fuera, pero eso
                        //  hay que saberlo: el aspa se ve.
                        MediaButton {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 12
                            glyph: Theme.ico.close
                            glyphSize: 15
                            glyphColor: Theme.muted
                            onActivated: ventana.plugin.cerrarVentana()
                        }
                    }
                }

                // ── las opciones ──────────────────────────────────
                K4.Rodillo {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Column {
                        width: parent.width
                        spacing: 14
                        topPadding: 2
                        bottomPadding: 24
                        leftPadding: 26
                        rightPadding: 22

                        Repeater {
                            model: ventana.contenido

                            delegate: ColumnLayout {
                                id: bloque
                                required property var modelData

                                width: parent.width - parent.leftPadding
                                       - parent.rightPadding
                                spacing: 6

                                //  Buscando hay varias secciones a la vez, y
                                //  sin su título las coincidencias se leen como
                                //  una lista suelta sin contexto. Con una
                                //  sección sola el título ya está en la
                                //  cabecera y repetirlo sería ruido.
                                IslandLabel {
                                    visible: ventana.busqueda.length > 0
                                    text: bloque.modelData.grupo
                                    textFormat: Text.PlainText
                                    color: Theme.dim
                                    font.pixelSize: 9
                                    font.capitalization: Font.AllUppercase
                                    Layout.leftMargin: 2
                                }

                                //  Y una sección puede traer algo suyo encima
                                //  de sus opciones. La Island trae un croquis
                                //  de la pantalla: es lo que convierte tres
                                //  palabras parecidas en una diferencia que se
                                //  ve.
                                Loader {
                                    Layout.fillWidth: true
                                    Layout.bottomMargin: active ? 6 : 0
                                    active: bloque.modelData.vista === "island"
                                    sourceComponent: Component { PrevioIsland {} }
                                }

                                //  Cada grupo elige cómo se pinta. Hoy solo
                                //  Plugins pide algo distinto —casi cuarenta
                                //  filas, cada una con lo suyo dentro— y el
                                //  resto se pinta como siempre. Cuando otra
                                //  sección quiera lo suyo, se añade aquí y no
                                //  se toca nada más.
                                Repeater {
                                    model: bloque.modelData.opciones
                                    delegate: Loader {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: item
                                            ? item.Layout.preferredHeight : 40
                                        property var dato: modelData
                                        sourceComponent:
                                            bloque.modelData.vista === "plugins"
                                                ? comoPlugin : comoOpcion
                                    }
                                }
                            }
                        }

                        //  Ni una opción. Solo puede pasar buscando: una
                        //  sección sin opciones no se ofrece en la lateral.
                        IslandLabel {
                            visible: ventana.contenido.length === 0
                            width: parent.width - parent.leftPadding
                                   - parent.rightPadding
                            horizontalAlignment: Text.AlignHCenter
                            topPadding: 60
                            text: Idioma.f(Idioma.t("Nada casa con «%1»"),
                                           ventana.busqueda)
                            textFormat: Text.PlainText
                            color: Theme.dim
                            font.pixelSize: 12
                        }
                    }
                }

                // ── el pie ────────────────────────────────────────
                //
                //  Estado del cargador y las dos herramientas del sistema.
                //  Venían del panel de la island y se vienen enteras: el
                //  contador distingue «lo apagaste tú» de «falló al cargar»,
                //  que es lo que evita diagnosticar a ciegas desde el
                //  terminal, y Redes y Sonido son las dos ventanas del
                //  escritorio que uno acaba abriendo desde aquí.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    Layout.leftMargin: 26
                    Layout.rightMargin: 22
                    Layout.bottomMargin: 8
                    spacing: 8

                    IconGlyph {
                        text: String.fromCodePoint(0xF06A0)
                        color: Object.keys(PluginManager.errores).length > 0
                            ? Theme.red : Theme.green
                        font.pixelSize: 13
                        renderType: Text.NativeRendering
                        Layout.alignment: Qt.AlignVCenter
                    }

                    //  Abre la tienda en vez de taparse con ella. Los
                    //  interruptores de cada plugin siguen en su sección, que
                    //  sí son ajustes; traer, actualizar y quitar son otra
                    //  cosa y viven en lo suyo.
                    K4.Baldosa {
                        Layout.preferredWidth: 78
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        radius: 13
                        onPulsada: {
                            ventana.plugin.cerrarVentana()
                            PluginManager.abrirAplicacion("tienda")
                        }

                        IslandLabel {
                            anchors.centerIn: parent
                            text: Idioma.t("Plugins")
                            textFormat: Text.PlainText
                            color: Theme.muted
                            font.pixelSize: 10
                        }
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: PluginManager.catalogo.length + Idioma.t(" plugins · ")
                            + PluginManager.catalogo.filter(function (m) {
                                return PluginManager.estaHabilitado(m.id)
                            }).length + Idioma.t(" habilitados")
                            + (Object.keys(PluginManager.errores).length > 0
                               ? " · " + Object.keys(PluginManager.errores).length
                                 + Idioma.t(" con errores") : "")
                        color: Theme.dim
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }

                    IslandLabel {
                        text: Idioma.t("Herramientas del sistema")
                        color: Theme.dim
                        font.pixelSize: 9
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Repeater {
                        model: [
                            { nombre: Idioma.t("Redes"), glifo: 0xF05A9,
                              orden: ["nm-connection-editor"] },
                            { nombre: Idioma.t("Sonido"), glifo: 0xF057E,
                              orden: ["pavucontrol"] }
                        ]

                        delegate: K4.Baldosa {
                            id: herramienta
                            required property var modelData

                            Layout.preferredWidth: contenido.implicitWidth + 22
                            Layout.preferredHeight: 26
                            Layout.alignment: Qt.AlignVCenter
                            radius: 13

                            onPulsada: {
                                K4.Sistema.lanzar(herramienta.modelData.orden)
                                ventana.plugin.cerrarVentana()
                            }

                            RowLayout {
                                id: contenido
                                anchors.centerIn: parent
                                spacing: 6

                                IconGlyph {
                                    text: String.fromCodePoint(herramienta.modelData.glifo)
                                    color: Theme.muted
                                    font.pixelSize: 12
                                    renderType: Text.NativeRendering
                                }

                                IslandLabel {
                                    text: herramienta.modelData.nombre
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── las dos formas de pintar una fila ─────────────────────────
    Component {
        id: comoOpcion
        FilaOpcion { modelData: parent.dato }
    }

    Component {
        id: comoPlugin
        FilaPlugin { modelData: parent.dato }
    }
}
