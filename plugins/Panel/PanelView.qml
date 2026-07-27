import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import "../../core"
import "../../services"
import "../../widgets"

FadeIn {
    id: view

    required property var plugin

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 16
        spacing: 12

        // ── cabecera
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 30
            spacing: 10

            MediaButton {
                visible: view.plugin.tab !== "controls"
                glyph: Theme.ico.back
                glyphSize: 16
                glyphColor: Theme.muted
                onActivated: {
                    Wifi.cancelPsk()
                    view.plugin.tab = "controls"
                }
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: view.plugin.tab === "notifications" ? "Notificaciones"
                    : view.plugin.tab === "wifi" ? "Wi‑Fi"
                    : view.plugin.tab === "bluetooth" ? "Bluetooth"
                    : "Centro de control"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                visible: view.plugin.tab === "notifications" && Notifs.tracked.values.length > 0
                Layout.preferredWidth: clearAllFila.implicitWidth + 20
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                radius: 12
                // Rojo al pasar por encima y con su icono: en gris sobre gris
                // y sin símbolo parecía una etiqueta más, no algo que se pulsa.
                color: clearAllMouse.containsMouse ? Theme.red : Theme.surfaceHi

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    id: clearAllFila
                    anchors.centerIn: parent
                    spacing: 5

                    IconGlyph {
                        text: Theme.ico.clearAll
                        color: clearAllMouse.containsMouse ? Theme.ink : Theme.muted
                        font.pixelSize: 13
                    }

                    IslandLabel {
                        id: clearAllLabel
                        text: "Borrar todo"
                        color: clearAllMouse.containsMouse ? Theme.ink : Theme.muted
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: clearAllMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.clear()
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 5
                Layout.fillWidth: false
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter

                Repeater {
                    model: Workspaces.list

                    delegate: Rectangle {
                        required property var modelData
                        Layout.preferredWidth: modelData.focused ? 24 : 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: modelData.focused ? Theme.ink : Theme.surfaceHi

                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.modelData.activate()
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            IslandLabel {
                text: Qt.formatDateTime(Clock.date, "HH:mm")
                color: Theme.muted
                font.pixelSize: 13
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Notifs.count > 0 ? Theme.ico.bell : Theme.ico.bellOutline
                glyphSize: 15
                glyphColor: view.plugin.tab === "notifications" ? Theme.ink : Theme.muted
                Layout.alignment: Qt.AlignVCenter
                onActivated: {
                    view.plugin.tab = view.plugin.tab === "notifications" ? "controls" : "notifications"
                    if (view.plugin.tab === "notifications")
                        Notifs.markRead()
                }
            }

            MediaButton {
                glyph: Theme.ico.chevronUp
                glyphSize: 16
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── tarjetas de conmutación
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 78
            spacing: 10
            visible: view.plugin.tab === "controls"

            IslandTile {
                id: wifiTile
                Layout.fillWidth: true
                Layout.fillHeight: true
                // el círculo del icono lleva su propio MouseArea encima, así
                // que pulsarlo conmuta la radio y el resto abre el detalle
                onPulsada: view.plugin.openTab("wifi")

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
                            color: Networking.wifiEnabled ? Theme.blue : Theme.surfaceHi

                            Behavior on color { ColorAnimation { duration: 180 } }

                            IconGlyph {
                                anchors.centerIn: parent
                                text: Networking.wifiEnabled ? Theme.ico.wifi : Theme.ico.wifiOff
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
                                text: Networking.wifiEnabled ? Wifi.name : "Desactivado"
                                color: Theme.muted
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        IconGlyph {
                            text: Theme.ico.forward
                            color: wifiTile.hovered ? Theme.ink : Theme.dim
                            font.pixelSize: 14
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }

            IslandTile {
                id: btTile
                Layout.fillWidth: true
                Layout.fillHeight: true
                onPulsada: view.plugin.openTab("bluetooth")

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
                            color: Bt.adapter && Bt.adapter.enabled ? Theme.blue : Theme.surfaceHi

                            Behavior on color { ColorAnimation { duration: 180 } }

                            IconGlyph {
                                anchors.centerIn: parent
                                text: Bt.adapter && Bt.adapter.enabled
                                    ? Theme.ico.bluetooth : Theme.ico.bluetoothOff
                                font.pixelSize: 15
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (Bt.adapter) Bt.adapter.enabled = !Bt.adapter.enabled
                            }
                        }

                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Layout.fillHeight: false

                            IslandLabel { text: "Bluetooth"; font.pixelSize: 12; font.weight: Font.DemiBold }
                            IslandLabel {
                                text: Bt.adapter
                                    ? (Bt.adapter.enabled ? "Activado" : "Desactivado")
                                    : "Sin adaptador"
                                color: Theme.muted
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        IconGlyph {
                            text: Theme.ico.forward
                            color: btTile.hovered ? Theme.ink : Theme.dim
                            font.pixelSize: 14
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }

            IslandTile {
                Layout.fillWidth: true
                Layout.fillHeight: true
                pulsable: false

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
                            text: Audio.muted ? "Silenciado" : Audio.volume + "%"
                            color: Theme.muted
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
                            color: Theme.surfaceHi
                            clip: true

                            Rectangle {
                                width: volumeSliderTrack.width * Math.max(0, Math.min(100, Audio.volume)) / 100
                                height: parent.height
                                radius: parent.radius
                                color: Audio.muted ? Theme.dim : Theme.ink

                                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }

                            IconGlyph {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: Audio.muted ? Theme.ico.volOff : Theme.ico.volMed
                                color: Audio.volume > 12 && !Audio.muted ? "#000000" : Theme.muted
                                font.pixelSize: 13
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function (mouse) { Audio.setVolume(mouse.x / width * 100) }
                            onPositionChanged: function (mouse) {
                                if (pressed)
                                    Audio.setVolume(mouse.x / width * 100)
                            }
                        }
                    }
                }
            }
        }

        // ── reproducción, compacta ────────────────────────────────
        // Ocupaba media pestaña con una carátula de 52 px. En el centro de
        // control de macOS "Reproduciendo" es una fila discreta, no el
        // protagonista: aquí baja a 62 px de alto y gana el ancho entero.
        IslandTile {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 62
            visible: view.plugin.tab === "controls"
            pulsable: false

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 12

                Artwork {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    placeholder: Theme.surfaceHi
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    IslandLabel {
                        Layout.fillWidth: true
                        text: Media.hasPlayer && Media.activePlayer.trackTitle.length > 0
                            ? Media.activePlayer.trackTitle : "Nada en reproducción"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    IslandLabel {
                        Layout.fillWidth: true
                        text: Media.hasPlayer ? Media.activePlayer.trackArtist : ""
                        color: Theme.muted
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                Visualizer {
                    visible: Media.isPlaying
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: 12
                    Layout.rightMargin: 2
                }

                MediaButton {
                    glyph: Theme.ico.prev
                    glyphSize: 16
                    glyphColor: Theme.muted
                    enabledAction: Media.hasPlayer && Media.activePlayer.canGoPrevious
                    onActivated: Media.activePlayer.previous()
                    Layout.alignment: Qt.AlignVCenter
                }

                MediaButton {
                    glyph: Media.isPlaying ? Theme.ico.pause : Theme.ico.play
                    glyphSize: 21
                    enabledAction: Media.hasPlayer && Media.activePlayer.canTogglePlaying
                    onActivated: Media.activePlayer.togglePlaying()
                    Layout.alignment: Qt.AlignVCenter
                }

                MediaButton {
                    glyph: Theme.ico.next
                    glyphSize: 16
                    glyphColor: Theme.muted
                    enabledAction: Media.hasPlayer && Media.activePlayer.canGoNext
                    onActivated: Media.activePlayer.next()
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }

        // ── accesos directos, en rejilla ──────────────────────────
        // Cuatro filas apiladas ocupaban una columna entera; en dos por dos
        // caben en una franja y se leen de un vistazo.
        RowLayout {
            Layout.fillWidth: true
            // altura propia: con fillHeight se aplastaban y los rótulos se
            // salían de la tarjeta
            Layout.fillHeight: false
            Layout.preferredHeight: 40
            visible: view.plugin.tab === "controls"
            spacing: 10

            Repeater {
                model: [
                    { id: "apps",  nombre: "Buscar apps", glifo: Theme.ico.search,  color: Theme.muted },
                    { id: "juego", nombre: "Mazmorra",    glifo: 0xF04E5,           color: "#ff9f0a" },
                    { id: "tema",  nombre: "Tema",        glifo: Theme.ico.palette, color: "#c78fff" },
                    { id: "sistema", nombre: "Sistema",   glifo: 0xF035B,           color: "#0a84ff" },
                    { id: "ajustes", nombre: "Ajustes",   glifo: Theme.ico.cog,     color: Theme.muted }
                ]

                delegate: IslandTile {
                    id: acceso
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    radius: 12

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 7

                        IconGlyph {
                            text: typeof acceso.modelData.glifo === "number"
                                ? String.fromCodePoint(acceso.modelData.glifo)
                                : acceso.modelData.glifo
                            color: acceso.modelData.color
                            font.pixelSize: 15
                        }

                        IslandLabel {
                            text: acceso.modelData.nombre
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    onPulsada: {
                        view.plugin.close()
                        const cual = acceso.modelData.id
                        if (cual === "apps" && view.plugin.launcher)
                            view.plugin.launcher.toggle()
                        else if (cual === "juego" && view.plugin.juego)
                            view.plugin.juego.toggle()
                        else if (cual === "tema" && view.plugin.theme)
                            view.plugin.theme.toggle()
                        else if (cual === "sistema" && view.plugin.sistema)
                            view.plugin.sistema.toggle()
                        else if (cual === "ajustes" && view.plugin.ajustes)
                            view.plugin.ajustes.toggle()
                    }
                }
            }
        }

        // ── pestaña de notificaciones
        IslandTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            pulsable: false
            visible: view.plugin.tab === "notifications"

            ListView {
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                spacing: 8
                model: Notifs.tracked

                delegate: Rectangle {
                    id: notificationCard
                    required property var modelData
                    readonly property var actions: Notifs.buttons(modelData)
                    readonly property string icon: Notifs.iconFor(modelData)

                    width: ListView.view.width
                    height: notificationBody.implicitHeight + 22
                        + (actions.length > 0 ? 28 : 0)
                    radius: 12
                    color: cardMouse.containsMouse ? "#38383a" : Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: 120 } }

                    // Además de llevar a la aplicación, se traga los clics para
                    // que un fallo cerca de la ✕ no llegue al fondo de la
                    // island (que cerraría el panel).
                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.activate(notificationCard.modelData)
                    }

                    Image {
                        id: cardIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        width: 20
                        height: 20
                        source: notificationCard.icon
                        sourceSize.width: 40
                        sourceSize.height: 40
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }

                    Column {
                        id: notificationBody
                        anchors.left: cardIcon.visible ? cardIcon.right : parent.left
                        anchors.right: closeButton.left
                        anchors.top: parent.top
                        anchors.topMargin: 11
                        anchors.leftMargin: cardIcon.visible ? 10 : 14
                        anchors.rightMargin: 10
                        spacing: 2

                        IslandLabel {
                            text: notificationCard.modelData.appName
                            color: Theme.muted
                            font.pixelSize: 10
                        }
                        IslandLabel {
                            text: notificationCard.modelData.summary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        IslandLabel {
                            text: notificationCard.modelData.body
                            color: Theme.muted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            width: parent.width
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    // los botones que manda la aplicación
                    Row {
                        anchors.left: notificationBody.left
                        anchors.top: notificationBody.bottom
                        anchors.topMargin: 6
                        spacing: 6
                        visible: notificationCard.actions.length > 0

                        Repeater {
                            model: notificationCard.actions

                            delegate: Rectangle {
                                id: cardAction
                                required property var modelData
                                width: Math.min(cardActionLabel.implicitWidth + 20, 160)
                                height: 22
                                radius: 11
                                color: cardActionMouse.containsMouse ? Theme.blue : Theme.track

                                Behavior on color { ColorAnimation { duration: 120 } }

                                IslandLabel {
                                    id: cardActionLabel
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: cardAction.modelData.text
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    id: cardActionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Notifs.invokeAction(notificationCard.modelData,
                                                                   cardAction.modelData)
                                }
                            }
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
                        color: closeMouse.containsMouse ? Theme.track : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        IconGlyph {
                            anchors.centerIn: parent
                            text: Theme.ico.close
                            color: closeMouse.containsMouse ? Theme.ink : Theme.muted
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
                    visible: Notifs.tracked.values.length === 0
                    text: "Sin notificaciones"
                    color: Theme.muted
                    font.pixelSize: 12
                }
            }
        }

        // ── detalle Wi‑Fi
        IslandTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            pulsable: false
            visible: view.plugin.tab === "wifi"

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
                            ? (Wifi.device && Wifi.device.scannerEnabled ? "Buscando redes…" : "Redes")
                            : "Wi‑Fi desactivado"
                        color: Theme.muted
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
                    model: Wifi.networks
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: ConnectionRow {
                        required property var modelData
                        width: ListView.view.width
                        glyph: Wifi.strengthIcon(modelData)
                        title: modelData.name.length > 0 ? modelData.name : "(red oculta)"
                        subtitle: Wifi.status(modelData)
                        active: modelData.connected
                        busy: modelData.stateChanging
                        secure: Wifi.isSecure(modelData) && !modelData.known
                        forgettable: modelData.known
                        onActivated: Wifi.activate(modelData)
                        onForgotten: modelData.forget()
                    }

                    IslandLabel {
                        anchors.centerIn: parent
                        visible: Wifi.networks.length === 0
                        text: Networking.wifiEnabled ? "Buscando redes…" : "Activa el Wi‑Fi para ver redes"
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }

                // contraseña de una red protegida
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: Wifi.pskTarget ? 40 : 0
                    visible: Wifi.pskTarget !== null
                    radius: 12
                    color: Theme.surfaceHi

                    Behavior on Layout.preferredHeight {
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        IconGlyph {
                            text: Theme.ico.lock
                            color: Theme.muted
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter

                            IslandLabel {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: Wifi.pskInput.length === 0
                                text: Wifi.pskTarget ? "Contraseña de " + Wifi.pskTarget.name : ""
                                color: Theme.dim
                                font.pixelSize: 12
                            }

                            TextInput {
                                id: pskInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                color: Theme.ink
                                font.family: Theme.uiFont
                                font.pixelSize: 12
                                clip: true
                                selectByMouse: true
                                selectionColor: Theme.blue
                                text: Wifi.pskInput
                                onTextEdited: Wifi.pskInput = text

                                Connections {
                                    target: Wifi
                                    function onPskTargetChanged() {
                                        if (Wifi.pskTarget)
                                            Qt.callLater(function () { pskInput.forceActiveFocus() })
                                    }
                                }

                                Keys.onPressed: function (event) {
                                    if (event.key === Qt.Key_Escape) {
                                        Wifi.cancelPsk()
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        Wifi.submitPsk()
                                        event.accepted = true
                                    }
                                }
                            }
                        }

                        MediaButton {
                            glyph: Theme.ico.check
                            glyphSize: 15
                            glyphColor: Wifi.pskInput.length > 0 ? Theme.green : Theme.dim
                            enabledAction: Wifi.pskInput.length > 0
                            onActivated: Wifi.submitPsk()
                            Layout.alignment: Qt.AlignVCenter
                        }

                        MediaButton {
                            glyph: Theme.ico.close
                            glyphSize: 14
                            glyphColor: Theme.muted
                            onActivated: Wifi.cancelPsk()
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }

        // ── detalle Bluetooth
        IslandTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            pulsable: false
            visible: view.plugin.tab === "bluetooth"

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
                        text: !Bt.adapter ? "Sin adaptador"
                            : !Bt.adapter.enabled ? "Bluetooth desactivado"
                            : Bt.adapter.discovering ? "Buscando dispositivos…"
                            : "Dispositivos"
                        color: Theme.muted
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    IslandSwitch {
                        checked: Bt.adapter && Bt.adapter.enabled
                        onToggled: if (Bt.adapter) Bt.adapter.enabled = !Bt.adapter.enabled
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: Bt.devices
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: ConnectionRow {
                        required property var modelData
                        width: ListView.view.width
                        glyph: Bt.deviceIcon(modelData)
                        title: modelData.name.length > 0 ? modelData.name : modelData.address
                        subtitle: Bt.deviceStatus(modelData)
                        active: modelData.connected
                        busy: modelData.pairing
                        forgettable: modelData.paired || modelData.bonded
                        onActivated: Bt.activate(modelData)
                        onForgotten: modelData.forget()
                    }

                    IslandLabel {
                        anchors.centerIn: parent
                        visible: Bt.devices.length === 0
                        text: Bt.adapter && Bt.adapter.enabled
                            ? "Buscando dispositivos…" : "Activa el Bluetooth para buscar"
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
