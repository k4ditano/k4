//  Lo que se le hace a un trozo: velocidad, color y sus cuatro botones.
//  Vivía dentro de CuerpoEditor; ahora es una pieza con nombre.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: fichaClip

    required property var view

    visible: Editor.clipSel !== null
    Layout.fillWidth: true
    Layout.topMargin: 6
    spacing: 6

    IslandLabel {
        text: Idioma.t("Velocidad")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    //  El trozo del fichero no cambia: lo que cambia es cuánto
    //  ocupa en la línea. Por eso al tocar esto los zooms y los
    //  rótulos que hubiera después se recolocan solos.
    RowLayout {
        Layout.fillWidth: true
        spacing: 3

        Repeater {
            model: [0.25, 0.5, 1, 1.5, 2, 4]

            delegate: Rectangle {
                id: chipVel
                required property var modelData

                readonly property bool puesto: Editor.clipSel
                    && Math.abs(Editor.velocidadDe(Editor.clipSel)
                                - chipVel.modelData) < 0.001

                Layout.fillWidth: true
                Layout.preferredHeight: 24
                radius: 12
                color: chipVel.puesto ? Theme.blue
                     : velRaton.containsMouse ? Theme.surfaceHi
                                              : Theme.surface

                IslandLabel {
                    anchors.centerIn: parent
                    text: "×" + (chipVel.modelData === 1
                        ? "1" : String(chipVel.modelData))
                    color: chipVel.puesto ? "#ffffff" : Theme.muted
                    font.pixelSize: 10
                    font.weight: chipVel.puesto ? Font.DemiBold
                                                : Font.Normal
                }

                MouseArea {
                    id: velRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Editor.ponerVelocidad(
                        Editor.idSel, chipVel.modelData)
                }
            }
        }
    }

    IslandLabel {
        text: Idioma.t("Color")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    //  Del TROZO, no de la línea: sirve para juntar dos
    //  grabaciones que no casan sin tocar la otra.
    //
    //  La previa no lo enseña —`VideoOutput` no tiene un `eq`
    //  que aplicarle—, así que aquí abajo se dice y para verlo
    //  de verdad está «previa exacta».
    Repeater {
        model: [
            { clave: "brillo",     nombre: Idioma.t("Brillo"),
              min: -0.5, max: 0.5, def: 0 },
            { clave: "contraste",  nombre: Idioma.t("Contraste"),
              min: 0.0,  max: 2.0, def: 1 },
            { clave: "saturacion", nombre: Idioma.t("Saturación"),
              min: 0.0,  max: 2.0, def: 1 }
        ]

        delegate: RowLayout {
            id: filaColor
            required property var modelData

            readonly property real valor: Editor.colorDe(
                Editor.clipSel, filaColor.modelData.clave)
            readonly property real recorrido:
                filaColor.modelData.max - filaColor.modelData.min

            Layout.fillWidth: true
            spacing: 6

            IslandLabel {
                Layout.preferredWidth: 58
                text: filaColor.modelData.nombre
                color: Theme.muted
                font.pixelSize: 9
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: Theme.track

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1,
                        (filaColor.valor - filaColor.modelData.min)
                        / filaColor.recorrido))
                    height: parent.height
                    radius: parent.radius
                    color: Theme.green
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    cursorShape: Qt.PointingHandCursor

                    function poner(x) {
                        if (!Editor.clipSel)
                            return
                        const u = Math.max(0, Math.min(1,
                            x / Math.max(1, width)))
                        const v = filaColor.modelData.min
                            + u * filaColor.recorrido
                        const campos = {}
                        campos[filaColor.modelData.clave] =
                            Math.round(v * 20) / 20
                        Editor.ponerColor(Editor.idSel, campos)
                    }
                    onPressed: function (ev) { poner(ev.x) }
                    onPositionChanged: function (ev) {
                        if (pressed) poner(ev.x)
                    }
                    //  Doble clic devuelve el valor de fábrica:
                    //  con un deslizador tan corto, volver al
                    //  centro exacto a mano es una pelea.
                    onDoubleClicked: {
                        if (!Editor.clipSel)
                            return
                        const campos = {}
                        campos[filaColor.modelData.clave] =
                            filaColor.modelData.def
                        Editor.ponerColor(Editor.idSel, campos)
                    }
                }
            }

            IslandLabel {
                Layout.preferredWidth: 26
                horizontalAlignment: Text.AlignRight
                text: filaColor.valor.toFixed(2)
                color: Theme.dim
                font.pixelSize: 9
            }
        }
    }

    IslandLabel {
        Layout.fillWidth: true
        text: Idioma.t("El color solo se ve al renderizar")
        color: Theme.dim
        font.pixelSize: 9
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: [
            { texto: Idioma.t("Cortar aquí"), icono: 0xF0190,             // md-content_cut
              accion: "cortar" },
            //  Separar el audio saca el sonido del trozo a
            //  su propia capa y deja el trozo mudo. Desde
            //  ahí se mueve y se recorta como cualquier
            //  música añadida.
            { texto: Editor.clipSel && Editor.clipSel.mudo
                        ? Idioma.t("Devolver el audio")
                        : Idioma.t("Separar el audio"),
              icono: 0xF057E,            // md-volume_high
              accion: "audio" },
            //  Congelar mete un trozo NUEVO, así que va con los
            //  demás botones del trozo y no con los de añadir:
            //  lo que congela es el fotograma que estás viendo.
            { texto: Idioma.t("Congelar 2 s"), icono: 0xF03E4,            // md-pause
              accion: "congelar" },
            { texto: Idioma.t("Quitar el trozo"), icono: 0xF01B4,
              accion: "quitar" }
        ]

        delegate: Rectangle {
            id: botonClip
            required property var modelData

            Layout.fillWidth: true
            Layout.preferredHeight: 26
            radius: 13
            color: clipRaton.containsMouse ? Theme.surfaceHi
                                           : Theme.surface
            // Quitar el último trozo dejaría la línea vacía.
            opacity: botonClip.modelData.accion === "quitar"
                     && Editor.tramos.length <= 1 ? 0.4 : 1

            RowLayout {
                anchors.centerIn: parent
                spacing: 5

                IconGlyph {
                    text: String.fromCodePoint(botonClip.modelData.icono)
                    color: botonClip.modelData.accion === "quitar"
                        ? Theme.red : Theme.muted
                    font.pixelSize: 12
                }

                IslandLabel {
                    text: botonClip.modelData.texto
                    font.pixelSize: 10
                }
            }

            MouseArea {
                id: clipRaton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const a = botonClip.modelData.accion
                    if (a === "cortar")
                        Editor.cortar(fichaClip.view.segundos)
                    else if (a === "audio")
                        Editor.clipSel && Editor.clipSel.mudo
                            ? Editor.devolverAudio(Editor.idSel)
                            : Editor.separarAudio(Editor.idSel)
                    else if (a === "congelar")
                        Editor.congelar(fichaClip.view.segundos, 2)
                    else
                        Editor.quitarClip(Editor.idSel)
                }
            }
        }
    }
}
