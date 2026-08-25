//  Desenfoque, opacidad y animaciones, de los ajustes de Hyprland.
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

RowLayout {
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

    //  `anchors.fill` era de cuando esto vivía dentro de un panel propio. Aquí
    //  lo coloca la columna de la sección, así que se pide ancho y ya.
    Layout.fillWidth: true
    spacing: 20

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            IslandLabel { text: Idioma.t("Desenfoque"); font.pixelSize: 12; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            IslandSwitch {
                checked: raiz.motor.blur
                onToggled: { raiz.motor.blur = !raiz.motor.blur; raiz.tocado() }
            }
        }

        IslandSlider {
            Layout.fillWidth: true
            enabled: raiz.motor.blur
            opacity: raiz.motor.blur ? 1 : 0.35
            label: Idioma.t("Radio")
            from: 1; to: 20; step: 1
            value: raiz.motor.blurSize
            onMoved: function (v) { raiz.motor.blurSize = v; raiz.tocado() }
        }

        IslandSlider {
            Layout.fillWidth: true
            enabled: raiz.motor.blur
            opacity: raiz.motor.blur ? 1 : 0.35
            label: Idioma.t("Pasadas")
            from: 1; to: 6; step: 1
            value: raiz.motor.blurPasses
            onMoved: function (v) { raiz.motor.blurPasses = v; raiz.tocado() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 10

            IslandLabel { text: Idioma.t("Sombras"); font.pixelSize: 12; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            IslandSwitch {
                checked: raiz.motor.shadow
                onToggled: { raiz.motor.shadow = !raiz.motor.shadow; raiz.tocado() }
            }
        }

        Item { Layout.fillHeight: true }
    }

    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Theme.surfaceHi }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 6

        IslandSlider {
            Layout.fillWidth: true
            label: Idioma.t("Opacidad de la ventana activa")
            from: 0.4; to: 1; step: 0.05
            value: raiz.motor.activeOpacity
            onMoved: function (v) { raiz.motor.activeOpacity = v; raiz.tocado() }
        }

        IslandSlider {
            Layout.fillWidth: true
            label: Idioma.t("Opacidad de las inactivas")
            from: 0.4; to: 1; step: 0.05
            value: raiz.motor.inactiveOpacity
            onMoved: function (v) { raiz.motor.inactiveOpacity = v; raiz.tocado() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 10

            IslandLabel { text: Idioma.t("Animaciones"); font.pixelSize: 12; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            IslandSwitch {
                checked: raiz.motor.animEnabled
                onToggled: { raiz.motor.animEnabled = !raiz.motor.animEnabled; raiz.tocado() }
            }
        }

        IslandSlider {
            Layout.fillWidth: true
            enabled: raiz.motor.animEnabled
            opacity: raiz.motor.animEnabled ? 1 : 0.35
            label: Idioma.t("Velocidad (más alto = más rápido)")
            from: 1; to: 10; step: 1
            value: raiz.motor.animSpeed
            onMoved: function (v) { raiz.motor.animSpeed = v; raiz.tocado() }
        }

        Item { Layout.fillHeight: true }
    }
}
