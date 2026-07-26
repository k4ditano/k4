pragma Singleton

//  Bandeja del sistema (StatusNotifierItem).
//
//  Instanciar este servicio es lo que registra a k4 como anfitrión de bandeja:
//  hasta que existe, las aplicaciones no publican nada. Las que arrancaron
//  antes que la barra puede que no vuelvan a intentarlo, así que si falta
//  alguna hay que reiniciar esa aplicación, no la barra.

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: tray

    readonly property var items: SystemTray.items

    // Ordenados por nombre para que no bailen de sitio cada vez que una
    // aplicación se registra de nuevo.
    readonly property var sorted: {
        const list = SystemTray.items.values.slice()
        list.sort(function (a, b) {
            return (a.title || a.id || "").localeCompare(b.title || b.id || "")
        })
        return list
    }

    readonly property int count: sorted.length

    // Los que piden atención: en la píldora parpadean.
    readonly property var attention: sorted.filter(function (i) {
        return i.status === Status.NeedsAttention
    })

    readonly property bool hasAttention: attention.length > 0

    function label(item) {
        if (!item)
            return ""
        if (item.title && item.title.length > 0)
            return item.title
        if (item.tooltipTitle && item.tooltipTitle.length > 0)
            return item.tooltipTitle
        return item.id || "Sin nombre"
    }

    function detail(item) {
        if (!item)
            return ""
        // el tooltip repite el título más veces de las que aporta algo
        if (item.tooltipDescription && item.tooltipDescription.length > 0
            && item.tooltipDescription !== label(item))
            return item.tooltipDescription
        if (item.tooltipTitle && item.tooltipTitle.length > 0
            && item.tooltipTitle !== label(item))
            return item.tooltipTitle
        return item.id || ""
    }

    function statusText(item) {
        if (!item)
            return ""
        if (item.status === Status.NeedsAttention)
            return "Requiere atención"
        if (item.status === Status.Passive)
            return "En segundo plano"
        return "Activo"
    }

    // Clic izquierdo. Hay aplicaciones que solo traen menú (onlyMenu): para
    // esas, activar no hace nada y hay que enseñar el menú directamente.
    function primary(item) {
        if (!item || item.onlyMenu)
            return false
        item.activate()
        return true
    }

    function secondary(item) {
        if (item)
            item.secondaryActivate()
    }
}
