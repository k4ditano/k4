import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications

Scope {
    id: root

    // ─────────────────────────────────────────────────────────────
    //  Design tokens (macOS Dynamic Island / Atoll)
    // ─────────────────────────────────────────────────────────────
    readonly property string uiFont: "Adwaita Sans"
    readonly property var locale: Qt.locale("es_ES")
    readonly property string iconFont: "MesloLGS Nerd Font"

    readonly property color islandBg: "#000000"
    readonly property color ink: "#ffffff"
    readonly property color muted: "#8e8e93"
    readonly property color dim: "#48484a"
    readonly property color surface: "#1c1c1e"
    readonly property color surfaceHi: "#2c2c2e"
    readonly property color track: "#3a3a3c"
    readonly property color green: "#30d158"
    readonly property color red: "#ff453a"

    // Material Design icons from the Nerd Font (supplementary plane → fromCodePoint)
    readonly property var ico: ({
        play: String.fromCodePoint(0xF040A),
        pause: String.fromCodePoint(0xF03E4),
        next: String.fromCodePoint(0xF04AD),
        prev: String.fromCodePoint(0xF04AE),
        shuffle: String.fromCodePoint(0xF049D),
        repeat: String.fromCodePoint(0xF0456),
        repeatOne: String.fromCodePoint(0xF0458),
        output: String.fromCodePoint(0xF0F5F),
        music: String.fromCodePoint(0xF0387),
        wifi: String.fromCodePoint(0xF05A9),
        wifiOff: String.fromCodePoint(0xF05AA),
        bluetooth: String.fromCodePoint(0xF00AF),
        bluetoothOff: String.fromCodePoint(0xF00B2),
        volHigh: String.fromCodePoint(0xF057E),
        volMed: String.fromCodePoint(0xF0580),
        volOff: String.fromCodePoint(0xF0581),
        bell: String.fromCodePoint(0xF009A),
        bellOutline: String.fromCodePoint(0xF009C),
        search: String.fromCodePoint(0xF0349),
        chevronUp: String.fromCodePoint(0xF0143),
        chevronDown: String.fromCodePoint(0xF0140),
        cog: String.fromCodePoint(0xF0493),
        close: String.fromCodePoint(0xF0156),
        apps: String.fromCodePoint(0xF003B),
        enter: String.fromCodePoint(0xF0311),
        ask: String.fromCodePoint(0xF0674),
        shot: String.fromCodePoint(0xF0E51),
        selection: String.fromCodePoint(0xF05E7),
        copy: String.fromCodePoint(0xF018F),
        alert: String.fromCodePoint(0xF0026),
        back: String.fromCodePoint(0xF0141),
        forward: String.fromCodePoint(0xF0142),
        loading: String.fromCodePoint(0xF0772),
        install: String.fromCodePoint(0xF03D4),
        package: String.fromCodePoint(0xF03D7),
        installed: String.fromCodePoint(0xF05E0),
        lock: String.fromCodePoint(0xF033E),
        check: String.fromCodePoint(0xF012C),
        linkOff: String.fromCodePoint(0xF0338),
        devices: String.fromCodePoint(0xF0FB0),
        headphones: String.fromCodePoint(0xF02CB),
        cellphone: String.fromCodePoint(0xF011C),
        mouse: String.fromCodePoint(0xF037D),
        keyboard: String.fromCodePoint(0xF030C),
        speaker: String.fromCodePoint(0xF04C3),
        watch: String.fromCodePoint(0xF0589),
        gamepad: String.fromCodePoint(0xF0EB5),
        laptop: String.fromCodePoint(0xF0322),
        printer: String.fromCodePoint(0xF042A),
        television: String.fromCodePoint(0xF0502),
        wifi0: String.fromCodePoint(0xF092D),
        wifi1: String.fromCodePoint(0xF091F),
        wifi2: String.fromCodePoint(0xF0922),
        wifi3: String.fromCodePoint(0xF0925),
        wifi4: String.fromCodePoint(0xF0928)
    })

    // island geometry
    readonly property int wing: 16          // inverted-corner radius that melts into the screen edge
    readonly property int baseHeight: 34    // collapsed height, also the strip reserved from windows
    readonly property int maxIslandHeight: 520 // ceiling for the surface, see PanelWindow below

    // ─────────────────────────────────────────────────────────────
    //  State
    // ─────────────────────────────────────────────────────────────
    property bool hovered: false
    property bool panelOpen: false
    property string panelTab: "controls"    // "controls" | "notifications" | "wifi" | "bluetooth"
    property var wifiPskTarget: null        // red esperando contraseña
    property string wifiPskInput: ""
    property string networkNotice: ""
    property bool launcherOpen: false
    property bool launcherClosing: false
    property bool notificationToastOpen: false
    property var latestNotification: null
    property int notificationCount: 0
    property string launcherQuery: ""
    property int launcherIndex: 0
    property var launcherMatches: []
    property string launcherMode: "apps"     // "apps" | "packages"
    property var repoResults: []
    property var aurResults: []
    property var installedPackages: ({})
    property bool aurSearching: false
    property string wifiName: "Buscando Wi‑Fi…"
    property int audioVolume: 0
    property bool audioMuted: false
    property bool audioVolumeInitialized: false
    property bool audioOverlayOpen: false

    // ── ask (Codex CLI con la cuenta de ChatGPT del usuario)
    property bool askOpen: false
    property string askQuery: ""
    property string askStatus: ""       // "" | "thinking" | "error"
    property string askImage: ""
    property string askSelection: ""          // adjunto de verdad (opt-in)
    property string askSelectionCandidate: "" // lo que hay seleccionado, aún sin adjuntar
    property bool askAttachSelectionOnOpen: false
    property var askMessages: []        // [{ role: "user"|"assistant"|"error", text }]
    // id de sesión de Codex de ESTA conversación. Vacío = sesión nueva.
    // Nunca se resume con --last, que engancharía con otras sesiones de Codex.
    property string askThreadId: ""
    readonly property string askDir: "/tmp/k4-ask"
    readonly property string askScript: Quickshell.shellPath("ask.sh")

    property var activeMediaPlayer: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; ++i) {
            if (players[i].isPlaying)
                return players[i]
        }
        return players.length > 0 ? players[0] : null
    }

    readonly property var workspaceList: {
        const list = Hyprland.workspaces.values.slice()
        list.sort(function (a, b) { return a.id - b.id })
        return list
    }

    // ancho que ocupan los puntos en la píldora: activo + resto + hueco al reloj
    readonly property int workspaceDotsWidth: workspaceList.length === 0
        ? 0 : (workspaceList.length - 1) * 10 + 18 + 8

    readonly property bool hasPlayer: activeMediaPlayer !== null
    readonly property bool isPlaying: hasPlayer && activeMediaPlayer.isPlaying
    // some players (Firefox/Zen) never publish mpris:length — hide the timeline for those.
    // debounced so a track change (length briefly 0) doesn't make the island jump.
    readonly property bool hasTimelineRaw: hasPlayer && activeMediaPlayer.lengthSupported && activeMediaPlayer.length > 0
    property bool hasTimeline: false
    onHasTimelineRawChanged: {
        if (hasTimelineRaw)
            hasTimeline = true
        else
            timelineDropTimer.restart()
    }

    property string debugMode: ""

    readonly property string mode: debugMode.length > 0 ? debugMode
        : askOpen ? "ask"
        : launcherOpen || launcherClosing ? "launcher"
        : notificationToastOpen ? "toast"
        : panelOpen ? "panel"
        : hovered ? (isPlaying ? "player" : "clock")
        : audioOverlayOpen ? "volume"
        : "idle"

    readonly property int islandWidth: mode === "ask" ? 700
        : mode === "launcher" ? 720
        : mode === "toast" ? 440
        : mode === "panel" ? 860
        : mode === "player" ? 340
        : mode === "clock" ? 300
        : mode === "volume" ? 240
        : (isPlaying ? 210 : 176) + workspaceDotsWidth

    readonly property int islandHeight: mode === "ask"
            ? (askMessages.length > 0 ? 430 : 128)
        : mode === "launcher" ? 440
        : mode === "toast" ? 96
        : mode === "panel" ? (panelTab === "controls" ? 274 : 400)
        : mode === "player" ? (hasTimeline ? 140 : 115)
        : mode === "clock" ? 68
        : mode === "volume" ? 40
        : baseHeight

    // ─────────────────────────────────────────────────────────────
    //  Services
    // ─────────────────────────────────────────────────────────────
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Process {
        id: wifiNameProcess
        command: ["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.updateWifiName(this.text)
        }

        onExited: wifiPoll.restart()
    }

    Timer {
        id: wifiPoll
        interval: 4000
        onTriggered: wifiNameProcess.running = true
    }

    Process {
        id: audioVolumeProcess
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.updateAudioVolume(this.text)
        }

        onExited: audioVolumePoll.restart()
    }

    Timer {
        id: audioVolumePoll
        interval: 350
        onTriggered: audioVolumeProcess.running = true
    }

    Timer {
        id: audioOverlayTimer
        interval: 1600
        onTriggered: root.audioOverlayOpen = false
    }

    // MPRIS position does not update reactively — poll it while the player is on screen.
    Timer {
        interval: 500
        repeat: true
        running: root.hasPlayer && root.isPlaying && (root.mode === "player" || root.mode === "panel")
        onTriggered: root.activeMediaPlayer.positionChanged()
    }

    // ── ask: Codex CLI, autenticado con la cuenta de ChatGPT del usuario.
    //    Nada de automatizar chatgpt.com: esto es el binario oficial de OpenAI.
    Process {
        id: askWorkdirProcess
        command: ["mkdir", "-p", root.askDir]
        running: true
    }

    Process {
        id: askSelectionProcess
        command: ["wl-paste", "--primary", "--no-newline"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.askSelectionCandidate = this.text.trim().substring(0, 4000)
                // solo se adjunta si lo pediste explícitamente
                if (root.askAttachSelectionOnOpen)
                    root.askSelection = root.askSelectionCandidate
            }
        }
    }

    Process {
        id: askShotProcess
        onExited: function (code) {
            const shot = code === 0 ? root.askDir + "/shot.png" : ""
            root.openAsk(false)
            root.askImage = shot
        }
    }

    Process {
        id: askProcess

        stdout: SplitParser {
            onRead: function (line) { root.handleAskEvent(line) }
        }

        stderr: SplitParser {
            onRead: function (line) {
                if (line.indexOf("ERROR") !== -1 || line.indexOf("error:") !== -1)
                    root.askLastError = line
            }
        }

        onExited: function (code) {
            askTimeoutTimer.stop()

            const last = root.askMessages.length > 0
                ? root.askMessages[root.askMessages.length - 1] : null
            const answered = last && last.role === "assistant" && last.text.length > 0

            if (!answered) {
                root.askStatus = "error"
                root.updateLastAskMessage("error", root.askLastError.length > 0
                    ? root.askLastError
                    : "Codex terminó con código " + code + " y sin respuesta.")
            } else if (root.askStatus === "thinking") {
                root.askStatus = ""
            }
        }
    }

    property string askLastError: ""

    Timer {
        id: askTimeoutTimer
        interval: 120000
        onTriggered: {
            if (askProcess.running) {
                askProcess.signal(15)
                root.askStatus = "error"
                root.updateLastAskMessage("error", "Codex no respondió en 2 minutos.")
            }
        }
    }

    // ── búsqueda de paquetes ──────────────────────────────────────
    // Dos velocidades: pacman lee la base local (~0.3s) y sale al instante;
    // yay consulta el RPC de AUR (~1.3s) y se deja para cuando dejas de teclear.
    Process {
        id: installedListProcess
        command: ["pacman", "-Qq"]

        stdout: StdioCollector {
            onStreamFinished: {
                const set = ({})
                const names = this.text.split("\n")
                for (let i = 0; i < names.length; ++i) {
                    const name = names[i].trim()
                    if (name.length > 0)
                        set[name] = true
                }
                root.installedPackages = set
            }
        }
    }

    Process {
        id: repoSearchProcess
        environment: ({ "LC_ALL": "C" })

        stdout: StdioCollector {
            onStreamFinished: root.repoResults = root.parsePackages(this.text, false)
        }
    }

    Process {
        id: aurSearchProcess
        environment: ({ "LC_ALL": "C" })

        stdout: StdioCollector {
            onStreamFinished: {
                root.aurResults = root.parsePackages(this.text, true)
                root.aurSearching = false
            }
        }

        onExited: root.aurSearching = false
    }

    Timer {
        id: repoSearchTimer
        interval: 180
        onTriggered: root.runRepoSearch()
    }

    Timer {
        id: aurSearchTimer
        interval: 500
        onTriggered: root.runAurSearch()
    }

    // Escanear solo mientras se mira la lista: dejarlo encendido gasta radio.
    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.mode === "panel" && root.panelTab === "wifi"
        when: root.wifiDevice !== null
    }

    Binding {
        target: Bluetooth.defaultAdapter
        property: "discovering"
        value: root.mode === "panel" && root.panelTab === "bluetooth"
        when: Bluetooth.defaultAdapter !== null
    }

    NotificationServer {
        id: notificationServer
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
    }

    Timer {
        id: timelineDropTimer
        interval: 1500
        onTriggered: root.hasTimeline = root.hasTimelineRaw
    }

    Timer {
        id: panelCloseTimer
        interval: 700
        onTriggered: {
            if (!root.launcherOpen)
                root.panelOpen = false
        }
    }

    Timer {
        id: hoverExitTimer
        interval: 240
        onTriggered: root.hovered = false
    }

    Timer {
        id: notificationToastTimer
        interval: 5000
        onTriggered: root.dismissNotificationToast()
    }

    Timer {
        id: launcherCloseTimer
        interval: 320
        onTriggered: root.launcherClosing = false
    }

    Connections {
        target: notificationServer
        function onNotification(notification) {
            notification.tracked = true
            root.latestNotification = notification
            root.notificationCount += 1
            root.launcherOpen = false
            root.panelOpen = false
            root.notificationToastOpen = true
            notificationToastTimer.restart()
        }
    }

    Connections {
        target: Networking
        function onWifiEnabledChanged() { root.refreshNetwork() }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { root.rebuildLauncher() }
    }

    Timer {
        id: launcherRefreshTimer
        interval: 1000
        repeat: true
        running: root.launcherOpen && root.launcherMode === "apps"
        onTriggered: root.rebuildLauncher()
    }

    IpcHandler {
        target: "k4"
        function toggleLauncher() { root.toggleLauncher() }
        function install(query: string): void { root.openPackageSearch(query) }
        function search(query: string): void {
            if (!root.launcherOpen)
                root.toggleLauncher()
            root.launcherQuery = query
            root.rebuildLauncher()
        }
        function togglePanel() { root.togglePanel("controls") }
        function toggleNotifications() { root.togglePanel("notifications") }
        function wifi() { root.openNetworkTab("wifi") }
        function bluetooth() { root.openNetworkTab("bluetooth") }
        function clearNotifications() { root.clearNotifications() }
        function ask() {
            if (root.askOpen)
                root.closeAsk()
            else
                root.openAsk(false)
        }
        function askSelection() { root.openAsk(true) }
        function askNow(question: string): void {
            root.openAsk(false)
            root.askQuery = question
            root.sendAsk()
        }
        function askFollowUp(question: string): void {
            if (!root.askOpen)
                root.openAsk(false)
            root.askQuery = question
            root.sendAsk()
        }
        function askScreen() { root.askWithScreenshot() }
        function askRegion() { root.askWithRegion() }
        function togglePlay() { if (root.hasPlayer) root.activeMediaPlayer.togglePlaying() }
        function setMode(mode: string): void { root.debugMode = mode }
    }

    Component.onCompleted: {
        root.refreshNetwork()
        root.hasTimeline = root.hasTimelineRaw
    }

    // ─────────────────────────────────────────────────────────────
    //  Logic
    // ─────────────────────────────────────────────────────────────
    function refreshNetwork() {
        const devices = Networking.devices.values
        for (let i = 0; i < devices.length; ++i) {
            const device = devices[i]
            if (device.type !== DeviceType.Wifi || !device.connected)
                continue

            const networks = device.networks.values
            for (let j = 0; j < networks.length; ++j) {
                if (networks[j].connected) {
                    root.wifiName = networks[j].name
                    return
                }
            }
        }

        root.wifiName = Networking.wifiEnabled ? "Buscando Wi‑Fi…" : "Wi‑Fi apagada"
    }

    // ── redes ─────────────────────────────────────────────────────
    // El escáner y el descubrimiento solo se activan mientras miras la lista:
    // dejarlos encendidos gasta batería y radio para nada.
    readonly property var wifiDevice: {
        const devices = Networking.devices.values
        for (let i = 0; i < devices.length; ++i) {
            if (devices[i].type === DeviceType.Wifi)
                return devices[i]
        }
        return null
    }

    readonly property var wifiNetworks: {
        if (!wifiDevice)
            return []

        const networks = wifiDevice.networks.values.slice()
        networks.sort(function (a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1
            if (a.known !== b.known)
                return a.known ? -1 : 1
            return (b.signalStrength || 0) - (a.signalStrength || 0)
        })
        return networks
    }

    readonly property var bluetoothDevices: {
        const adapter = Bluetooth.defaultAdapter
        if (!adapter)
            return []

        const devices = adapter.devices.values.slice()
        devices.sort(function (a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1
            if (a.paired !== b.paired)
                return a.paired ? -1 : 1
            return a.name.localeCompare(b.name)
        })
        return devices
    }

    function wifiStrengthIcon(network) {
        const strength = network && network.signalStrength ? network.signalStrength : 0
        if (strength >= 0.75) return root.ico.wifi4
        if (strength >= 0.5) return root.ico.wifi3
        if (strength >= 0.25) return root.ico.wifi2
        if (strength > 0) return root.ico.wifi1
        return root.ico.wifi0
    }

    function wifiIsSecure(network) {
        if (!network)
            return false

        // Open y Owe (Enhanced Open) no piden credenciales
        return network.security !== WifiSecurityType.Open
            && network.security !== WifiSecurityType.Owe
    }

    // connectWithPsk solo vale para estas; en EAP/empresa hay que tirar de
    // perfil de NetworkManager, así que ahí se intenta connect() a secas.
    function wifiNeedsPsk(network) {
        if (!network)
            return false

        return network.security === WifiSecurityType.WpaPsk
            || network.security === WifiSecurityType.Wpa2Psk
            || network.security === WifiSecurityType.Sae
    }

    function wifiNetworkStatus(network) {
        if (!network)
            return ""
        if (network.stateChanging)
            return network.connected ? "Desconectando…" : "Conectando…"
        if (network.connected)
            return "Conectada"
        if (network.known)
            return "Guardada"
        return root.wifiIsSecure(network) ? "Protegida" : "Abierta"
    }

    function activateWifiNetwork(network) {
        if (!network)
            return

        root.networkNotice = ""

        if (network.connected) {
            network.disconnect()
            return
        }

        if (network.known || !root.wifiNeedsPsk(network)) {
            network.connect()
            return
        }

        // red protegida y sin credenciales guardadas: hace falta la contraseña
        root.wifiPskInput = ""
        root.wifiPskTarget = network
    }

    function submitWifiPsk() {
        const network = root.wifiPskTarget
        if (!network)
            return

        if (root.wifiPskInput.length > 0)
            network.connectWithPsk(root.wifiPskInput)

        root.wifiPskInput = ""
        root.wifiPskTarget = null
    }

    function cancelWifiPsk() {
        root.wifiPskInput = ""
        root.wifiPskTarget = null
    }

    function bluetoothDeviceIcon(device) {
        const icon = device && device.icon ? device.icon : ""
        if (icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1) return root.ico.headphones
        if (icon.indexOf("phone") !== -1) return root.ico.cellphone
        if (icon.indexOf("mouse") !== -1) return root.ico.mouse
        if (icon.indexOf("keyboard") !== -1) return root.ico.keyboard
        if (icon.indexOf("speaker") !== -1 || icon.indexOf("audio") !== -1) return root.ico.speaker
        if (icon.indexOf("watch") !== -1) return root.ico.watch
        if (icon.indexOf("gaming") !== -1 || icon.indexOf("joystick") !== -1) return root.ico.gamepad
        if (icon.indexOf("computer") !== -1 || icon.indexOf("laptop") !== -1) return root.ico.laptop
        if (icon.indexOf("printer") !== -1) return root.ico.printer
        if (icon.indexOf("video") !== -1 || icon.indexOf("tv") !== -1) return root.ico.television
        return root.ico.devices
    }

    function bluetoothDeviceStatus(device) {
        if (!device)
            return ""
        if (device.pairing)
            return "Emparejando…"
        if (device.connected)
            return device.batteryAvailable
                ? "Conectado · " + Math.round(device.battery * 100) + "%"
                : "Conectado"
        if (device.paired || device.bonded)
            return "Emparejado"
        return "Disponible"
    }

    function activateBluetoothDevice(device) {
        if (!device)
            return

        root.networkNotice = ""

        if (device.connected)
            device.disconnect()
        else if (device.paired || device.bonded)
            device.connect()
        else
            device.pair()
    }

    function openNetworkTab(tab) {
        root.panelTab = tab
        root.panelOpen = true
        root.cancelWifiPsk()
        root.networkNotice = ""
    }

    function updateWifiName(output) {
        const lines = output.trim().split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const fields = lines[i].split(":")
            if (fields[0] === "yes" && fields.length > 1 && fields[1].length > 0) {
                root.wifiName = fields.slice(1).join(":")
                return
            }
        }

        root.refreshNetwork()
    }

    function updateAudioVolume(output) {
        const match = output.match(/Volume:\s+([0-9.]+)/)
        const nextVolume = match ? Math.round(parseFloat(match[1]) * 100) : root.audioVolume
        const nextMuted = output.indexOf("[MUTED]") !== -1
        const changed = root.audioVolumeInitialized
            && (nextVolume !== root.audioVolume || nextMuted !== root.audioMuted)

        root.audioVolume = nextVolume
        root.audioMuted = nextMuted
        root.audioVolumeInitialized = true

        if (changed)
            root.showAudioOverlay()
    }

    function showAudioOverlay() {
        root.audioOverlayOpen = true
        audioOverlayTimer.restart()
    }

    function setAudioVolume(percent) {
        const bounded = Math.max(0, Math.min(100, Math.round(percent)))
        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", String(bounded / 100)])
        root.audioVolume = bounded
        root.audioMuted = false
        root.showAudioOverlay()
        audioVolumePoll.restart()
    }

    function toggleAudioMute() {
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        root.showAudioOverlay()
        audioVolumePoll.restart()
    }

    // ── Artwork resolution ────────────────────────────────────────
    // Browsers (Firefox/Zen and friends) publish no mpris:artUrl, but they do
    // publish xesam:url — enough to build the thumbnail ourselves.
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

        const url = root.trackUrl(player)
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

    // last resort before the note glyph: the site's favicon, then the app icon
    function faviconFor(player) {
        const host = root.trackUrl(player).match(/^https?:\/\/([^\/]+)/)
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
        if (!root.hasPlayer)
            return

        const player = root.activeMediaPlayer
        if (!player.canSeek || !player.positionSupported || !(player.length > 0))
            return

        player.position = Math.max(0, Math.min(1, fraction)) * player.length
    }

    function togglePanel(tab) {
        // asking for a tab that is not the one on screen switches to it instead of closing
        const wantsTab = tab !== undefined && tab.length > 0
        root.panelOpen = !root.panelOpen || (wantsTab && tab !== root.panelTab)

        if (root.panelOpen) {
            if (wantsTab)
                root.panelTab = tab
            root.notificationToastOpen = false
            notificationToastTimer.stop()
            if (root.panelTab === "notifications")
                root.notificationCount = 0
        }
    }

    // ── paquetes ──────────────────────────────────────────────────
    function packageQuery() {
        // pacman -Ss interpreta el patrón como regex: fuera todo lo que pueda
        // romperlo o convertirse en un comodín inesperado
        return root.launcherQuery.replace(/[^A-Za-z0-9 _.+-]/g, "").trim()
    }

    function parsePackages(text, onlyAur) {
        const lines = text.split("\n")
        const packages = []
        let current = null

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            if (line.length === 0)
                continue

            if (line.charAt(0) === " " || line.charAt(0) === "\t") {
                if (current && current.description.length === 0)
                    current.description = line.trim()
                continue
            }

            const match = line.match(/^([^\s\/]+)\/(\S+)\s+(\S+)/)
            if (!match) {
                current = null
                continue
            }

            if (onlyAur && match[1] !== "aur") {
                current = null
                continue
            }

            current = {
                repo: match[1],
                name: match[2],
                version: match[3],
                description: ""
            }
            packages.push(current)
        }

        return packages
    }

    function runRepoSearch() {
        const query = root.packageQuery()
        if (query.length < 2) {
            root.repoResults = []
            return
        }

        if (repoSearchProcess.running)
            repoSearchProcess.signal(15)

        repoSearchProcess.command = ["pacman", "-Ss", "--"].concat(query.split(/\s+/))
        repoSearchProcess.running = true
    }

    function runAurSearch() {
        const query = root.packageQuery()
        if (query.length < 2) {
            root.aurResults = []
            root.aurSearching = false
            return
        }

        if (aurSearchProcess.running)
            aurSearchProcess.signal(15)

        root.aurSearching = true
        aurSearchProcess.command = ["yay", "-Ss", "--aur", "--color=never", "--"].concat(query.split(/\s+/))
        aurSearchProcess.running = true
    }

    function schedulePackageSearch() {
        repoSearchTimer.restart()
        aurSearchTimer.restart()
    }

    // repos primero, y dentro de cada origen los nombres más parecidos arriba
    readonly property var packageMatches: {
        const query = root.packageQuery().toLowerCase()
        const scored = []
        const all = root.repoResults.concat(root.aurResults)

        for (let i = 0; i < all.length; ++i) {
            const pkg = all[i]
            const name = pkg.name.toLowerCase()
            let score = 0
            if (name === query) score = 0
            else if (name.indexOf(query) === 0) score = 1
            else if (name.indexOf(query) !== -1) score = 2
            else score = 3

            scored.push({
                repo: pkg.repo,
                name: pkg.name,
                version: pkg.version,
                description: pkg.description,
                installed: root.installedPackages[pkg.name] === true,
                score: score + (pkg.repo === "aur" ? 4 : 0),
                order: i
            })
        }

        scored.sort(function (a, b) {
            if (a.score !== b.score) return a.score - b.score
            return a.order - b.order
        })

        // CachyOS sirve muchos paquetes también desde sus repos propios: se
        // queda el primero, que es el que pacman elegiría por prioridad
        const seen = ({})
        const unique = []
        for (let j = 0; j < scored.length; ++j) {
            if (seen[scored[j].name] === true)
                continue
            seen[scored[j].name] = true
            unique.push(scored[j])
        }

        return unique.slice(0, 60)
    }

    // atajo directo al modo instalar, sin pasar por la lista de apps
    function openPackageSearch(query) {
        root.panelOpen = false
        root.askOpen = false
        root.notificationToastOpen = false
        root.launcherClosing = false
        root.launcherOpen = true
        root.launcherQuery = query !== undefined ? query : ""
        root.enterPackageMode()
    }

    function enterPackageMode() {
        root.launcherMode = "packages"
        root.launcherIndex = 0
        root.repoResults = []
        root.aurResults = []
        installedListProcess.running = true
        root.schedulePackageSearch()
    }

    function leavePackageMode() {
        root.launcherMode = "apps"
        root.launcherIndex = 0
        repoSearchTimer.stop()
        aurSearchTimer.stop()
        root.aurSearching = false
        root.rebuildLauncher()
    }

    function installPackage(pkg) {
        if (!pkg)
            return

        // yay no puede correr como root (makepkg se niega), y AUR pide revisar
        // PKGBUILD y responder preguntas: por eso va en una terminal de verdad.
        const script = "yay -S --needed " + pkg.name
            + " && notify-send -a 'Instalar' '" + pkg.name + "' 'Instalado correctamente'"
            + " || { notify-send -a 'Instalar' -u critical '" + pkg.name + "' 'La instalación falló';"
            + " printf '\\nPulsa Enter para cerrar…'; read _; }"

        Quickshell.execDetached(["uwsm", "app", "--", "kitty", "-e", "sh", "-c", script])
        root.closeLauncher()
    }

    function rebuildLauncher() {
        const query = root.launcherQuery.trim().toLowerCase()
        const applications = DesktopEntries.applications.values
        const matches = []

        for (let i = 0; i < applications.length; ++i) {
            const app = applications[i]
            if (app.noDisplay)
                continue

            const haystack = (app.name + " " + app.genericName + " " + app.id).toLowerCase()
            if (query.length === 0 || haystack.indexOf(query) !== -1)
                matches.push(app)
        }

        matches.sort(function (a, b) { return a.name.localeCompare(b.name) })

        const list = matches.slice(0, 40)

        if (query.length > 0) {
            const installEntry = {
                isInstall: true,
                name: "Instalar «" + root.launcherQuery.trim() + "»",
                genericName: "Buscar en los repos oficiales y AUR",
                icon: ""
            }

            // se puede alcanzar escribiendo "instalar"/"install", que la sube arriba
            const triggered = "instalar".indexOf(query) === 0 || "install".indexOf(query) === 0
            if (triggered)
                list.unshift(installEntry)
            else
                list.push(installEntry)
        }

        root.launcherMatches = list
        root.launcherIndex = 0
    }

    function toggleLauncher() {
        if (root.launcherOpen) {
            root.closeLauncher()
            return
        }

        root.launcherQuery = ""
        root.launcherMode = "apps"
        root.launcherClosing = false
        root.panelOpen = false
        root.notificationToastOpen = false
        root.launcherOpen = true
        root.rebuildLauncher()
    }

    function closeLauncher() {
        root.launcherOpen = false
        root.launcherClosing = true
        root.launcherQuery = ""
        root.launcherMode = "apps"
        repoSearchTimer.stop()
        aurSearchTimer.stop()
        root.aurSearching = false
        launcherCloseTimer.restart()
    }

    // ── ask ───────────────────────────────────────────────────────
    function openAsk(attachSelection) {
        root.newAskConversation()
        root.panelOpen = false
        root.launcherOpen = false
        root.notificationToastOpen = false
        root.askAttachSelectionOnOpen = attachSelection === true
        // se lee para poder ofrecerla, pero no se adjunta sin permiso
        askSelectionProcess.running = true
        root.askOpen = true
    }

    function attachSelection() {
        if (root.askSelectionCandidate.length > 0)
            root.askSelection = root.askSelectionCandidate
    }

    // Abrir la island siempre empieza conversación nueva: así nunca se hereda
    // el contexto de la consulta anterior ni de ninguna otra sesión de Codex.
    function newAskConversation() {
        if (askProcess.running)
            askProcess.signal(15)

        askTimeoutTimer.stop()
        root.askQuery = ""
        root.askMessages = []
        root.askThreadId = ""
        root.askLastError = ""
        root.askStatus = ""
        root.askSelection = ""
        root.askSelectionCandidate = ""
        root.askAttachSelectionOnOpen = false
    }

    function appendAskMessage(role, text) {
        root.askMessages = root.askMessages.concat([{ role: role, text: text }])
    }

    function updateLastAskMessage(role, text) {
        const messages = root.askMessages.slice()
        for (let i = messages.length - 1; i >= 0; --i) {
            if (messages[i].role === "assistant" || messages[i].role === "error") {
                messages[i] = { role: role, text: text }
                root.askMessages = messages
                return
            }
        }
        root.appendAskMessage(role, text)
    }

    function askWithScreenshot() {
        // se captura antes de expandir la island, así no sale ella en la foto
        root.askImage = ""
        root.askAttachSelectionOnOpen = false
        askShotProcess.command = ["grim", root.askDir + "/shot.png"]
        askShotProcess.running = true
    }

    function askWithRegion() {
        root.askImage = ""
        askShotProcess.command = ["sh", "-c", "grim -g \"$(slurp -d)\" " + root.askDir + "/shot.png"]
        askShotProcess.running = true
    }

    function closeAsk() {
        root.newAskConversation()
        root.askOpen = false
        root.askImage = ""
    }

    function sendAsk() {
        const question = root.askQuery.trim()
        if (question.length === 0 || root.askStatus === "thinking")
            return

        root.askLastError = ""
        root.askStatus = "thinking"
        root.appendAskMessage("user", question)
        root.appendAskMessage("assistant", "")
        root.askQuery = ""

        // el preámbulo solo en el primer turno: después ya vive en la sesión
        let prompt = root.askThreadId.length === 0
            ? "Eres un asistente rápido integrado en la barra del escritorio. "
                + "Responde en español, breve y directo, en texto plano sin markdown ni listas numeradas. "
                + "No ejecutes comandos ni leas archivos salvo que la pregunta lo pida explícitamente.\n\n"
                + "Pregunta: " + question
            : question

        if (root.askSelection.length > 0)
            prompt += "\n\nTexto que el usuario tiene seleccionado en pantalla:\n" + root.askSelection

        if (root.askImage.length > 0)
            prompt += "\n\nSe adjunta una captura de la pantalla del usuario."

        // vía wrapper: necesita cerrar stdin, si no `codex exec` se cuelga
        // esperando EOF (Quickshell le deja el pipe abierto)
        askProcess.command = [root.askScript, prompt, root.askImage, root.askThreadId]
        askProcess.running = true
        askTimeoutTimer.restart()

        // los adjuntos son de este turno, no de toda la conversación
        root.askImage = ""
        root.askSelection = ""
    }

    function handleAskEvent(line) {
        const text = line.trim()
        if (text.length === 0 || text.charAt(0) !== "{")
            return

        let event
        try {
            event = JSON.parse(text)
        } catch (error) {
            return
        }

        if (event.type === "thread.started" && event.thread_id) {
            root.askThreadId = event.thread_id
        } else if ((event.type === "item.completed" || event.type === "item.updated") && event.item) {
            if (event.item.type === "agent_message" && event.item.text)
                root.updateLastAskMessage("assistant", event.item.text)
        } else if (event.type === "turn.failed" || event.type === "error") {
            root.askStatus = "error"
            root.updateLastAskMessage("error",
                event.error && event.error.message ? event.error.message : "Codex devolvió un error.")
        } else if (event.type === "turn.completed") {
            if (root.askStatus === "thinking")
                root.askStatus = ""
        }
    }

    // Lo que se adjunta tiene que verse: un texto seleccionado que el usuario
    // ya no recuerda haber marcado envenena la respuesta sin dejar rastro.
    function selectionPreview(source) {
        const text = source.replace(/\s+/g, " ").trim()
        return text.length > 30 ? text.substring(0, 30) + "…" : text
    }

    function copyAnswer() {
        for (let i = root.askMessages.length - 1; i >= 0; --i) {
            if (root.askMessages[i].role === "assistant" && root.askMessages[i].text.length > 0) {
                Quickshell.execDetached(["wl-copy", "--", root.askMessages[i].text])
                return
            }
        }
    }

    function clearNotifications() {
        // copy first: dismissing mutates the tracked list while we walk it
        const tracked = notificationServer.trackedNotifications.values.slice()
        for (let i = 0; i < tracked.length; ++i)
            tracked[i].dismiss()

        root.notificationCount = 0
        root.notificationToastOpen = false
        notificationToastTimer.stop()
    }

    function dismissNotificationToast() {
        notificationToastTimer.stop()
        root.notificationToastOpen = false
    }

    function launchSelected() {
        if (root.launcherMode === "packages") {
            root.installPackage(root.packageMatches[root.launcherIndex])
            return
        }

        if (root.launcherMatches.length === 0)
            return

        const entry = root.launcherMatches[root.launcherIndex]

        if (entry && entry.isInstall === true) {
            root.enterPackageMode()
            return
        }

        root.closeLauncher()
        entry.execute()
    }

    readonly property int launcherCount: launcherMode === "packages"
        ? packageMatches.length : launcherMatches.length

    function moveLauncherSelection(delta) {
        if (root.launcherCount === 0)
            return

        root.launcherIndex = Math.max(0, Math.min(root.launcherCount - 1, root.launcherIndex + delta))
    }

    // ─────────────────────────────────────────────────────────────
    //  The island
    // ─────────────────────────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData
            anchors.top: true
            anchors.left: true
            anchors.right: true
            color: "transparent"
            aboveWindows: true
            focusable: true
            WlrLayershell.keyboardFocus: root.launcherOpen || root.askOpen || root.wifiPskTarget
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // reserve only the collapsed strip: windows never sit under the pill,
            // but every expanded state floats above them
            exclusiveZone: root.baseHeight
            // Resizing a layer surface costs a configure/ack round trip, so doing it
            // once per animation frame is what made the panel flicker. The surface now
            // grows once when the island starts expanding and shrinks once when the
            // animation is over; in between only the island itself animates.
            readonly property int targetHeight: Math.min(root.maxIslandHeight, root.islandHeight + 2)
            property int surfaceHeight: targetHeight

            onTargetHeightChanged: {
                if (targetHeight > surfaceHeight)
                    surfaceHeight = targetHeight
                else
                    surfaceShrinkTimer.restart()
            }

            Timer {
                id: surfaceShrinkTimer
                interval: 520
                onTriggered: panelWindow.surfaceHeight = panelWindow.targetHeight
            }

            implicitHeight: surfaceHeight
            mask: Region { item: island }

            Item {
                id: island
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, root.islandWidth + root.wing * 2)
                height: root.islandHeight

                readonly property real bodyRadius: Math.min(32, height / 2)

                Behavior on width {
                    NumberAnimation {
                        duration: 440
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.42
                    }
                }

                Behavior on height {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.32
                    }
                }

                HoverHandler {
                    id: islandHover
                    onHoveredChanged: {
                        if (hovered) {
                            hoverExitTimer.stop()
                            panelCloseTimer.stop()
                            root.hovered = true
                            if (root.notificationToastOpen)
                                notificationToastTimer.stop()
                        } else {
                            hoverExitTimer.restart()
                            // sólo se arma al salir, así que un panel abierto por
                            // atajo de teclado sigue abierto hasta que lo toques
                            if (root.panelOpen)
                                panelCloseTimer.restart()
                            if (root.notificationToastOpen)
                                notificationToastTimer.restart()
                        }
                    }
                }

                // right click anywhere on the island → control centre
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.togglePanel()
                }

                // ── the notch silhouette: body + inverted corners melting into the screen edge
                Shape {
                    id: islandShape
                    anchors.fill: parent
                    // CurveRenderer suaviza mejor, pero descarta las esquinas
                    // invertidas (las alas), así que se antialiasa con MSAA.
                    antialiasing: true
                    layer.enabled: true
                    layer.samples: 8
                    layer.smooth: true

                    ShapePath {
                        id: islandPath
                        fillColor: root.islandBg
                        strokeWidth: 0
                        strokeColor: "transparent"

                        readonly property real w: island.width
                        readonly property real h: island.height
                        readonly property real r: island.bodyRadius
                        readonly property real g: Math.min(root.wing, island.height / 2)

                        startX: 0
                        startY: 0

                        // left inverted corner
                        PathArc {
                            x: islandPath.g
                            y: islandPath.g
                            radiusX: islandPath.g
                            radiusY: islandPath.g
                            direction: PathArc.Clockwise
                        }

                        PathLine { x: islandPath.g; y: islandPath.h - islandPath.r }

                        // bottom left
                        PathArc {
                            x: islandPath.g + islandPath.r
                            y: islandPath.h
                            radiusX: islandPath.r
                            radiusY: islandPath.r
                            direction: PathArc.Counterclockwise
                        }

                        PathLine { x: islandPath.w - islandPath.g - islandPath.r; y: islandPath.h }

                        // bottom right
                        PathArc {
                            x: islandPath.w - islandPath.g
                            y: islandPath.h - islandPath.r
                            radiusX: islandPath.r
                            radiusY: islandPath.r
                            direction: PathArc.Counterclockwise
                        }

                        PathLine { x: islandPath.w - islandPath.g; y: islandPath.g }

                        // right inverted corner
                        PathArc {
                            x: islandPath.w
                            y: 0
                            radiusX: islandPath.g
                            radiusY: islandPath.g
                            direction: PathArc.Clockwise
                        }

                        PathLine { x: 0; y: 0 }
                    }
                }

                // ── content area (inside the body, wings excluded)
                Item {
                    id: clipper
                    anchors.fill: parent
                    anchors.leftMargin: root.wing
                    anchors.rightMargin: root.wing
                    clip: true

                    // Sits under every view: buttons and sliders grab their own clicks,
                    // anything else lands here → control centre.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.mode === "toast")
                                root.dismissNotificationToast()
                            else
                                root.togglePanel()
                        }
                    }

                    // laid out at the final size and revealed by the clip, so no
                    // layout recalculation happens during the animation
                    Item {
                        id: bodyArea
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.islandWidth
                        height: root.islandHeight

                    Loader {
                        anchors.fill: parent
                        active: root.mode === "idle"
                        sourceComponent: idleView
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.mode === "volume"
                        sourceComponent: volumeView
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.mode === "clock"
                        sourceComponent: clockView
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.mode === "player"
                        sourceComponent: playerView
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.mode === "toast"
                        sourceComponent: toastView
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.mode === "panel"
                        sourceComponent: panelView
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.mode === "launcher" && root.launcherOpen
                        sourceComponent: launcherView
                    }

                    Loader {
                        anchors.fill: parent
                        active: root.mode === "ask"
                        sourceComponent: askView
                    }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    //  Reusable bits
    // ─────────────────────────────────────────────────────────────
    component IslandLabel: Text {
        color: root.ink
        font.family: root.uiFont
        font.pixelSize: 12
    }

    component IconGlyph: Text {
        color: root.ink
        font.family: root.iconFont
        font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component FadeIn: Item {
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    // Artwork — cover / video thumbnail, else the site favicon, else the app
    // icon, else a note. Each step only shows once the previous one has failed.
    component Artwork: ClippingRectangle {
        id: artworkRoot
        property var player: root.activeMediaPlayer
        property color placeholder: root.surface

        readonly property string coverUrl: root.coverFor(player)
        readonly property string faviconUrl: root.faviconFor(player)
        readonly property string appIcon: root.appIconFor(player)

        color: placeholder
        radius: Math.round(width * 0.22)

        Image {
            id: coverImage
            anchors.fill: parent
            source: artworkRoot.coverUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: 256
            visible: status === Image.Ready
        }

        Image {
            id: siteIcon
            anchors.centerIn: parent
            width: Math.round(parent.height * 0.5)
            height: width
            // only asked for when there is no usable cover, so a thumbnail hit
            // never costs a second request
            source: artworkRoot.coverUrl.length === 0 || coverImage.status === Image.Error
                ? artworkRoot.faviconUrl : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            sourceSize.width: 64
            visible: !coverImage.visible && status === Image.Ready
        }

        IconImage {
            id: appIconImage
            anchors.centerIn: parent
            width: Math.round(parent.height * 0.56)
            height: width
            source: artworkRoot.appIcon
            visible: !coverImage.visible && !siteIcon.visible && artworkRoot.appIcon.length > 0
        }

        IconGlyph {
            anchors.centerIn: parent
            visible: !coverImage.visible && !siteIcon.visible && !appIconImage.visible
            text: root.ico.music
            color: root.muted
            font.pixelSize: Math.round(parent.height * 0.44)
        }
    }

    // Interruptor tipo macOS
    component IslandSwitch: Rectangle {
        property bool checked: false
        signal toggled()

        implicitWidth: 40
        implicitHeight: 24
        radius: 12
        color: checked ? "#30d158" : root.surfaceHi

        Behavior on color { ColorAnimation { duration: 180 } }

        Rectangle {
            width: 18
            height: 18
            radius: 9
            color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: parent.checked ? parent.width - width - 3 : 3

            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.toggled()
        }
    }

    // Fila de una red o dispositivo
    component ConnectionRow: Rectangle {
        property string glyph
        property string title
        property string subtitle
        property bool active: false
        property bool busy: false
        property bool secure: false
        property bool forgettable: false
        signal activated()
        signal forgotten()

        height: 46
        radius: 12
        color: rowMouse.containsMouse ? root.surfaceHi : "transparent"

        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 12

            IconGlyph {
                text: glyph
                color: active ? "#0a84ff" : root.ink
                font.pixelSize: 17
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 6

                    IslandLabel {
                        text: title
                        font.pixelSize: 13
                        font.weight: active ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    IconGlyph {
                        visible: secure
                        text: root.ico.lock
                        color: root.dim
                        font.pixelSize: 10
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                IslandLabel {
                    text: subtitle
                    color: active ? "#30d158" : root.muted
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            IslandLabel {
                visible: rowMouse.containsMouse && !busy
                text: active ? "Desconectar" : "Conectar"
                color: root.muted
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            IconGlyph {
                visible: busy
                text: root.ico.loading
                color: root.muted
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter

                RotationAnimation on rotation {
                    running: busy
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                }
            }

            Rectangle {
                visible: forgettable && rowMouse.containsMouse
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter
                radius: 13
                color: forgetMouse.containsMouse ? root.track : "transparent"

                IconGlyph {
                    anchors.centerIn: parent
                    text: root.ico.linkOff
                    color: forgetMouse.containsMouse ? root.ink : root.dim
                    font.pixelSize: 13
                }

                MouseArea {
                    id: forgetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: forgotten()
                }
            }
        }
    }

    // 4-bar audio visualiser
    component Visualizer: Item {
        property bool active: root.isPlaying
        property color barColor: root.ink
        implicitWidth: 17
        implicitHeight: 14

        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2.5

            Repeater {
                model: 4

                delegate: Rectangle {
                    required property int index
                    readonly property var restHeights: [9, 13, 6, 11]
                    width: 2.5
                    radius: 1.25
                    color: barColor
                    height: restHeights[index]
                    anchors.bottom: parent.bottom

                    SequentialAnimation on height {
                        running: active
                        loops: Animation.Infinite
                        NumberAnimation { to: 4 + (index % 2 === 0 ? 8 : 4); duration: 320 + index * 85; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 3; duration: 280 + index * 65; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 11 - index; duration: 300 + index * 40; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 4; duration: 260 + index * 55; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
    }

    // Round, monochrome media button
    component MediaButton: Item {
        property string glyph
        property int glyphSize: 18
        property color glyphColor: root.ink
        property bool enabledAction: true
        signal activated()

        implicitWidth: glyphSize + 16
        implicitHeight: glyphSize + 12
        opacity: enabledAction ? (mouse.containsMouse ? 0.65 : 1) : 0.28

        Behavior on opacity { NumberAnimation { duration: 120 } }

        IconGlyph {
            anchors.centerIn: parent
            text: glyph
            color: glyphColor
            font.pixelSize: glyphSize
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: enabledAction
            onClicked: activated()
        }

        scale: mouse.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    }

    // ─────────────────────────────────────────────────────────────
    //  Views
    // ─────────────────────────────────────────────────────────────

    // Collapsed pill — artwork · clock · visualiser
    Component {
        id: idleView

        FadeIn {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 11
                spacing: 8

                Artwork {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.isPlaying
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 4
                    Layout.fillWidth: false
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        model: root.workspaceList

                        delegate: Rectangle {
                            required property var modelData
                            Layout.preferredWidth: modelData.focused ? 18 : 6
                            Layout.preferredHeight: 6
                            Layout.alignment: Qt.AlignVCenter
                            radius: 3
                            color: modelData.focused ? root.ink : root.track

                            Behavior on Layout.preferredWidth {
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }

                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                }

                IslandLabel {
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: root.hasPlayer ? root.ink : root.muted
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                Visualizer {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 12
                    visible: root.isPlaying
                }
            }
        }
    }

    // Volume HUD
    Component {
        id: volumeView

        FadeIn {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                IconGlyph {
                    text: root.audioMuted ? root.ico.volOff : root.audioVolume > 45 ? root.ico.volHigh : root.ico.volMed
                    color: root.audioMuted ? root.muted : root.ink
                    font.pixelSize: 15
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    id: volumePillTrack
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    Layout.alignment: Qt.AlignVCenter
                    radius: 2
                    color: root.track

                    Rectangle {
                        width: volumePillTrack.width * Math.max(0, Math.min(100, root.audioVolume)) / 100
                        height: parent.height
                        radius: 2
                        color: root.audioMuted ? root.muted : root.ink

                        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }

                IslandLabel {
                    text: root.audioMuted ? "—" : root.audioVolume + "%"
                    color: root.muted
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 30
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    // Hover without media — date & time
    Component {
        id: clockView

        FadeIn {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                spacing: 12

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: false
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter

                    IslandLabel {
                        text: clock.date.toLocaleDateString(root.locale, "dddd")
                        color: root.muted
                        font.pixelSize: 11
                        font.capitalization: Font.Capitalize
                    }

                    IslandLabel {
                        text: clock.date.toLocaleDateString(root.locale, "d MMMM")
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                }

                Item { Layout.fillWidth: true }

                IslandLabel {
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    font.pixelSize: 30
                    font.weight: Font.Light
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    // ── The macOS media island
    Component {
        id: playerView

        FadeIn {
            id: playerRoot

            readonly property var player: root.activeMediaPlayer
            readonly property real progress: player && player.length > 0
                ? Math.max(0, Math.min(1, player.position / player.length))
                : 0

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 14
                anchors.bottomMargin: 14
                spacing: 13

                // ── track row
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 44
                    spacing: 11

                    Artwork {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        IslandLabel {
                            Layout.fillWidth: true
                            text: playerRoot.player && playerRoot.player.trackTitle.length > 0
                                ? playerRoot.player.trackTitle
                                : "Sin reproducción"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        IslandLabel {
                            Layout.fillWidth: true
                            text: playerRoot.player && playerRoot.player.trackArtist.length > 0
                                ? playerRoot.player.trackArtist
                                : (playerRoot.player ? playerRoot.player.identity : "")
                            color: root.muted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    Visualizer {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 4
                    }
                }

                // ── timeline
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 12
                    spacing: 8
                    visible: root.hasTimeline

                    IslandLabel {
                        text: playerRoot.player ? root.formatTime(playerRoot.player.position) : "0:00"
                        color: root.muted
                        font.pixelSize: 10
                        Layout.preferredWidth: 28
                    }

                    Item {
                        id: seekArea
                        Layout.fillWidth: true
                        Layout.preferredHeight: 12
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            id: seekTrack
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: seekMouse.containsMouse ? 6 : 4
                            radius: height / 2
                            color: root.track

                            Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            Rectangle {
                                width: seekTrack.width * playerRoot.progress
                                height: parent.height
                                radius: parent.radius
                                color: root.ink

                                Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            }
                        }

                        MouseArea {
                            id: seekMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function (mouse) { root.seekTo(mouse.x / width) }
                        }
                    }

                    IslandLabel {
                        text: playerRoot.player && playerRoot.player.length > 0
                            ? "-" + root.formatTime(playerRoot.player.length - playerRoot.player.position)
                            : "0:00"
                        color: root.muted
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: 32
                    }
                }

                // ── transport
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 30
                    spacing: 0

                    MediaButton {
                        glyph: root.ico.shuffle
                        glyphSize: 14
                        glyphColor: playerRoot.player && playerRoot.player.shuffle ? root.ink : root.muted
                        enabledAction: !!playerRoot.player && playerRoot.player.shuffleSupported
                        onActivated: playerRoot.player.shuffle = !playerRoot.player.shuffle
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    MediaButton {
                        glyph: root.ico.prev
                        glyphSize: 20
                        enabledAction: !!playerRoot.player && playerRoot.player.canGoPrevious
                        onActivated: playerRoot.player.previous()
                        Layout.alignment: Qt.AlignVCenter
                    }

                    MediaButton {
                        glyph: root.isPlaying ? root.ico.pause : root.ico.play
                        glyphSize: 24
                        enabledAction: !!playerRoot.player && playerRoot.player.canTogglePlaying
                        onActivated: playerRoot.player.togglePlaying()
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        Layout.alignment: Qt.AlignVCenter
                    }

                    MediaButton {
                        glyph: root.ico.next
                        glyphSize: 20
                        enabledAction: !!playerRoot.player && playerRoot.player.canGoNext
                        onActivated: playerRoot.player.next()
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    MediaButton {
                        glyph: root.ico.output
                        glyphSize: 15
                        glyphColor: root.muted
                        onActivated: root.togglePanel()
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }

    // ── Notification toast
    Component {
        id: toastView

        FadeIn {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    Layout.alignment: Qt.AlignVCenter
                    radius: 19
                    color: root.surface

                    IconGlyph {
                        anchors.centerIn: parent
                        text: root.ico.bell
                        color: root.ink
                        font.pixelSize: 17
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 6

                        IslandLabel {
                            text: root.latestNotification ? root.latestNotification.summary : "Notificación"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        IslandLabel {
                            text: root.latestNotification ? root.latestNotification.appName : ""
                            color: root.muted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.maximumWidth: 90
                        }
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        text: root.latestNotification ? root.latestNotification.body : ""
                        color: root.muted
                        font.pixelSize: 11
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                    }
                }

                MediaButton {
                    glyph: root.ico.close
                    glyphSize: 14
                    glyphColor: root.muted
                    onActivated: root.dismissNotificationToast()
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    // ── Control centre
    Component {
        id: panelView

        FadeIn {
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 14
                anchors.bottomMargin: 16
                spacing: 12

                // header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 30
                    spacing: 10

                    MediaButton {
                        visible: root.panelTab !== "controls"
                        glyph: root.ico.back
                        glyphSize: 16
                        glyphColor: root.muted
                        onActivated: {
                            root.cancelWifiPsk()
                            root.panelTab = "controls"
                        }
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IslandLabel {
                        text: root.panelTab === "notifications" ? "Notificaciones"
                            : root.panelTab === "wifi" ? "Wi‑Fi"
                            : root.panelTab === "bluetooth" ? "Bluetooth"
                            : "Centro de control"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Rectangle {
                        id: clearAllButton
                        visible: root.panelTab === "notifications"
                            && notificationServer.trackedNotifications.values.length > 0
                        Layout.preferredWidth: clearAllLabel.implicitWidth + 22
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        radius: 12
                        color: clearAllMouse.containsMouse ? root.track : root.surfaceHi

                        Behavior on color { ColorAnimation { duration: 120 } }

                        IslandLabel {
                            id: clearAllLabel
                            anchors.centerIn: parent
                            text: "Borrar todo"
                            color: clearAllMouse.containsMouse ? root.ink : root.muted
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: clearAllMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearNotifications()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    RowLayout {
                        spacing: 5
                        Layout.fillWidth: false
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignVCenter

                        Repeater {
                            model: root.workspaceList

                            delegate: Rectangle {
                                required property var modelData
                                Layout.preferredWidth: modelData.focused ? 24 : 8
                                Layout.preferredHeight: 8
                                radius: 4
                                color: modelData.focused ? root.ink : root.surfaceHi

                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.activate()
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    IslandLabel {
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: root.muted
                        font.pixelSize: 13
                        Layout.alignment: Qt.AlignVCenter
                    }

                    MediaButton {
                        glyph: root.notificationCount > 0 ? root.ico.bell : root.ico.bellOutline
                        glyphSize: 15
                        glyphColor: root.panelTab === "notifications" ? root.ink : root.muted
                        Layout.alignment: Qt.AlignVCenter
                        onActivated: {
                            root.panelTab = root.panelTab === "notifications" ? "controls" : "notifications"
                            if (root.panelTab === "notifications")
                                root.notificationCount = 0
                        }
                    }

                    MediaButton {
                        glyph: root.ico.chevronUp
                        glyphSize: 16
                        glyphColor: root.muted
                        onActivated: root.panelOpen = false
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // toggles
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 78
                    spacing: 10
                    visible: root.panelTab === "controls"

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 16
                        color: wifiTileMouse.containsMouse ? root.surfaceHi : root.surface

                        Behavior on color { ColorAnimation { duration: 140 } }

                        // debajo del contenido: el círculo tiene su propio MouseArea
                        // encima, así que pulsarlo conmuta y el resto abre el detalle
                        MouseArea {
                            id: wifiTileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openNetworkTab("wifi")
                        }

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    radius: 15
                                    color: Networking.wifiEnabled ? "#0a84ff" : root.surfaceHi

                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    IconGlyph {
                                        anchors.centerIn: parent
                                        text: Networking.wifiEnabled ? root.ico.wifi : root.ico.wifiOff
                                        font.pixelSize: 15
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                                    }
                                }

                                ColumnLayout {
                                    spacing: 0
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false

                                    IslandLabel { text: "Wi‑Fi"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    IslandLabel {
                                        text: Networking.wifiEnabled ? root.wifiName : "Desactivado"
                                        color: root.muted
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                IconGlyph {
                                    text: root.ico.forward
                                    color: wifiTileMouse.containsMouse ? root.ink : root.dim
                                    font.pixelSize: 14
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 16
                        color: btTileMouse.containsMouse ? root.surfaceHi : root.surface

                        Behavior on color { ColorAnimation { duration: 140 } }

                        MouseArea {
                            id: btTileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openNetworkTab("bluetooth")
                        }

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    radius: 15
                                    color: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? "#0a84ff" : root.surfaceHi

                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    IconGlyph {
                                        anchors.centerIn: parent
                                        text: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled
                                            ? root.ico.bluetooth : root.ico.bluetoothOff
                                        font.pixelSize: 15
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (Bluetooth.defaultAdapter)
                                            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                                    }
                                }

                                ColumnLayout {
                                    spacing: 0
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false

                                    IslandLabel { text: "Bluetooth"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    IslandLabel {
                                        text: Bluetooth.defaultAdapter
                                            ? (Bluetooth.defaultAdapter.enabled ? "Activado" : "Desactivado")
                                            : "Sin adaptador"
                                        color: root.muted
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                IconGlyph {
                                    text: root.ico.forward
                                    color: btTileMouse.containsMouse ? root.ink : root.dim
                                    font.pixelSize: 14
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 16
                        color: root.surface

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 8

                                IslandLabel { text: "Sonido"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                Item { Layout.fillWidth: true }
                                IslandLabel {
                                    text: root.audioMuted ? "Silenciado" : root.audioVolume + "%"
                                    color: root.muted
                                    font.pixelSize: 11
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26

                                Rectangle {
                                    id: volumeSliderTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 26
                                    radius: 13
                                    color: root.surfaceHi
                                    clip: true

                                    Rectangle {
                                        width: volumeSliderTrack.width * Math.max(0, Math.min(100, root.audioVolume)) / 100
                                        height: parent.height
                                        radius: parent.radius
                                        color: root.audioMuted ? root.dim : root.ink

                                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    }

                                    IconGlyph {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.audioMuted ? root.ico.volOff : root.ico.volMed
                                        color: root.audioVolume > 12 && !root.audioMuted ? "#000000" : root.muted
                                        font.pixelSize: 13
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function (mouse) { root.setAudioVolume(mouse.x / width * 100) }
                                    onPositionChanged: function (mouse) {
                                        if (pressed)
                                            root.setAudioVolume(mouse.x / width * 100)
                                    }
                                }
                            }
                        }
                    }
                }

                // now playing + shortcuts
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10
                    visible: root.panelTab === "controls"

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 16
                        color: root.surface

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            Artwork {
                                Layout.preferredWidth: 52
                                Layout.preferredHeight: 52
                                Layout.alignment: Qt.AlignVCenter
                                placeholder: root.surfaceHi
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                IslandLabel {
                                    Layout.fillWidth: true
                                    text: root.hasPlayer && root.activeMediaPlayer.trackTitle.length > 0
                                        ? root.activeMediaPlayer.trackTitle : "Nada en reproducción"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                IslandLabel {
                                    Layout.fillWidth: true
                                    text: root.hasPlayer ? root.activeMediaPlayer.trackArtist : ""
                                    color: root.muted
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            MediaButton {
                                glyph: root.ico.prev
                                glyphSize: 18
                                glyphColor: root.muted
                                enabledAction: root.hasPlayer && root.activeMediaPlayer.canGoPrevious
                                onActivated: root.activeMediaPlayer.previous()
                                Layout.alignment: Qt.AlignVCenter
                            }

                            MediaButton {
                                glyph: root.isPlaying ? root.ico.pause : root.ico.play
                                glyphSize: 22
                                enabledAction: root.hasPlayer && root.activeMediaPlayer.canTogglePlaying
                                onActivated: root.activeMediaPlayer.togglePlaying()
                                Layout.alignment: Qt.AlignVCenter
                            }

                            MediaButton {
                                glyph: root.ico.next
                                glyphSize: 18
                                glyphColor: root.muted
                                enabledAction: root.hasPlayer && root.activeMediaPlayer.canGoNext
                                onActivated: root.activeMediaPlayer.next()
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: 210
                        Layout.fillWidth: false
                        Layout.fillHeight: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 16
                            color: root.surface

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 10

                                IconGlyph { text: root.ico.search; color: root.muted; font.pixelSize: 16 }
                                IslandLabel { text: "Buscar apps"; font.pixelSize: 12; Layout.fillWidth: true }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.panelOpen = false
                                    root.toggleLauncher()
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 16
                            color: root.surface

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 10

                                IconGlyph { text: root.ico.cog; color: root.muted; font.pixelSize: 16 }
                                IslandLabel { text: "Ajustes"; font.pixelSize: 12; Layout.fillWidth: true }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["nm-connection-editor"])
                            }
                        }
                    }
                }

                // notifications tab
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: root.surface
                    visible: root.panelTab === "notifications"

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 10
                        clip: true
                        spacing: 8
                        model: notificationServer.trackedNotifications

                        delegate: Rectangle {
                            id: notificationCard
                            required property var modelData
                            width: ListView.view.width
                            height: notificationBody.implicitHeight + 22
                            radius: 12
                            color: cardMouse.containsMouse ? "#38383a" : root.surfaceHi

                            Behavior on color { ColorAnimation { duration: 120 } }

                            // swallows clicks so a near-miss on ✕ never reaches the
                            // island background (which would close the panel)
                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            Column {
                                id: notificationBody
                                anchors.left: parent.left
                                anchors.right: closeButton.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14
                                anchors.rightMargin: 10
                                spacing: 2

                                IslandLabel { text: modelData.appName; color: root.muted; font.pixelSize: 10 }
                                IslandLabel {
                                    text: modelData.summary
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                IslandLabel {
                                    text: modelData.body
                                    color: root.muted
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    width: parent.width
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                id: closeButton
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                height: 30
                                radius: 15
                                color: closeMouse.containsMouse ? root.track : "transparent"

                                Behavior on color { ColorAnimation { duration: 120 } }

                                IconGlyph {
                                    anchors.centerIn: parent
                                    text: root.ico.close
                                    color: closeMouse.containsMouse ? root.ink : root.muted
                                    font.pixelSize: 15
                                }

                                MouseArea {
                                    id: closeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: notificationCard.modelData.dismiss()
                                }
                            }
                        }

                        IslandLabel {
                            anchors.centerIn: parent
                            visible: notificationServer.trackedNotifications.values.length === 0
                            text: "Sin notificaciones"
                            color: root.muted
                            font.pixelSize: 12
                        }
                    }
                }

                // ── detalle Wi‑Fi
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: root.surface
                    visible: root.panelTab === "wifi"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.preferredHeight: 26
                            spacing: 10

                            IslandLabel {
                                text: Networking.wifiEnabled
                                    ? (root.wifiDevice && root.wifiDevice.scannerEnabled ? "Buscando redes…" : "Redes")
                                    : "Wi‑Fi desactivado"
                                color: root.muted
                                font.pixelSize: 11
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Item { Layout.fillWidth: true }

                            IslandSwitch {
                                checked: Networking.wifiEnabled
                                onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            model: root.wifiNetworks
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: ConnectionRow {
                                required property var modelData
                                width: ListView.view.width
                                glyph: root.wifiStrengthIcon(modelData)
                                title: modelData.name.length > 0 ? modelData.name : "(red oculta)"
                                subtitle: root.wifiNetworkStatus(modelData)
                                active: modelData.connected
                                busy: modelData.stateChanging
                                secure: root.wifiIsSecure(modelData) && !modelData.known
                                forgettable: modelData.known
                                onActivated: root.activateWifiNetwork(modelData)
                                onForgotten: modelData.forget()
                            }

                            IslandLabel {
                                anchors.centerIn: parent
                                visible: root.wifiNetworks.length === 0
                                text: Networking.wifiEnabled ? "Buscando redes…" : "Activa el Wi‑Fi para ver redes"
                                color: root.muted
                                font.pixelSize: 12
                            }
                        }

                        // contraseña de una red protegida
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.preferredHeight: root.wifiPskTarget ? 40 : 0
                            visible: root.wifiPskTarget !== null
                            radius: 12
                            color: root.surfaceHi

                            Behavior on Layout.preferredHeight {
                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                IconGlyph {
                                    text: root.ico.lock
                                    color: root.muted
                                    font.pixelSize: 13
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 24
                                    Layout.alignment: Qt.AlignVCenter

                                    IslandLabel {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: root.wifiPskInput.length === 0
                                        text: root.wifiPskTarget
                                            ? "Contraseña de " + root.wifiPskTarget.name
                                            : ""
                                        color: root.dim
                                        font.pixelSize: 12
                                    }

                                    TextInput {
                                        id: pskInput
                                        anchors.fill: parent
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: TextInput.Password
                                        color: root.ink
                                        font.family: root.uiFont
                                        font.pixelSize: 12
                                        clip: true
                                        selectByMouse: true
                                        selectionColor: "#0a84ff"
                                        text: root.wifiPskInput
                                        onTextEdited: root.wifiPskInput = text

                                        Connections {
                                            target: root
                                            function onWifiPskTargetChanged() {
                                                if (root.wifiPskTarget)
                                                    Qt.callLater(function () { pskInput.forceActiveFocus() })
                                            }
                                        }

                                        Keys.onPressed: function (event) {
                                            if (event.key === Qt.Key_Escape) {
                                                root.cancelWifiPsk()
                                                event.accepted = true
                                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                root.submitWifiPsk()
                                                event.accepted = true
                                            }
                                        }
                                    }
                                }

                                MediaButton {
                                    glyph: root.ico.check
                                    glyphSize: 15
                                    glyphColor: root.wifiPskInput.length > 0 ? "#30d158" : root.dim
                                    enabledAction: root.wifiPskInput.length > 0
                                    onActivated: root.submitWifiPsk()
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                MediaButton {
                                    glyph: root.ico.close
                                    glyphSize: 14
                                    glyphColor: root.muted
                                    onActivated: root.cancelWifiPsk()
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                    }
                }

                // ── detalle Bluetooth
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: root.surface
                    visible: root.panelTab === "bluetooth"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.preferredHeight: 26
                            spacing: 10

                            IslandLabel {
                                text: !Bluetooth.defaultAdapter ? "Sin adaptador"
                                    : !Bluetooth.defaultAdapter.enabled ? "Bluetooth desactivado"
                                    : Bluetooth.defaultAdapter.discovering ? "Buscando dispositivos…"
                                    : "Dispositivos"
                                color: root.muted
                                font.pixelSize: 11
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Item { Layout.fillWidth: true }

                            IslandSwitch {
                                checked: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled
                                onToggled: if (Bluetooth.defaultAdapter)
                                    Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            model: root.bluetoothDevices
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: ConnectionRow {
                                required property var modelData
                                width: ListView.view.width
                                glyph: root.bluetoothDeviceIcon(modelData)
                                title: modelData.name.length > 0 ? modelData.name : modelData.address
                                subtitle: root.bluetoothDeviceStatus(modelData)
                                active: modelData.connected
                                busy: modelData.pairing
                                forgettable: modelData.paired || modelData.bonded
                                onActivated: root.activateBluetoothDevice(modelData)
                                onForgotten: modelData.forget()
                            }

                            IslandLabel {
                                anchors.centerIn: parent
                                visible: root.bluetoothDevices.length === 0
                                text: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled
                                    ? "Buscando dispositivos…" : "Activa el Bluetooth para buscar"
                                color: root.muted
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Consulta rápida a Codex (cuenta de ChatGPT)
    Component {
        id: askView

        FadeIn {
            id: askRoot
            property int focusAttempts: 0

            Component.onCompleted: {
                focusAttempts = 0
                askFocusTimer.start()
                Qt.callLater(function () { askInput.forceActiveFocus() })
            }

            Timer {
                id: askFocusTimer
                interval: 140
                onTriggered: {
                    if (!root.askOpen)
                        return

                    askInput.forceActiveFocus()
                    if (!askInput.activeFocus && askRoot.focusAttempts < 6) {
                        askRoot.focusAttempts += 1
                        restart()
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 14
                anchors.bottomMargin: 14
                spacing: 10

                // ── cabecera: qué se envía y control de la sesión
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 22
                    spacing: 8

                    IconGlyph {
                        text: root.ico.ask
                        color: root.muted
                        font.pixelSize: 15
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IslandLabel {
                        text: "Preguntar"
                        color: root.muted
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Repeater {
                        model: [
                            { key: "image", on: root.askImage.length > 0, attached: true,
                              glyph: root.ico.shot, label: "captura" },
                            { key: "selection",
                              on: root.askSelection.length > 0 || root.askSelectionCandidate.length > 0,
                              attached: root.askSelection.length > 0,
                              glyph: root.ico.selection,
                              label: root.askSelection.length > 0
                                  ? root.selectionPreview(root.askSelection)
                                  : "adjuntar: " + root.selectionPreview(root.askSelectionCandidate) }
                        ]

                        delegate: Rectangle {
                            id: attachmentChip
                            required property var modelData
                            visible: modelData.on
                            Layout.preferredWidth: Math.min(chipRow.implicitWidth + 18, 260)
                            Layout.preferredHeight: 20
                            Layout.alignment: Qt.AlignVCenter
                            radius: 10
                            color: attachmentChip.modelData.attached
                                ? (attachmentMouse.containsMouse ? root.track : root.surfaceHi)
                                : (attachmentMouse.containsMouse ? root.surfaceHi : "transparent")
                            border.width: attachmentChip.modelData.attached ? 0 : 1
                            border.color: root.surfaceHi

                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                id: chipRow
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                spacing: 5

                                IconGlyph {
                                    text: attachmentChip.modelData.glyph
                                    color: attachmentChip.modelData.attached ? root.ink : root.muted
                                    font.pixelSize: 11
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                IslandLabel {
                                    text: attachmentChip.modelData.label
                                    color: attachmentChip.modelData.attached ? root.ink : root.muted
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                IconGlyph {
                                    text: attachmentChip.modelData.attached ? root.ico.close : "⇥"
                                    color: attachmentMouse.containsMouse ? root.ink : root.dim
                                    font.pixelSize: attachmentChip.modelData.attached ? 11 : 10
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            // clic: adjunta lo ofrecido, o quita lo ya adjuntado
                            MouseArea {
                                id: attachmentMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (attachmentChip.modelData.key === "image")
                                        root.askImage = ""
                                    else if (attachmentChip.modelData.attached)
                                        root.askSelection = ""
                                    else
                                        root.attachSelection()
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // acciones sobre la conversación
                    Repeater {
                        model: [
                            { key: "new", glyph: root.ico.ask, label: "nueva" },
                            { key: "copy", glyph: root.ico.copy, label: "copiar" }
                        ]

                        delegate: Rectangle {
                            id: actionChip
                            required property var modelData
                            visible: root.askMessages.length > 0
                            Layout.preferredWidth: actionRow.implicitWidth + 18
                            Layout.preferredHeight: 20
                            Layout.alignment: Qt.AlignVCenter
                            radius: 10
                            color: actionMouse.containsMouse ? root.track : root.surfaceHi

                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                id: actionRow
                                anchors.centerIn: parent
                                spacing: 5

                                IconGlyph {
                                    text: actionChip.modelData.glyph
                                    color: root.muted
                                    font.pixelSize: 11
                                }

                                IslandLabel {
                                    text: actionChip.modelData.label
                                    color: root.muted
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (actionChip.modelData.key === "new")
                                        root.newAskConversation()
                                    else
                                        root.copyAnswer()
                                }
                            }
                        }
                    }

                    IslandLabel {
                        text: root.askStatus === "thinking" ? "pensando…" : "esc"
                        color: root.dim
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter

                        SequentialAnimation on opacity {
                            running: root.askStatus === "thinking"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 620; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                        }
                    }
                }

                // ── conversación
                ListView {
                    id: conversationList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.askMessages.length > 0
                    clip: true
                    spacing: 12
                    model: root.askMessages
                    boundsBehavior: Flickable.StopAtBounds

                    onCountChanged: Qt.callLater(function () { conversationList.positionViewAtEnd() })
                    onContentHeightChanged: Qt.callLater(function () { conversationList.positionViewAtEnd() })

                    delegate: Item {
                        id: messageRow
                        required property var modelData
                        readonly property bool mine: modelData.role === "user"
                        width: ListView.view.width
                        height: bubble.height

                        Rectangle {
                            id: bubble
                            x: messageRow.mine ? messageRow.width - width : 0
                            width: messageRow.mine
                                ? Math.min(messageText.implicitWidth + 28, messageRow.width * 0.78)
                                : messageRow.width
                            height: messageText.implicitHeight + (messageRow.mine ? 18 : 4)
                            radius: 14
                            color: messageRow.mine ? root.surfaceHi : "transparent"

                            TextEdit {
                                id: messageText
                                x: messageRow.mine ? 14 : 0
                                y: messageRow.mine ? 9 : 2
                                width: bubble.width - (messageRow.mine ? 28 : 0)
                                readOnly: true
                                selectByMouse: true
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                                color: messageRow.modelData.role === "error" ? "#ff453a" : root.ink
                                selectionColor: "#0a84ff"
                                font.family: root.uiFont
                                font.pixelSize: 14
                                opacity: messageRow.modelData.text.length > 0 ? 1 : 0.45
                                text: messageRow.modelData.text.length > 0 ? messageRow.modelData.text : "…"
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 1
                    color: root.surfaceHi
                    visible: root.askMessages.length > 0
                }

                // ── entrada, siempre abajo para poder seguir preguntando
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 34

                    IslandLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.askQuery.length === 0
                        text: root.askMessages.length > 0 ? "Sigue preguntando…" : "Pregunta lo que quieras…"
                        color: root.dim
                        font.pixelSize: root.askMessages.length > 0 ? 15 : 19
                    }

                    TextInput {
                        id: askInput
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.ink
                        font.family: root.uiFont
                        font.pixelSize: root.askMessages.length > 0 ? 15 : 19
                        focus: true
                        activeFocusOnTab: true
                        clip: true
                        selectByMouse: true
                        cursorVisible: true
                        selectionColor: "#0a84ff"
                        text: root.askQuery
                        onTextEdited: root.askQuery = text

                        Keys.onPressed: function (event) {
                            if (event.key === Qt.Key_Escape) {
                                root.closeAsk()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.sendAsk()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Tab) {
                                root.attachSelection()   // adjunta el texto seleccionado
                                event.accepted = true
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Spotlight-ish launcher
    Component {
        id: launcherView

        FadeIn {
            id: launcherRoot
            property int focusAttempts: 0

            Component.onCompleted: {
                root.rebuildLauncher()
                focusAttempts = 0
                launcherFocusTimer.start()
                Qt.callLater(function () { launcherInput.forceActiveFocus() })
            }

            Timer {
                id: launcherFocusTimer
                interval: 140
                onTriggered: {
                    if (!root.launcherOpen)
                        return

                    launcherInput.forceActiveFocus()
                    if (!launcherInput.activeFocus && launcherRoot.focusAttempts < 6) {
                        launcherRoot.focusAttempts += 1
                        restart()
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 14
                anchors.bottomMargin: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 40
                    spacing: 12

                    IconGlyph {
                        text: root.launcherMode === "packages" ? root.ico.install : root.ico.search
                        color: root.launcherMode === "packages" ? "#0a84ff" : root.muted
                        font.pixelSize: 20
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        Layout.alignment: Qt.AlignVCenter

                        IslandLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.launcherQuery.length === 0
                            text: root.launcherMode === "packages"
                                ? "Buscar paquetes para instalar" : "Buscar aplicaciones"
                            color: root.dim
                            font.pixelSize: 19
                        }

                        TextInput {
                            id: launcherInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.ink
                            font.family: root.uiFont
                            font.pixelSize: 19
                            focus: true
                            activeFocusOnTab: true
                            clip: true
                            selectByMouse: true
                            cursorVisible: true
                            selectionColor: "#0a84ff"
                            text: root.launcherQuery
                            onTextEdited: {
                                root.launcherQuery = text
                                if (root.launcherMode === "packages") {
                                    root.launcherIndex = 0
                                    root.schedulePackageSearch()
                                } else {
                                    root.rebuildLauncher()
                                }
                            }

                            Keys.onPressed: function (event) {
                                if (event.key === Qt.Key_Escape) {
                                    if (root.launcherMode === "packages")
                                        root.leavePackageMode()
                                    else
                                        root.closeLauncher()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    root.launchSelected()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Down) {
                                    root.moveLauncherSelection(1)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Up) {
                                    root.moveLauncherSelection(-1)
                                    event.accepted = true
                                }
                            }
                        }
                    }

                    IslandLabel {
                        text: root.launcherMode !== "packages" ? "esc"
                            : root.aurSearching ? "buscando en AUR…" : "esc vuelve a apps"
                        color: root.dim
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter

                        SequentialAnimation on opacity {
                            running: root.aurSearching
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 620; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.surfaceHi
                }

                ListView {
                    id: launcherList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.launcherMode === "apps"
                    clip: true
                    spacing: 2
                    model: root.launcherMatches
                    currentIndex: root.launcherIndex
                    highlightMoveDuration: 140
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 42
                        radius: 10
                        color: index === root.launcherIndex ? root.surfaceHi : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 12
                            spacing: 12

                            IconImage {
                                id: appIcon
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                Layout.alignment: Qt.AlignVCenter
                                visible: appRow.modelData.isInstall !== true
                                source: appRow.modelData.icon.length > 0 ? Quickshell.iconPath(appRow.modelData.icon, true) : ""
                            }

                            IconGlyph {
                                visible: appRow.modelData.isInstall === true
                                text: root.ico.install
                                color: "#0a84ff"
                                font.pixelSize: 20
                                Layout.preferredWidth: 26
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0

                                IslandLabel {
                                    Layout.fillWidth: true
                                    text: appRow.modelData.name
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }

                                IslandLabel {
                                    Layout.fillWidth: true
                                    text: appRow.modelData.genericName || appRow.modelData.id
                                    color: root.muted
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            IconGlyph {
                                text: root.ico.enter
                                color: root.muted
                                font.pixelSize: 14
                                visible: appRow.index === root.launcherIndex
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.launcherIndex = appRow.index
                            onClicked: {
                                root.launcherIndex = appRow.index
                                root.launchSelected()
                            }
                        }
                    }

                    IslandLabel {
                        anchors.centerIn: parent
                        visible: root.launcherMatches.length === 0
                        text: "Sin resultados"
                        color: root.muted
                        font.pixelSize: 13
                    }
                }

                // ── resultados de paquetes
                ListView {
                    id: packageList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.launcherMode === "packages"
                    clip: true
                    spacing: 2
                    model: root.packageMatches
                    currentIndex: root.launcherIndex
                    boundsBehavior: Flickable.StopAtBounds
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    delegate: Rectangle {
                        id: packageRow
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 48
                        radius: 10
                        color: index === root.launcherIndex ? root.surfaceHi : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            IconGlyph {
                                text: packageRow.modelData.installed ? root.ico.installed : root.ico.package
                                color: packageRow.modelData.installed ? "#30d158" : root.muted
                                font.pixelSize: 18
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    spacing: 7

                                    IslandLabel {
                                        text: packageRow.modelData.name
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 260
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: repoLabel.implicitWidth + 12
                                        Layout.preferredHeight: 15
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: 7
                                        color: packageRow.modelData.repo === "aur" ? "#3a2a12" : root.surfaceHi

                                        IslandLabel {
                                            id: repoLabel
                                            anchors.centerIn: parent
                                            text: packageRow.modelData.repo
                                            color: packageRow.modelData.repo === "aur" ? "#ff9f0a" : root.muted
                                            font.pixelSize: 9
                                        }
                                    }

                                    IslandLabel {
                                        text: packageRow.modelData.version
                                        color: root.dim
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                IslandLabel {
                                    Layout.fillWidth: true
                                    text: packageRow.modelData.installed
                                        ? "Instalado · " + packageRow.modelData.description
                                        : packageRow.modelData.description
                                    color: packageRow.modelData.installed ? "#30d158" : root.muted
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            IslandLabel {
                                visible: packageRow.index === root.launcherIndex
                                text: packageRow.modelData.installed ? "reinstalar ↵" : "instalar ↵"
                                color: root.muted
                                font.pixelSize: 10
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.launcherIndex = packageRow.index
                            onClicked: {
                                root.launcherIndex = packageRow.index
                                root.launchSelected()
                            }
                        }
                    }

                    IslandLabel {
                        anchors.centerIn: parent
                        visible: root.packageMatches.length === 0
                        text: root.packageQuery().length < 2
                            ? "Escribe al menos dos letras"
                            : root.aurSearching ? "Buscando…" : "Ningún paquete coincide"
                        color: root.muted
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
