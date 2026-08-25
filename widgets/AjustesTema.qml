//  El color y los presets, de los ajustes de Hyprland.
//
//  Vivía dentro de `HyprThemeView`, la pantalla propia del plugin del tema.
//  Sale aquí porque esa pantalla ha desaparecido: todo lo que se configura
//  vive ahora en la ventana de Ajustes, y tener dos sitios donde tocar lo
//  mismo era exactamente lo que se venía a arreglar.
//
//  El `motor` es quien sabe aplicarlo —el plugin del tema, que escribe el Lua
//  de Hyprland—. Llega como objeto y no como import: un plugin no depende de
//  otro, y sin motor esto no se enseña.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../core"
import "../services"

ColumnLayout {
    id: raiz

    //  Quien sabe escribir esto en la config de Hyprland.
    property var motor: null

    //  Cualquier retoque a mano deja de ser «el preset tal cual».
    function tocado() {
        if (!raiz.motor)
            return
        raiz.motor.dirty = true
        raiz.motor.apply()
    }

    //  Sin `anchors.fill`: eso era de cuando esto vivía dentro de una pantalla
    //  propia. Aquí lo coloca la columna de la sección, y mezclar anchors con
    //  Layout deja el widget del tamaño equivocado.
    Layout.fillWidth: true
    spacing: 14

    //  ── el color, ¿lo pone el fondo o lo pones tú? ──
    //
    //  Va lo primero porque es la decisión que manda sobre todo lo
    //  demás de esta pestaña: con el fondo mandando, elegir un
    //  preset es apagarlo.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 46
        radius: 10
        color: Theme.islandBg

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                IslandLabel {
                    text: Idioma.t("El color lo pone el fondo")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                IslandLabel {
                    text: raiz.motor.paletaAuto
                        ? Idioma.t("Cambia de fondo y se recolocan la barra, los bordes y la terminal")
                        : Idioma.t("Apagado al elegir un preset o un color a mano")
                    color: Theme.dim
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            //  Lo que ha salido del fondo, para que se vea que no es
            //  magia: los tres colores que se están repartiendo.
            Repeater {
                model: raiz.motor.paletaAuto
                    ? [raiz.motor.accentFrom, raiz.motor.accentTo,
                       raiz.motor.inactive] : []

                delegate: Rectangle {
                    required property var modelData
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    radius: 9
                    color: modelData
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                }
            }

            IslandSwitch {
                checked: raiz.motor.paletaAuto
                Layout.alignment: Qt.AlignVCenter
                onToggled: {
                    raiz.motor.paletaAuto = !raiz.motor.paletaAuto
                    if (raiz.motor.paletaAuto)
                        raiz.motor.sacarPaleta()
                    else
                        Theme.destintar("hyprtheme")
                    raiz.motor.saveState()
                }
            }
        }
    }

    IslandLabel {
        text: Idioma.t("Presets")
        color: Theme.muted
        font.pixelSize: 11
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: raiz.motor.presets

            delegate: Rectangle {
                id: presetCard
                required property var modelData
                readonly property bool current: raiz.motor.preset === modelData.id
                    && !raiz.motor.dirty

                Layout.fillWidth: true
                Layout.preferredHeight: 56
                radius: 12
                color: presetMouse.containsMouse ? Theme.surfaceHi : Theme.islandBg
                border.width: presetCard.current ? 2 : 0
                border.color: Theme.blue

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    // muestra del degradado que tendrá el borde activo
                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        Layout.alignment: Qt.AlignVCenter
                        radius: 8

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: presetCard.modelData.from }
                            GradientStop { position: 1; color: presetCard.modelData.to }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        IslandLabel {
                            text: presetCard.modelData.name
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        IslandLabel {
                            text: presetCard.current ? "aplicado" : presetCard.modelData.from
                            color: presetCard.current ? Theme.green : Theme.dim
                            font.pixelSize: 10
                        }
                    }

                    IconGlyph {
                        visible: presetCard.current
                        text: Theme.ico.check
                        color: Theme.green
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                MouseArea {
                    id: presetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: raiz.motor.applyPreset(presetCard.modelData.id)
                }
            }
        }
    }

    Item { Layout.fillHeight: true }

    IslandSlider {
        Layout.fillWidth: true
        label: Idioma.t("Ángulo del degradado del borde")
        suffix: "°"
        from: 0
        to: 360
        step: 5
        value: raiz.motor.angle
        onMoved: function (v) { raiz.motor.angle = v; raiz.tocado() }
    }
}
