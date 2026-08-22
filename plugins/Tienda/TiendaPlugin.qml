//  La tienda de plugins, como aplicación.
//
//  Empezó siendo una pantalla dentro de Ajustes, detrás de un botón en el pie.
//  Estaba mal por donde se mire: instalar un plugin no es «ajustar» nada, y
//  sobre todo no se encontraba — quien no supiera que ese botón existía no
//  llegaba nunca. Aquí es una aplicación más del centro, con su icono, igual
//  que Ajustes o Portapapeles, y se abre desde el lanzador o por IPC.
//
//  Ajustes conserva el interruptor de cada plugin, que sí es un ajuste. Lo que
//  se ha mudado es traer, actualizar y quitar.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "tienda"
    title: Idioma.t("Plugins")
    priority: 55
    active: habilitado && abierto

    property bool abierto: false

    //  El teclado, mientras esté abierta.
    //
    //  Sin esto no llega ni una tecla: la capa solo recibe teclas si la
    //  PINCHAS, y a esto se llega desde el centro de aplicaciones o por IPC,
    //  donde nadie la pincha. El ESC no cerraba, y encima parecía funcionar si
    //  antes habías pasado el ratón por encima — que es la peor forma de estar
    //  roto, porque probándolo a mano sale bien.
    //
    //  Es lo mismo que declaran Ajustes, Portapapeles y Sistema, y por la
    //  misma razón: esto se abre, se mira y se cierra. Está escrito en
    //  `tecladoOpcional`, en api/K4/Plugin.qml, y aun así me lo salté.
    grabKeyboard: abierto

    //  Grande a propósito: se listan plugins con descripción, permisos y
    //  procedencia, y en un panel estrecho eso se convierte en una columna de
    //  texto cortado. Es la misma razón por la que no cabía en Ajustes.
    islandWidth: 620
    //  700 y no 640: con 640 la quinta tarjeta quedaba cortada por abajo. Con
    //  más plugins la lista hará scroll de todos modos —para eso está— pero
    //  que el caso normal de hoy entre entero se nota.
    islandHeight: 700

    function toggle() { abierto = !abierto }
    //  Sin `close()` el ESC no cierra: el host cierra llamándola.
    function close() { abierto = false }

    K4.Ipc {
        target: "k4.tienda"
        function toggle(): void { self.toggle() }
        function abrir(): void { self.abrir() }
        function close(): void { self.close() }
    }

    view: Component {
        TiendaVista { plugin: self }
    }
}
