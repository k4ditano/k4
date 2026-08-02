//  La rejilla del centro de aplicaciones.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    readonly property int celdaAncho: 128
    readonly property int celdaAlto: 104

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ── el buscador ───────────────────────────────────────────
        Rectangle {
            visible: !view.plugin.modoActualizaciones
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 12
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                IconGlyph {
                    text: ""  // fa-search
                    color: Theme.muted
                    font.pixelSize: 15
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextInput {
                        id: entrada
                        cursorDelegate: IslandCursor {}
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 16
                        focus: true
                        clip: true
                        selectByMouse: true
                        selectionColor: Theme.blue
                        text: view.plugin.busqueda

                        onTextEdited: {
                            view.plugin.busqueda = text
                            view.plugin.seleccion = 0
                        }

                        Keys.onPressed: function (ev) {
                            if (ev.key === Qt.Key_Escape)
                                view.plugin.cerrar()
                            else if (ev.key === Qt.Key_Return
                                     || ev.key === Qt.Key_Enter)
                                view.plugin.lanzarSeleccion()
                            else if (ev.key === Qt.Key_Right)
                                view.plugin.mover(1, 0)
                            else if (ev.key === Qt.Key_Left)
                                view.plugin.mover(-1, 0)
                            else if (ev.key === Qt.Key_Down)
                                view.plugin.mover(0, 1)
                            else if (ev.key === Qt.Key_Up)
                                view.plugin.mover(0, -1)
                            else
                                return
                            ev.accepted = true
                        }

                        IslandLabel {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: entrada.text.length === 0
                            text: Idioma.t("Buscar aplicaciones")
                            color: Theme.dim
                            font.pixelSize: 16
                        }
                    }
                }

                IslandLabel {
                    text: view.plugin.lista.length
                    color: Theme.muted
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }

        // ── la rejilla ────────────────────────────────────────────
        K4.Rodillo {
            visible: !view.plugin.modoActualizaciones
            Layout.fillWidth: true
            Layout.fillHeight: true
            muesca: view.celdaAlto

            Flow {
                width: parent.width
                spacing: 4

                Repeater {
                    model: view.plugin.lista

                    delegate: IslandTile {
                        id: celda
                        required property var modelData
                        required property int index

                        width: view.celdaAncho
                        height: view.celdaAlto

                        //  La elegida con el teclado lleva borde azul, no solo
                        //  el fondo claro: el fondo claro ya lo pone el ratón
                        //  al pasar y las dos cosas se confundían — no se sabía
                        //  qué iba a abrir el Enter.
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.blue
                            visible: celda.index === view.plugin.seleccion
                        }
                        //  Una apagada no se abre, pero sí se puede pulsar:
                        //  el clic lleva a Ajustes, que es lo que hace falta.
                        onPulsada: modelData.habilitado
                            ? view.plugin.lanzar(modelData.id)
                            : view.plugin.lanzar("settings")

                        //  La chincheta: pone o quita esta aplicación de la
                        //  franja del centro de control. Solo al pasar por
                        //  encima —o si ya está puesta, siempre—, que si no
                        //  la rejilla se llena de iconos que no son la app.
                        IconGlyph {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            z: 2
                            text: String.fromCodePoint(0xF0403)   // md-pin
                            font.pixelSize: 13
                            visible: celda.encima
                                || Settings.esAccesoDirecto(celda.modelData.id)
                            color: Settings.esAccesoDirecto(celda.modelData.id)
                                ? Theme.blue : Theme.dim
                            rotation: Settings.esAccesoDirecto(celda.modelData.id)
                                ? 0 : 45

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Settings.alternarAcceso(celda.modelData.id)
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            K4.IconoPlugin {
                                anchors.horizontalCenter: parent.horizontalCenter
                                imagen: celda.modelData.imagen
                                glifo: celda.modelData.glifo
                                tamano: 30
                                //  Apagada en gris, rota en rojo. Una imagen
                                //  propia no se tiñe —es del autor— pero sí
                                //  se apaga, que si no una apagada se nota
                                //  menos que las demás y desconcierta.
                                opacity: celda.modelData.habilitado ? 1 : 0.35
                                color: celda.modelData.habilitado
                                    ? (celda.modelData.disponible ? Theme.ink
                                                                  : Theme.red)
                                    : Theme.dim
                            }

                            IslandLabel {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: view.celdaAncho - 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: celda.modelData.nombre
                                font.pixelSize: 11
                                color: celda.modelData.habilitado ? Theme.ink
                                                                  : Theme.dim
                            }
                        }
                    }
                }
            }
        }

        // ── elegir qué actualizar ─────────────────────────────────
        //
        //  La rejilla se aparta y sale la lista de pendientes, cada una
        //  con su interruptor. Elegir aquí es EXCLUIR: lo desmarcado se
        //  queda quieto con --ignore y el resto sube en una actualización
        //  completa — subir paquetes sueltos sobre un sistema viejo es la
        //  forma clásica de romper un Arch, y esta es la que pacman
        //  contempla de fábrica.
        Rectangle {
            visible: view.plugin.modoActualizaciones
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 12
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 14
                spacing: 8

                MediaButton {
                    glyph: String.fromCodePoint(0xF004D)   // md-arrow_left
                    glyphSize: 15
                    glyphColor: Theme.muted
                    onActivated: view.plugin.modoActualizaciones = false
                }

                IslandLabel {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: K4.Idioma.t("Elige qué actualizar")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.ink
                }

                IslandLabel {
                    text: K4.Idioma.f(K4.Idioma.t("%1 de %2 marcadas"),
                                      String(Paquetes.marcadas),
                                      String(Paquetes.pendientes))
                    color: Theme.muted
                    font.pixelSize: 11
                }
            }
        }

        K4.Rodillo {
            visible: view.plugin.modoActualizaciones
            Layout.fillWidth: true
            Layout.fillHeight: true
            muesca: 38

            Column {
                width: parent.width
                spacing: 4

                Repeater {
                    model: view.plugin.modoActualizaciones
                        ? Paquetes.detalles : []

                    delegate: Rectangle {
                        id: fila
                        required property var modelData
                        //  Marcada = sube. Se lee del servicio y no de un
                        //  estado local para que la cuenta de la cabecera,
                        //  el botón del pie y la fila cuenten lo mismo.
                        readonly property bool dentro:
                            !Paquetes.excluidos[modelData.nombre]

                        width: parent.width
                        height: 34
                        radius: 10
                        color: filaRaton.containsMouse
                            ? Qt.lighter(Theme.surface, 1.4) : Theme.surface

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 12
                            spacing: 10

                            //  El interruptor de esta app, lo que pedía la
                            //  pregunta: azul con su marca cuando va a subir,
                            //  hueco cuando se queda.
                            Rectangle {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                radius: 9
                                color: fila.dentro ? Theme.blue : "transparent"
                                border.width: fila.dentro ? 0 : 1
                                border.color: Theme.dim

                                IconGlyph {
                                    anchors.centerIn: parent
                                    visible: fila.dentro
                                    text: String.fromCodePoint(0xF012C) // md-check
                                    font.pixelSize: 11
                                    color: Theme.ink
                                }
                            }

                            IslandLabel {
                                text: fila.modelData.nombre
                                font.pixelSize: 12
                                color: fila.dentro ? Theme.ink : Theme.dim
                            }

                            IslandLabel {
                                visible: fila.modelData.aur
                                text: "AUR"
                                font.pixelSize: 9
                                color: Theme.yellow
                            }

                            Item { Layout.fillWidth: true }

                            IslandLabel {
                                Layout.maximumWidth: 280
                                elide: Text.ElideLeft
                                text: fila.modelData.de + "  →  "
                                    + fila.modelData.a
                                font.pixelSize: 10
                                color: Theme.dim
                            }
                        }

                        MouseArea {
                            id: filaRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Paquetes.alternarExcluida(
                                           fila.modelData.nombre)
                        }
                    }
                }
            }
        }

        // ── las actualizaciones del sistema ───────────────────────
        //
        //  El pie del centro: cuántas esperan y el botón que las aplica.
        //  Aquí y no en otro módulo porque este ES el sitio de las
        //  aplicaciones, y mantenerlas al día es parte de tenerlas.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 12
            color: Theme.surface

            //  Pulsar la franja abre (o cierra) la lista para elegir. Va
            //  DEBAJO de la fila de botones: los que llevan ratón propio
            //  —volver a mirar, actualizar— se quedan el clic para ellos.
            MouseArea {
                anchors.fill: parent
                enabled: Paquetes.pendientes > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: view.plugin.modoActualizaciones =
                               !view.plugin.modoActualizaciones
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 8

                IconGlyph {
                    text: String.fromCodePoint(0xF06B0)  // md-update
                    color: Paquetes.pendientes > 0 ? Theme.yellow
                                                      : Theme.dim
                    font.pixelSize: 14
                }

                ColumnLayout {
                    id: pieTextos
                    Layout.fillWidth: true
                    spacing: 0

                    IslandLabel {
                        text: Paquetes.comprobando
                            ? K4.Idioma.t("Buscando actualizaciones…")
                            : Paquetes.pendientesRepo < 0
                            ? K4.Idioma.t("Actualizaciones sin comprobar")
                            : Paquetes.pendientes === 0
                            ? K4.Idioma.t("El sistema está al día")
                            : K4.Idioma.f(
                                K4.Idioma.t("%1 actualizaciones (%2)"),
                                String(Paquetes.pendientes),
                                Math.max(0, Paquetes.pendientesRepo)
                                    + " repos · "
                                    + Math.max(0, Paquetes.pendientesAur)
                                    + " AUR")
                        color: Paquetes.pendientes > 0 ? Theme.ink
                                                          : Theme.muted
                        font.pixelSize: 11
                    }

                    IslandLabel {
                        visible: Paquetes.nombresPendientes.length > 0
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Paquetes.nombresPendientes.slice(0, 8)
                            .join("  ·  ")
                        color: Theme.dim
                        font.pixelSize: 9
                    }
                }

                IconGlyph {
                    visible: Paquetes.pendientes > 0
                    text: String.fromCodePoint(
                              view.plugin.modoActualizaciones
                                  ? 0xF0140 : 0xF0143)  // chevron down / up
                    color: Theme.dim
                    font.pixelSize: 14
                }

                //  Volver a mirar, saltándose la caché de diez minutos.
                MediaButton {
                    glyph: String.fromCodePoint(0xF0450)   // md-refresh
                    glyphSize: 13
                    glyphColor: Theme.dim
                    onActivated: Paquetes.comprobar(true)
                }

                //  Sin nada marcado el botón se apaga: una tanda vacía no
                //  es una orden, es un despiste.
                Rectangle {
                    visible: Paquetes.pendientes > 0
                    Layout.preferredWidth: actualizarTexto.implicitWidth + 22
                    Layout.preferredHeight: 26
                    radius: 13
                    color: Paquetes.marcadas === 0 ? Theme.surface
                        : actualizarRaton.containsMouse
                        ? Qt.lighter(Theme.blue, 1.15) : Theme.blue

                    IslandLabel {
                        id: actualizarTexto
                        anchors.centerIn: parent
                        text: Paquetes.marcadas < Paquetes.pendientes
                            ? K4.Idioma.f(K4.Idioma.t("Actualizar %1"),
                                          String(Paquetes.marcadas))
                            : K4.Idioma.t("Actualizar")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Paquetes.marcadas === 0 ? Theme.dim : Theme.ink
                    }

                    MouseArea {
                        id: actualizarRaton
                        anchors.fill: parent
                        enabled: Paquetes.marcadas > 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Paquetes.actualizarMarcadas()
                            view.plugin.cerrar()
                        }
                    }
                }
            }
        }
    }

    //  El teclado en la lista: el buscador está oculto y alguien tiene que
    //  responder — Escape vuelve a la rejilla, Enter aplica lo marcado.
    Item {
        id: tecladoLista
        visible: view.plugin.modoActualizaciones

        Keys.onPressed: function (ev) {
            if (ev.key === Qt.Key_Escape) {
                view.plugin.modoActualizaciones = false
                ev.accepted = true
            } else if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter)
                       && Paquetes.marcadas > 0) {
                Paquetes.actualizarMarcadas()
                view.plugin.cerrar()
                ev.accepted = true
            }
        }
    }

    //  El foco al buscador en cuanto se abre —se abre para escribir—, o a
    //  la lista si lo que está delante es la lista.
    FocoInicial {
        id: foco
        objetivo: view.plugin.modoActualizaciones ? tecladoLista : entrada
    }
    Component.onCompleted: foco.reclamar()

    Connections {
        target: view.plugin
        function onModoActualizacionesChanged() { foco.reclamar() }
    }
}
