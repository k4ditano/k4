//  Aviso emergente de notificación. Caduca solo salvo que tengas el ratón
//  encima (de eso se encarga el host), y un clic en el fondo lo descarta en
//  vez de abrir el centro de control.

import QtQuick
import "../../core"
import "../../services"

K4Plugin {
    name: "toast"
    title: "Notificación"
    priority: 70
    active: Notifs.toastOpen

    islandWidth: 440
    islandHeight: 96

    handlesBackgroundTap: true
    onBackgroundTapped: Notifs.dismissToast()

    view: Component { ToastView {} }
}
