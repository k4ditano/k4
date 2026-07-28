pragma Singleton

//  Reproductor activo (MPRIS) y resolución de carátula.
//
//  Los navegadores no publican mpris:artUrl, pero sí xesam:url, que basta para
//  construir la miniatura. Cada paso solo se intenta si el anterior no dio nada.

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: media

    readonly property var activePlayer: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; ++i) {
            if (players[i].isPlaying)
                return players[i]
        }
        return players.length > 0 ? players[0] : null
    }

    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: hasPlayer && activePlayer.isPlaying

    // Algunos reproductores (Firefox/Zen) nunca publican mpris:length: para
    // ellos se oculta la línea de tiempo. Con retardo, para que un cambio de
    // pista (length brevemente a 0) no haga saltar la island.
    readonly property bool hasTimelineRaw: hasPlayer && activePlayer.lengthSupported && activePlayer.length > 0
    property bool hasTimeline: false

    onHasTimelineRawChanged: {
        if (hasTimelineRaw)
            hasTimeline = true
        else
            timelineDropTimer.restart()
    }

    Component.onCompleted: hasTimeline = hasTimelineRaw

    // ── sondeo de posición ────────────────────────────────────────
    // MPRIS no notifica la posición, hay que preguntarla. Solo mientras alguna
    // vista la esté mirando: las vistas se apuntan al montarse y se borran al
    // destruirse, así que con la island plegada no se gasta nada.
    property int positionWatchers: 0

    function watchPosition() { positionWatchers += 1 }
    function unwatchPosition() { positionWatchers = Math.max(0, positionWatchers - 1) }

    function trackUrl(player) {
        if (!player || !player.metadata)
            return ""

        const url = player.metadata["xesam:url"]
        return url ? String(url) : ""
    }

    function coverFor(player) {
        if (!player)
            return ""

        if (player.trackArtUrl && player.trackArtUrl.length > 0)
            return player.trackArtUrl

        const url = trackUrl(player)
        if (url.length === 0)
            return ""

        const yt = url.match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/|live\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/)
        if (yt)
            return "https://i.ytimg.com/vi/" + yt[1] + "/mqdefault.jpg"

        const tw = url.match(/^https?:\/\/(?:www\.)?twitch\.tv\/([A-Za-z0-9_]+)\/?(?:\?.*)?$/)
        if (tw && ["videos", "directory", "settings", "downloads", "subscriptions", "u", "p"].indexOf(tw[1].toLowerCase()) === -1)
            return "https://static-cdn.jtvnw.net/previews-ttv/live_user_" + tw[1].toLowerCase() + "-440x248.jpg"

        return ""
    }

    // último recurso antes del glifo de nota: favicon del sitio, luego icono de la app
    function faviconFor(player) {
        const host = trackUrl(player).match(/^https?:\/\/([^\/]+)/)
        return host ? "https://" + host[1] + "/favicon.ico" : ""
    }

    function appIconFor(player) {
        return player && player.desktopEntry ? Quickshell.iconPath(player.desktopEntry, true) : ""
    }

    function formatTime(seconds) {
        if (!isFinite(seconds) || seconds < 0)
            seconds = 0

        const total = Math.floor(seconds)
        const mins = Math.floor(total / 60)
        const secs = total % 60
        return mins + ":" + (secs < 10 ? "0" + secs : secs)
    }

    function seekTo(fraction) {
        if (!hasPlayer)
            return

        const player = activePlayer
        if (!player.canSeek || !player.positionSupported || !(player.length > 0))
            return

        player.position = Math.max(0, Math.min(1, fraction)) * player.length
    }

    function siguiente() {
        if (activePlayer && activePlayer.canGoNext)
            activePlayer.next()
    }

    function anterior() {
        if (activePlayer && activePlayer.canGoPrevious)
            activePlayer.previous()
    }

    function togglePlaying() {
        if (hasPlayer)
            activePlayer.togglePlaying()
    }

    Timer {
        interval: 500
        repeat: true
        running: media.isPlaying && media.positionWatchers > 0
        onTriggered: media.activePlayer.positionChanged()
    }

    Timer {
        id: timelineDropTimer
        interval: 1500
        onTriggered: media.hasTimeline = media.hasTimelineRaw
    }
}
