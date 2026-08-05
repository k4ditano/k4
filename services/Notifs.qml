pragma Singleton

//  Servidor de notificaciones propio.
//
//  Al llegar una notificación se emite `notified()` en vez de tocar el estado
//  de otros módulos: quien tenga que apartarse (lanzador, panel) se suscribe.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications

Singleton {
    id: notifs

    signal notified()

    property var latest: null
    property int count: 0
    property bool toastOpen: false

    readonly property var tracked: server.trackedNotifications

    // Las últimas primero, para la tira que sale al pasar el ratón por la
    // island: ahí lo que interesa es lo que acaba de llegar.
    readonly property var recent: {
        const list = server.trackedNotifications.values.slice()
        list.reverse()
        return list
    }

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

    // Alto de la tira de notificaciones (widgets/NotifStrip.qml). La medida
    // vive aquí porque los plugins la necesitan para dimensionar la island
    // antes de que la vista exista, y así hay una sola fórmula.
    readonly property int stripRow: 38          // fila de 34 + separación de 4

    //  Lo que MIDE la tira: la cabecera, las filas y sus separaciones.
    //
    //  Y nada más. Antes devolvía veinte píxeles de propina para el hueco y el
    //  aire de abajo, y no llegaba: cada vista tiene sus propios márgenes y su
    //  propio espaciado, así que una propina fija se quedaba corta en una y larga
    //  en otra. El resultado se veía: las notificaciones aplastadas contra el
    //  borde de abajo de la island. Ahora quien la incruste suma lo suyo, que es
    //  lo único que sabe.
    function stripHeight(max) {
        const n = Math.min(recent.length, max)
        // 14 de cabecera + 4 de separación + n filas de 34 separadas por 4
        return n === 0 ? 0 : 18 + n * 34 + (n - 1) * 4
    }

    // ── pulsar una notificación ───────────────────────────────────
    // Por convención del protocolo, la acción de identificador "default" es la
    // que corresponde al clic en el cuerpo; el resto son botones.
    function defaultAction(n) {
        if (!n || !n.actions)
            return null

        for (let i = 0; i < n.actions.length; ++i) {
            if (n.actions[i].identifier === "default")
                return n.actions[i]
        }
        return null
    }

    function buttons(n) {
        if (!n || !n.actions)
            return []

        return n.actions.filter(function (a) { return a.identifier !== "default" })
    }

    // El icono que manda la aplicación: primero la imagen de la notificación,
    // luego el icono de la aplicación. Si no hay ninguno, quien llame pone la
    // campana genérica.
    function iconFor(n) {
        if (!n)
            return ""
        if (n.image && n.image.length > 0)
            return n.image
        if (n.appIcon && n.appIcon.length > 0)
            return Quickshell.iconPath(n.appIcon, true)
        return ""
    }

    // Clic en el cuerpo: la acción por defecto si la hay y, si no, enfocar la
    // ventana de la aplicación, que es lo que espera cualquiera al pulsar.
    //
    // Si no se puede hacer ninguna de las dos, la notificación se queda donde
    // está. Descartarla sin llevar a ninguna parte es lo peor de los dos
    // mundos: parece que la aplicación te ha ignorado.
    function activate(n) {
        if (!n)
            return

        const action = defaultAction(n)
        if (action) {
            action.invoke()
            // el protocolo dice que la notificación se cierra al invocar una
            // acción, salvo que se declare residente
            if (!n.resident)
                n.dismiss()
            return
        }

        focusApp(n)
    }

    function invokeAction(n, action) {
        if (!action)
            return

        action.invoke()
        if (n && !n.resident)
            n.dismiss()
    }

    // ── enfocar la ventana de la aplicación ───────────────────────
    // Hyprland.toplevels llega vacío aquí, así que se pregunta por hyprctl y
    // se busca a mano: clase exacta, luego clase que contenga, luego título.
    property string pendingMatch: ""
    property var pendingNotification: null

    // Para lo que no se puede adivinar. Hay notificaciones que no llevan
    // identidad utilizable —las que manda una herramienta de terminal: ni
    // desktopEntry, ni una clase de ventana con su nombre— y la única forma de
    // resolverlas es decir a mano a qué ventana pertenecen.
    //
    // La clave es el appName o el desktopEntry en minúsculas; el valor, lo que
    // haya que buscar en la clase o el título de la ventana. El nombre exacto
    // que manda cada aplicación se lee en la tarjeta del panel, encima del
    // título.
    //  La terminal de la casa, sea cual sea: quien la cambie no tiene por qué
    //  venir a corregir esta lista a mano. Estaba clavada en «kitty», y con
    //  k4term instalada eso mandaba las notificaciones de los agentes a una
    //  ventana que no existe —así que ni llevaban a ninguna parte ni se
    //  descartaban—.
    readonly property string terminal: (Consola.binario || "kitty").toLowerCase()

    readonly property var aliases: ({
        // herramientas de terminal: llevan al emulador donde corren
        "claude code": terminal,
        "claude": terminal,
        "codex": terminal
    })

    function focusApp(n) {
        const raw = (n.desktopEntry && n.desktopEntry.length > 0 ? n.desktopEntry : n.appName) || ""
        if (raw.length === 0)
            return

        const key = raw.toLowerCase()
        pendingMatch = aliases[key] !== undefined ? String(aliases[key]).toLowerCase() : key
        pendingNotification = n
        clientQuery.running = true
    }

    function matchAndFocus(json) {
        const key = pendingMatch
        const n = pendingNotification
        pendingMatch = ""
        pendingNotification = null

        if (key.length === 0)
            return

        let list
        try {
            list = JSON.parse(json)
        } catch (e) {
            return
        }

        // "org.gnome.Nautilus" → también vale probar con "nautilus"
        const tail = key.indexOf(".") !== -1 ? key.substring(key.lastIndexOf(".") + 1) : key

        let exact = null
        let partial = null
        for (let i = 0; i < list.length; ++i) {
            const c = list[i]
            const cls = String(c.class || "").toLowerCase()
            const initial = String(c.initialClass || "").toLowerCase()
            const title = String(c.title || "").toLowerCase()
            const initialTitle = String(c.initialTitle || "").toLowerCase()

            if (cls === key || initial === key || cls === tail || initial === tail) {
                exact = c
                break
            }
            if (partial === null
                && (cls.indexOf(tail) !== -1 || initial.indexOf(tail) !== -1
                    || initialTitle.indexOf(tail) !== -1 || title.indexOf(tail) !== -1))
                partial = c
        }

        const found = exact || partial
        if (found) {
            // Sintaxis Lua, como el resto de la configuración de Hyprland: con
            // el parser nuevo, `dispatch focuswindow address:…` no compila —se
            // envuelve en hl.dispatch(...) y revienta— y hay que pasar un
            // dispatcher de verdad. Las claves que admite `focus` son
            // direction, monitor, window, urgent_or_last y last.
            Hyprland.dispatch('hl.dsp.focus({ window = "address:' + found.address + '" })')
            if (n && !n.resident)
                n.dismiss()
            return
        }

        // No está abierta: si la notificación dice de qué aplicación viene, se
        // abre. Y si tampoco eso, se deja la notificación en su sitio.
        if (n && launchEntry(n))
            n.dismiss()
    }

    function launchEntry(n) {
        const id = (n.desktopEntry || "").toLowerCase()
        if (id.length === 0)
            return false

        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; ++i) {
            const app = apps[i]
            const appId = String(app.id || "").toLowerCase()
            if (appId === id || appId === id + ".desktop"
                || appId.replace(/\.desktop$/, "") === id) {
                app.execute()
                return true
            }
        }
        return false
    }

    // ── se descartan solas al ir a la aplicación ──────────────────
    //
    //  Un aviso está para llevarte a un sitio. Cuando YA estás en ese sitio ha
    //  hecho su trabajo, y seguir pidiéndote un clic para quitarlo es cobrar
    //  dos veces por lo mismo: la campana de un agente que ha acabado su turno
    //  se quedaba puesta —y de paso en la tira de debajo del reloj, que sale al
    //  pasar el ratón— hasta que uno se acordaba de ir a descartarla.
    //
    //  Se mira la ventana que toma el foco y se descarta lo que sea suyo con el
    //  mismo criterio con el que se la busca al pulsar la notificación, alias
    //  incluidos: así lo que manda una herramienta de consola se va al volver a
    //  la terminal donde corre.
    //
    //  El título de la ventana NO entra en la comparación, y eso es a
    //  propósito: al pulsar una notificación es un último recurso razonable
    //  —lo peor que pasa es que te lleve a la ventana de al lado—, pero
    //  descartando solo se lleva por delante avisos que no había leído nadie.
    //  Una pestaña del navegador titulada «Slack» borraría los de Slack.
    function perteneceA(n, cls, initial) {
        const raw = (n.desktopEntry && n.desktopEntry.length > 0
                     ? n.desktopEntry : n.appName) || ""
        if (raw.length === 0)
            return false

        const bajo = raw.toLowerCase()
        const key = aliases[bajo] !== undefined ? String(aliases[bajo]).toLowerCase() : bajo
        const tail = key.indexOf(".") !== -1 ? key.substring(key.lastIndexOf(".") + 1) : key

        if (cls === key || initial === key || cls === tail || initial === tail)
            return true

        //  Por debajo de tres letras, «contiene» empareja cualquier cosa con
        //  cualquier cosa: ahí solo vale la igualdad de arriba.
        return tail.length >= 3
            && (cls.indexOf(tail) !== -1 || initial.indexOf(tail) !== -1)
    }

    function descartarDeVentana(t) {
        const d = t && t.lastIpcObject ? t.lastIpcObject : null
        if (!d)
            return

        const cls = String(d.class || "").toLowerCase()
        const initial = String(d.initialClass || "").toLowerCase()
        if (cls.length === 0 && initial.length === 0)
            return

        // se copia antes: descartar muta la lista mientras se recorre
        const list = server.trackedNotifications.values.slice()
        let idas = 0
        for (let i = 0; i < list.length; ++i) {
            if (!perteneceA(list[i], cls, initial))
                continue
            if (latest === list[i])
                dismissToast()
            list[i].dismiss()
            ++idas
        }

        //  La cuenta del panel es de las SIN LEER, y estas ya se han atendido:
        //  dejarla quieta pondría un número rojo sobre una bandeja vacía.
        if (idas > 0)
            count = Math.max(0, count - idas)
    }

    //  Y para lo que no tiene ventana que enfocar. La terminal de la isla vive
    //  DENTRO de la barra: abrir su pestaña es haber atendido la campana, pero
    //  ahí no cambia el foco de Hyprland y su notificación se quedaba puesta.
    //  Quien sepa que algo ya está atendido lo dice, y aquí se retira.
    function descartarDeApp(app, cuerpo) {
        const quien = String(app || "").toLowerCase()
        if (quien.length === 0)
            return

        const texto = cuerpo === undefined ? null : String(cuerpo)
        const list = server.trackedNotifications.values.slice()
        let idas = 0
        for (let i = 0; i < list.length; ++i) {
            const n = list[i]
            if (String(n.appName || "").toLowerCase() !== quien)
                continue
            //  Sin cuerpo se va todo lo de esa aplicación; con él, solo la que
            //  lo lleva: dos agentes esperando son dos avisos distintos y
            //  atender a uno no atiende al otro.
            if (texto !== null && String(n.body || "") !== texto)
                continue
            if (latest === n)
                dismissToast()
            n.dismiss()
            ++idas
        }
        if (idas > 0)
            count = Math.max(0, count - idas)
    }

    Connections {
        target: Hyprland

        function onActiveToplevelChanged() {
            if (Settings.notificacionesAlEnfocar)
                notifs.descartarDeVentana(Hyprland.activeToplevel)
        }
    }

    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("notifs:", l)
            }
        }
        id: clientQuery
        command: ["hyprctl", "-j", "clients"]

        stdout: StdioCollector {
            onStreamFinished: notifs.matchAndFocus(this.text)
        }
    }

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
