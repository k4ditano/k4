//  La tienda de plugins: lo que tienes y lo que hay publicado.
//
//  Instalar un plugin era exclusivamente de terminal, y en la barra los
//  permisos aparecían concatenados a la descripción en nueve píxeles
//  truncados. Eso no es enseñar unos permisos: es tenerlos escritos.
//
//  Aquí hay sitio para decir de dónde viene un plugin, en qué commit está, qué
//  pide y qué significa cada cosa que pide. En una fila de Ajustes no cabía, y
//  por eso antes no estaba.
//
//  Todo pasa por `tools/plugins.py`, el mismo que usa la terminal. No hay un
//  camino «de la barra»: serían dos validaciones distintas, y la menos usada
//  sería la que tiene los agujeros.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"

//  `FadeIn` y no `Item`: es lo que usan las demás vistas y es lo que hace que
//  aparezca como aparecen ellas. Salió de vivir dentro de Ajustes, donde el
//  padre ponía la aparición, los márgenes y la cabecera; al sacarla a
//  aplicación se quedó sin las tres y pegada a los bordes.
FadeIn {
    id: tienda

    //  El host inyecta el plugin al crear la vista; el estado que tiene que
    //  sobrevivir a cerrar la island vive ahí, no aquí.
    required property var plugin

    //  Qué se está mirando: 0 lo instalado, 1 lo publicado.
    property int pestana: 0

    //  Lo que se ha escrito en el buscador. Vive aquí y no en el plugin, como
    //  `pestana`: si se cierra la island, que la próxima vez se abra limpia.
    property string busqueda: ""

    //  La lista de la pestaña de turno, ya filtrada. Se busca por id, por
    //  nombre y por descripción: con treinta y siete plugins uno se acuerda de
    //  «lo del portapapeles» antes que de cómo se llama.
    readonly property var visibles: {
        const base = tienda.pestana === 0 ? tienda.mios : tienda.entradas
        const q = String(tienda.busqueda).trim().toLowerCase()
        if (q.length === 0)
            return base
        return base.filter(function (m) { return tienda.casa(m, q) })
    }

    function casa(m, q) {
        return String(m.id || "").toLowerCase().indexOf(q) >= 0
            || String(m.title || "").toLowerCase().indexOf(q) >= 0
            || String(m.description || "").toLowerCase().indexOf(q) >= 0
    }

    //  Cuántos casarían en LA OTRA pestaña. Buscas «pomodoro» en Instalados,
    //  no lo tienes, y lo que quieres saber es justo eso: que está en
    //  Descubrir. Sólo se dice si esa lista ya está cargada — si no, callar,
    //  que prometer resultados que no se han pedido es peor que no decir nada.
    readonly property int enLaOtra: {
        const q = String(tienda.busqueda).trim().toLowerCase()
        if (q.length === 0)
            return 0
        const otra = tienda.pestana === 0 ? tienda.entradas : tienda.mios
        let n = 0
        for (let i = 0; i < otra.length; ++i)
            if (tienda.casa(otra[i], q))
                n += 1
        return n
    }

    //  Lo que devolvió el registro, ya con `instalado` y `alDia` marcados.
    property var entradas: []
    property var descartadas: []
    property string queja: ""

    //  ¿Ha saltado algo de lo que impide publicar? En la barra no impide
    //  instalar —es tu máquina—, pero cambia lo que dice el botón.
    readonly property bool bloqueado: {
        if (!examen || !examen.reglas)
            return false
        for (let i = 0; i < examen.reglas.length; ++i)
            if (examen.reglas[i].bloquea)
                return true
        return false
    }

    //  El plugin que se está a punto de instalar, tal y como lo vio el examen.
    //  Mientras esto no sea nulo, manda el diálogo.
    property var examen: null

    //  Lo instalado, del catálogo que ya tiene la barra: así la pestaña de
    //  siempre funciona aunque no haya red.
    readonly property var mios: PluginManager.catalogo.filter(function (m) {
        return !!m.deUsuario
    })

    property int intentosFoco: 0

    Component.onCompleted: {
        PluginManager.comprobarNovedades()
        //  Que se pueda escribir nada más abrir, sin tener que pinchar el
        //  campo. `grabKeyboard` lleva las teclas a la superficie, pero el
        //  foco dentro hay que pedirlo, y la capa tarda un poco en concederlo:
        //  es el mismo reintento que hace el lanzador.
        campo.forceActiveFocus()
        foco.start()
    }

    Timer {
        id: foco
        interval: 140
        onTriggered: {
            campo.forceActiveFocus()
            if (!campo.activeFocus && tienda.intentosFoco < 6) {
                tienda.intentosFoco += 1
                restart()
            }
        }
    }

    Connections {
        target: PluginManager

        function onRegistroListo(lista, fuera) {
            tienda.entradas = lista
            tienda.descartadas = fuera
            tienda.queja = ""
        }

        function onExamenListo(d) {
            tienda.examen = d
        }

        function onObraFallo(que, motivo) {
            tienda.queja = motivo
            //  Si falla el examen, el diálogo no llega a abrirse: lo que se
            //  ve es el porqué, y no una ventana pidiendo permiso para algo
            //  que no se ha podido mirar.
            tienda.examen = null
        }

        function onObraHecha(que, id, bien, motivo) {
            tienda.queja = bien ? "" : motivo
            tienda.examen = null
            if (bien && tienda.pestana === 1)
                PluginManager.buscarEnRegistro()
            if (bien)
                PluginManager.comprobarNovedades()
        }
    }

    onPestanaChanged: {
        if (pestana === 1 && entradas.length === 0)
            PluginManager.buscarEnRegistro()
    }

    ColumnLayout {
        anchors.fill: parent
        //  Los mismos de Ajustes y del resto: 18 a los lados, 12 arriba y 22
        //  abajo, que lo último de la columna no quede pegado al borde.
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 12
        anchors.bottomMargin: 22
        spacing: 10

        //  ── cabecera ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 9

            IconGlyph {
                text: String.fromCodePoint(0xF0431)
                color: Theme.muted
                font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Idioma.t("Plugins")
                textFormat: Text.PlainText
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            //  Cerrar. El ESC también cierra —el host llama a `close()`— pero
            //  un panel sin botón de cerrar obliga a saberlo, y eso no se
            //  supone: el resto de aplicaciones lo tienen.
            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 15
                glyphColor: Theme.muted
                onActivated: tienda.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        //  ── las dos pestañas ─────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [Idioma.t("Instalados"), Idioma.t("Descubrir")]

                K4.Baldosa {
                    required property int index
                    required property string modelData

                    Layout.preferredWidth: 108
                    Layout.preferredHeight: 30
                    radius: 15
                    activa: tienda.pestana === index
                    onPulsada: tienda.pestana = index

                    IslandLabel {
                        anchors.centerIn: parent
                        text: parent.modelData
                        textFormat: Text.PlainText
                        color: tienda.pestana === parent.index
                            ? Theme.ink : Theme.muted
                        font.pixelSize: 11
                    }
                }
            }

            //  El buscador va en el hueco que ya había entre las pestañas y
            //  el botón de refrescar: no roba una línea a la lista, que es lo
            //  que se ha venido a mirar.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 15
                color: Theme.surface
                border.width: 1
                border.color: campo.activeFocus ? Theme.blue : "transparent"

                Behavior on border.color { ColorAnimation { duration: 140 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 11
                    anchors.rightMargin: 6
                    spacing: 7

                    IconGlyph {
                        text: Theme.ico.search
                        color: campo.activeFocus ? Theme.muted : Theme.dim
                        font.pixelSize: 12
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        IslandLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: campo.text.length === 0
                            text: Idioma.t("Buscar plugins")
                            color: Theme.dim
                            font.pixelSize: 11
                        }

                        TextInput {
                            id: campo
                            anchors.fill: parent
                            cursorDelegate: IslandCursor {}
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 11
                            clip: true
                            selectByMouse: true
                            selectionColor: Theme.blue
                            text: tienda.busqueda
                            onTextEdited: tienda.busqueda = text

                            //  ESC deshace primero lo de dentro y sólo cierra
                            //  cuando ya no hay nada que deshacer. Si se dejara
                            //  subir siempre, borrar la búsqueda costaría cerrar
                            //  la aplicación entera.
                            Keys.onPressed: function (ev) {
                                if (ev.key !== Qt.Key_Escape)
                                    return
                                if (campo.text.length > 0) {
                                    campo.text = ""
                                    tienda.busqueda = ""
                                } else {
                                    tienda.plugin.close()
                                }
                                ev.accepted = true
                            }
                        }
                    }

                    //  Borrar lo escrito sin tener que mantener el borrado.
                    K4.Baldosa {
                        visible: campo.text.length > 0
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Layout.alignment: Qt.AlignVCenter
                        radius: 10
                        onPulsada: {
                            campo.text = ""
                            tienda.busqueda = ""
                            campo.forceActiveFocus()
                        }

                        IconGlyph {
                            anchors.centerIn: parent
                            text: Theme.ico.close
                            color: Theme.dim
                            font.pixelSize: 10
                        }
                    }
                }
            }

            //  Refrescar. En «Descubrir» vuelve a pedir el registro; en
            //  «Instalados», a preguntar si hay algo más nuevo.
            K4.Baldosa {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 15
                pulsable: !PluginManager.ocupado
                onPulsada: {
                    if (tienda.pestana === 1)
                        PluginManager.buscarEnRegistro()
                    else
                        PluginManager.comprobarNovedades()
                }

                IconGlyph {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF0450)
                    color: PluginManager.ocupado ? Theme.dim : Theme.muted
                    font.pixelSize: 13

                    RotationAnimation on rotation {
                        running: PluginManager.ocupado
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                }
            }
        }

        //  ── lo que haya salido mal, dicho y no escondido ─────────────
        IslandLabel {
            Layout.fillWidth: true
            visible: tienda.queja.length > 0
            text: tienda.queja
            textFormat: Text.PlainText
            color: Theme.red
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }

        //  Cuando la barra ha tenido que tirar de sus copias. No es un error
        //  —tus plugins están y funcionan— pero enterarse importa: significa
        //  que algo de debajo se rompió y se salvó por la red, y la red no
        //  conviene gastarla dos veces sin mirar.
        IslandLabel {
            Layout.fillWidth: true
            visible: PluginManager.catalogoDe === "cache"
                     || PluginManager.estadoRepuesto
            text: PluginManager.catalogoDe === "cache"
                ? Idioma.t("No se ha podido leer la lista de plugins: esto es la última buena. Pulsa refrescar.")
                : Idioma.t("El fichero de plugins encendidos estaba ilegible: repuesto de la copia.")
            textFormat: Text.PlainText
            color: Theme.yellow
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }

        //  ── cuando la búsqueda no casa con nada ──────────────────────
        //
        //  Sólo para el filtro. Que la lista salga vacía por otros motivos
        //  —el registro aún cargando, o no tener plugins de usuario— ya se
        //  contaba como se contaba, y no es lo que se está tocando aquí.
        IslandLabel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tienda.busqueda.trim().length > 0
                     && tienda.visibles.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: {
                const q = tienda.busqueda.trim()
                const aqui = tienda.pestana === 0
                    ? Idioma.f(Idioma.t("No tienes nada que case con «%1»"), q)
                    : Idioma.f(Idioma.t("Nada publicado casa con «%1»"), q)
                if (tienda.enLaOtra === 0)
                    return aqui
                //  Y dónde sí está, que es lo que se ha venido a saber.
                return aqui + "\n" + (tienda.pestana === 0
                    ? Idioma.f(Idioma.t("Hay %1 en Descubrir"), tienda.enLaOtra)
                    : Idioma.f(Idioma.t("Tienes %1 instalado(s)"), tienda.enLaOtra))
            }
            color: Theme.dim
            font.pixelSize: 11
        }

        //  ── la lista ─────────────────────────────────────────────────
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            visible: tienda.visibles.length > 0
            model: tienda.visibles

            ScrollBar.vertical: IslandScrollBar {}

            delegate: K4.Baldosa {
                id: fila
                required property var modelData

                width: ListView.view ? ListView.view.width : 0
                height: cuerpo.implicitHeight + 22
                pulsable: false

                readonly property bool esDelRegistro: tienda.pestana === 1
                readonly property string ident: String(modelData.id || "")
                readonly property var novedad: PluginManager.novedadDe(ident)

                ColumnLayout {
                    id: cuerpo
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        IslandLabel {
                            text: String(fila.modelData.title || fila.ident)
                            textFormat: Text.PlainText
                            color: Theme.ink
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.maximumWidth: 200
                        }

                        IslandLabel {
                            visible: !!fila.modelData.version
                            text: "v" + String(fila.modelData.version || "")
                            textFormat: Text.PlainText
                            color: Theme.dim
                            font.pixelSize: 9
                        }

                        //  El sello de estado. Que se lea de un vistazo qué
                        //  pasa con este plugin es la mitad del trabajo.
                        Rectangle {
                            visible: fila.sello.length > 0
                            radius: 7
                            Layout.preferredHeight: 15
                            Layout.preferredWidth: selloTexto.implicitWidth + 12
                            color: Qt.rgba(fila.selloColor.r, fila.selloColor.g,
                                           fila.selloColor.b, 0.16)

                            IslandLabel {
                                id: selloTexto
                                anchors.centerIn: parent
                                text: fila.sello
                                textFormat: Text.PlainText
                                color: fila.selloColor
                                font.pixelSize: 8
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: String(fila.modelData.description || "")
                        textFormat: Text.PlainText
                        color: Theme.muted
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    //  De dónde viene y en qué commit. Antes esto no se
                    //  enseñaba en ningún sitio de la barra.
                    IslandLabel {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: fila.procedencia
                        textFormat: Text.PlainText
                        color: Theme.dim
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 6

                        //  Los permisos, uno a uno y no en una lista pegada
                        //  a la descripción.
                        Repeater {
                            model: fila.modelData.permisos || []

                            Rectangle {
                                required property string modelData
                                radius: 6
                                Layout.preferredHeight: 15
                                Layout.preferredWidth: permiso.implicitWidth + 12
                                color: Theme.track

                                IslandLabel {
                                    id: permiso
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    textFormat: Text.PlainText
                                    color: Theme.muted
                                    font.pixelSize: 8
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        BotonTienda {
                            visible: fila.esDelRegistro && !fila.modelData.instalado
                            texto: Idioma.t("Instalar")
                            resalta: true
                            onPulsado: tienda.pedirInstalar(fila.modelData)
                        }

                        BotonTienda {
                            visible: fila.esDelRegistro && !!fila.modelData.instalado
                                     && !fila.modelData.alDia
                            texto: Idioma.t("Actualizar")
                            resalta: true
                            onPulsado: tienda.pedirInstalar(fila.modelData)
                        }

                        BotonTienda {
                            visible: !fila.esDelRegistro && !!fila.novedad
                                     && fila.novedad.estado === "novedad"
                            texto: Idioma.t("Actualizar")
                            resalta: true
                            onPulsado: PluginManager.actualizarPlugin(
                                fila.ident, fila.novedad.suyo)
                        }

                        IslandLabel {
                            visible: !fila.esDelRegistro
                                     && fila.modelData.cargable === false
                            Layout.fillWidth: true
                            text: Idioma.porque(fila.modelData.motivo,
                                                fila.modelData.detalle)
                            textFormat: Text.PlainText
                            color: Theme.red
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                        BotonTienda {
                            visible: !fila.esDelRegistro
                            texto: Idioma.t("Quitar")
                            peligro: true
                            onPulsado: PluginManager.quitarPlugin(fila.ident, false)
                        }
                    }
                }

                //  ── el sello de esta fila ────────────────────────────
                readonly property string sello: {
                    if (esDelRegistro)
                        return modelData.instalado
                            ? (modelData.alDia ? Idioma.t("al día")
                                               : Idioma.t("hay novedad"))
                            : ""
                    if (PluginManager.errores[ident])
                        return Idioma.t("no carga")
                    if (novedad && novedad.estado === "novedad")
                        return Idioma.t("hay novedad")
                    if (novedad && novedad.estado === "sin-anclar")
                        return Idioma.t("sin commit")
                    if (novedad && novedad.estado === "al-dia")
                        return Idioma.t("al día")
                    return ""
                }

                readonly property color selloColor: {
                    if (sello === Idioma.t("no carga"))
                        return Theme.red
                    if (sello === Idioma.t("hay novedad"))
                        return Theme.yellow
                    if (sello === Idioma.t("al día"))
                        return Theme.green
                    return Theme.dim
                }

                readonly property string procedencia: {
                    if (esDelRegistro) {
                        const sha = String(modelData.commit || "")
                        return String(modelData.repo || "")
                            + (sha ? "  ·  " + sha.substring(0, 12) : "")
                    }
                    if (!novedad)
                        return ""
                    if (novedad.estado === "sin-anclar")
                        return Idioma.t("instalado antes de que se guardara el commit")
                    if (novedad.estado === "fuera-del-registro")
                        return Idioma.t("no está en el registro")
                    const mio = String(novedad.mio || "").substring(0, 12)
                    return mio ? Idioma.t("commit ") + mio : ""
                }
            }
        }

        //  Cuántas entradas del registro venían mal puestas. Se dice en vez de
        //  callarlo: si alguien publica algo roto, quiere enterarse.
        IslandLabel {
            Layout.fillWidth: true
            visible: tienda.pestana === 1 && tienda.descartadas.length > 0
            text: tienda.descartadas.length
                  + Idioma.t(" entrada(s) del registro mal puestas, no se enseñan")
            textFormat: Text.PlainText
            color: Theme.yellow
            font.pixelSize: 9
        }
    }

    //  ── el diálogo de permisos ───────────────────────────────────────
    //
    //  Lo que hace que instalar desde la barra sea defendible. Enseña QUÉ se
    //  va a instalar, DE DÓNDE y EN QUÉ COMMIT — y ese commit es el que se
    //  instala después, porque es el que devolvió el examen: si la rama se
    //  mueve mientras lees esto, lo que llega sigue siendo lo que leíste.
    Rectangle {
        anchors.fill: parent
        visible: !!tienda.examen
        color: Qt.rgba(0, 0, 0, 0.72)

        //  Que no se pulse lo de detrás mientras el diálogo está abierto.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {}
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 24, 380)
            height: dialogo.implicitHeight + 32
            radius: 18
            color: Theme.surface

            ColumnLayout {
                id: dialogo
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 18
                spacing: 8

                IslandLabel {
                    Layout.fillWidth: true
                    text: tienda.examen
                        ? (tienda.examen.reemplaza ? Idioma.t("Actualizar ")
                                                   : Idioma.t("Instalar "))
                          + String(tienda.examen.plugin.title || "")
                        : ""
                    textFormat: Text.PlainText
                    color: Theme.ink
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                IslandLabel {
                    Layout.fillWidth: true
                    text: tienda.examen
                        ? String(tienda.examen.plugin.description || "") : ""
                    textFormat: Text.PlainText
                    color: Theme.muted
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    Layout.preferredHeight: 1
                    color: Theme.track
                }

                //  El origen, con el commit entero a la vista.
                IslandLabel {
                    Layout.fillWidth: true
                    text: tienda.examen ? String(tienda.examen.repo || "") : ""
                    textFormat: Text.PlainText
                    color: Theme.muted
                    font.pixelSize: 9
                    elide: Text.ElideMiddle
                }

                IslandLabel {
                    Layout.fillWidth: true
                    text: tienda.examen
                        ? Idioma.t("commit ") + String(tienda.examen.commit || "")
                        : ""
                    textFormat: Text.PlainText
                    color: Theme.dim
                    font.pixelSize: 9
                    elide: Text.ElideMiddle
                }

                IslandLabel {
                    Layout.fillWidth: true
                    visible: !!tienda.examen && !!tienda.examen.commitAnterior
                             && tienda.examen.commitAnterior !== tienda.examen.commit
                    text: tienda.examen
                        ? Idioma.t("tienes el ")
                          + String(tienda.examen.commitAnterior || "").substring(0, 12)
                        : ""
                    textFormat: Text.PlainText
                    color: Theme.dim
                    font.pixelSize: 9
                }

                //  Los permisos, desglosados y explicados. Esta es la parte
                //  que no cabía en Ajustes.
                IslandLabel {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: Idioma.t("Pide:")
                    textFormat: Text.PlainText
                    color: Theme.ink
                    font.pixelSize: 10
                    visible: permisos.count > 0
                }

                Repeater {
                    id: permisos
                    model: tienda.examen ? (tienda.examen.plugin.permisos || []) : []

                    RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        spacing: 7

                        IconGlyph {
                            text: String.fromCodePoint(0xF0133)
                            color: Theme.yellow
                            font.pixelSize: 10
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 2
                        }

                        IslandLabel {
                            Layout.fillWidth: true
                            text: tienda.explicar(parent.modelData)
                            textFormat: Text.PlainText
                            color: Theme.muted
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                IslandLabel {
                    Layout.fillWidth: true
                    visible: permisos.count === 0
                    text: Idioma.t("No pide ningún permiso.")
                    textFormat: Text.PlainText
                    color: Theme.muted
                    font.pixelSize: 10
                }

                //  Lo que hayan saltado las reglas. Un plugin del registro
                //  no llega aquí con nada que bloquee —eso se para al
                //  publicar—, pero uno traído a mano sí puede, y entonces es
                //  justo lo que hay que leer antes de decir que sí.
                Repeater {
                    id: reglas
                    model: tienda.examen ? (tienda.examen.reglas || []) : []

                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 7

                        IconGlyph {
                            text: String.fromCodePoint(0xF0026)
                            color: parent.modelData.bloquea ? Theme.red
                                                            : Theme.yellow
                            font.pixelSize: 11
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 2
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            IslandLabel {
                                Layout.fillWidth: true
                                text: String(parent.parent.modelData.que || "")
                                textFormat: Text.PlainText
                                color: parent.parent.modelData.bloquea
                                    ? Theme.red : Theme.ink
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                            }

                            IslandLabel {
                                Layout.fillWidth: true
                                text: String(parent.parent.modelData.porque || "")
                                textFormat: Text.PlainText
                                color: Theme.muted
                                font.pixelSize: 9
                                wrapMode: Text.WordWrap
                            }

                            IslandLabel {
                                Layout.fillWidth: true
                                text: String(parent.parent.modelData.donde || "")
                                textFormat: Text.PlainText
                                color: Theme.dim
                                font.pixelSize: 9
                            }
                        }
                    }
                }

                //  Y la frase honesta, la misma que sale en la terminal. No
                //  se suaviza para la barra: los permisos son lo que DECLARA,
                //  no una jaula.
                IslandLabel {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: Idioma.t("Un plugin corre dentro de la barra y puede hacer lo que la barra pueda hacer. Los permisos son lo que declara, no una jaula: instalarlo es confiar en quien lo escribió.")
                    textFormat: Text.PlainText
                    color: Theme.dim
                    font.pixelSize: 9
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    BotonTienda {
                        texto: Idioma.t("Cancelar")
                        onPulsado: tienda.examen = null
                    }

                    BotonTienda {
                        //  Si algo bloquea, el botón lo dice y avisa en rojo.
                        //  No se deshabilita: instalar en TU máquina algo que
                        //  has traído tú es tu decisión, y quitarte el botón
                        //  sin explicar nada sería peor que dejarte elegir
                        //  habiendo leído por qué.
                        texto: tienda.bloqueado
                            ? Idioma.t("Instalar de todos modos")
                            : (tienda.examen && tienda.examen.reemplaza
                               ? Idioma.t("Actualizar") : Idioma.t("Instalar"))
                        resalta: !tienda.bloqueado
                        peligro: tienda.bloqueado
                        habilitado: !PluginManager.ocupado
                        onPulsado: tienda.confirmar()
                    }
                }
            }
        }
    }

    //  ── lo que hacen los botones ─────────────────────────────────────

    function pedirInstalar(e) {
        queja = ""
        //  Se examina con el commit del registro: lo que se enseña es lo
        //  publicado, no lo que haya en la rama en este momento.
        PluginManager.examinar(String(e.repo || ""),
                               String(e.carpeta || ""),
                               String(e.commit || ""))
    }

    function confirmar() {
        if (!examen)
            return
        const d = examen
        examen = null
        //  El commit que se instala es el que VIO el examen, no el que decía
        //  el registro: si el registro estuviera sin anclar, aquí ya hay un
        //  SHA concreto y se usa ese.
        PluginManager.instalarDesde(String(d.repo || ""),
                                    String(d.carpeta || ""),
                                    String(d.commit || ""),
                                    String(d.plugin.id || ""))
    }

    //  Qué significa cada permiso, en una frase. Es el mismo texto que la
    //  tabla de la guía; aquí sale cuando importa, que es al aceptar.
    //
    //  La traducción se pide AQUÍ, en cada rama, y no fuera con el resultado:
    //  `Idioma.t(explicar(p))` deja las frases fuera del alcance de
    //  `tools/textos.py`, que busca literales dentro de `Idioma.t(`. Quedarían
    //  en español para todo el mundo sin que nada avisara.
    function explicar(p) {
        switch (p) {
        case "red":            return Idioma.t("Salir a internet.")
        case "procesos":       return Idioma.t("Ejecutar programas de tu sistema.")
        case "ficheros":       return Idioma.t("Leer y escribir ficheros.")
        case "portapapeles":   return Idioma.t("Leer y escribir el portapapeles.")
        case "notificaciones": return Idioma.t("Enviar notificaciones.")
        case "sonido":         return Idioma.t("Reproducir sonido.")
        case "ubicacion":      return Idioma.t("Saber dónde estás.")
        case "atajos":         return Idioma.t("Registrar atajos de teclado.")
        case "ipc":            return Idioma.t("Recibir órdenes de fuera de la barra.")
        default:               return p
        }
    }
}
