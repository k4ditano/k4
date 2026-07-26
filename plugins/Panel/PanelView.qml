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
                Layout.preferredWidth: clearAllLabel.implicitWidth + 22
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                radius: 12
                color: clearAllMouse.containsMouse ? Theme.track : Theme.surfaceHi

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: clearAllLabel
                    anchors.centerIn: parent
                    text: "Borrar todo"
                    color: clearAllMouse.containsMouse ? Theme.ink : Theme.muted
                    font.pixelSize: 11
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

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: wifiTileMouse.containsMouse ? Theme.surfaceHi : Theme.surface

                Behavior on color { ColorAnimation { duration: 140 } }

                // debajo del contenido: el círculo tiene su propio MouseArea
                // encima, así que pulsarlo conmuta y el resto abre el detalle
                MouseArea {
                    id: wifiTileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.plugin.openTab("wifi")
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
                            color: wifiTileMouse.containsMouse ? Theme.ink : Theme.dim
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
                color: btTileMouse.containsMouse ? Theme.surfaceHi : Theme.surface

                Behavior on color { ColorAnimation { duration: 140 } }

                MouseArea {
                    id: btTileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.plugin.openTab("bluetooth")
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
                            color: btTileMouse.containsMouse ? Theme.ink : Theme.dim
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
                color: Theme.surface

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

        // ── reproducción + accesos directos
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            visible: view.plugin.tab === "controls"

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: Theme.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Artwork {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        Layout.alignment: Qt.AlignVCenter
                        placeholder: Theme.surfaceHi
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        IslandLabel {
                            Layout.fillWidth: true
                            text: Media.hasPlayer && Media.activePlayer.trackTitle.length > 0
                                ? Media.activePlayer.trackTitle : "Nada en reproducción"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        IslandLabel {
                            Layout.fillWidth: true
                            text: Media.hasPlayer ? Media.activePlayer.trackArtist : ""
                            color: Theme.muted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    MediaButton {
                        glyph: Theme.ico.prev
                        glyphSize: 18
                        glyphColor: Theme.muted
                        enabledAction: Media.hasPlayer && Media.activePlayer.canGoPrevious
                        onActivated: Media.activePlayer.previous()
                        Layout.alignment: Qt.AlignVCenter
                    }

                    MediaButton {
                        glyph: Media.isPlaying ? Theme.ico.pause : Theme.ico.play
                        glyphSize: 22
                        enabledAction: Media.hasPlayer && Media.activePlayer.canTogglePlaying
                        onActivated: Media.activePlayer.togglePlaying()
                        Layout.alignment: Qt.AlignVCenter
                    }

                    MediaButton {
                        glyph: Theme.ico.next
                        glyphSize: 18
                        glyphColor: Theme.muted
                        enabledAction: Media.hasPlayer && Media.activePlayer.canGoNext
                        onActivated: Media.activePlayer.next()
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
                    color: Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        IconGlyph { text: Theme.ico.search; color: Theme.muted; font.pixelSize: 16 }
                        IslandLabel { text: "Buscar apps"; font.pixelSize: 12; Layout.fillWidth: true }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.plugin.close()
                            if (view.plugin.launcher)
                                view.plugin.launcher.toggle()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: Weather.current
                                ? Weather.icon(Weather.current.code, Weather.current.isDay)
                                : String.fromCodePoint(0xE374)
                            color: Theme.muted
                            font.family: Theme.iconFont
                            font.pixelSize: 16
                        }

                        IslandLabel {
                            text: Weather.current ? Weather.current.temp + "°" : "El tiempo"
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }

                        IslandLabel {
                            visible: Weather.current !== null
                            text: Weather.place
                            color: Theme.dim
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.maximumWidth: 80
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.plugin.close()
                            if (view.plugin.weather)
                                view.plugin.weather.toggle()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        IconGlyph { text: Theme.ico.palette; color: Theme.muted; font.pixelSize: 16 }
                        IslandLabel { text: "Tema"; font.pixelSize: 12; Layout.fillWidth: true }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.plugin.close()
                            if (view.plugin.theme)
                                view.plugin.theme.toggle()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        IconGlyph { text: Theme.ico.cog; color: Theme.muted; font.pixelSize: 16 }
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

        // ── pestaña de notificaciones
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: Theme.surface
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
                    width: ListView.view.width
                    height: notificationBody.implicitHeight + 22
                    radius: 12
                    color: cardMouse.containsMouse ? "#38383a" : Theme.surfaceHi

                    Behavior on color { ColorAnimation { duration: 120 } }

                    // se traga los clics para que un fallo cerca de la ✕ no
                    // llegue al fondo de la island (que cerraría el panel)
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
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: Theme.surface
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
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: Theme.surface
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
