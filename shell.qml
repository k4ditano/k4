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

Scope {
    id: root

    // ── los módulos ───────────────────────────────────────────────
    // Las referencias cruzadas se inyectan aquí, así ningún plugin importa a
    // otro: sabe que le pasan "un panel", no de qué carpeta sale.
    IdlePlugin   { id: idlePlugin }
    VolumePlugin { id: volumePlugin }
    ClockPlugin  { id: clockPlugin }
    PlayerPlugin { id: playerPlugin; panel: panelPlugin }
    ToastPlugin  { id: toastPlugin }
    PanelPlugin  { id: panelPlugin; launcher: launcherPlugin }
    LauncherPlugin { id: launcherPlugin; panel: panelPlugin }
    AskPlugin    { id: askPlugin; panel: panelPlugin; launcher: launcherPlugin }

    readonly property var plugins: [
        idlePlugin,
        volumePlugin,
        clockPlugin,
        playerPlugin,
        toastPlugin,
        panelPlugin,
        launcherPlugin,
        askPlugin
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
            if (p.active && (best === null || p.priority > best.priority))
                best = p
        }
        return best
    }

    readonly property int islandWidth: activePlugin ? activePlugin.islandWidth : 176
    readonly property int islandHeight: activePlugin ? activePlugin.islandHeight : Theme.baseHeight

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
    }

    // ── IPC ───────────────────────────────────────────────────────
    // Cada módulo publica su propio target (k4.panel, k4.ask, k4.launcher).
    // Esto es la capa de compatibilidad: mantiene el target `k4` con los
    // nombres de siempre para no romper los atajos ya configurados.
    IpcHandler {
        target: "k4"
        function toggleLauncher(): void { launcherPlugin.toggle() }
        function install(query: string): void { launcherPlugin.openPackageSearch(query) }
        function search(query: string): void {
            if (!launcherPlugin.open)
                launcherPlugin.toggle()
            launcherPlugin.query = query
            launcherPlugin.rebuild()
        }
        function togglePanel(): void { panelPlugin.toggle("controls") }
        function toggleNotifications(): void { panelPlugin.toggle("notifications") }
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

            WlrLayershell.keyboardFocus: root.activePlugin && root.activePlugin.grabKeyboard
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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
            mask: Region { item: island }

            Item {
                id: island
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, root.islandWidth + Theme.wing * 2)
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
                    onHoveredChanged: {
                        if (hovered) {
                            hoverExitTimer.stop()
                            panelPlugin.hoverEntered()
                            Island.hovered = true
                            Notifs.holdToast()
                        } else {
                            hoverExitTimer.restart()
                            // solo se arma al salir, así que un panel abierto
                            // por atajo sigue abierto hasta que lo toques
                            panelPlugin.hoverExited()
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

}
