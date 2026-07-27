//  Ajustes de la barra, dentro de la island.
//
//  Antes la tarjeta "Ajustes" del centro de control lanzaba directamente
//  nm-connection-editor: una ventana del sistema, con su propio marco y su
//  propia tipografía, que no tenía nada que ver con la barra. Ahora los
//  ajustes viven aquí y esa herramienta queda como un acceso más.

import QtQuick
import Quickshell.Io
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

    islandWidth: 560
    // Sube al entrar la zona peligrosa: con 320 el bloque de reinicio quedaba
    // fuera, que en un botón destructivo es peor que no tenerlo.
    islandHeight: 410

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

    IpcHandler {
        target: "k4.settings"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
        function alternar(id: string): void { Settings.alternar(id) }
    }

    view: Component {
        SettingsView { plugin: self }
    }
}
