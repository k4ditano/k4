//  Bandeja del sistema.
//
//  La lista y el registro del anfitrión están en el servicio Tray; esto es la
//  vista y la selección. El menú de cada aplicación se dibuja dentro de la
//  island con QsMenuOpener, en vez de abrir una ventana emergente nativa que
//  desentonaría al lado de la píldora.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "tray"
    title: Idioma.t("Bandeja")
    priority: 63
    active: habilitado && open
    //  El teclado entero mientras está abierto: «opcional» es OnDemand y
    //  el compositor solo lo da si PINCHAS la superficie, así que abierto
    //  desde el centro de aplicaciones o por atajo no llegaba ni el ESC.
    //  Ver `tecladoOpcional` en api/K4/Plugin.qml.
    grabKeyboard: open

    property bool open: false
    property var selected: null

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    islandWidth: 640
    islandHeight: 360

    handlesBackgroundTap: true
    onBackgroundTapped: {}   // se traga el clic: cerrar es cosa del botón

    closeOnHoverExit: true
    hoverExitDelay: 900
    onHoverTimedOut: close()

    function toggle() {
        open = !open
        if (open) {
            if (panel) panel.close()
            Notifs.dismissToast()
            if (selected === null || Tray.sorted.indexOf(selected) === -1)
                selected = Tray.count > 0 ? Tray.sorted[0] : null
        }
    }

    function close() { open = false }

    function select(item) { selected = item }

    // Si la aplicación seleccionada desaparece (se cierra), no dejar colgada
    // una referencia muerta.
    Connections {
        target: Tray.items
        function onValuesChanged() {
            if (self.selected !== null && Tray.sorted.indexOf(self.selected) === -1)
                self.selected = Tray.count > 0 ? Tray.sorted[0] : null
        }
    }

    K4.Ipc {
        target: "k4.tray"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
    }

    view: Component {
        TrayView { plugin: self }
    }
}
