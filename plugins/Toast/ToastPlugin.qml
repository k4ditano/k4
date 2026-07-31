//  Aviso emergente de notificación. Caduca solo salvo que tengas el ratón
//  encima (de eso se encarga el host), y un clic en el fondo lo descarta en
//  vez de abrir el centro de control.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    name: "toast"
    title: Idioma.t("Notificación")
    priority: 70
    active: habilitado && Notifs.toastOpen

    islandWidth: 440

    // El toast crece un poco cuando la aplicación manda botones de acción.
    islandHeight: Notifs.buttons(Notifs.latest).length > 0 ? 112 : 96

    // Pulsar el cuerpo lleva a la aplicación: su acción por defecto si la
    // manda y, si no, enfocar su ventana. Antes solo descartaba el aviso.
    handlesBackgroundTap: true
    onBackgroundTapped: {
        Notifs.activate(Notifs.latest)
        Notifs.dismissToast()
    }

    view: Component { ToastView {} }
}
