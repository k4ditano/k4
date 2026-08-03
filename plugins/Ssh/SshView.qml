//  La lista de servidores.
//
//  Se escribe para filtrar, como en el lanzador y en el portapapeles: la
//  misma pieza y las mismas teclas, que una casa donde cada cajón se abre de
//  otra forma no es una casa.
//
//  Cada fila dice lo justo para reconocer el sitio —el alias grande, el
//  destino de verdad en pequeño— y nada más. El resto (la clave, el salto) lo
//  sabe ssh y no hay por qué repetirlo aquí.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: vista

    required property var plugin

    //  Sin esto hay que hacer clic antes de poder escribir: la raíz de la
    //  island se queda el foco y la superficie tarda en recibirlo.
    FocoInicial { id: foco; objetivo: entrada }
    Component.onCompleted: foco.reclamar()

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        anchors.bottomMargin: 10
        spacing: 8

        // ── búsqueda ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF08C0)
                color: Theme.muted
                font.pixelSize: 15
                Layout.alignment: Qt.AlignVCenter
            }

            TextInput {
                id: entrada
                cursorDelegate: IslandCursor {}
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                text: vista.plugin.busqueda
                onTextEdited: {
                    vista.plugin.busqueda = text
                    vista.plugin.indice = 0
                }

                color: Theme.ink
                font.pixelSize: 15
                font.family: Theme.uiFont
                selectByMouse: true
                selectionColor: Theme.blue
                cursorVisible: true
                verticalAlignment: TextInput.AlignVCenter
                focus: true
                activeFocusOnTab: true
                clip: true

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: entrada.text.length === 0
                    text: Idioma.t("Buscar un servidor, o escribir usuario@máquina")
                    color: Theme.dim
                    font.pixelSize: 15
                }

                Keys.onPressed: function (ev) {
                    const conCtrl = (ev.modifiers & Qt.ControlModifier) !== 0
                    const conShift = (ev.modifiers & Qt.ShiftModifier) !== 0

                    if (ev.key === Qt.Key_Escape) {
                        vista.plugin.cerrar(); ev.accepted = true
                    } else if (ev.key === Qt.Key_Down) {
                        vista.plugin.mover(1); ev.accepted = true
                    } else if (ev.key === Qt.Key_Up) {
                        vista.plugin.mover(-1); ev.accepted = true
                    } else if (ev.key === Qt.Key_PageDown) {
                        vista.plugin.mover(6); ev.accepted = true
                    } else if (ev.key === Qt.Key_PageUp) {
                        vista.plugin.mover(-6); ev.accepted = true
                    } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                        //  Con shift, en ventana grande. Es el mismo par que
                        //  en la terminal: la isla para lo rápido, la ventana
                        //  cuando sabes que vas a estar un rato.
                        vista.plugin.elegir(conShift); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_S) {
                        vista.plugin.guardarActual(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_F) {
                        vista.plugin.favoritoActual(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_K) {
                        vista.plugin.crearClave(); ev.accepted = true
                    } else if (ev.key === Qt.Key_Delete) {
                        vista.plugin.borrarActual(); ev.accepted = true
                    }
                }
            }

            IslandLabel {
                text: vista.plugin.cuantos + (vista.plugin.cuantos === 1
                    ? Idioma.t(" servidor") : Idioma.t(" servidores"))
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: vista.plugin.cerrar()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── la lista ──────────────────────────────────────────────
        ListView {
            id: filas
            ScrollBar.vertical: IslandScrollBar {}

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3
            model: vista.plugin.lista
            currentIndex: vista.plugin.indice
            highlightMoveDuration: 130
            boundsBehavior: Flickable.StopAtBounds

            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: fila
                required property var modelData
                required property int index

                readonly property bool elegida: index === vista.plugin.indice

                width: ListView.view.width
                height: 44
                radius: 9
                color: elegida ? Theme.surfaceHi
                     : (raton.containsMouse ? Theme.surface : "transparent")

                Behavior on color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    spacing: 10

                    //  Un destino al vuelo se distingue de uno guardado: el
                    //  primero es un salto al vacío, el segundo tu casa.
                    IconGlyph {
                        text: String.fromCodePoint(fila.modelData.rapido ? 0xF0432
                                                 : (fila.modelData.favorito ? 0xF04CE
                                                                            : 0xF08C0))
                        color: fila.modelData.favorito ? Theme.yellow
                             : (fila.elegida ? Theme.ink : Theme.muted)
                        font.pixelSize: 15
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        RowLayout {
                            spacing: 7

                            IslandLabel {
                                text: fila.modelData.rapido
                                    ? Idioma.t("Conectar a ") + fila.modelData.host
                                    : fila.modelData.alias
                                color: Theme.ink
                                font.pixelSize: 14
                                font.weight: fila.elegida ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.maximumWidth: 330
                            }

                            //  Las etiquetas, si las hay: son de las nuestras
                            //  —van en hosts.json— y sirven para agrupar sin
                            //  carpetas, que en una lista que se filtra
                            //  escribiendo las carpetas sobran.
                            Repeater {
                                model: fila.modelData.etiquetas

                                delegate: Rectangle {
                                    required property var modelData
                                    height: 15
                                    width: etiqueta.implicitWidth + 12
                                    radius: 7
                                    color: Theme.surfaceHi

                                    IslandLabel {
                                        id: etiqueta
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        color: Theme.muted
                                        font.pixelSize: 9
                                    }
                                }
                            }
                        }

                        IslandLabel {
                            text: {
                                const m = fila.modelData
                                const usuario = m.usuario ? m.usuario + "@" : ""
                                const puerto = m.puerto && m.puerto !== "22" ? ":" + m.puerto : ""
                                const salto = m.salto ? "  ·  " + Idioma.t("por ") + m.salto : ""
                                return usuario + m.host + puerto + salto
                            }
                            color: Theme.muted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    //  Guardar lo que acabas de escribir, sin teclas que
                    //  aprenderse: el atajo está, pero el botón es lo que se
                    //  ve la primera vez.
                    Rectangle {
                        visible: fila.modelData.rapido && fila.elegida
                        Layout.preferredWidth: guardar.implicitWidth + 18
                        Layout.preferredHeight: 20
                        radius: 10
                        color: guardarRaton.containsMouse ? Theme.blue : Theme.surfaceHi

                        Behavior on color { ColorAnimation { duration: 120 } }

                        IslandLabel {
                            id: guardar
                            anchors.centerIn: parent
                            text: Idioma.t("Guardar")
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: guardarRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: vista.plugin.guardarActual()
                        }
                    }
                }

                MouseArea {
                    id: raton
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    //  El botón de guardar va por encima: si el ratón está en
                    //  él, esta zona no se queda el clic.
                    z: -1
                    onPositionChanged: vista.plugin.indice = fila.index
                    onClicked: function (ev) {
                        vista.plugin.indice = fila.index
                        vista.plugin.conectar(fila.modelData,
                                              (ev.modifiers & Qt.ShiftModifier) !== 0)
                    }
                }
            }
        }

        //  ── el pie ────────────────────────────────────────────────
        //
        //  Lo que se puede hacer aquí, y —si no tienes ninguna clave— lo que
        //  de verdad hace falta antes que nada. Ese aviso desaparece solo en
        //  cuanto exista una.
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            IslandLabel {
                visible: vista.plugin.sinClaves
                text: Idioma.t("No tienes ninguna clave: ctrl+K la crea y la manda al servidor")
                color: Theme.yellow
                font.pixelSize: 10
                Layout.fillWidth: true
            }

            IslandLabel {
                visible: !vista.plugin.sinClaves
                text: Idioma.t("intro conecta · shift+intro en ventana · ctrl+S guarda · ctrl+F favorito · supr borra")
                color: Theme.dim
                font.pixelSize: 10
                Layout.fillWidth: true
            }
        }
    }
}
