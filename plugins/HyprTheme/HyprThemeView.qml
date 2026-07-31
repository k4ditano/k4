import QtQuick
import "../../services"
import QtQuick.Layouts
import "../../core"

FadeIn {
    id: view

    required property var plugin

    // cualquier retoque a mano deja de ser "el preset tal cual"
    function touched() {
        view.plugin.dirty = true
        view.plugin.apply()
    }

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

            IconGlyph {
                text: Theme.ico.palette
                color: Theme.muted
                font.pixelSize: 17
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Idioma.t("Tema de Hyprland")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            // pestañas
            RowLayout {
                spacing: 6
                Layout.alignment: Qt.AlignVCenter

                Repeater {
                    model: [
                        { id: "tema",     label: "Tema",     glyph: Theme.ico.palette },
                        { id: "ventanas", label: "Ventanas", glyph: Theme.ico.window },
                        { id: "efectos",  label: "Efectos",  glyph: Theme.ico.effects },
                        { id: "fondo",    label: "Fondo",    glyph: Theme.ico.wallpaper }
                    ]

                    delegate: Rectangle {
                        id: tabChip
                        required property var modelData
                        readonly property bool current: view.plugin.tab === modelData.id

                        Layout.preferredWidth: tabRow.implicitWidth + 20
                        Layout.preferredHeight: 26
                        radius: 13
                        color: current ? Theme.surfaceHi
                            : (tabMouse.containsMouse ? Theme.surface : "transparent")

                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 6

                            IconGlyph {
                                text: tabChip.modelData.glyph
                                color: tabChip.current ? Theme.ink : Theme.muted
                                font.pixelSize: 12
                            }

                            IslandLabel {
                                text: tabChip.modelData.label
                                color: tabChip.current ? Theme.ink : Theme.muted
                                font.pixelSize: 11
                                font.weight: tabChip.current ? Font.DemiBold : Font.Normal
                            }
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.plugin.tab = tabChip.modelData.id
                        }
                    }
                }
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 16
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── contenido
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: Theme.surface

            // ══ TEMA ═══════════════════════════════════════════════
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14
                visible: view.plugin.tab === "tema"

                IslandLabel {
                    text: Idioma.t("Presets")
                    color: Theme.muted
                    font.pixelSize: 11
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: view.plugin.presets

                        delegate: Rectangle {
                            id: presetCard
                            required property var modelData
                            readonly property bool current: view.plugin.preset === modelData.id
                                && !view.plugin.dirty

                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            radius: 12
                            color: presetMouse.containsMouse ? Theme.surfaceHi : Theme.islandBg
                            border.width: presetCard.current ? 2 : 0
                            border.color: Theme.blue

                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                // muestra del degradado que tendrá el borde activo
                                Rectangle {
                                    Layout.preferredWidth: 34
                                    Layout.preferredHeight: 34
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 8

                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: presetCard.modelData.from }
                                        GradientStop { position: 1; color: presetCard.modelData.to }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 1

                                    IslandLabel {
                                        text: presetCard.modelData.name
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    IslandLabel {
                                        text: presetCard.current ? "aplicado" : presetCard.modelData.from
                                        color: presetCard.current ? Theme.green : Theme.dim
                                        font.pixelSize: 10
                                    }
                                }

                                IconGlyph {
                                    visible: presetCard.current
                                    text: Theme.ico.check
                                    color: Theme.green
                                    font.pixelSize: 14
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            MouseArea {
                                id: presetMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.plugin.applyPreset(presetCard.modelData.id)
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                IslandSlider {
                    Layout.fillWidth: true
                    label: "Ángulo del degradado del borde"
                    suffix: "°"
                    from: 0
                    to: 360
                    step: 5
                    value: view.plugin.angle
                    onMoved: function (v) { view.plugin.angle = v; view.touched() }
                }
            }

            // ══ VENTANAS ═══════════════════════════════════════════
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6
                visible: view.plugin.tab === "ventanas"

                IslandSlider {
                    Layout.fillWidth: true
                    label: "Separación interior entre ventanas"
                    suffix: " px"
                    from: 0; to: 30; step: 1
                    value: view.plugin.gapsIn
                    onMoved: function (v) { view.plugin.gapsIn = v; view.touched() }
                }

                IslandSlider {
                    Layout.fillWidth: true
                    label: "Separación con el borde de la pantalla"
                    suffix: " px"
                    from: 0; to: 60; step: 1
                    value: view.plugin.gapsOut
                    onMoved: function (v) { view.plugin.gapsOut = v; view.touched() }
                }

                IslandSlider {
                    Layout.fillWidth: true
                    label: "Grosor del borde"
                    suffix: " px"
                    from: 0; to: 10; step: 1
                    value: view.plugin.borderSize
                    onMoved: function (v) { view.plugin.borderSize = v; view.touched() }
                }

                IslandSlider {
                    Layout.fillWidth: true
                    label: "Redondeo de esquinas"
                    suffix: " px"
                    from: 0; to: 30; step: 1
                    value: view.plugin.rounding
                    onMoved: function (v) { view.plugin.rounding = v; view.touched() }
                }

                Item { Layout.fillHeight: true }
            }

            // ══ EFECTOS ════════════════════════════════════════════
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 20
                visible: view.plugin.tab === "efectos"

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        IslandLabel { text: Idioma.t("Desenfoque"); font.pixelSize: 12; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        IslandSwitch {
                            checked: view.plugin.blur
                            onToggled: { view.plugin.blur = !view.plugin.blur; view.touched() }
                        }
                    }

                    IslandSlider {
                        Layout.fillWidth: true
                        enabled: view.plugin.blur
                        opacity: view.plugin.blur ? 1 : 0.35
                        label: "Radio"
                        from: 1; to: 20; step: 1
                        value: view.plugin.blurSize
                        onMoved: function (v) { view.plugin.blurSize = v; view.touched() }
                    }

                    IslandSlider {
                        Layout.fillWidth: true
                        enabled: view.plugin.blur
                        opacity: view.plugin.blur ? 1 : 0.35
                        label: "Pasadas"
                        from: 1; to: 6; step: 1
                        value: view.plugin.blurPasses
                        onMoved: function (v) { view.plugin.blurPasses = v; view.touched() }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 10

                        IslandLabel { text: Idioma.t("Sombras"); font.pixelSize: 12; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        IslandSwitch {
                            checked: view.plugin.shadow
                            onToggled: { view.plugin.shadow = !view.plugin.shadow; view.touched() }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Theme.surfaceHi }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    IslandSlider {
                        Layout.fillWidth: true
                        label: "Opacidad de la ventana activa"
                        from: 0.4; to: 1; step: 0.05
                        value: view.plugin.activeOpacity
                        onMoved: function (v) { view.plugin.activeOpacity = v; view.touched() }
                    }

                    IslandSlider {
                        Layout.fillWidth: true
                        label: "Opacidad de las inactivas"
                        from: 0.4; to: 1; step: 0.05
                        value: view.plugin.inactiveOpacity
                        onMoved: function (v) { view.plugin.inactiveOpacity = v; view.touched() }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 10

                        IslandLabel { text: Idioma.t("Animaciones"); font.pixelSize: 12; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        IslandSwitch {
                            checked: view.plugin.animEnabled
                            onToggled: { view.plugin.animEnabled = !view.plugin.animEnabled; view.touched() }
                        }
                    }

                    IslandSlider {
                        Layout.fillWidth: true
                        enabled: view.plugin.animEnabled
                        opacity: view.plugin.animEnabled ? 1 : 0.35
                        label: "Velocidad (más alto = más rápido)"
                        from: 1; to: 10; step: 1
                        value: view.plugin.animSpeed
                        onMoved: function (v) { view.plugin.animSpeed = v; view.touched() }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ══ FONDO ══════════════════════════════════════════════
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10
                visible: view.plugin.tab === "fondo"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    IslandLabel {
                        text: view.plugin.wallTool.length === 0
                            ? Idioma.t("Sin programa de fondo instalado")
                            : view.plugin.wallpapers.length + Idioma.t(" imágenes · usando ") + view.plugin.wallTool
                        color: view.plugin.wallTool.length === 0 ? Theme.red : Theme.muted
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    IslandLabel {
                        visible: view.plugin.wallTool === "swaybg"
                        text: Idioma.t("instala awww para tener transiciones")
                        color: Theme.dim
                        font.pixelSize: 10
                        Layout.alignment: Qt.AlignVCenter
                    }

                    MediaButton {
                        glyph: Theme.ico.loading
                        glyphSize: 14
                        glyphColor: Theme.muted
                        onActivated: view.plugin.refreshWallpapers()
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                GridView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    cellWidth: Math.floor(width / 4)
                    cellHeight: Math.round(cellWidth * 0.6)
                    model: view.plugin.wallpapers
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: wallCell
                        required property var modelData
                        width: GridView.view.cellWidth
                        height: GridView.view.cellHeight

                        readonly property bool current: view.plugin.wallpaper === modelData

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 10
                            color: Theme.islandBg
                            border.width: wallCell.current ? 2 : (wallMouse.containsMouse ? 1 : 0)
                            border.color: wallCell.current ? Theme.blue : Theme.surfaceHi
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: wallCell.current ? 2 : 0
                                source: "file://" + wallCell.modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize.width: 320
                            }

                            // el nombre, legible sobre cualquier imagen
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 20
                                color: "#cc000000"
                                visible: wallMouse.containsMouse || wallCell.current

                                IslandLabel {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    verticalAlignment: Text.AlignVCenter
                                    text: wallCell.modelData.substring(wallCell.modelData.lastIndexOf("/") + 1)
                                    font.pixelSize: 9
                                    elide: Text.ElideMiddle
                                }
                            }

                            MouseArea {
                                id: wallMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.plugin.setWallpaper(wallCell.modelData)
                            }
                        }
                    }

                    IslandLabel {
                        anchors.centerIn: parent
                        visible: view.plugin.wallpapers.length === 0
                        text: Idioma.t("No hay imágenes en Imágenes, Descargas ni en las carpetas del sistema")
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
            }
        }

        // ── pie: estado de la persistencia
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 22
            spacing: 10

            readonly property bool fondo: view.plugin.tab === "fondo"
            readonly property bool fondoAplicado: view.plugin.wallpaper.length > 0
            readonly property bool fondoDisponible: view.plugin.wallTool.length > 0

            IconGlyph {
                text: parent.fondo
                    ? (parent.fondoDisponible && parent.fondoAplicado ? Theme.ico.check : Theme.ico.alert)
                    : (view.plugin.isPersisted() ? Theme.ico.check : Theme.ico.alert)
                color: parent.fondo
                    ? (parent.fondoDisponible && parent.fondoAplicado ? Theme.green : Theme.muted)
                    : (view.plugin.isPersisted() ? Theme.green : Theme.muted)
                font.pixelSize: 12
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: parent.fondo
                    ? (parent.fondoDisponible
                        ? (parent.fondoAplicado
                            ? Idioma.t("Fondo aplicado y guardado automáticamente")
                            : Idioma.t("Selecciona una imagen para cambiar el fondo"))
                        : Idioma.t("Instala awww, swww o swaybg para aplicar fondos"))
                    : (view.plugin.isPersisted()
                        ? Idioma.t("Guardado en config/k4-theme.lua · sobrevive al reinicio")
                        : Idioma.t("Aplicado solo en esta sesión · pulsa Guardar para que persista"))
                color: Theme.muted
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: !parent.fondo
                Layout.preferredWidth: saveLabel.implicitWidth + 26
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                radius: 12
                color: saveMouse.containsMouse ? Theme.blue : Theme.surfaceHi

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: saveLabel
                    anchors.centerIn: parent
                    text: Idioma.t("Guardar")
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: saveMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.plugin.persist()
                }
            }
        }
    }
}
