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

    //  Grande a propósito: se listan plugins con descripción, permisos y
    //  procedencia, y en un panel estrecho eso se convierte en una columna de
    //  texto cortado. Es la misma razón por la que no cabía en Ajustes.
    islandWidth: 620
    islandHeight: 640

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
