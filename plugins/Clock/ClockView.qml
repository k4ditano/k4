import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    property var tray: null
    property var juego: null

    //  Lo que mide de verdad CADA zona, para que el plugin sepa cuánto tiene
    //  que reservar. Se mide aquí porque es aquí donde están los widgets con su
    //  fuente puesta: cuánto ocupa «🔔 claude · k4» no se sabe contando
    //  constantes, y contándolas era como se sabía —de ahí que las píldoras de
    //  los agentes acabaran pintadas encima de la hora—.
    //
    //  Las tres y no solo la derecha: con las zonas encadenadas, lo que mida la
    //  fecha corre el reloj, y lo que mida el reloj corre los indicadores.
    readonly property int anchoIzquierdo: grupoIzq.implicitWidth
    readonly property int anchoCentro: reloj.implicitWidth
    readonly property int anchoDerecho: grupoDer.implicitWidth

    //  El aire entre una zona y la siguiente. El plugin reparte con este mismo
    //  número, así que si cambia, cambia en los dos sitios o la cuenta deja de
    //  cuadrar y vuelve el solape.
    readonly property int hueco: 24

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 0
        anchors.bottomMargin: Notifs.recent.length > 0 ? 12 : 0
        spacing: 6

        //  Tres zonas ENCADENADAS, igual que en la píldora plegada: cada una
        //  empieza donde acaba la anterior, y esa es toda la regla.
        //
        //  Estaban ancladas a su borde —fecha a la izquierda, hora al centro de
        //  la caja, indicadores a la derecha—, y eso obliga a que lo reservado
        //  cuadre AL PÍXEL con lo que mide de verdad. No cuadraba: el plugin
        //  acotaba el flanco derecho para que la island no se comiera la
        //  pantalla, y al pasarse de ese tope la fila crecía hacia dentro desde
        //  el borde derecho y acababa pintada encima de la hora. Es exactamente
        //  el fallo que ya se arregló en la píldora, y la misma cura: colgadas
        //  unas de otras, el solape no es que no pase, es que no cabe. Lo que no
        //  quepa se sale por la derecha y lo recorta la island, que es lo menos
        //  malo de las dos cosas.
        //
        //  El precio es el mismo que allí: la hora deja de estar en el centro
        //  exacto de la caja y queda donde la dejen la fecha y su aire. A cambio
        //  cada píxel de indicador vale uno y no dos, así que ahora cabe casi el
        //  doble de flanco derecho antes de tocar el tope.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 68

            ColumnLayout {
                id: grupoIzq
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                IslandLabel {
                    text: Clock.date.toLocaleDateString(Idioma.locale, "dddd")
                    color: Theme.muted
                    font.pixelSize: 11
                    font.capitalization: Font.Capitalize
                }

                IslandLabel {
                    text: Clock.date.toLocaleDateString(Idioma.locale, "d MMMM")
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }

            IslandLabel {
                id: reloj

                //  Colgada de la fecha, no al centro de la caja: la caja ya no
                //  reserva lo mismo a los dos lados, así que su centro no es
                //  donde va la hora.
                anchors.left: grupoIzq.right
                anchors.leftMargin: view.hueco
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                font.pixelSize: 30
                font.weight: Font.Light
            }

            RowLayout {
                id: grupoDer

                //  Y los indicadores colgados de la HORA, cerrando la cadena.
                anchors.left: reloj.right
                anchors.leftMargin: view.hueco
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Minimizados {
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                }

                GrabacionPildora {
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                    onParar: Captura.parar()
                }

                JuegoPildora {
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                    onAbrir: if (view.juego) view.juego.toggle()
                }

                PluginPildora {
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                }

                // La island ya está desplegada y quieta: aquí sí se pincha.
                TrayRow {
                    max: 5
                    iconSize: 16
                    interactive: true
                    Layout.alignment: Qt.AlignVCenter
                    onMenuRequested: if (view.tray) view.tray.toggle()
                }
            }
        }

        // Lo que acaba de llegar, sin tener que abrir el panel.
        NotifStrip {
            max: 3
            Layout.fillWidth: true
        }
    }
}
