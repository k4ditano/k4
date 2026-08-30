//  Una fila de Ajustes: el icono, el nombre, la explicación y el control.
//
//  Vivía dentro de `SettingsView.qml`, incrustada como delegado. Sale a su
//  propio fichero porque ahora la usan DOS vistas —el panel de siempre y la
//  ventana con barra lateral— y dos copias de trescientas líneas divergen a la
//  primera corrección: se arregla una y la otra sigue mintiendo.
//
//  No sabe dónde la pintan. Recibe la definición de la opción y habla con el
//  servicio `Settings`, igual que hacía antes.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"

Rectangle {
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
    //  Y `disponible: false` a secas, para lo que
    //  no depende de otro ajuste sino del mundo:
    //  un programa que no está instalado. Sin
    //  esto, la única forma de decir «esto no
    //  puede funcionar aquí» era no ofrecerlo, y
    //  entonces nadie se entera de que existe.
    readonly property bool disponible:
        (!modelData.requiere
         || Settings.valor(modelData.requiere))
        && modelData.disponible !== false

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

        //  ── opciones numéricas ────────────────────────
        //  Un ancho, un alto, un número de píxeles: un valor
        //  que se empuja, no que se teclea. Dos pulsadores y
        //  la cifra en medio, en el mismo idioma de chips que
        //  las respuestas de arriba — un campo con teclado
        //  pediría escribir en una pantalla que nunca lo
        //  necesitó, y encima habría que validar lo tecleado.
        RowLayout {
            id: numerico
            visible: opcion.modelData.tipo === "numero"
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            //  El valor de ahora, como número: lo que llega de
            //  `Settings` después de un `poner` es un entero,
            //  pero un fichero editado a mano puede traer una
            //  cadena, y `parseInt` de nada es NaN — que se
            //  pintaría como «NaN px» y acotaría a disparates.
            readonly property int valor: {
                const v = parseInt(Settings.valor(opcion.modelData.id), 10)
                return isNaN(v) ? 0 : v
            }

            //  Un paso en un sentido, acotado a los límites de
            //  la opción. Se acota AQUÍ además de en quien
            //  guarde: el pulsador no puede ofrecer un valor
            //  que luego alguien tenga que corregir.
            //
            //  Y al SIGUIENTE punto de la rejilla, no al valor
            //  actual más el paso. Sumando a pelo, un valor que
            //  no esté en la rejilla no vuelve a ella nunca: con
            //  la alineación en 48 y paso de 5, el más lleva a 53
            //  y el menos a 43, y el 50 —el centro, que es lo que
            //  quiere casi todo el mundo— queda entre dos
            //  pulsaciones para siempre. Pasó en cuanto se
            //  arrastró la barra a un punto cualquiera.
            //
            //  La rejilla se cuenta desde `min` y no desde cero,
            //  que hay opciones que no empiezan ahí.
            function paso(cuantos) {
                const salto = opcion.modelData.paso || 1
                const base = opcion.modelData.min !== undefined
                    ? opcion.modelData.min : 0
                const cuantos_ = (numerico.valor - base) / salto
                let n = base + salto * (cuantos > 0
                    ? Math.floor(cuantos_) + 1
                    : Math.ceil(cuantos_) - 1)
                if (opcion.modelData.min !== undefined)
                    n = Math.max(opcion.modelData.min, n)
                if (opcion.modelData.max !== undefined)
                    n = Math.min(opcion.modelData.max, n)
                if (n !== numerico.valor)
                    Settings.poner(opcion.modelData.id, n)
            }

            //  Un pulsador gastado no responde Y lo dice, al 35 %.
            //  `enabled` y no solo opacidad, o enseñaría que
            //  pulsar no hace nada.
            //
            //  El menos va por códice, como la × de más abajo: un
            //  signo suelto en un `text:` se lo lleva el
            //  extractor de textos y acaba pidiendo traducción.
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                opacity: menosRaton.enabled ? 1 : 0.35
                color: menosRaton.enabled && menosRaton.containsMouse
                    ? Theme.surfaceHi : Theme.track

                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                    id: menosRaton
                    enabled: opcion.modelData.min === undefined
                        || numerico.valor > opcion.modelData.min
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: numerico.paso(-1)
                }

                IslandLabel {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0x2212)
                    color: menosRaton.enabled ? Theme.ink : Theme.muted
                    font.pixelSize: 14
                }
            }

            IslandLabel {
                text: numerico.valor
                    + (opcion.modelData.unidad
                       ? " " + opcion.modelData.unidad : "")
                color: Theme.ink
                font.pixelSize: 11
                font.weight: Font.DemiBold
                Layout.preferredWidth: 64
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                opacity: masRaton.enabled ? 1 : 0.35
                color: masRaton.enabled && masRaton.containsMouse
                    ? Theme.surfaceHi : Theme.track

                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                    id: masRaton
                    enabled: opcion.modelData.max === undefined
                        || numerico.valor < opcion.modelData.max
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: numerico.paso(1)
                }

                IslandLabel {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0x002B)
                    color: masRaton.enabled ? Theme.ink : Theme.muted
                    font.pixelSize: 14
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
