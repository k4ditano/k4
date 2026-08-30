//  Por qué borde se abre cada vista.
//
//  La barra tiene su casa —la sección Island— y lo que se ABRE puede tener
//  otra: el lanzador pegado a la izquierda, la captura abajo, sin mudar la
//  barra entera. Lo guarda `Settings.colocacionVistas`, vacío de fábrica: una
//  vista sin entrada se abre exactamente donde se abría siempre.
//
//  La vista NO gira. En un lateral el lanzador sigue siendo tan ancho como
//  siempre; lo que cambia es contra qué borde se apoya. Por eso esto es una
//  lista de bordes y no un editor de maquetación.
//
//  Qué se lista: lo que el usuario ABRE, con la misma regla que usa la propia
//  colocación —ni la píldora, ni lo que sale sin que nadie lo pida—. Así lo
//  que aparece aquí es exactamente lo que puede colocarse, y no hay filas que
//  no hagan nada.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: raiz

    spacing: 8

    readonly property var lados: [
        { codigo: "",           nombre: Idioma.t("Por defecto") },
        { codigo: "arriba",     nombre: Idioma.t("Arriba") },
        { codigo: "abajo",      nombre: Idioma.t("Abajo") },
        { codigo: "izquierda",  nombre: Idioma.t("Izquierda") },
        { codigo: "derecha",    nombre: Idioma.t("Derecha") }
    ]

    //  Los módulos que se abren. `closeOnClickOutside` es lo que separa lo que
    //  abre el usuario de lo que aparece solo —el reloj al pasar el ratón, el
    //  aviso de una notificación—, así que se reutiliza en vez de inventar una
    //  segunda lista que se desincronizaría con la primera.
    readonly property var abribles: {
        const fuera = []
        const l = PluginManager.instancias
        for (let i = 0; i < l.length; ++i) {
            const p = l[i]
            if (!p.habilitado || p.name === "idle" || !p.view)
                continue
            if (!p.closeOnClickOutside || p.transitorio)
                continue
            fuera.push(p)
        }
        return fuera
    }

    IslandLabel {
        Layout.fillWidth: true
        text: Idioma.t("La píldora y lo que se abre al pasar el ratón viven donde diga la sección Island. Aquí se coloca lo que abres tú.")
        color: Theme.dim
        font.pixelSize: 10
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: raiz.abribles

        delegate: Rectangle {
            id: fila
            required property var modelData

            readonly property string lado: Settings.ladoDe(modelData.name)
            readonly property int alineacion: {
                const a = Settings.alineacionDe(modelData.name)
                return a >= 0 ? a : 50
            }

            Layout.fillWidth: true
            //  Crece cuando hay borde puesto: la fila del punto solo tiene
            //  sentido si hay un borde por el que correrse.
            Layout.preferredHeight: fila.lado.length > 0 ? 84 : 48
            radius: 12
            color: Theme.surface

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    IslandLabel {
                        text: fila.modelData.title || fila.modelData.name
                        color: Theme.ink
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Repeater {
                        model: raiz.lados

                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool puesto: fila.lado === modelData.codigo

                            Layout.preferredWidth: chipTexto.implicitWidth + 20
                            Layout.preferredHeight: 24
                            radius: 12
                            color: puesto ? Theme.blue
                                : (chipRaton.containsMouse ? Theme.surfaceHi : Theme.track)

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IslandLabel {
                                id: chipTexto
                                anchors.centerIn: parent
                                text: chip.modelData.nombre
                                color: chip.puesto ? Theme.ink : Theme.muted
                                font.pixelSize: 10
                                font.weight: chip.puesto ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                id: chipRaton
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                //  Se conserva el punto al cambiar de borde: si
                                //  lo tenías al 20 % arriba y lo pasas a la
                                //  izquierda, sigue al 20 %. Volver al valor de
                                //  fábrica cada vez sería castigar el probar.
                                onClicked: Settings.colocarVista(
                                    fila.modelData.name, chip.modelData.codigo,
                                    fila.alineacion)
                            }
                        }
                    }
                }

                //  El punto a lo largo de ese borde. Los mismos pulsadores que
                //  el resto de Ajustes, con su rejilla de cinco.
                RowLayout {
                    Layout.fillWidth: true
                    visible: fila.lado.length > 0
                    spacing: 6

                    IslandLabel {
                        text: Idioma.t("Punto del borde")
                        color: Theme.muted
                        font.pixelSize: 10
                        Layout.fillWidth: true
                    }

                    Repeater {
                        model: [-1, 1]

                        delegate: Rectangle {
                            id: paso
                            required property int modelData
                            readonly property bool gastado: modelData < 0
                                ? fila.alineacion <= 0 : fila.alineacion >= 100

                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 12
                            opacity: gastado ? 0.35 : 1
                            color: !gastado && pasoRaton.containsMouse
                                ? Theme.surfaceHi : Theme.track

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IslandLabel {
                                anchors.centerIn: parent
                                //  Por códice, que un signo suelto en un `text:`
                                //  se lo lleva el extractor de textos.
                                text: String.fromCodePoint(
                                    paso.modelData < 0 ? 0x2212 : 0x002B)
                                color: paso.gastado ? Theme.muted : Theme.ink
                                font.pixelSize: 13
                            }

                            MouseArea {
                                id: pasoRaton
                                anchors.fill: parent
                                enabled: !paso.gastado
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                //  Al siguiente punto de la rejilla y no al
                                //  valor más el paso, por lo mismo que en
                                //  FilaOpcion: desde un valor que no esté en la
                                //  rejilla no se vuelve a ella nunca.
                                onClicked: {
                                    const v = fila.alineacion
                                    const n = paso.modelData > 0
                                        ? (Math.floor(v / 5) + 1) * 5
                                        : (Math.ceil(v / 5) - 1) * 5
                                    Settings.colocarVista(fila.modelData.name,
                                        fila.lado, Math.max(0, Math.min(100, n)))
                                }
                            }
                        }
                    }

                    IslandLabel {
                        text: fila.alineacion + " %"
                        color: Theme.ink
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Layout.preferredWidth: 46
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    IslandLabel {
        Layout.fillWidth: true
        visible: raiz.abribles.length === 0
        text: Idioma.t("No hay ningún módulo abrible encendido.")
        color: Theme.dim
        font.pixelSize: 10
    }
}
