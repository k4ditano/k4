//  Un plugin instalado, en una fila que se despliega.
//
//  Antes eran dos sitios: aquí un interruptor con el nombre, y en OTRA sección
//  de la lateral los ajustes de ese mismo plugin. Para apagar lo que acababas
//  de configurar había que cruzar la ventana, y para saber qué era «senda»
//  había que abrir su repositorio.
//
//  Cerrada dice lo justo —nombre, versión y si está encendido—. Abierta dice lo
//  que hace, de dónde vino, qué permisos pide, por dónde se le llama, y trae
//  sus propios ajustes al lado del interruptor que los enciende.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

Rectangle {
    id: fila

    required property var modelData

    //  `modelData` viene de `PluginManager.opcionesAjustes`: lo justo para la
    //  fila cerrada. Lo demás se busca cuando hace falta.
    readonly property string ident: String(modelData.pluginId || "")
    readonly property var meta: PluginManager.metadata(fila.ident)

    //  Sus ajustes, los que registró con `K4.Ajustes`. Puede no tener.
    readonly property var suGrupo: {
        const gs = Enganches.gruposAjustes
        for (let i = 0; i < gs.length; ++i)
            if (gs[i].dePlugin === fila.ident)
                return gs[i]
        return null
    }

    readonly property bool encendido: !!Settings.valor(modelData.id)

    //  Roto o sin requisitos: se dice y no se deja tocar. `fijo` es que no hay
    //  nada que hacer desde aquí; `recargable` es que se puede reintentar.
    readonly property bool averiado: modelData.error === "fijo"

    property bool abierta: false

    Layout.fillWidth: true
    Layout.preferredHeight: cuerpo.implicitHeight + 18

    radius: 12
    color: fila.abierta ? Theme.surfaceHi
        : (raton.containsMouse ? Theme.surfaceHi : Theme.surface)

    Behavior on color { ColorAnimation { duration: 140 } }

    ColumnLayout {
        id: cuerpo
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 9
        spacing: 10

        // ── lo que se ve siempre ──────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            spacing: 11

            //  La flecha. Gira al abrir, que es la forma de decir «esto tiene
            //  más» sin escribirlo.
            IconGlyph {
                Layout.alignment: Qt.AlignVCenter
                text: String.fromCodePoint(0xF0142)   // md-chevron_right
                color: Theme.dim
                font.pixelSize: 14
                renderType: Text.NativeRendering
                rotation: fila.abierta ? 90 : 0
                Behavior on rotation {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            //  Su icono: la imagen si trae una, y si no el códice.
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 18
                implicitHeight: 18

                Image {
                    anchors.fill: parent
                    visible: String(fila.modelData.imagen || "").length > 0
                    source: fila.modelData.imagen || ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                }

                IconGlyph {
                    anchors.centerIn: parent
                    visible: String(fila.modelData.imagen || "").length === 0
                    text: String.fromCodePoint(fila.modelData.glifo)
                    color: fila.encendido ? Theme.ink : Theme.muted
                    font.pixelSize: 15
                    renderType: Text.NativeRendering
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                IslandLabel {
                    Layout.fillWidth: true
                    text: fila.modelData.nombre
                    textFormat: Text.PlainText
                    color: fila.averiado ? Theme.red
                        : (fila.encendido ? Theme.ink : Theme.muted)
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                //  Cerrada, la descripción en una línea. Abierta se calla:
                //  abajo va entera y sin recortar.
                IslandLabel {
                    Layout.fillWidth: true
                    visible: !fila.abierta
                    text: fila.modelData.desc
                    textFormat: Text.PlainText
                    color: fila.averiado ? Theme.red : Theme.dim
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            //  Cuántos ajustes trae, cuando trae. Es la pista de que ahí dentro
            //  hay algo, sin tener que abrir para averiguarlo.
            Rectangle {
                visible: !fila.abierta && fila.suGrupo !== null
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: cuenta.implicitWidth + 14
                implicitHeight: 18
                radius: 9
                color: Theme.track

                IslandLabel {
                    id: cuenta
                    anchors.centerIn: parent
                    text: fila.suGrupo ? String(fila.suGrupo.opciones.length) : ""
                    color: Theme.muted
                    font.pixelSize: 9
                }
            }

            //  El interruptor. Lo mismo que había, en el mismo sitio.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 40
                implicitHeight: 22
                radius: 11
                opacity: fila.averiado ? 0.35 : 1
                color: fila.encendido ? Theme.green : Theme.track

                Behavior on color { ColorAnimation { duration: 140 } }

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                    x: fila.encendido ? parent.width - width - 2 : 2

                    Behavior on x {
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !fila.averiado
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Settings.alternar(fila.modelData.id)
                }
            }
        }

        // ── lo que aparece al desplegar ───────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 25
            Layout.bottomMargin: 9
            visible: fila.abierta
            spacing: 8

            IslandLabel {
                Layout.fillWidth: true
                visible: text.length > 0
                text: fila.modelData.desc
                textFormat: Text.PlainText
                color: fila.averiado ? Theme.red : Theme.muted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            //  De dónde salió y qué se queda. Un plugin de fuera corre dentro
            //  de la barra y puede hacer lo que la barra pueda: saber de quién
            //  es y qué pide no es un detalle de más.
            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: {
                        const m = fila.meta
                        if (!m)
                            return []
                        const chips = []
                        if (m.permisos)
                            for (let i = 0; i < m.permisos.length; ++i)
                                chips.push({ t: m.permisos[i], aviso: true })
                        const c = m.comandos || ({})
                        if (c.atajos)
                            for (let j = 0; j < c.atajos.length; ++j)
                                chips.push({ t: "k4:" + c.atajos[j], aviso: false })
                        if (c.ipc)
                            for (let k = 0; k < c.ipc.length; ++k)
                                chips.push({ t: c.ipc[k], aviso: false })
                        return chips
                    }

                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: etiqueta.implicitWidth + 16
                        implicitHeight: 20
                        radius: 10
                        color: modelData.aviso
                            ? Qt.rgba(Theme.yellow.r, Theme.yellow.g,
                                      Theme.yellow.b, 0.14)
                            : Theme.track

                        IslandLabel {
                            id: etiqueta
                            anchors.centerIn: parent
                            text: parent.modelData.t
                            textFormat: Text.PlainText
                            color: parent.modelData.aviso ? Theme.yellow : Theme.muted
                            font.pixelSize: 9
                        }
                    }
                }
            }

            //  Y sus ajustes, aquí mismo. Las mismas filas que el resto de la
            //  ventana: un interruptor de plugin no tiene por qué verse
            //  distinto de uno de la barra.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: fila.suGrupo !== null && fila.encendido
                spacing: 5

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.06)
                }

                Repeater {
                    model: fila.suGrupo ? fila.suGrupo.opciones : []
                    delegate: FilaOpcion {}
                }
            }

            //  Tiene ajustes pero está apagado: decirlo, en vez de enseñar
            //  controles que no gobiernan nada.
            IslandLabel {
                Layout.fillWidth: true
                visible: fila.suGrupo !== null && !fila.encendido
                text: Idioma.t("Enciéndelo para ver sus ajustes")
                color: Theme.dim
                font.pixelSize: 10
            }
        }
    }

    //  El clic que despliega. Va DEBAJO de los controles —se declara antes—,
    //  así que el interruptor y las filas de dentro se quedan los suyos.
    MouseArea {
        id: raton
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: fila.abierta = !fila.abierta
    }
}
