//  Una ventana propia, aparte de la island.
//
//  Es lo que necesita un módulo que se queda pequeño dentro de la barra: un
//  selector a pantalla completa, un editor, una vista a la que quieras dedicar
//  media pantalla.
//
//  Por debajo es una superficie de capa (`wlr-layer-shell`), que es lo que
//  permite ponerse por encima de todo sin ser una ventana normal que el
//  compositor coloque, mueva y meta en el Alt+Tab. El día que exista un host de
//  Windows o Mac esto será otra cosa, y el plugin no se enterará.
//
//  De fábrica viene a pantalla completa y transparente, que es el caso de uso
//  habitual: pintar tú lo que quieras encima de lo que haya.
//
//      K4.Ventana {
//          nombre: "mi-selector"
//          conTeclado: true
//          Item { anchors.fill: parent; ... }
//      }

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: ventana

    // Sale en `hyprctl layers` y sirve para darle reglas en el compositor.
    property string nombre: "k4"

    //  En qué monitor sale, por nombre (los de `hyprctl monitors`). Vacío es
    //  el que el compositor prefiera. Casa con `K4.Isla.rectEn(pantalla)`
    //  para anclar lo que asoma a la island de ESA pantalla.
    property string pantalla: ""

    screen: {
        if (pantalla.length === 0)
            return null
        const lista = Quickshell.screens
        for (let i = 0; i < lista.length; ++i)
            if (lista[i].name === pantalla)
                return lista[i]
        return null
    }

    //  Si se queda el teclado en exclusiva. Solo para lo que de verdad lo
    //  necesita mientras está delante: mientras lo tenga, ninguna otra ventana
    //  recibe una tecla.
    property bool conTeclado: false

    // Por encima de todo, la island incluida.
    property bool encima: true

    //  Qué parte de la superficie captura los clics.
    //
    //  Sin esto, una ventana a pantalla completa se traga TODO el ratón aunque
    //  solo pinte un panel en medio. Señalando el panel, lo de fuera sigue
    //  siendo utilizable mientras la ventana está delante.
    property Item zonaActiva: null

    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true

    color: "transparent"

    // No reserva sitio: las ventanas de debajo no se recolocan por su culpa.
    exclusionMode: ExclusionMode.Ignore

    mask: ventana.zonaActiva ? recorteZona : null

    property Region recorteZona: Region { item: ventana.zonaActiva }

    WlrLayershell.namespace: ventana.nombre
    WlrLayershell.layer: ventana.encima ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: ventana.conTeclado
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
}
