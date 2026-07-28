//  Los momentos de zoom que se han propuesto, para poder retocarlos.
//
//  No es un editor de vídeo: es una lista de cuatro o cinco momentos con la
//  posibilidad de quitar los que sobren, moverlos un poco y apretar o soltar el
//  zoom. Eso cubre lo que falla en la práctica —«este de aquí no lo quiero» y
//  «este entra un pelín tarde»— sin construir una línea de tiempo de verdad,
//  que no cabe en una island de 520 px de alto ni haría falta.
//
//  La previa es un fotograma renderizado con el mismo filtro que el vídeo
//  final. Dentro de la island no hay forma de reproducir vídeo, así que enseñar
//  el fotograma exacto del instante elegido es lo más cerca que se puede estar.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    focus: true

    property int elegido: 0
    property string previa: ""
    property int serie: 0

    readonly property var momento: Captura.momentos.length > 0
        ? Captura.momentos[Math.min(elegido, Captura.momentos.length - 1)] : null

    Component.onCompleted: {
        forceActiveFocus()
        pedirPrevia()
    }

    onMomentoChanged: pedirPrevia()

    //  El fotograma del centro del momento: es donde el zoom ya ha llegado y se
    //  ve de verdad a qué está apuntando.
    //
    //  Solo una a la vez. Al abrirse el editor se pide dos veces casi seguidas
    //  —al crearse y al resolverse el binding del momento—, y la segunda
    //  pisaba el destino de la primera: al terminar, la vista acababa
    //  apuntando a un fichero que todavía no existía, y el Image se quedaba en
    //  blanco para siempre porque no reintenta.
    property bool repetir: false

    function pedirPrevia() {
        if (!momento || Captura.rutaPlan.length === 0)
            return
        if (previador.running) {
            repetir = true
            return
        }
        serie += 1
        const destino = "/tmp/k4-captura/previa-" + serie + ".png"
        previador.command = ["python3", Quickshell.shellPath("tools/zoom.py"),
                             "previa", Captura.rutaVideo, Captura.rutaPlan,
                             String((momento.t0 + momento.t1) / 2), destino]
        previador.pedida = destino
        previador.running = true
    }

    Process {
        id: previador
        property string pedida: ""
        onExited: function (codigo) {
            if (codigo === 0)
                view.previa = pedida
            if (view.repetir) {
                view.repetir = false
                view.pedirPrevia()
            }
        }
    }

    Keys.onPressed: function (ev) {
        if (Captura.momentos.length === 0)
            return

        if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab) {
            view.elegido = (view.elegido + 1) % Captura.momentos.length
        } else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) {
            view.elegido = (view.elegido - 1 + Captura.momentos.length)
                % Captura.momentos.length
        } else if (ev.key === Qt.Key_Left) {
            Captura.moverMomento(view.momento.id, -0.2)
        } else if (ev.key === Qt.Key_Right) {
            Captura.moverMomento(view.momento.id, 0.2)
        } else if (ev.key === Qt.Key_Plus || ev.key === Qt.Key_Equal) {
            Captura.ajustarNivel(view.momento.id, 0.2)
        } else if (ev.key === Qt.Key_Minus) {
            Captura.ajustarNivel(view.momento.id, -0.2)
        } else if (ev.key === Qt.Key_Delete || ev.key === Qt.Key_Backspace) {
            Captura.quitarMomento(view.momento.id)
        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
            Captura.renderizar()
        } else {
            return
        }
        ev.accepted = true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ── cabecera ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF1276)      // md-magnify_scan
                color: Theme.blue
                font.pixelSize: 16
            }

            IslandLabel {
                text: Idioma.f(Idioma.t("%1 momentos de zoom"),
                               String(Captura.momentos.length))
                color: Theme.ink
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            IslandLabel {
                text: Captura.rutaVideo.split("/").pop()
                color: Theme.dim
                font.pixelSize: 10
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: Captura.descartarZoom()
            }
        }

        // ── previa y ficha ────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 356
                Layout.fillHeight: true
                radius: 8
                color: Theme.surface
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    source: view.previa.length > 0 ? "file://" + view.previa : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                }

                IslandLabel {
                    anchors.centerIn: parent
                    visible: view.previa.length === 0
                    text: Idioma.t("preparando la previa…")
                    color: Theme.dim
                    font.pixelSize: 11
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                IslandLabel {
                    visible: view.momento !== null
                    text: view.momento
                        ? Idioma.t("Momento ") + view.momento.id : ""
                    color: Theme.ink
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                IslandLabel {
                    visible: view.momento !== null
                    text: view.momento
                        ? view.momento.t0.toFixed(1) + " – " + view.momento.t1.toFixed(1) + " s"
                          + "   ·   ×" + view.momento.z.toFixed(1)
                        : ""
                    color: Theme.muted
                    font.pixelSize: 11
                }

                Item { Layout.fillHeight: true }

                // ── retoques ──────────────────────────────────────
                GridLayout {
                    columns: 2
                    columnSpacing: 6
                    rowSpacing: 6
                    Layout.fillWidth: true

                    Repeater {
                        model: [
                            { texto: Idioma.t("Antes"),  icono: 0xF0141, accion: "antes" },
                            { texto: Idioma.t("Después"), icono: 0xF0142, accion: "despues" },
                            { texto: Idioma.t("Menos"),  icono: 0xF034A, accion: "menos" },
                            { texto: Idioma.t("Más"),    icono: 0xF034B, accion: "mas" }
                        ]

                        delegate: Rectangle {
                            id: boton
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            radius: 13
                            color: botonRaton.containsMouse ? Theme.surfaceHi : Theme.surface

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5

                                IconGlyph {
                                    text: String.fromCodePoint(boton.modelData.icono)
                                    color: Theme.muted
                                    font.pixelSize: 12
                                }

                                IslandLabel {
                                    text: boton.modelData.texto
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                id: botonRaton
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: view.momento !== null
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const a = boton.modelData.accion
                                    if (a === "antes")        Captura.moverMomento(view.momento.id, -0.2)
                                    else if (a === "despues") Captura.moverMomento(view.momento.id, 0.2)
                                    else if (a === "menos")   Captura.ajustarNivel(view.momento.id, -0.2)
                                    else if (a === "mas")     Captura.ajustarNivel(view.momento.id, 0.2)
                                    view.pedirPrevia()
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    radius: 13
                    color: quitarRaton.containsMouse ? "#3a1416" : Theme.surface
                    border.width: 1
                    border.color: Qt.rgba(1, 0.27, 0.23, 0.3)

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 5

                        IconGlyph {
                            text: String.fromCodePoint(0xF01B4)    // md-delete
                            color: Theme.red
                            font.pixelSize: 12
                        }

                        IslandLabel {
                            text: Idioma.t("Quitar este momento")
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: quitarRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: view.momento !== null
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Captura.quitarMomento(view.momento.id)
                    }
                }
            }
        }

        // ── la línea de tiempo ────────────────────────────────────
        //
        //  Toda la grabación en una barra, con los momentos encima. No se puede
        //  arrastrar —para eso están los botones—, pero de un vistazo se ve si
        //  el zoom está repartido o amontonado.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 6
            color: Theme.surface

            Repeater {
                model: Captura.momentos

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool esta: index === view.elegido
                    readonly property real total: Math.max(0.001, Captura.duracionVideo)

                    x: parent.width * (modelData.t0 / total)
                    width: Math.max(3, parent.width * ((modelData.t1 - modelData.t0) / total))
                    y: 4
                    height: parent.height - 8
                    radius: 4
                    color: esta ? Theme.blue : Qt.rgba(10 / 255, 132 / 255, 1, 0.35)

                    Behavior on color { ColorAnimation { duration: 140 } }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.elegido = parent.index
                    }
                }
            }
        }

        // ── pie ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IslandLabel {
                visible: Captura.estado !== "renderizando"
                text: Idioma.t("↑↓ elige · ←→ mueve · +− nivel · supr quita · intro renderiza")
                color: Theme.dim
                font.pixelSize: 9
            }

            // Mientras renderiza, la barra sustituye a la chuleta: es lo único
            // que importa en ese momento.
            Rectangle {
                visible: Captura.estado === "renderizando"
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: Theme.track

                Rectangle {
                    width: parent.width * Captura.progreso
                    height: parent.height
                    radius: parent.radius
                    color: Theme.blue
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }

            IslandLabel {
                visible: Captura.estado === "renderizando"
                text: Math.round(Captura.progreso * 100) + " %"
                color: Theme.muted
                font.pixelSize: 10
            }

            Item { Layout.fillWidth: true; visible: Captura.estado !== "renderizando" }

            Rectangle {
                visible: Captura.estado !== "renderizando"
                Layout.preferredWidth: renderTexto.implicitWidth + 24
                Layout.preferredHeight: 26
                radius: 13
                color: Captura.momentos.length === 0 ? Theme.surface
                    : (renderRaton.containsMouse ? Qt.lighter(Theme.blue, 1.15) : Theme.blue)
                opacity: Captura.momentos.length === 0 ? 0.4 : 1

                IslandLabel {
                    id: renderTexto
                    anchors.centerIn: parent
                    text: Idioma.t("Renderizar")
                    color: Theme.ink
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: renderRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: Captura.momentos.length > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Captura.renderizar()
                }
            }
        }
    }
}
