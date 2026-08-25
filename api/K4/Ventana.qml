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
    //
    //  Y ojo con esto en varios monitores: un agarre exclusivo NO es por
    //  pantalla. El foco de teclado en Wayland es uno para toda la sesión, y
    //  Hyprland trata una capa exclusiva como un agarre modal — deja de
    //  repartir eventos al resto, teclado Y puntero. Comprobado: con una
    //  ventana así abierta en el segundo monitor, la island del primero ya no
    //  se abre al pasarle el ratón, y lo que escribas se lo lleva ella aunque
    //  tengas otra ventana enfocada. Para eso está `tecladoAlPasar`.
    property bool conTeclado: false

    //  El teclado SOLO mientras el ratón esté encima de esta ventana.
    //
    //  Es la respuesta a lo de arriba: mientras la usas, manda ella; en cuanto
    //  te vas a otra pantalla lo suelta y el escritorio vuelve a funcionar.
    //  Gana a `conTeclado` si se ponen las dos.
    //
    //  Al soltarlo se queda en OnDemand y no en None a propósito: OnDemand
    //  sigue recibiendo el ratón, que es lo que permite volver a entrar.
    property bool tecladoAlPasar: false

    //  ¿Está el ratón dentro? Lo dice QUIEN PINTA la ventana, no la ventana.
    //
    //  Suena al revés y no lo es. La ventana no sabe qué hay dentro, y el roce
    //  solo lo ve quien está encima del todo: una zona de escucha puesta aquí
    //  la tapa el contenido del que la usa, porque sus hijos se crean después.
    //  Quien monta la vista sí controla su propia pila, así que enlaza esto a
    //  lo que sea que tenga —el fondo, la tarjeta, los dos con un OR—.
    //
    //  Se intentó de las dos formas automáticas y ninguna vale: un `Item` con
    //  `HoverHandler` detrás de todo no se entera de nada porque lo tapan, y
    //  un `HoverHandler` suelto dentro del PanelWindow no se engancha a ningún
    //  item y su `hovered` sale `undefined`. Y asignarle `parent` a mano
    //  —`HoverHandler { parent: ventana.contentItem }`— no da un error de QML:
    //  ESTRELLA Quickshell entero al construir la ventana. Aprendido por las
    //  malas y comprobado después en el banco.
    property bool ratonDentro: false


    // Por encima de todo, la island incluida.
    property bool encima: true

    //  En qué capa se pone. Tres, y la de en medio es la de siempre:
    //
    //   · "fondo"  — DEBAJO de las ventanas. Es la capa del fondo de escritorio:
    //     no la tapa la island porque no la tapa nada, y a cambio no se ve en
    //     cuanto hay una ventana maximizada delante.
    //
    //     Y va en `Bottom`, no en `Background`, aunque «fondo» suene a lo
    //     segundo. `Background` es donde viven los demonios de fondo de
    //     pantalla —swaybg, swww— y dentro de una misma capa manda el orden de
    //     creación: al cambiar de fondo se relanza swaybg, su superficie nueva
    //     queda por ENCIMA y lo que pintes deja de verse sin que nada avise.
    //     Medido: `hyprctl layers` daba `0. k4-fondo` y `1. wallpaper`, y el
    //     lienzo estaba dibujando perfectamente debajo de su propio suelo.
    //     `Bottom` sigue estando debajo de todas las ventanas y por encima de
    //     ellos, que es lo que hace falta para dibujar un fondo de verdad.
    //   · "normal" — encima de las ventanas y debajo de la island.
    //   · "encima" — encima de todo, la island incluida.
    //
    //  `encima` es lo que había y sigue valiendo: es el atajo para las dos de
    //  siempre, y por eso `capa` nace enlazada a él. En cuanto alguien asigne
    //  `capa` el enlace se rompe solo, que es justo lo que se quiere — manda lo
    //  más concreto— y quien no la asigne nunca no nota que existe.
    //
    //  OJO en "fondo" con `zonaActiva`: sin ella el mask se queda en `null` y
    //  esta superficie se lleva TODOS los clics del escritorio, que en la capa
    //  de abajo significa un escritorio que deja de responder. Un fondo no
    //  recoge clics: dale un Item de 0×0, como hacen las escenas del modo dual.
    property string capa: ventana.encima ? "encima" : "normal"

    //  Y de paso: un fondo no le quita sitio a nadie —lo de debajo no puede
    //  empujar a lo de arriba— así que `reserva` ahí no significa nada.

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
    WlrLayershell.layer: ventana.capa === "fondo" ? WlrLayer.Bottom
        : (ventana.capa === "encima" ? WlrLayer.Overlay : WlrLayer.Top)
    WlrLayershell.keyboardFocus: {
        if (ventana.tecladoAlPasar)
            return ventana.ratonDentro ? WlrKeyboardFocus.Exclusive
                                       : WlrKeyboardFocus.OnDemand
        return ventana.conTeclado ? WlrKeyboardFocus.Exclusive
                                  : WlrKeyboardFocus.None
    }
}
