//  Bordes, huecos y redondeo, de los ajustes de Hyprland.
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
    spacing: 6

    IslandSlider {
        Layout.fillWidth: true
        label: Idioma.t("Separación interior entre ventanas")
        suffix: " px"
        from: 0; to: 30; step: 1
        value: raiz.motor.gapsIn
        onMoved: function (v) { raiz.motor.gapsIn = v; raiz.tocado() }
    }

    IslandSlider {
        Layout.fillWidth: true
        label: Idioma.t("Separación con el borde de la pantalla")
        suffix: " px"
        from: 0; to: 60; step: 1
        value: raiz.motor.gapsOut
        onMoved: function (v) { raiz.motor.gapsOut = v; raiz.tocado() }
    }

    IslandSlider {
        Layout.fillWidth: true
        label: Idioma.t("Grosor del borde")
        suffix: " px"
        from: 0; to: 10; step: 1
        value: raiz.motor.borderSize
        onMoved: function (v) { raiz.motor.borderSize = v; raiz.tocado() }
    }

    IslandSlider {
        Layout.fillWidth: true
        label: Idioma.t("Redondeo de esquinas")
        suffix: " px"
        from: 0; to: 30; step: 1
        value: raiz.motor.rounding
        onMoved: function (v) { raiz.motor.rounding = v; raiz.tocado() }
    }

    Item { Layout.fillHeight: true }
}
