import QtQuick
import "../../services"
import QtQuick.Layouts
import "../../core"

FadeIn {
    id: view

    required property var plugin

    //  Las pantallas que hay, y qué fondo tiene puesto el destino elegido. Se
    //  calculan aquí porque los dos los quieren varios sitios de la rejilla y
    //  llamarlos en cada celda serían cuarenta y cinco llamadas por fotograma.
    readonly property var pantallas: plugin ? plugin.pantallasConocidas() : []
    readonly property string destinoActual: {
        if (!plugin)
            return ""
        return plugin.pantallaElegida.length > 0
            ? plugin.fondoDe(plugin.pantallaElegida) : plugin.wallpaper
    }

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

                //  ── el color, ¿lo pone el fondo o lo pones tú? ──
                //
                //  Va lo primero porque es la decisión que manda sobre todo lo
                //  demás de esta pestaña: con el fondo mandando, elegir un
                //  preset es apagarlo.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: 10
                    color: Theme.islandBg

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            IslandLabel {
                                text: Idioma.t("El color lo pone el fondo")
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            IslandLabel {
                                text: view.plugin.paletaAuto
                                    ? Idioma.t("Cambia de fondo y se recolocan la barra, los bordes y la terminal")
                                    : Idioma.t("Apagado al elegir un preset o un color a mano")
                                color: Theme.dim
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        //  Lo que ha salido del fondo, para que se vea que no es
                        //  magia: los tres colores que se están repartiendo.
                        Repeater {
                            model: view.plugin.paletaAuto
                                ? [view.plugin.accentFrom, view.plugin.accentTo,
                                   view.plugin.inactive] : []

                            delegate: Rectangle {
                                required property var modelData
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                Layout.alignment: Qt.AlignVCenter
                                radius: 9
                                color: modelData
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.12)
                            }
                        }

                        IslandSwitch {
                            checked: view.plugin.paletaAuto
                            Layout.alignment: Qt.AlignVCenter
                            onToggled: {
                                view.plugin.paletaAuto = !view.plugin.paletaAuto
                                if (view.plugin.paletaAuto)
                                    view.plugin.sacarPaleta()
                                else
                                    Theme.destintar("hyprtheme")
                                view.plugin.saveState()
                            }
                        }
                    }
                }

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

                //  ── en qué pantalla estamos trabajando ──────────
                //
                //  Con dos monitores, «poner este fondo» es ambiguo, y la
                //  rejilla de antes decidía por ti: uno para los dos. Aquí se
                //  elige primero el destino y luego la imagen, que es el orden
                //  en que se piensa.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [""].concat(view.pantallas)

                        delegate: Rectangle {
                            id: chipPantalla
                            required property var modelData
                            readonly property bool puesta:
                                view.plugin.pantallaElegida === modelData

                            Layout.preferredWidth: textoPantalla.implicitWidth + 22
                            Layout.preferredHeight: 24
                            radius: 12
                            color: puesta ? Theme.blue
                                : (ratonPantalla.containsMouse ? Theme.surfaceHi
                                                               : Theme.surface)

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IslandLabel {
                                id: textoPantalla
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: chipPantalla.modelData.length === 0
                                    ? Idioma.t("Todas") : chipPantalla.modelData
                                color: chipPantalla.puesta ? Theme.ink : Theme.muted
                                font.pixelSize: 10
                                font.weight: chipPantalla.puesta
                                    ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                id: ratonPantalla
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.plugin.pantallaElegida =
                                    chipPantalla.modelData
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    IslandLabel {
                        text: view.plugin.wallpapers.length + Idioma.t(" fondos")
                        color: Theme.dim
                        font.pixelSize: 10
                        Layout.alignment: Qt.AlignVCenter
                    }

                    //  ── traer uno de fuera ──────────────────────
                    //
                    //  El rastreo mira unas cuantas carpetas y ninguna tiene por
                    //  qué ser la tuya: el fondo que te acabas de bajar a un
                    //  sitio raro no aparece, y la única salida era moverlo.
                    Rectangle {
                        Layout.preferredWidth: textoAnadir.implicitWidth + 22
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        radius: 12
                        color: anadirRaton.containsMouse ? Theme.surfaceHi
                                                         : Theme.surface

                        Behavior on color { ColorAnimation { duration: 120 } }

                        IslandLabel {
                            id: textoAnadir
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: Idioma.t("Añadir…")
                            color: Theme.muted
                            font.pixelSize: 10
                        }

                        MouseArea {
                            id: anadirRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.plugin.elegirFondo()
                        }
                    }

                    MediaButton {
                        glyph: Theme.ico.loading
                        glyphSize: 14
                        glyphColor: Theme.muted
                        onActivated: view.plugin.refreshWallpapers()
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                //  ── cómo se pasa de uno a otro ─────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    IslandLabel {
                        text: Idioma.t("Transición")
                        color: Theme.dim
                        font.pixelSize: 10
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Repeater {
                        model: view.plugin.transiciones

                        delegate: Rectangle {
                            id: chipTrans
                            required property var modelData
                            readonly property bool puesta:
                                view.plugin.transicion === modelData

                            Layout.preferredWidth: textoTrans.implicitWidth + 20
                            Layout.preferredHeight: 22
                            radius: 11
                            color: puesta ? Theme.blue
                                : (ratonTrans.containsMouse ? Theme.surfaceHi
                                                            : Theme.track)

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IslandLabel {
                                id: textoTrans
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: chipTrans.modelData
                                color: chipTrans.puesta ? Theme.ink : Theme.muted
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: ratonTrans
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    view.plugin.transicion = chipTrans.modelData
                                    view.plugin.saveState()
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
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

                        //  Lo puesto EN EL DESTINO elegido, no el fondo común:
                        //  con «HDMI-A-1» seleccionado, lo que hay que marcar es
                        //  lo de esa pantalla.
                        readonly property bool current: view.destinoActual === modelData
                        readonly property bool mueve: !view.plugin.esQuieto(modelData)
                        //  ¿Lo has traído tú? Solo esos se pueden quitar.
                        readonly property bool propio:
                            view.plugin.extras.indexOf(modelData) >= 0

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 10
                            color: Theme.islandBg
                            border.width: wallCell.current ? 2
                                : (wallMouse.containsMouse ? 1 : 0)
                            border.color: wallCell.current ? Theme.blue : Theme.surfaceHi
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: wallCell.current ? 2 : 0
                                //  De un vídeo o un GIF se enseña su póster, que
                                //  el plugin cocina de una tacada al escanear.
                                source: "file://"
                                    + view.plugin.miniaturaDe(wallCell.modelData)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize.width: 320
                            }

                            //  Que se mueve, y qué es. Sin esto, un vídeo y una
                            //  foto se ven idénticos en la rejilla —el póster ES
                            //  una foto— y no sabes lo que estás eligiendo.
                            Rectangle {
                                visible: wallCell.mueve
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                width: etiquetaMueve.implicitWidth + 12
                                height: 16
                                radius: 8
                                color: "#cc000000"

                                IslandLabel {
                                    id: etiquetaMueve
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: /\.(gif|apng)$/i.test(wallCell.modelData)
                                        ? "GIF" : Idioma.t("vídeo")
                                    color: Theme.ink
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                }
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
                                    text: wallCell.modelData.substring(
                                        wallCell.modelData.lastIndexOf("/") + 1)
                                    font.pixelSize: 9
                                    elide: Text.ElideMiddle
                                }
                            }

                            //  La cruz de quitar, solo en los que has traído
                            //  tú: los que salen del rastreo no se pueden
                            //  quitar de una lista en la que no están.
                            Rectangle {
                                visible: wallCell.propio
                                    && (wallMouse.containsMouse || quitarRaton.containsMouse)
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 6
                                width: 18
                                height: 18
                                radius: 9
                                color: quitarRaton.containsMouse
                                    ? Theme.red : "#cc000000"

                                IslandLabel {
                                    anchors.centerIn: parent
                                    //  Por codepoint y no como literal: el extractor
                                    //  de textos ve cualquier cadena en un `text:` y la
                                    //  mete en la plantilla, y una aspa no se traduce.
                                    text: String.fromCodePoint(0x00d7)
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: quitarRaton
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: view.plugin.quitarFondo(wallCell.modelData)
                                }
                            }

                            MouseArea {
                                id: wallMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                //  Debajo de la cruz a propósito: declarado
                                //  después iría encima y se comería su clic.
                                z: -1
                                onClicked: view.plugin.ponerEnElegida(wallCell.modelData)
                            }
                        }
                    }

                    IslandLabel {
                        anchors.centerIn: parent
                        visible: view.plugin.wallpapers.length === 0
                        text: Idioma.t("No hay fondos en tus carpetas de imágenes ni en las del sistema")
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
