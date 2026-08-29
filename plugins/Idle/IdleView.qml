//  Píldora plegada, en tres zonas ENCADENADAS: la carátula, la hora colgada de
//  la carátula y los indicadores colgados de la hora.
//
//  Cada zona empieza donde acaba la anterior, y esa es toda la regla. Antes
//  iban las tres ancladas a su borde —izquierda, centro, derecha—, y eso obliga
//  a que lo reservado cuadre al píxel con lo que mide de verdad: en cuanto se
//  descuadraba, la fila de la derecha caminaba por encima de la hora y el clip
//  lo escondía en vez de arreglarlo. Encadenadas, el solape no es que no pase:
//  es que no cabe.
//
//  Con espaciadores flexibles tampoco: un RowLayout centra el grupo del medio
//  respecto al CONTENIDO de los flancos, así que la hora se corría medio ancho
//  de lo que hubiera a la derecha y bailaba al aparecer un icono de bandeja.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var plugin: null
    property var tray: null
    property int shown: 0

    // ── los escritorios asoman al cambiar ─────────────────────────
    property bool mostrandoEscritorios: false
    property int inicioEscritorios: 0
    readonly property var escritoriosVisibles:
        Workspaces.list.slice(inicioEscritorios, inicioEscritorios + 3)

    // Una mirilla de tres: 1·2·3, después 2·3·4, después 3·4·5… El activo
    // recorre la mirilla y esta solo avanza cuando llega a un borde.
    function ajustarVentanaEscritorios() {
        const lista = Workspaces.list
        if (lista.length <= 3) {
            inicioEscritorios = 0
            return
        }
        let indice = -1
        for (let i = 0; i < lista.length; ++i)
            if (lista[i].focused) {
                indice = i
                break
            }
        if (indice < 0)
            return
        let inicio = Math.max(0, Math.min(inicioEscritorios, lista.length - 3))
        if (indice < inicio)
            inicio = indice
        else if (indice > inicio + 2)
            inicio = indice - 2
        inicioEscritorios = Math.max(0, Math.min(inicio, lista.length - 3))
    }

    //  El primer cambio de `activo` es el de arrancar —pasa de -1 al que
    //  toque—, y no es un cambio de escritorio: sin esta guarda la píldora
    //  enseñaría los puntos cada vez que se recarga la barra.
    property bool arrancado: false

    Component.onCompleted: {
        ajustarVentanaEscritorios()
        arranque.start()
    }

    Timer {
        id: arranque
        interval: 700
        onTriggered: view.arrancado = true
    }

    Connections {
        target: Workspaces
        function onActivoChanged() {
            view.ajustarVentanaEscritorios()
            if (!view.arrancado)
                return
            view.mostrandoEscritorios = true
            volver.restart()
        }
        function onListChanged() { view.ajustarVentanaEscritorios() }
    }

    Timer {
        id: volver
        interval: 1800
        onTriggered: view.mostrandoEscritorios = false
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: 11
        anchors.rightMargin: 11

        // ── izquierda
        RowLayout {
            id: izquierda
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            //  Igual que la derecha: el ancho real, al plugin. Este flanco
            //  abre la cadena, así que lo que mida corre a los otros dos y una
            //  cuenta a ojo aquí se ve tanto como una al otro lado.
            onImplicitWidthChanged: if (view.plugin)
                view.plugin.ladoIzqMedido = Math.ceil(implicitWidth)
            Component.onCompleted: if (view.plugin)
                view.plugin.ladoIzqMedido = Math.ceil(implicitWidth)

            //  Las extensiones de flanco, lo PRIMERO de este flanco: es lo
            //  más pegado al borde de la pantalla, que es hacia donde crecen.
            ZonaExtension {
                lado: "izquierda"
                Layout.alignment: Qt.AlignVCenter
            }

            Artwork {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                visible: Media.isPlaying
            }

            // Las barras, pegadas a la carátula. Estaban al otro lado de la
            // píldora, y eso obligaba a mirar a dos sitios para saber si
            // suena algo y qué es: son la misma información.
            Visualizer {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 12
                visible: Media.isPlaying
            }

        }

        // ── centro
        //
        //  La hora casi siempre, y los escritorios solo cuando cambias de uno:
        //  aparecen en su sitio, se dejan ver un par de segundos y se van. Los
        //  puntos fijos a la izquierda estaban ahí todo el día para decir algo
        //  que solo importa en el instante en que cambia.
        Item {
            id: centro

            //  Colgada de la carátula, no al centro de la caja: la caja ya
            //  no reserva lo mismo a los dos lados, así que su centro no es
            //  donde va la hora.
            anchors.left: izquierda.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            width: 46
            height: parent.height

            IslandLabel {
                anchors.centerIn: parent
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                font.pixelSize: 12
                font.weight: Font.Medium
                color: Media.hasPlayer ? Theme.ink : Theme.muted

                opacity: view.mostrandoEscritorios ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 4

                opacity: view.mostrandoEscritorios ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                Repeater {
                    model: view.escritoriosVisibles

                    delegate: Rectangle {
                        required property var modelData
                        Layout.preferredWidth: modelData.focused ? 18 : 6
                        Layout.preferredHeight: 6
                        Layout.alignment: Qt.AlignVCenter
                        radius: 3
                        color: modelData.focused ? Theme.ink : Theme.track

                        Behavior on Layout.preferredWidth {
                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }

                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
            }
        }

        // ── derecha
        //  Indicadores nada más: aquí no se puede pinchar, porque al acercar el
        //  ratón la island ya ha cambiado a la vista de reloj o de reproductor.
        //  Es en esas donde la fila es pulsable.
        RowLayout {
            id: derecha

            //  Colgada de la HORA, cerrando la cadena.
            anchors.left: centro.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            //  El ancho real de la fila, publicado al plugin: la píldora se
            //  ensancha con lo que HAY, no con lo que alguien recordó sumar.
            //  implicitWidth no depende del ancho del padre, así que no hay
            //  bucle de binding posible.
            onImplicitWidthChanged: if (view.plugin)
                view.plugin.ladoDerMedido = Math.ceil(implicitWidth)
            Component.onCompleted: if (view.plugin)
                view.plugin.ladoDerMedido = Math.ceil(implicitWidth)

            Minimizados { Layout.alignment: Qt.AlignVCenter }

            GrabacionPildora { Layout.alignment: Qt.AlignVCenter }

            JuegoPildora { Layout.alignment: Qt.AlignVCenter }

            PluginPildora { Layout.alignment: Qt.AlignVCenter }

            TrayRow {
                max: view.shown
                iconSize: 14
                interactive: false
                Layout.alignment: Qt.AlignVCenter
            }

            //  Y las extensiones cierran la cadena: lo último de la fila,
            //  pegado al borde de la pantalla, que es hacia donde crecen. Cada
            //  instancia pinta solo las suyas — la otra mira al otro lado.
            ZonaExtension {
                lado: "derecha"
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
