//  La bolsa: abrir cofres, equipar y desguazar.
//
//  Clic izquierdo equipa en el héroe al que más le sirve; clic derecho
//  desguaza; y las piezas se arrastran para colocarlas donde quieras.
//
//  La raíz es un Item y no el ColumnLayout a propósito: la ficha que sale al
//  pasar el ratón y la ceremonia del cofre tienen que quedar FUERA del layout.
//  Declaradas dentro, el layout las contaba como una fila más y recolocaba el
//  panel entero cada vez que aparecían, que era el parpadeo.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: panel

    property var plugin: null
    property var ultimo: null           // lo último que salió de un cofre

    // Agrupar iguales: con sesenta casillas, ver «×4» dice más que cuatro
    // dibujos repetidos. Va como interruptor porque agrupando no se puede
    // arrastrar para ordenar, y eso también se usa.
    property bool agrupado: true

    // Modo fusión: la rejilla se aparta a la izquierda y entra el crisol.
    property bool fundiendo: false
    property string avisoCombina: ""
    property color avisoColor: Theme.ink

    // pieza bajo el ratón, para la ficha flotante
    property var mirando: null
    property real mirandoX: 0
    property real mirandoY: 0

    // A quién le viene mejor una pieza: la clase que más gana con ella, de
    // entre las que tengan nivel para ponérsela. Así equipar es un clic.
    function mejorDestino(objeto) {
        let mejor = Game.clases[0].id
        let ganancia = -Infinity

        for (let i = 0; i < Game.clases.length; ++i) {
            const clase = Game.clases[i].id
            if (!Game.puedeEquipar(objeto, clase))
                continue

            const puesto = (Game.equipo[clase] || ({}))[objeto.hueco]
            const delta = Items.puntuacion(objeto) - Items.puntuacion(puesto)

            // el arma le luce más a quien más daño base tiene, y la armadura
            // a quien aguanta: se pondera por el papel de la clase
            const peso = objeto.hueco === "arma" ? Game.clases[i].daño / 10
                : objeto.hueco === "armadura" || objeto.hueco === "escudo"
                    ? Game.clases[i].vida / 150 : 1

            if (delta * peso > ganancia) {
                ganancia = delta * peso
                mejor = clase
            }
        }
        return mejor
    }

    function combinar(clave) {
        Game.combinarGrupo(clave)
    }

    Connections {
        target: Game

        function onCombinado(cambio, objeto) {
            panel.avisoCombina = cambio === "mejor" ? Idioma.t("¡Ha subido de grado!")
                : cambio === "peor" ? Idioma.t("Ha bajado de grado")
                : Idioma.t("Se ha quedado igual")
            panel.avisoColor = cambio === "mejor" ? Theme.green
                : cambio === "peor" ? Theme.red : Theme.muted
            borrarAviso.restart()
        }
    }

    Timer {
        id: borrarAviso
        interval: 2600
        onTriggered: panel.avisoCombina = ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // ── cofres ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 34
            spacing: 6

            Repeater {
                model: Items.cofres

                delegate: IslandTile {
                    id: cofre
                    required property var modelData
                    required property int index
                    readonly property int cuantos: Game.cofresPorTipo[index]

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 9
                    pulsable: cuantos > 0
                    opacity: cuantos > 0 ? 1 : 0.45
                    onPulsada: panel.plugin.abrirConCeremonia(cofre.index)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 7

                        // El sprite del cofre, no un icono genérico: es el
                        // mismo que vas a ver abrirse, así que la tarjeta y la
                        // ceremonia hablan de lo mismo. El cuadro 0 de cada
                        // tipo es el cerrado.
                        Image {
                            source: "assets/cofres/c"
                                + String(cofre.index * 4).padStart(2, "0") + ".png"
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            Layout.alignment: Qt.AlignVCenter
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            opacity: cofre.cuantos > 0 ? 1 : 0.5
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            IslandLabel {
                                text: cofre.modelData.nombre
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            IslandLabel {
                                text: cofre.cuantos > 1 ? Idioma.t("pulsa, o ▶▶ para todos")
                                    : (cofre.cuantos > 0 ? Idioma.t("pulsa para abrir")
                                       : Idioma.t("no tienes"))
                                color: Theme.dim
                                font.pixelSize: 8
                            }
                        }

                        IslandLabel {
                            text: cofre.cuantos
                            color: cofre.cuantos > 0 ? Theme.ink : Theme.dim
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Abrir todos los de este tipo del tirón. Va con z por
                        // encima: la tarjeta tiene su propio ratón que si no se
                        // queda con el clic.
                        Rectangle {
                            id: cadena
                            z: 2
                            visible: cofre.cuantos > 1
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 20
                            Layout.alignment: Qt.AlignVCenter
                            radius: 10

                            readonly property bool activa: panel.plugin
                                && panel.plugin.enCadena === cofre.index

                            color: activa ? Theme.red
                                : (cadenaRaton.containsMouse ? Theme.blue : Theme.surfaceHi)

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IconGlyph {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(cadena.activa ? 0xF04DB : 0xF0211)
                                color: Theme.ink
                                font.pixelSize: 11
                            }

                            MouseArea {
                                id: cadenaRaton
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (cadena.activa)
                                        panel.plugin.pararCadena()
                                    else
                                        panel.plugin.abrirEnCadena(cofre.index)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── estado de la bolsa ────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 18
            spacing: 8

            IslandLabel {
                text: Game.bolsa.length + " / " + Game.topeBolsa + Idioma.t(" piezas")
                color: Theme.muted
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Idioma.t("izquierdo equipa · derecho desguaza · arrastra para ordenar")
                color: Theme.dim
                font.pixelSize: 9
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }

            // aviso de lo que ha salido al combinar
            IslandLabel {
                visible: panel.avisoCombina.length > 0
                text: panel.avisoCombina
                color: panel.avisoColor
                font.pixelSize: 10
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                Layout.preferredWidth: fundirTexto.implicitWidth + 20
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                radius: 9
                color: panel.fundiendo ? "#b8860b"
                    : (fundirModoRaton.containsMouse ? Theme.surfaceHi : Theme.surface)

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: fundirTexto
                    anchors.centerIn: parent
                    text: Idioma.t("Fusionar")
                    color: panel.fundiendo ? Theme.ink : Theme.muted
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: fundirModoRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        panel.fundiendo = !panel.fundiendo
                        // el agrupado se queda: es donde se ven los ×N y de
                        // donde salen las piezas repetidas que vas a fundir
                        if (!panel.fundiendo)
                            crisolPieza.vaciar()
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: agruparTexto.implicitWidth + 20
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                radius: 9
                color: panel.agrupado ? Theme.blue
                    : (agruparMouse.containsMouse ? Theme.surfaceHi : Theme.surface)

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: agruparTexto
                    anchors.centerIn: parent
                    text: Idioma.t("Agrupar")
                    color: panel.agrupado ? Theme.ink : Theme.muted
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: agruparMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.agrupado = !panel.agrupado
                }
            }

            Rectangle {
                Layout.preferredWidth: limpiar.implicitWidth + 20
                Layout.preferredHeight: 18
                radius: 9
                color: limpiarMouse.containsMouse ? Theme.red : Theme.surfaceHi
                visible: Game.bolsa.length > 0

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: limpiar
                    anchors.centerIn: parent
                    text: Idioma.t("Desguazar sobrantes")
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: limpiarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Game.desguazarSobrantes()
                }
            }
        }

        // ── la bolsa, en rejilla ──────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

        GridView {
            id: rejilla
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            // 32 del sprite + 14 de aire para el borde y la insignia. Las
            // columnas salen de ahí y el sobrante se reparte, así que la
            // rejilla llena el ancho sin dejar el icono a escala rara.
            readonly property int celda: 46
            readonly property int columnas: Math.max(6, Math.floor(width / celda))
            cellWidth: Math.floor(width / columnas)
            cellHeight: cellWidth
            model: panel.agrupado ? Game.grupos.length : Game.bolsa.length
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: hueco
                required property int index
                width: rejilla.cellWidth
                height: rejilla.cellHeight

                readonly property var grupo: panel.agrupado
                    ? Game.grupos[hueco.index] : null

                CeldaObjeto {
                    anchors.fill: parent
                    anchors.margins: 2
                    objeto: hueco.grupo ? hueco.grupo.mejor : Game.bolsa[hueco.index]
                    posicion: hueco.index
                    cuantos: hueco.grupo ? hueco.grupo.piezas.length : 0
                    grupoClave: hueco.grupo ? hueco.grupo.clave : ""
                    modoFusion: panel.fundiendo
                    // arrastrar vale siempre que no estemos reordenando
                    // Siempre: antes se apagaba al agrupar, y como agrupar
                    // viene puesto de fábrica, el arrastre no funcionaba nunca.
                    arrastrable: true

                    onAlCrisol: {
                        if (hueco.grupo)
                            crisolPieza.meterDelGrupo(hueco.grupo.clave)
                        else
                            crisolPieza.meter(Game.bolsa[hueco.index])
                    }


                    onPulsado: {
                        const it = Game.bolsa[hueco.index]
                        if (it) Game.equipar(it, panel.mejorDestino(it))
                    }
                    onSecundario: {
                        const it = Game.bolsa[hueco.index]
                        if (it) Game.desguazar(it)
                    }
                    onSoltadoEn: function (desde) { Game.moverEnBolsa(desde, hueco.index) }
                    onSoltadoGrupo: function (clave) { Game.moverGrupo(clave, hueco.index) }

                    onEncimaChanged: {
                        if (encima) {
                            panel.mirando = objeto
                            const pos = mapToItem(panel, width / 2, 0)
                            panel.mirandoX = pos.x
                            panel.mirandoY = pos.y
                        } else if (panel.mirando === objeto) {
                            panel.mirando = null
                        }
                    }
                }
            }

            IslandLabel {
                anchors.centerIn: parent
                visible: Game.bolsa.length === 0
                text: Game.cofres > 0 ? Idioma.t("Abre un cofre ahí arriba") : Idioma.t("La bolsa está vacía")
                color: Theme.muted
                font.pixelSize: 11
            }
        }
        Crisol {
            id: crisolPieza
            visible: panel.fundiendo
            Layout.preferredWidth: visible ? 190 : 0
            Layout.fillHeight: true

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
        }
        }

    }
    // ── ficha flotante, fuera del layout ──────────────────────────
    Rectangle {
        id: emergente
        z: 30
        visible: panel.mirando !== null
        width: Math.min(230, panel.width - 12)
        height: contenidoFicha.implicitHeight + 14
        radius: 9
        color: "#f2101014"
        border.width: 1
        border.color: panel.mirando
            ? Items.rarezaDe(panel.mirando.rareza).color : Theme.surfaceHi

        x: Math.max(4, Math.min(panel.width - width - 4, panel.mirandoX - width / 2))
        y: Math.max(4, panel.mirandoY - height - 6)

        ColumnLayout {
            id: contenidoFicha
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 7
            spacing: 3

            IslandLabel {
                text: panel.mirando ? panel.mirando.nombre : ""
                font.pixelSize: 11
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                spacing: 5

                InsigniaRareza {
                    rareza: panel.mirando ? panel.mirando.rareza : 0
                    nivel: Items.nivelDe(panel.mirando)
                }

                IslandLabel {
                    text: panel.mirando ? Items.huecoDe(panel.mirando.hueco).nombre : ""
                    color: Theme.muted
                    font.pixelSize: 9
                }
            }

            IslandLabel {
                text: panel.mirando ? Items.resumen(panel.mirando) : ""
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            IslandLabel {
                visible: panel.mirando !== null && !Game.algunoPuede(panel.mirando)
                text: Idioma.t("necesita nivel ") + Items.nivelRequerido(panel.mirando)
                color: Theme.red
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }

            IslandLabel {
                text: panel.mirando
                    ? Idioma.t("desguace: ") + Game.cifra(Items.valorDesguace(panel.mirando)) + Idioma.t(" reliquias")
                    : ""
                color: Theme.dim
                font.pixelSize: 9
            }
        }
    }

    // ── ceremonia de apertura, por encima de todo ─────────────────
    AperturaCofre {
        id: ceremonia
        anchors.fill: parent
        z: 40
        visible: panel.plugin && panel.plugin.abriendo !== null
        tipo: panel.plugin ? panel.plugin.tipoAbriendo : 0
        objeto: panel.plugin ? panel.plugin.abriendo : null

        rapido: panel.plugin ? panel.plugin.encadenando : false
        encadenando: panel.plugin ? panel.plugin.encadenando : false
        quedan: panel.plugin && panel.plugin.enCadena >= 0
            ? Game.cofresPorTipo[panel.plugin.enCadena] : 0

        onParar: panel.plugin.pararCadena()

        onTerminado: {
            panel.ultimo = panel.plugin.abriendo
            panel.plugin.abriendo = null
            panel.plugin.seguirCadena()
        }

        // Arranca al anunciarse un cofre y también al montarse: abrir desde
        // fuera cambia de pestaña, así que la señal salta antes de que exista
        // este panel y la ceremonia se quedaba congelada en el primer cuadro.
        Component.onCompleted: if (panel.plugin && panel.plugin.abriendo) abrir()

        Connections {
            target: panel.plugin
            function onAbriendoChanged() {
                if (panel.plugin.abriendo)
                    ceremonia.abrir()
            }
        }
    }
}
