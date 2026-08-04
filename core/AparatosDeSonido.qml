//  Los aparatos de sonido: por dónde sale y por dónde entra.
//
//  Vive en `core` porque lo enseñan dos sitios —el módulo de Sonido y el
//  detalle del centro de control— y una lista de aparatos que se pinta en dos
//  ficheros acaba divergiendo: se arregla el mudo en uno y el otro se queda
//  como estaba.
//
//  Cada aparato con su volumen y su mudo, el activo marcado, y una marca en el
//  deslizador donde está la UNIDAD del aparato —su nivel natural—. Esa marca
//  es media razón para que esto exista: por encima de ella no se sube el
//  volumen, se AMPLIFICA, y un micro amplificado entra saturado sin que nada
//  lo diga hasta que escuchas la grabación.

import QtQuick
import QtQuick.Layouts
import "../services"

ColumnLayout {
    id: aparatos

    //  Cuánto ocupa esto puesto entero, para que quien lo enseñe sepa cuánto
    //  crecer sin medirlo a ojo.
    readonly property int alturaNatural: {
        const filas = Audio.salidas.length + Audio.entradas.length
        return 36 + filas * 58
    }

    spacing: 8

    //  Las dos listas con el mismo molde: un aparato es un aparato, y lo único
    //  que cambia es a quién se le pide ser el predeterminado.
    Repeater {
        model: [
            { titulo: Idioma.t("Salida"), entrada: false },
            { titulo: Idioma.t("Entrada"), entrada: true }
        ]

        delegate: ColumnLayout {
            id: grupo
            required property var modelData

            readonly property var listaAparatos: grupo.modelData.entrada
                ? Audio.entradas : Audio.salidas
            readonly property var activo: grupo.modelData.entrada
                ? Audio.entradaActiva : Audio.salidaActiva

            Layout.fillWidth: true
            spacing: 4

            IslandLabel {
                text: grupo.modelData.titulo
                color: Theme.dim
                font.pixelSize: 9
                font.capitalization: Font.AllUppercase
                font.weight: Font.DemiBold
            }

            IslandLabel {
                visible: grupo.listaAparatos.length === 0
                text: Idioma.t("Nada enchufado")
                color: Theme.dim
                font.pixelSize: 11
            }

            Repeater {
                model: grupo.listaAparatos

                delegate: Rectangle {
                    id: fila
                    required property var modelData

                    readonly property bool esActivo:
                        grupo.activo && grupo.activo.id === fila.modelData.id
                    readonly property int volumen: Audio.volumenDe(fila.modelData)
                    readonly property bool mudo: Audio.mudoDe(fila.modelData)
                    //  Dónde está la unidad de este aparato, en tanto por
                    //  ciento. 0 = no se sabe, y entonces no se pinta nada:
                    //  una marca inventada es peor que ninguna.
                    readonly property int base: Audio.baseDe(fila.modelData)
                    readonly property real db: Audio.dbSobreNatural(fila.modelData)

                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: 10
                    color: esActivo ? Theme.surfaceHi
                         : filaRaton.containsMouse ? Theme.surface : "transparent"

                    Behavior on color { ColorAnimation { duration: 110 } }

                    MouseArea {
                        id: filaRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        //  Pulsar el aparato lo pone de predeterminado. El
                        //  deslizador y el mudo van por encima con lo suyo.
                        onClicked: grupo.modelData.entrada
                            ? Audio.elegirEntrada(fila.modelData)
                            : Audio.elegirSalida(fila.modelData)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            IconGlyph {
                                text: String.fromCodePoint(
                                    fila.esActivo ? 0xF012C : 0xF0130)
                                color: fila.esActivo ? Theme.green : Theme.dim
                                font.pixelSize: 12
                            }

                            IslandLabel {
                                Layout.fillWidth: true
                                text: Audio.nombreDe(fila.modelData)
                                color: fila.esActivo ? Theme.ink : Theme.muted
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            //  El aviso que faltaba: por encima de la unidad
                            //  esto no sube, AMPLIFICA. Y en decibelios, que
                            //  es lo que significa algo: «+44 %» no le dice
                            //  nada a nadie, «+15 dB» sí — y es la cifra con
                            //  la que se entiende por qué el micro entraba
                            //  saturado.
                            IslandLabel {
                                visible: fila.base > 0 && fila.volumen > fila.base
                                text: "+" + fila.db.toFixed(0) + Idioma.t(" dB de más")
                                color: fila.esActivo ? Theme.yellow : Theme.dim
                                font.pixelSize: 9
                            }

                            IslandLabel {
                                text: fila.volumen + "%"
                                color: fila.mudo ? Theme.dim : Theme.muted
                                font.pixelSize: 10
                            }

                            MediaButton {
                                glyph: String.fromCodePoint(
                                    fila.mudo ? 0xF0581 : 0xF057E)
                                glyphSize: 12
                                glyphColor: fila.mudo ? Theme.red : Theme.muted
                                onActivated: Audio.alternarMudoDe(fila.modelData)
                            }
                        }

                        //  El deslizador, hasta 150 %. La marca de la unidad
                        //  va encima, y lo que pasa de ahí se pinta en ámbar:
                        //  se ve de un vistazo que estás amplificando.
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 12

                            Rectangle {
                                id: carril
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: Theme.track
                                opacity: fila.mudo ? 0.4 : 1

                                //  En color solo el que está en uso; los demás
                                //  en gris. Cuatro barras verdes a la vez
                                //  decían «todo esto suena», y solo suena uno.
                                Rectangle {
                                    width: carril.width * Math.min(1, fila.volumen / 150)
                                    height: parent.height
                                    radius: parent.radius
                                    color: !fila.esActivo ? Theme.muted
                                         : (fila.base > 0 && fila.volumen > fila.base
                                            ? Theme.yellow : Theme.green)
                                }

                                //  La unidad del aparato.
                                Rectangle {
                                    visible: fila.base > 0
                                    x: carril.width * (fila.base / 150) - 1
                                    y: -3
                                    width: 2
                                    height: 10
                                    radius: 1
                                    color: Theme.ink
                                    opacity: 0.55
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.topMargin: -6
                                anchors.bottomMargin: -6
                                cursorShape: Qt.PointingHandCursor

                                function poner(x) {
                                    Audio.ponerVolumenDe(
                                        fila.modelData,
                                        x / Math.max(1, width) * 150)
                                }
                                onPressed: function (ev) { poner(ev.x) }
                                onPositionChanged: function (ev) {
                                    if (pressed) poner(ev.x)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
