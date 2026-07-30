import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    // El botón de borrar la partida está armado esperando confirmación.
    property bool armado: false

    Timer {
        id: desarme
        interval: 6000
        onTriggered: view.armado = false
    }

    // cerrar y volver a abrir no debe dejarlo armado
    onVisibleChanged: if (!visible) armado = false

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

            Item { Layout.fillWidth: true }

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
            ScrollBar.vertical: ScrollBar { policy: rodillo.contentHeight > rodillo.height
                ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }

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
                                readonly property bool activa: Settings.valor(modelData.id)

                                // Algunas opciones no pintan nada si su interruptor
                                // maestro está apagado: se atenúan y dejan de
                                // responder, en vez de mentir sobre lo que hacen.
                                readonly property bool disponible: !modelData.requiere
                                    || Settings.valor(modelData.requiere)

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
                                color: filaMouse.containsMouse ? Theme.surfaceHi : Theme.surface

                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 11

                                    IconGlyph {
                                        text: String.fromCodePoint(opcion.modelData.glifo)
                                        color: opcion.activa ? Theme.ink : Theme.dim
                                        font.pixelSize: 15
                                        Layout.preferredWidth: 18
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 0

                                        IslandLabel {
                                            text: opcion.modelData.nombre
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }

                                        IslandLabel {
                                            text: opcion.modelData.desc
                                            color: Theme.muted
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    IslandSwitch {
                                        visible: opcion.modelData.tipo !== "eleccion"
                                        checked: opcion.activa
                                        onToggled: if (opcion.disponible) Settings.alternar(opcion.modelData.id)
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // ── opciones de varias respuestas
                                    //  Las alternativas las da el servicio. Aquí estaba
                                    //  `de === "idiomas"` a fuego y cualquier otra cosa
                                    //  devolvía una lista vacía, así que añadir una
                                    //  elección obligaba a tocar esta pantalla.
                                    RowLayout {
                                        visible: opcion.modelData.tipo === "eleccion"
                                        Layout.fillWidth: false
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 5

                                        Repeater {
                                            model: Settings.opcionesDe(opcion.modelData.de)

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
                                MouseArea {
                                    id: filaMouse
                                    enabled: opcion.modelData.tipo !== "eleccion"
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

        // ── zona peligrosa
        //
        //  Va en dos tiempos a propósito: el primer toque arma y el segundo
        //  ejecuta, y si te lo piensas más de unos segundos se desarma solo.
        //  Un diálogo modal sería más aparatoso y no protegería más.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 46
            radius: 12
            color: view.armado ? "#2a0f12" : Theme.surface
            border.width: view.armado ? 1 : 0
            border.color: Theme.red

            Behavior on color { ColorAnimation { duration: 160 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 10

                IconGlyph {
                    text: Theme.ico.alert
                    color: view.armado ? Theme.red : Theme.muted
                    font.pixelSize: 15
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    IslandLabel {
                        text: view.armado
                            ? Idioma.t("¿Seguro? Esto no se puede deshacer")
                            : Idioma.t("Empezar la mazmorra de cero")
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: view.armado ? Theme.red : Theme.ink
                    }

                    IslandLabel {
                        text: view.armado
                            ? Idioma.t("pierdes ") + Game.mejorOleada + Idioma.t(" de récord, nivel ")
                              + Game.nivelMaximo + ", " + Game.logrosHechos.length
                              + Idioma.t(" logros y ") + Game.bolsa.length + Idioma.t(" piezas")
                            : Idioma.t("borra niveles, héroes, logros, equipo y reliquias")
                        color: view.armado ? "#ff9f9f" : Theme.dim
                        font.pixelSize: 9
                    }
                }

                Rectangle {
                    Layout.preferredWidth: etiquetaBorrar.implicitWidth + 24
                    Layout.preferredHeight: 26
                    Layout.alignment: Qt.AlignVCenter
                    radius: 13
                    color: view.armado
                        ? (borrarRaton.containsMouse ? "#ff6961" : Theme.red)
                        : (borrarRaton.containsMouse ? Theme.surfaceHi : Theme.track)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    IslandLabel {
                        id: etiquetaBorrar
                        anchors.centerIn: parent
                        text: view.armado ? Idioma.t("Sí, borrar todo") : Idioma.t("Reiniciar")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: borrarRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (view.armado) {
                                Game.borrarTodo()
                                view.armado = false
                                desarme.stop()
                            } else {
                                view.armado = true
                                desarme.restart()
                            }
                        }
                    }
                }

                // salida sin sustos: cancelar está al lado del botón rojo
                Rectangle {
                    visible: view.armado
                    Layout.preferredWidth: cancelar.implicitWidth + 20
                    Layout.preferredHeight: 26
                    Layout.alignment: Qt.AlignVCenter
                    radius: 13
                    color: cancelarRaton.containsMouse ? Theme.surfaceHi : Theme.track

                    IslandLabel {
                        id: cancelar
                        anchors.centerIn: parent
                        text: Idioma.t("Cancelar")
                        color: Theme.muted
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: cancelarRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.armado = false
                            desarme.stop()
                        }
                    }
                }
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
