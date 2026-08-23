import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    //  Los dispositivos de sonido se refrescan al abrir: enchufar unos
    //  auriculares a mitad de sesión es lo normal, y la lista tiene que
    //  enseñarlos sin reiniciar nada.
    Component.onCompleted: Captura.buscarAudios()

    required property var plugin





    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 12
        // Más margen abajo que arriba: la fila de herramientas es lo último
        // y con 14 quedaba pegada al borde.
        anchors.bottomMargin: 22
        spacing: 10

        // ── cabecera
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 24
            spacing: 9

            IconGlyph {
                text: Theme.ico.cog
                color: Theme.muted
                font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Idioma.t("Ajustes")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            // ── qué versión llevas, y si hay otra ────────────────
            //
            //  El commit va pegado al título y en gris: es la respuesta a «¿qué
            //  tengo?», que hasta ahora no estaba escrita en ninguna parte de la
            //  barra, pero no es una noticia y no tiene que competir con nada.
            IslandLabel {
                visible: view.plugin.version.commit.length > 0
                text: view.plugin.version.commit
                color: Theme.dim
                font.pixelSize: 9
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 2
            }

            Item { Layout.fillWidth: true }

            //  Y la novedad SÍ es una noticia, así que se pone azul y se pulsa.
            //
            //  Con cambios sin guardar no se ofrece el botón: `./instalar` no
            //  toca el código con el árbol sucio —a propósito— así que sería un
            //  botón que no hace lo que dice. Se dice lo que pasa y se deja que
            //  quien lo lea decida, que es de quien es el trabajo sin guardar.
            Rectangle {
                id: novedad
                visible: view.plugin.version.hayNovedad
                Layout.preferredWidth: textoNovedad.implicitWidth + 22
                Layout.preferredHeight: 22
                Layout.alignment: Qt.AlignVCenter
                radius: 11

                readonly property bool ofrece: !view.plugin.version.sucio

                color: !ofrece ? Theme.track
                    : (ratonNovedad.containsMouse ? "#4a9eff" : Theme.blue)

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: textoNovedad
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: novedad.ofrece
                        ? Idioma.f(Idioma.t("%1 nuevos · Actualizar"),
                                   view.plugin.version.detras)
                        : Idioma.f(Idioma.t("%1 nuevos · guarda tus cambios"),
                                   view.plugin.version.detras)
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
                        view.plugin.version.actualizar()
                        view.plugin.close()
                    }
                }
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 15
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        //  ── grupos de opciones, dentro de algo que se pueda recorrer
        //
        //  Antes eran hijos directos del reparto, con el alto de la island fijo
        //  en 516. Funcionaba mientras hubo tres grupos; al añadir los de
        //  captura, grabación y editor el contenido pasó de novecientos píxeles y
        //  el reparto lo aplastó: las últimas filas quedaban pegadas al borde y
        //  el grupo del editor no llegaba a verse. Un ajuste al que no se puede
        //  llegar es peor que no tenerlo.
        //
        //  La cabecera y la zona peligrosa se quedan FUERA, así que cerrar y el
        //  botón de borrar la partida están siempre a la vista y no hay que
        //  buscarlos desplazando.
        Flickable {
            id: rodillo
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: grupos.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            //  Con barra: sin nada que lo diga, un panel que se desplaza parece
            //  un panel al que le falta la mitad.
            ScrollBar.vertical: IslandScrollBar {}

            //  La rueda, en un área que solo escucha la rueda.
            //
            //  Sin esto la lista solo se movía arrastrando: cada fila lleva su
            //  MouseArea con hover y un MouseArea acepta la rueda tenga o no
            //  manejador, así que el Flickable no la veía nunca. Es la misma
            //  trampa —y el mismo arreglo— que la línea de tiempo del editor.
            MouseArea {
                anchors.fill: parent
                z: 10
                acceptedButtons: Qt.NoButton
                onWheel: function (ev) {
                    const paso = ev.angleDelta.y
                    rodillo.contentY = Math.max(0, Math.min(
                        rodillo.contentHeight - rodillo.height,
                        rodillo.contentY - paso))
                    ev.accepted = true
                }
            }

        ColumnLayout {
            id: grupos
            width: rodillo.width
            spacing: 10

                // ── grupos de opciones
                Repeater {
                    model: Settings.definicion

                    delegate: ColumnLayout {
                        id: seccion
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 4

                        IslandLabel {
                            text: seccion.modelData.grupo
                            color: Theme.dim
                            font.pixelSize: 9
                            font.capitalization: Font.AllUppercase
                            Layout.leftMargin: 2
                        }

                        Repeater {
                            model: seccion.modelData.opciones

                            delegate: Rectangle {
                                id: opcion
                                required property var modelData
                                //  Con `!!` y no a secas. `Settings.valor`
                                //  contesta `undefined` a las opciones que aún
                                //  no tienen nada guardado y a las que no son
                                //  interruptores, y asignar eso a un bool es un
                                //  aviso en el log por CADA fila y CADA vez que
                                //  se abren los Ajustes — ruido que tapa los
                                //  avisos de verdad.
                                //
                                //  Coaccionar y no comparar con `true`: esto
                                //  enciende el ICONO de la fila, y una elección
                                //  vale «viaje» y un campo de texto vale una
                                //  URL. Con `=== true` se apagaban todas las
                                //  filas que no fueran un interruptor.
                                readonly property bool activa:
                                    !!Settings.valor(modelData.id)

                                //  El valor de una opción de texto, siempre como
                                //  cadena: un registro externo contesta `false`
                                //  cuando todavía no hay nada guardado.
                                readonly property string valorTexto: {
                                    const v = Settings.valor(modelData.id)
                                    return (v === undefined || v === null || v === false)
                                        ? "" : String(v)
                                }

                                // Algunas opciones no pintan nada si su interruptor
                                // maestro está apagado: se atenúan y dejan de
                                // responder, en vez de mentir sobre lo que hacen.
                                readonly property bool disponible: !modelData.requiere
                                    || Settings.valor(modelData.requiere)

                                //  Las acciones con red van en dos tiempos: el
                                //  primer toque arma y el segundo ejecuta, y si
                                //  te lo piensas más de unos segundos se
                                //  desarma sola. Un diálogo modal sería más
                                //  aparatoso y no protegería más.
                                property bool armada: false

                                Timer {
                                    id: desarmar
                                    interval: 4000
                                    onTriggered: opcion.armada = false
                                }

                                //  Cerrar y volver a abrir no puede dejarla
                                //  armada esperando un clic despistado.
                                Connections {
                                    target: view
                                    function onVisibleChanged() {
                                        if (!view.visible)
                                            opcion.armada = false
                                    }
                                }

                                //  Y otras ni siquiera aparecen si no hay con qué.
                                //
                                //  Un interruptor de «grabar la cámara» sin cámara
                                //  enchufada no es una opción, es una promesa falsa.
                                //  En cuanto conectes una, aparece.
                                visible: modelData.si !== "camara" || Captura.hayCamara

                                opacity: disponible ? 1 : 0.4
                                Behavior on opacity { NumberAnimation { duration: 140 } }

                                Layout.fillWidth: true
                                Layout.preferredHeight: visible ? 40 : 0
                                radius: 10
                                color: opcion.armada ? "#2a0f12"
                                     : (filaMouse.containsMouse ? Theme.surfaceHi : Theme.surface)
                                border.width: opcion.armada ? 1 : 0
                                border.color: Theme.red

                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 11

                                    K4.IconoPlugin {
                                        //  Un plugin puede traer su propia
                                        //  imagen; el resto de opciones son
                                        //  glifos y caen por el mismo sitio.
                                        imagen: opcion.modelData.imagen || ""
                                        glifo: opcion.modelData.glifo
                                        color: opcion.activa ? Theme.ink : Theme.dim
                                        tamano: 15
                                        Layout.preferredWidth: 18
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 0

                                        IslandLabel {
                                            text: opcion.armada
                                                ? (opcion.modelData.nombreArmado
                                                   || Idioma.t("¿Seguro? Esto no se puede deshacer"))
                                                : opcion.modelData.nombre
                                            color: opcion.armada ? Theme.red : Theme.ink
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }

                                        IslandLabel {
                                            text: opcion.armada
                                                ? (opcion.modelData.descArmado || opcion.modelData.desc)
                                                : opcion.modelData.desc
                                            //  El motivo de un plugin roto va
                                            //  en rojo: es la diferencia entre
                                            //  «apagado» y «no puede».
                                            color: opcion.armada ? "#ff9f9f"
                                                 : (opcion.modelData.error ? Theme.red : Theme.muted)
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    //  Un plugin que no puede cargar no lleva
                                    //  interruptor: encender lo imposible es
                                    //  mentir. Si el fallo fue al cargar, la
                                    //  fila entera reintenta.
                                    IslandLabel {
                                        visible: opcion.modelData.error === "recargable"
                                        text: Idioma.t("reintentar")
                                        color: Theme.blue
                                        font.pixelSize: 10
                                        Layout.alignment: Qt.AlignVCenter

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: PluginManager.reintentar(
                                                opcion.modelData.pluginId)
                                        }
                                    }

                                    //  ── una acción con red ──────────────
                                    RowLayout {
                                        visible: opcion.modelData.tipo === "peligro"
                                        spacing: 8
                                        Layout.alignment: Qt.AlignVCenter

                                        //  Salida sin sustos: cancelar está al
                                        //  lado del botón rojo.
                                        IslandLabel {
                                            visible: opcion.armada
                                            text: Idioma.t("cancelar")
                                            color: Theme.muted
                                            font.pixelSize: 10

                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -6
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    opcion.armada = false
                                                    desarmar.stop()
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: etiquetaAccion.implicitWidth + 24
                                            Layout.preferredHeight: 26
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: 13
                                            color: opcion.armada
                                                ? (accionRaton.containsMouse ? "#ff6961" : Theme.red)
                                                : (accionRaton.containsMouse ? Theme.surfaceHi : Theme.track)

                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            IslandLabel {
                                                id: etiquetaAccion
                                                anchors.centerIn: parent
                                                text: opcion.armada
                                                    ? (opcion.modelData.confirmar || Idioma.t("Sí"))
                                                    : (opcion.modelData.accion || Idioma.t("Hacerlo"))
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                            }

                                            MouseArea {
                                                id: accionRaton
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (opcion.armada) {
                                                        Settings.ejecutar(opcion.modelData.id)
                                                        opcion.armada = false
                                                        desarmar.stop()
                                                    } else {
                                                        opcion.armada = true
                                                        desarmar.restart()
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    IslandSwitch {
                                        //  Solo el tipo por defecto: una elección
                                        //  lleva chips y un texto lleva campo.
                                        visible: !opcion.modelData.tipo
                                                 && opcion.modelData.error !== "fijo"
                                        checked: opcion.activa
                                        onToggled: if (opcion.disponible) Settings.alternar(opcion.modelData.id)
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // ── opciones de varias respuestas
                                    //  Las alternativas las da el servicio. Aquí estaba
                                    //  `de === "idiomas"` a fuego y cualquier otra cosa
                                    //  devolvía una lista vacía, así que añadir una
                                    //  elección obligaba a tocar esta pantalla.
                                    //
                                    //  Un plugin de fuera no puede añadir su caso al
                                    //  servicio: trae las suyas en `alternativas`, tal
                                    //  como promete K4.Ajustes desde el principio —
                                    //  hasta ahora esa promesa pintaba una fila vacía.
                                    RowLayout {
                                        visible: opcion.modelData.tipo === "eleccion"
                                        Layout.fillWidth: false
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 5

                                        Repeater {
                                            model: opcion.modelData.alternativas
                                                   || Settings.opcionesDe(opcion.modelData.de)

                                            delegate: Rectangle {
                                                id: eleccion
                                                required property var modelData
                                                readonly property bool puesta:
                                                    Settings.valor(opcion.modelData.id) === modelData.codigo

                                                Layout.preferredWidth: textoEleccion.implicitWidth + 20
                                                Layout.preferredHeight: 24
                                                radius: 12
                                                color: puesta ? Theme.blue
                                                    : (eleccionRaton.containsMouse
                                                       ? Theme.surfaceHi : Theme.track)

                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                IslandLabel {
                                                    id: textoEleccion
                                                    anchors.centerIn: parent
                                                    text: eleccion.modelData.nombre
                                                    color: eleccion.puesta ? Theme.ink : Theme.muted
                                                    font.pixelSize: 10
                                                    font.weight: eleccion.puesta
                                                        ? Font.DemiBold : Font.Normal
                                                }

                                                MouseArea {
                                                    id: eleccionRaton
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Settings.poner(opcion.modelData.id,
                                                                              eleccion.modelData.codigo)
                                                }
                                            }
                                        }
                                    }

                                    // ── opciones de texto libre
                                    //  Una URL, un modelo, una clave de API: lo que un
                                    //  interruptor no puede decir. El valor se entrega
                                    //  al confirmar —Intro o clic fuera—, no tecla a
                                    //  tecla: quien guarda escribe un fichero cada vez.
                                    Rectangle {
                                        visible: opcion.modelData.tipo === "texto"
                                        Layout.preferredWidth: 210
                                        Layout.preferredHeight: 26
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: 13
                                        color: campo.activeFocus ? Theme.surfaceHi : Theme.track
                                        border.width: campo.activeFocus ? 1 : 0
                                        border.color: Theme.blue

                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        //  La pista solo con el campo vacío y sin foco:
                                        //  en cuanto tecleas ya no hace falta.
                                        IslandLabel {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 11
                                            visible: campo.text.length === 0 && !campo.activeFocus
                                            text: opcion.modelData.pista || ""
                                            color: Theme.dim
                                            font.pixelSize: 10
                                        }

                                        TextInput {
                                            id: campo
                                            cursorDelegate: IslandCursor {}
                                            anchors.fill: parent
                                            anchors.leftMargin: 11
                                            anchors.rightMargin: 11
                                            verticalAlignment: TextInput.AlignVCenter
                                            color: Theme.ink
                                            font.family: Theme.uiFont
                                            font.pixelSize: 10
                                            clip: true
                                            selectByMouse: true
                                            selectionColor: Theme.blue
                                            //  Un secreto se ve mientras se teclea y se
                                            //  tapa al parar: se puede corregir sin que
                                            //  el token entero quede a la vista.
                                            echoMode: opcion.modelData.secreto
                                                ? TextInput.PasswordEchoOnEdit
                                                : TextInput.Normal
                                            text: opcion.valorTexto
                                            onEditingFinished: {
                                                if (text !== opcion.valorTexto)
                                                    Settings.poner(opcion.modelData.id, text)
                                            }
                                            //  Escape descarta lo tecleado, no lo guarda.
                                            Keys.onEscapePressed: {
                                                text = opcion.valorTexto
                                                focus = false
                                            }
                                        }
                                    }
                                }

                                //  Toda la fila conmuta, no solo el interruptor: son
                                //  objetivos de 40 px de alto, sería absurdo obligar a
                                //  apuntar al de 24.
                                //
                                //  Pero solo en las filas de interruptor. En las de varias
                                //  respuestas esta área va POR ENCIMA de los chips —se
                                //  declara después— y les comía el clic: el margen de 54
                                //  px por la derecha deja pasar el último y nada más, así
                                //  que en el selector de idioma solo se podía elegir
                                //  «English». Llevaba ahí desde que existe la pantalla.
                                //  Y en las de texto igual: el clic es para el campo.
                                MouseArea {
                                    id: filaMouse
                                    enabled: !opcion.modelData.tipo
                                    anchors.fill: parent
                                    anchors.rightMargin: 54     // deja pasar el interruptor
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (opcion.disponible)
                                            Settings.alternar(opcion.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Estado del cargador: distinguir «desactivado por el usuario» de
        // «falló al cargar» evita diagnosticar a ciegas desde la terminal.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            spacing: 7

            IconGlyph {
                text: String.fromCodePoint(0xF06A0)
                color: Object.keys(PluginManager.errores).length > 0
                    ? Theme.red : Theme.green
                font.pixelSize: 13
            }

            //  Abre la aplicación en vez de tapar los ajustes con ella. Los
            //  interruptores de arriba siguen aquí, que sí son ajustes; traer,
            //  actualizar y quitar se ha mudado a lo suyo.
            K4.Baldosa {
                Layout.preferredWidth: 78
                Layout.preferredHeight: 24
                radius: 12
                onPulsada: PluginManager.abrirAplicacion("tienda")

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
        }


        // ── herramientas del sistema
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 30
            spacing: 8

            IslandLabel {
                text: Idioma.t("Herramientas del sistema")
                color: Theme.dim
                font.pixelSize: 9
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    { nombre: Idioma.t("Redes"), glifo: 0xF05A9, orden: ["nm-connection-editor"] },
                    { nombre: Idioma.t("Sonido"), glifo: 0xF057E, orden: ["pavucontrol"] }
                ]

                delegate: Rectangle {
                    id: herramienta
                    required property var modelData

                    Layout.preferredWidth: contenido.implicitWidth + 22
                    Layout.preferredHeight: 26
                    radius: 13
                    color: herramientaMouse.containsMouse ? Theme.surfaceHi : Theme.surface

                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        id: contenido
                        anchors.centerIn: parent
                        spacing: 6

                        IconGlyph {
                            text: String.fromCodePoint(herramienta.modelData.glifo)
                            color: Theme.muted
                            font.pixelSize: 12
                        }

                        IslandLabel {
                            text: herramienta.modelData.nombre
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: herramientaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            K4.Sistema.lanzar(herramienta.modelData.orden)
                            view.plugin.close()
                        }
                    }
                }
            }
        }
    }
}
