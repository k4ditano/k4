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

    //  Y lo mismo al pasar al formulario: el campo activo se apunta aquí y se
    //  le reclama el foco con la misma pieza. Sin esto el formulario sale
    //  pintado pero sordo — se veía perfecto y no recibía ni una tecla.
    property Item entradaActiva: null
    FocoInicial { id: focoCampo; objetivo: vista.entradaActiva }

    Connections {
        target: vista.plugin
        function onModoChanged() {
            if (vista.plugin.modo === "editar" && vista.entradaActiva)
                focoCampo.reclamar()
            else if (vista.plugin.modo === "lista")
                foco.reclamar()
        }
    }

    ColumnLayout {
        visible: vista.plugin.modo === "lista"
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
                    } else if (conCtrl && ev.key === Qt.Key_E) {
                        vista.plugin.editarActual(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_N) {
                        vista.plugin.nuevoDesdeBusqueda(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_F) {
                        vista.plugin.favoritoActual(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_G) {
                        vista.plugin.alternarAgentes(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_K) {
                        vista.plugin.crearClave(); ev.accepted = true
                    } else if (conCtrl && ev.key === Qt.Key_I) {
                        vista.plugin.llevarIntegracion(); ev.accepted = true
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

                            //  La puerta de los agentes, si está abierta. Es un
                            //  permiso: se ve o no se revisa nunca.
                            IconGlyph {
                                visible: fila.modelData.agentes === true
                                text: String.fromCodePoint(0xF0493)   // md-cog
                                color: Theme.green
                                font.pixelSize: 11
                                Layout.alignment: Qt.AlignVCenter
                            }

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
                text: Idioma.t("intro conecta · shift+intro ventana · ctrl+E edita · ctrl+F favorito · ctrl+G agentes · ctrl+I integración · supr borra")
                color: Theme.dim
                font.pixelSize: 10
                Layout.fillWidth: true
            }
        }
    }

    //  ── configurar un servidor ────────────────────────────────────
    //
    //  La misma ventana cambia de cara en vez de abrir un diálogo encima:
    //  arriba lo que ssh entiende —y que por tanto aprovechan también scp,
    //  git y compañía— y abajo lo nuestro, separado por una línea para que se
    //  vea de un vistazo qué va a dónde.
    ColumnLayout {
        visible: vista.plugin.modo === "editar"
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        anchors.bottomMargin: 10
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF08C0)
                color: Theme.muted
                font.pixelSize: 15
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: vista.plugin.borrador.original
                    ? Idioma.t("Editar ") + vista.plugin.borrador.original
                    : Idioma.t("Servidor nuevo")
                color: Theme.ink
                font.pixelSize: 15
                Layout.fillWidth: true
            }

            //  Favorito aquí también: es parte de cómo lo quieres, no una
            //  acción aparte.
            Rectangle {
                Layout.preferredWidth: estrella.implicitWidth + 20
                Layout.preferredHeight: 22
                radius: 11
                color: vista.plugin.borrador.favorito ? Theme.surfaceHi : "transparent"
                border.width: 1
                border.color: Theme.surfaceHi

                IslandLabel {
                    id: estrella
                    anchors.centerIn: parent
                    text: (vista.plugin.borrador.favorito ? "★ " : "☆ ") + Idioma.t("favorito")
                    color: vista.plugin.borrador.favorito ? Theme.yellow : Theme.muted
                    font.pixelSize: 10
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vista.plugin.ponerCampo("favorito",
                                                       !vista.plugin.borrador.favorito)
                }
            }
        }

        Repeater {
            model: vista.plugin.campos

            delegate: ColumnLayout {
                id: filaCampo
                required property var modelData
                required property int index

                readonly property bool activo: index === vista.plugin.campo

                Layout.fillWidth: true
                spacing: 6

                //  Una raya antes de lo nuestro: arriba lo que entiende ssh,
                //  abajo lo que solo entendemos aquí. Va en su propia fila —no
                //  dentro de la del campo— o empujaría la etiqueta a un lado.
                Rectangle {
                    visible: filaCampo.modelData.suyo
                             && !vista.plugin.campos[Math.max(0, filaCampo.index - 1)].suyo
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 2
                    Layout.preferredHeight: 1
                    color: Theme.surfaceHi
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: 8

                IslandLabel {
                    text: filaCampo.modelData.nombre
                    color: filaCampo.activo ? Theme.ink : Theme.muted
                    font.pixelSize: 12
                    Layout.preferredWidth: 78
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    radius: 7
                    color: filaCampo.activo ? Theme.surfaceHi : Theme.surface
                    border.width: 1
                    border.color: filaCampo.activo ? Theme.blue : "transparent"

                    Behavior on color { ColorAnimation { duration: 110 } }

                    TextInput {
                        id: entradaCampo
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        cursorDelegate: IslandCursor {}
                        color: Theme.ink
                        font.family: Theme.uiFont
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true
                        selectionColor: Theme.blue

                        text: vista.plugin.borrador[filaCampo.modelData.id] || ""
                        onTextEdited: vista.plugin.ponerCampo(filaCampo.modelData.id, text)

                        //  El campo secreto va con puntos hasta que pidas
                        //  verlo: nadie quiere su contraseña en pantalla por
                        //  defecto con alguien detrás.
                        echoMode: filaCampo.modelData.secreto && !vista.plugin.verClave
                            ? TextInput.Password : TextInput.Normal
                        passwordCharacter: "•"
                        passwordMaskDelay: 0

                        //  El foco lo lleva el campo activo, y se pide cuando
                        //  cambia: así las flechas mueven de campo y lo que se
                        //  teclea va siempre al que está marcado.
                        focus: filaCampo.activo
                        onActiveFocusChanged: if (activeFocus) vista.plugin.campo = filaCampo.index

                        //  El activo se apunta en la vista para que el foco
                        //  sepa a quién ir, y se le pide en cuanto cambia.
                        Component.onCompleted: if (filaCampo.activo) vista.entradaActiva = entradaCampo

                        Connections {
                            target: vista.plugin
                            function onCampoChanged() {
                                if (filaCampo.activo) {
                                    vista.entradaActiva = entradaCampo
                                    entradaCampo.forceActiveFocus()
                                }
                            }
                        }

                        IslandLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: entradaCampo.text.length === 0
                            text: filaCampo.modelData.ayuda
                            color: Theme.dim
                            font.pixelSize: 11
                        }

                        Keys.onPressed: function (ev) {
                            if (ev.key === Qt.Key_Escape) {
                                vista.plugin.cancelarEdicion(); ev.accepted = true
                            } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                                //  Intro guarda desde cualquier campo: es un
                                //  formulario de ocho líneas, no un trámite.
                                vista.plugin.guardarBorrador(); ev.accepted = true
                            } else if ((ev.modifiers & Qt.ControlModifier)
                                       && ev.key === Qt.Key_O) {
                                //  El ojo del formulario, con tecla: aquí no
                                //  hay ratón que llevar hasta un icono.
                                vista.plugin.verClave = !vista.plugin.verClave
                                ev.accepted = true
                            } else if (ev.key === Qt.Key_Down
                                       || (ev.key === Qt.Key_Tab && !(ev.modifiers & Qt.ShiftModifier))) {
                                vista.plugin.moverCampo(1); ev.accepted = true
                            } else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) {
                                vista.plugin.moverCampo(-1); ev.accepted = true
                            }
                        }
                    }
                }
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IslandLabel {
                text: Idioma.t("intro guarda · esc cancela · ↑↓ o tab cambia de campo")
                color: Theme.dim
                font.pixelSize: 10
                Layout.fillWidth: true
            }

            IslandLabel {
                text: Idioma.t("lo de arriba va a ~/.ssh/config")
                color: Theme.dim
                font.pixelSize: 10
            }
        }
    }
}
