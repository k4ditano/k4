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

    //  A qué bordes se pega. Los cuatro —lo de fábrica— es pantalla completa,
    //  que es lo que quiere quien viene a pintar por encima. Soltando uno, la
    //  ventana se vuelve una franja pegada al borde de enfrente, que es la
    //  forma que necesita algo que quiera reservar sitio.
    property bool pegadaArriba: true
    property bool pegadaAbajo: true
    property bool pegadaIzquierda: true
    property bool pegadaDerecha: true

    anchors.top: pegadaArriba
    anchors.left: pegadaIzquierda
    anchors.right: pegadaDerecha
    anchors.bottom: pegadaAbajo

    color: "transparent"

    //  Sitio que le quita al escritorio por su borde, en píxeles. Cero —lo
    //  normal— es no quitarle ninguno: la ventana flota por encima y las
    //  ventanas de debajo no se recolocan por su culpa.
    //
    //  Lo pide lo que se QUEDA: un dock, una franja permanente. Lo que solo
    //  pasa por delante —una animación, un aviso, una mano que asoma— tiene
    //  que seguir en cero, o el escritorio entero se recolocaría a su paso.
    //
    //  Solo tiene sentido en una franja: pegada a los cuatro bordes no hay un
    //  borde del que quitar sitio, y el compositor lo ignora.
    property int reserva: 0

    //  Y -1 es el caso contrario y hace falta más de lo que parece: no reserva
    //  nada Y ADEMÁS se salta las reservas de los demás, así que se dibuja de
    //  borde a borde por debajo de ellas.
    //
    //  Lo necesita cualquiera que quiera pintar SOBRE la franja de la barra. Sin
    //  esto, una ventana a pantalla completa empieza donde acaba la barra y todo
    //  lo que dibuje sale 34 px más abajo de donde cree —medido, con el modo
    //  dual: los trozos salían en `y: 34-67` en vez de `0-33`, despegados del
    //  canto de la pantalla—.
    exclusionMode: reserva > 0 ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: reserva

    mask: ventana.zonaActiva ? recorteZona : null

    property Region recorteZona: Region { item: ventana.zonaActiva }

    WlrLayershell.namespace: ventana.nombre
    WlrLayershell.layer: ventana.encima ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: ventana.conTeclado
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
}
