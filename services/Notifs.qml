pragma Singleton

//  Servidor de notificaciones propio.
//
//  Al llegar una notificación se emite `notified()` en vez de tocar el estado
//  de otros módulos: quien tenga que apartarse (lanzador, panel) se suscribe.

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: notifs

    signal notified()

    property var latest: null
    property int count: 0
    property bool toastOpen: false

    readonly property var tracked: server.trackedNotifications

    function clear() {
        // se copia antes: descartar muta la lista mientras se recorre
        const list = server.trackedNotifications.values.slice()
        for (let i = 0; i < list.length; ++i)
            list[i].dismiss()

        count = 0
        toastOpen = false
        toastTimer.stop()
    }

    function dismissToast() {
        toastTimer.stop()
        toastOpen = false
    }

    // el toast no debe caducar mientras el ratón está encima
    function holdToast() { toastTimer.stop() }
    function resumeToast() { if (toastOpen) toastTimer.restart() }

    function markRead() { count = 0 }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true

        onNotification: function (notification) {
            notification.tracked = true
            notifs.latest = notification
            notifs.count += 1
            notifs.toastOpen = true
            toastTimer.restart()
            notifs.notified()
        }
    }

    Timer {
        id: toastTimer
        interval: 5000
        onTriggered: notifs.dismissToast()
    }
}
