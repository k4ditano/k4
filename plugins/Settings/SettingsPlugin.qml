//  Ajustes de la barra, dentro de la island.
//
//  Antes la tarjeta "Ajustes" del centro de control lanzaba directamente
//  nm-connection-editor: una ventana del sistema, con su propio marco y su
//  propia tipografía, que no tenía nada que ver con la barra. Ahora los
//  ajustes viven aquí y esa herramienta queda como un acceso más.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "settings"
    title: Idioma.t("Ajustes")
    priority: 66
    active: open
    tecladoOpcional: open

    property bool open: false
    property var panel: null

    islandWidth: 600
    //  El contenido ya no cabe en una pantalla y se recorre, así que esto no es
    //  «lo que mide» sino «cuánto se enseña de una vez». 640 deja ver cinco filas
    //  y media, que es bastante para no sentir que estás mirando por una rendija,
    //  y no se acerca al techo de 880 de la superficie.
    //
    //  Antes eran 516 y los ajustes eran tres grupos. Al añadir captura,
    //  grabación y editor el contenido pasó de novecientos píxeles y el reparto lo
    //  aplastó: el grupo del editor no llegaba a verse. Lo que faltaba no era
    //  alto, era poder desplazar.
    islandHeight: 640

    handlesBackgroundTap: true
    onBackgroundTapped: {}

    closeOnHoverExit: true
    hoverExitDelay: 1200
    onHoverTimedOut: close()

    function toggle() {
        open = !open
        if (open) {
            if (panel) panel.close()
            Notifs.dismissToast()
        }
    }

    function close() { open = false }

    K4.Ipc {
        target: "k4.settings"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
        function alternar(id: string): void { Settings.alternar(id) }
    }

    view: Component {
        SettingsView { plugin: self }
    }
}
