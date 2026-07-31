//  k4 — host de la island.
//
//  Aquí no hay lógica de ningún módulo: esto monta la superficie, dibuja la
//  silueta y decide qué plugin se queda la island. Añadir un módulo es crear
//  una carpeta en plugins/ y sumarlo a la lista de abajo.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "core"
import "services"
import "plugins/Idle"
import "plugins/Volume"
import "plugins/Clock"
import "plugins/Player"
import "plugins/Toast"
import "plugins/Panel"
import "plugins/Launcher"
import "plugins/Ask"
import "plugins/HyprTheme"
import "plugins/Weather"
import "plugins/Tray"
import "plugins/Game"
import "plugins/Settings"
import "plugins/Clipboard"
import "plugins/System"
import "plugins/Files"
import "plugins/Keys"
import "plugins/Windows"
import "plugins/Session"
import "plugins/Captura"

Scope {
    id: root

    // ── los módulos ───────────────────────────────────────────────
    // Las referencias cruzadas se inyectan aquí, así ningún plugin importa a
    // otro: sabe que le pasan "un panel", no de qué carpeta sale.
    IdlePlugin   { id: idlePlugin; habilitado: PluginManager.estaHabilitado("idle"); tray: trayPlugin }
    VolumePlugin { id: volumePlugin; habilitado: PluginManager.estaHabilitado("volume") }
    ClockPlugin  { id: clockPlugin; habilitado: PluginManager.estaHabilitado("clock"); tray: trayPlugin; juego: gamePlugin }
    PlayerPlugin { id: playerPlugin; habilitado: PluginManager.estaHabilitado("player"); panel: panelPlugin; tray: trayPlugin; juego: gamePlugin }
    ToastPlugin  { id: toastPlugin; habilitado: PluginManager.estaHabilitado("toast") }
    PanelPlugin  { id: panelPlugin; habilitado: PluginManager.estaHabilitado("panel"); launcher: launcherPlugin; theme: themePlugin; weather: weatherPlugin; ajustes: settingsPlugin; juego: gamePlugin; sistema: systemPlugin }
    LauncherPlugin { id: launcherPlugin; habilitado: PluginManager.estaHabilitado("launcher"); panel: panelPlugin }
    AskPlugin    { id: askPlugin; habilitado: PluginManager.estaHabilitado("ask"); panel: panelPlugin; launcher: launcherPlugin }
    HyprThemePlugin { id: themePlugin; habilitado: PluginManager.estaHabilitado("hyprtheme"); panel: panelPlugin }
    WeatherPlugin { id: weatherPlugin; habilitado: PluginManager.estaHabilitado("weather"); panel: panelPlugin }
    TrayPlugin   { id: trayPlugin; habilitado: PluginManager.estaHabilitado("tray"); panel: panelPlugin }
    GamePlugin   { id: gamePlugin; habilitado: PluginManager.estaHabilitado("game"); panel: panelPlugin }
    SettingsPlugin { id: settingsPlugin; habilitado: PluginManager.estaHabilitado("settings"); panel: panelPlugin }
    ClipboardPlugin { id: clipboardPlugin; habilitado: PluginManager.estaHabilitado("clipboard"); panel: panelPlugin }
    SystemPlugin { id: systemPlugin; habilitado: PluginManager.estaHabilitado("system"); panel: panelPlugin }
    FilesPlugin { id: filesPlugin; habilitado: PluginManager.estaHabilitado("files"); panel: panelPlugin }
    KeysPlugin { id: keysPlugin; habilitado: PluginManager.estaHabilitado("keys"); panel: panelPlugin }
    WindowsPlugin { id: windowsPlugin; habilitado: PluginManager.estaHabilitado("windows"); panel: panelPlugin }
    SessionPlugin { id: sessionPlugin; habilitado: PluginManager.estaHabilitado("session"); panel: panelPlugin }
    CapturaPlugin { id: capturaPlugin; habilitado: PluginManager.estaHabilitado("captura"); panel: panelPlugin }

    readonly property var plugins: [
        idlePlugin,
        volumePlugin,
        clockPlugin,
        playerPlugin,
        toastPlugin,
        panelPlugin,
        launcherPlugin,
        askPlugin,
        themePlugin,
        weatherPlugin,
        trayPlugin,
        gamePlugin,
        settingsPlugin,
        clipboardPlugin,
        systemPlugin,
        filesPlugin,
        keysPlugin,
        windowsPlugin,
        sessionPlugin,
        capturaPlugin
    ]

    // ── quién se queda la island ──────────────────────────────────
    // Gana el activo de mayor prioridad. El binding se recalcula solo cuando
    // cualquier plugin cambia su `active`.
    readonly property var activePlugin: {
        if (Island.debugMode.length > 0) {
            for (let i = 0; i < plugins.length; ++i) {
                if (plugins[i].name === Island.debugMode)
                    return plugins[i]
            }
        }

        let best = null
        for (let i = 0; i < plugins.length; ++i) {
            const p = plugins[i]
            if (p.habilitado && p.active
                    && (best === null || p.priority > best.priority))
                best = p
        }
        return best
    }

    readonly property int islandWidth: activePlugin ? activePlugin.islandWidth : 176
    readonly property int islandHeight: activePlugin ? activePlugin.islandHeight : Theme.baseHeight

    // Deshabilitar un plugin también cierra su estado interactivo. No se
    // destruye el objeto QML —las referencias entre módulos siguen siendo
    // estables—, pero deja de pedir la island y libera su vista.
    Connections {
        target: PluginManager
        function onCambiado(id, habilitado) {
            if (habilitado)
                return
            for (let i = 0; i < root.plugins.length; ++i) {
                const p = root.plugins[i]
                if (p.name === id && typeof p.close === "function") {
                    try { p.close() } catch (e) { PluginManager.registrarError(id, e) }
                }
            }
        }
    }

    // Clic en el fondo: lo atiende el plugin activo si lo pide; si no, abre el
    // centro de control.
    function backgroundTap() {
        const p = activePlugin
        if (p && p.handlesBackgroundTap)
            p.backgroundTapped()
        else
            panelPlugin.toggle()
    }

    // Los singletons de QML son perezosos: sin tocarlos no arrancan sus
    // procesos ni registran nada (el servidor de notificaciones, por ejemplo).
    Component.onCompleted: {
        void Audio.volume
        void Wifi.name
        void Bt.adapter
        void Notifs.count
        void Media.hasPlayer
        void Clock.date
        void Workspaces.list
        void Weather.located
        void Tray.count
        void Game.cargado
        void Idioma.cargado
        void Settings.cargado
        void PluginManager.cargado
        void Tokens.cargado
        void Clipboard.cargado
        void Ventanas.count
        void Captura.carpetaFotos
        void Modulos.count
    }

    // ── IPC ───────────────────────────────────────────────────────
    // Cada módulo publica su propio target (k4.panel, k4.ask, k4.launcher).
    // Esto es la capa de compatibilidad: mantiene el target `k4` con los
    // nombres de siempre para no romper los atajos ya configurados.
    IpcHandler {
        target: "k4"
        function toggleLauncher(): void { launcherPlugin.toggle() }
        function clipboard(): void { clipboardPlugin.toggle() }
        function system(): void { systemPlugin.toggle() }
        function files(): void { filesPlugin.toggle() }
        function keys(): void { keysPlugin.toggle() }
        function windows(): void { windowsPlugin.toggle() }
        function install(query: string): void { launcherPlugin.openPackageSearch(query) }
        function search(query: string): void {
            if (!launcherPlugin.open)
                launcherPlugin.toggle()
            launcherPlugin.query = query
            launcherPlugin.rebuild()
        }
        function togglePanel(): void { panelPlugin.toggle("controls") }
        function toggleNotifications(): void { panelPlugin.toggle("notifications") }
        function pluginEnable(id: string): void { PluginManager.habilitar(id) }
        function pluginDisable(id: string): void { PluginManager.deshabilitar(id) }
        function pluginToggle(id: string): void { PluginManager.alternar(id) }
        function pluginStatus(): void {
            console.log(JSON.stringify(PluginManager.catalogo.map(function (m) {
                return { id: m.id, enabled: PluginManager.estaHabilitado(m.id),
                         error: PluginManager.errores[m.id] || "" }
            })))
        }
        function wifi(): void { panelPlugin.openTab("wifi") }
        function bluetooth(): void { panelPlugin.openTab("bluetooth") }
        function clearNotifications(): void { Notifs.clear() }
        function ask(): void {
            if (askPlugin.open) askPlugin.close()
            else askPlugin.openAsk(false)
        }
        function askSelection(): void { askPlugin.openAsk(true) }
        function askNow(question: string): void {
            askPlugin.openAsk(false)
            askPlugin.query = question
            askPlugin.send()
        }
        function askFollowUp(question: string): void {
            if (!askPlugin.open)
                askPlugin.openAsk(false)
            askPlugin.query = question
            askPlugin.send()
        }
        function askScreen(): void { askPlugin.withScreenshot() }
        function askRegion(): void { askPlugin.withRegion() }
        function togglePlay(): void { Media.togglePlaying() }
        function nextTrack(): void { Media.siguiente() }
        function prevTrack(): void { Media.anterior() }
        function theme(): void { themePlugin.toggle() }
        function weather(): void { weatherPlugin.toggle() }
        function tray(): void { trayPlugin.toggle() }
        function game(): void { gamePlugin.toggle() }
        function settings(): void { settingsPlugin.toggle() }
        function session(): void { sessionPlugin.toggle() }
        function lock(): void { Sesion.bloquear() }
        function setMode(mode: string): void { Island.debugMode = mode }
    }

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

            //  Exclusivo solo para lo que se escribe; el resto, bajo demanda.
            //  Poner Exclusive en todos los módulos abribles dejaba el teclado
            //  secuestrado mientras tuvieras cualquiera abierto: no se podía
            //  escribir en ninguna ventana.
            WlrLayershell.keyboardFocus: {
                //  Con un diálogo del sistema delante, el teclado es suyo.
                //
                //  Apartar la island de la vista no bastaba: seguía teniendo el
                //  foco en exclusiva, así que el selector de ficheros se veía
                //  pero no se podía ni escribir en él ni cerrarlo con Escape.
                if (Island.apartada)
                    return WlrKeyboardFocus.None
                const p = root.activePlugin
                if (!p)
                    return WlrKeyboardFocus.None
                if (p.grabKeyboard)
                    return WlrKeyboardFocus.Exclusive
                if (p.tecladoOpcional)
                    return WlrKeyboardFocus.OnDemand
                return WlrKeyboardFocus.None
            }

            // se reserva solo la franja plegada: las ventanas nunca se meten
            // bajo la píldora, y todo lo que crece por encima flota
            exclusiveZone: Theme.baseHeight

            // Redimensionar una layer surface cuesta un ciclo configure/ack, así
            // que hacerlo por frame es lo que hacía parpadear el panel. La
            // superficie crece una vez al empezar y encoge una vez al acabar;
            // entre medias solo se anima la island dentro de ella.
            readonly property int targetHeight: Math.min(Theme.maxIslandHeight, root.islandHeight + 2)
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
            //  Sin la island, la ventana no acepta ni un clic.
            //
            //  No basta con dejar de dibujarla: la región de entrada seguía
            //  siendo la suya, así que un selector de ficheros que le quedara
            //  debajo perdía todos los clics de esa franja sin que se viera por
            //  qué. Con la región vacía, el ratón pasa de largo.
            mask: Region { item: Island.apartada ? null : island }

            Item {
                id: island
                anchors.top: parent.top

                // Ver services/Island.qml: apartarse para las capturas y
                // mientras haya un diálogo del sistema abierto.
                opacity: Island.apartada ? 0 : 1

                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, root.islandWidth + Theme.wing * 2)
                height: root.islandHeight

                readonly property real bodyRadius: Math.min(32, height / 2)

                // ESC cierra el módulo que esté abierto, sea cual sea.
                //
                // Va aquí y no en cada vista por dos razones: los módulos que
                // vengan después lo heredan sin hacer nada, y las vistas que ya
                // tratan la tecla —el lanzador, el portapapeles, la clave de
                // wifi— la consumen antes de llegar hasta aquí, que es
                // justamente lo que se quiere: primero cancela lo de dentro y
                // solo después cierra el módulo.
                focus: true

                Keys.onPressed: function (ev) {
                    if (ev.key !== Qt.Key_Escape)
                        return
                    const p = root.activePlugin
                    if (p && typeof p.close === "function") {
                        p.close()
                        ev.accepted = true
                    }
                }

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
                    onHoveredChanged: {
                        if (hovered) {
                            hoverExitTimer.stop()
                            root.holdHoverExit()
                            Island.hovered = true
                            Notifs.holdToast()
                        } else {
                            hoverExitTimer.restart()
                            root.armHoverExit()
                            Notifs.resumeToast()
                        }
                    }
                }

                // clic derecho en cualquier parte → centro de control
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: panelPlugin.toggle()
                }

                // ── la silueta: cuerpo + esquinas invertidas que funden con el borde
                Shape {
                    anchors.fill: parent
                    // CurveRenderer suaviza mejor, pero descarta las esquinas
                    // invertidas (las alas), así que se antialiasa con MSAA.
                    antialiasing: true
                    layer.enabled: true
                    layer.samples: 8
                    layer.smooth: true

                    ShapePath {
                        id: islandPath
                        fillColor: Theme.islandBg
                        strokeWidth: 0
                        strokeColor: "transparent"

                        readonly property real w: island.width
                        readonly property real h: island.height
                        readonly property real r: island.bodyRadius
                        readonly property real g: Math.min(Theme.wing, island.height / 2)

                        startX: 0
                        startY: 0

                        // esquina invertida izquierda
                        PathArc {
                            x: islandPath.g
                            y: islandPath.g
                            radiusX: islandPath.g
                            radiusY: islandPath.g
                            direction: PathArc.Clockwise
                        }

                        PathLine { x: islandPath.g; y: islandPath.h - islandPath.r }

                        // inferior izquierda
                        PathArc {
                            x: islandPath.g + islandPath.r
                            y: islandPath.h
                            radiusX: islandPath.r
                            radiusY: islandPath.r
                            direction: PathArc.Counterclockwise
                        }

                        PathLine { x: islandPath.w - islandPath.g - islandPath.r; y: islandPath.h }

                        // inferior derecha
                        PathArc {
                            x: islandPath.w - islandPath.g
                            y: islandPath.h - islandPath.r
                            radiusX: islandPath.r
                            radiusY: islandPath.r
                            direction: PathArc.Counterclockwise
                        }

                        PathLine { x: islandPath.w - islandPath.g; y: islandPath.g }

                        // esquina invertida derecha
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

                // ── zona de contenido (dentro del cuerpo, sin las alas)
                Item {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.wing
                    anchors.rightMargin: Theme.wing
                    clip: true

                    // Debajo de toda vista: los botones y sliders se quedan sus
                    // clics, lo que no coja nadie cae aquí.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.backgroundTap()
                    }

                    // Se dispone al tamaño final y se destapa con el clip, así
                    // que no hay recálculo de layout durante la animación.
                    Item {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.islandWidth
                        height: root.islandHeight

                        Repeater {
                            model: root.plugins

                            delegate: Loader {
                                required property var modelData
                                anchors.fill: parent
                                active: modelData === root.activePlugin && modelData.viewLoaded
                                sourceComponent: modelData.view
                                onStatusChanged: {
                                    if (status === Loader.Error)
                                        PluginManager.registrarError(
                                            modelData.name, "No se pudo cargar la vista")
                                    else if (status === Loader.Ready)
                                        PluginManager.limpiarError(modelData.name)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: hoverExitTimer
        interval: 240
        onTriggered: Island.hovered = false
    }

    // ── salida del ratón ──────────────────────────────────────────
    // Los módulos que se abren con el ratón se van al sacarlo, pero cada uno
    // decide qué hacer: aquí solo se cuenta el tiempo y se avisa al activo.
    function armHoverExit() {
        const p = activePlugin
        if (!p || !p.closeOnHoverExit)
            return

        pluginHoverExitTimer.interval = p.hoverExitDelay
        pluginHoverExitTimer.restart()
    }

    function holdHoverExit() { pluginHoverExitTimer.stop() }

    Timer {
        id: pluginHoverExitTimer
        interval: 700
        onTriggered: {
            const p = root.activePlugin
            if (p && p.closeOnHoverExit)
                p.hoverTimedOut()
        }
    }

}
