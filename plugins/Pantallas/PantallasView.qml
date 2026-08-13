import QtQuick
import K4 as K4

K4.Aparicion {
    id: view

    required property var plugin
    property string dropdownAbierto: ""

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool selected: false
        property bool enabled: true
        property int minimumWidth: 54
        signal clicked()

        width: Math.max(minimumWidth, labelText.implicitWidth + 20)
        height: 28
        radius: 14
        color: selected ? K4.Tema.superficieAlta
                        : (mouse.containsMouse && enabled ? K4.Tema.superficie : "transparent")
        border.width: selected ? 1 : 0
        border.color: selected ? K4.Tema.azul : "transparent"
        opacity: enabled ? 1 : 0.35

        K4.Etiqueta {
            id: labelText
            anchors.centerIn: parent
            text: chip.label
            font.pixelSize: 11
            font.weight: chip.selected ? Font.DemiBold : Font.Normal
            color: chip.selected ? K4.Tema.tinta : K4.Tema.apagado
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: chip.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component Action: Rectangle {
        id: action
        property string label: ""
        property bool primary: false
        property bool enabled: true
        signal clicked()

        width: actionText.implicitWidth + 28
        height: 34
        radius: 17
        color: primary ? K4.Tema.tinta
            : (actionMouse.containsMouse && enabled ? K4.Tema.superficieAlta : K4.Tema.superficie)
        opacity: enabled ? 1 : 0.4

        K4.Etiqueta {
            id: actionText
            anchors.centerIn: parent
            text: action.label
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: action.primary ? K4.Tema.fondo : K4.Tema.tinta
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: action.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: action.clicked()
        }
    }

    component Dropdown: Item {
        id: dropdown
        property string key: ""
        property string label: ""
        property var options: []
        property var selectedValue
        property int menuHeight: 170
        property bool openUpward: false
        signal picked(var value)

        readonly property bool open: view.dropdownAbierto === key
        readonly property string selectedText: {
            for (let i = 0; i < options.length; ++i)
                if (String(options[i].value) === String(selectedValue))
                    return options[i].label
            return K4.Idioma.t("Elegir")
        }

        height: 58
        z: open ? 100 : 1

        K4.Etiqueta {
            text: dropdown.label
            font.pixelSize: 10
            font.weight: Font.DemiBold
            color: K4.Tema.apagado
        }

        Rectangle {
            id: dropdownHead
            y: 19
            width: parent.width
            height: 36
            radius: 11
            color: dropdownMouse.containsMouse ? K4.Tema.superficieAlta
                                               : K4.Tema.superficie
            border.width: dropdown.open ? 1 : 0
            border.color: K4.Tema.azul

            K4.Etiqueta {
                x: 12
                width: parent.width - 44
                anchors.verticalCenter: parent.verticalCenter
                text: dropdown.selectedText
                elide: Text.ElideRight
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            K4.Etiqueta {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: dropdown.open ? "⌃" : "⌄"
                color: K4.Tema.apagado
                font.pixelSize: 13
            }

            MouseArea {
                id: dropdownMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: view.dropdownAbierto = dropdown.open ? "" : dropdown.key
            }
        }

        Rectangle {
            y: dropdown.openUpward ? -height - 5 : 60
            width: parent.width
            height: Math.min(dropdown.menuHeight, dropdown.options.length * 31 + 8)
            visible: dropdown.open
            radius: 12
            color: K4.Tema.superficieAlta
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
            z: 200

            K4.Rodillo {
                anchors.fill: parent
                anchors.margins: 4
                muesca: 32

                Column {
                    width: parent.width
                    spacing: 1

                    Repeater {
                        model: dropdown.options
                        delegate: Rectangle {
                            id: dropdownOption
                            required property var modelData
                            width: parent.width
                            height: 30
                            radius: 8
                            color: optionMouse.containsMouse
                                ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                            Rectangle {
                                x: 7
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5
                                height: 5
                                radius: 3
                                visible: String(dropdownOption.modelData.value)
                                    === String(dropdown.selectedValue)
                                color: K4.Tema.azul
                            }

                            K4.Etiqueta {
                                x: 20
                                width: parent.width - 28
                                anchors.verticalCenter: parent.verticalCenter
                                text: dropdownOption.modelData.label
                                elide: Text.ElideRight
                                font.pixelSize: 10
                                font.weight: String(dropdownOption.modelData.value)
                                    === String(dropdown.selectedValue)
                                    ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                id: optionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dropdown.picked(dropdownOption.modelData.value)
                                    view.dropdownAbierto = ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Cabecera
    Row {
        id: header
        x: 18
        y: 12
        width: parent.width - 36
        height: 34
        spacing: 10

        K4.Glifo {
            text: "󰍹"
            width: 24
            height: parent.height
            color: K4.Tema.azul
            font.pixelSize: 19
        }

        K4.Etiqueta {
            text: K4.Idioma.t("Pantallas")
            width: 112
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 15
            font.weight: Font.Bold
        }

        Chip {
            label: K4.Idioma.t("Distribución")
            selected: view.plugin.tab === "pantallas"
            anchors.verticalCenter: parent.verticalCenter
            onClicked: view.plugin.tab = "pantallas"
        }

        Chip {
            label: K4.Idioma.t("Escritorios")
            selected: view.plugin.tab === "workspaces"
            anchors.verticalCenter: parent.verticalCenter
            onClicked: view.plugin.tab = "workspaces"
        }

        Item { width: Math.max(0, header.width - 478); height: 1 }

        K4.Boton {
            glifo: "󰑐"
            tamano: 15
            activo: !view.plugin.ocupado
            anchors.verticalCenter: parent.verticalCenter
            onPulsado: view.plugin.refresh()
        }

        K4.Boton {
            glifo: "󰅖"
            tamano: 16
            anchors.verticalCenter: parent.verticalCenter
            onPulsado: view.plugin.close()
        }
    }

    // Distribución: el centro es una mesa, no un formulario.
    Item {
        id: displaysPage
        x: 18
        y: 56
        width: parent.width - 36
        height: parent.height - 118
        visible: view.plugin.tab === "pantallas"

        Rectangle {
            id: layoutCanvas
            width: parent.width
            height: 232
            radius: 18
            color: K4.Tema.superficie
            clip: true

            property bool dragging: false
            property var frozenMetrics: ({})
            readonly property var liveMetrics: view.plugin.layoutMetrics(width, height - 46)
            readonly property var metrics: dragging ? frozenMetrics : liveMetrics

            function beginDrag(name) {
                view.plugin.seleccionado = name
                frozenMetrics = liveMetrics
                dragging = true
            }

            function endDrag(name) {
                view.plugin.snapPosition(name)
                dragging = false
            }

            // Rejilla tenue: ayuda a percibir el desplazamiento sin ruido.
            Repeater {
                model: 18
                delegate: Rectangle {
                    required property int index
                    x: index * layoutCanvas.width / 18
                    y: 40
                    width: 1
                    height: layoutCanvas.height - 40
                    color: Qt.rgba(1, 1, 1, 0.025)
                }
            }
            Repeater {
                model: 6
                delegate: Rectangle {
                    required property int index
                    x: 0
                    y: 40 + index * (layoutCanvas.height - 40) / 6
                    width: layoutCanvas.width
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.025)
                }
            }

            Row {
                x: 14
                y: 9
                spacing: 8

                K4.Glifo {
                    text: "󰇄"
                    width: 18
                    height: 26
                    font.pixelSize: 15
                    color: K4.Tema.azul
                }
                K4.Etiqueta {
                    text: K4.Idioma.t("Arrastra las pantallas como están colocadas en tu mesa")
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                y: 7
                spacing: 4
                enabled: view.plugin.monitores.length > 1

                Chip { label: "←"; minimumWidth: 34; onClicked: view.plugin.place("left") }
                Chip { label: "→"; minimumWidth: 34; onClicked: view.plugin.place("right") }
                Chip { label: "↑"; minimumWidth: 34; onClicked: view.plugin.place("above") }
                Chip { label: "↓"; minimumWidth: 34; onClicked: view.plugin.place("below") }
                Chip { label: "⊙"; minimumWidth: 34; onClicked: view.plugin.place("mirror") }
            }

            Repeater {
                model: view.plugin.monitores
                delegate: Rectangle {
                    id: screen
                    required property var modelData
                    required property int index
                    readonly property var draft: view.plugin.draft(modelData.name)
                    readonly property var logical: view.plugin.logicalSize(modelData.name)
                    readonly property var metric: layoutCanvas.metrics

                    x: draft ? metric.offsetX + (draft.x - metric.minX) * metric.zoom : 0
                    y: draft ? 42 + metric.offsetY + (draft.y - metric.minY) * metric.zoom : 42
                    width: draft ? Math.max(100, logical.width * metric.zoom) : 100
                    height: draft ? Math.max(58, logical.height * metric.zoom) : 58
                    radius: 10
                    z: modelData.name === view.plugin.seleccionado ? 3 : 1
                    color: modelData.name === view.plugin.seleccionado
                        ? Qt.rgba(0.04, 0.52, 1, 0.30) : K4.Tema.superficieAlta
                    border.width: modelData.name === view.plugin.seleccionado ? 2 : 1
                    border.color: modelData.name === view.plugin.seleccionado
                        ? K4.Tema.azul : K4.Tema.tenue

                    Behavior on color { ColorAnimation { duration: 130 } }

                    // El pequeño bisel hace que se lea como pantalla, no tarjeta.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: 6
                        color: Qt.rgba(0, 0, 0, 0.20)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: Math.min(42, parent.width * 0.22)
                        height: 3
                        radius: 2
                        color: modelData.name === view.plugin.seleccionado
                            ? K4.Tema.azul : K4.Tema.apagado
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        K4.Etiqueta {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: String(screen.index + 1)
                            font.pixelSize: Math.min(24, screen.height * 0.23)
                            font.weight: Font.Bold
                        }
                        K4.Etiqueta {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: screen.modelData.model || screen.modelData.name
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        K4.Etiqueta {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: screen.modelData.name + " · "
                                + Number(screen.modelData.refreshRate).toFixed(0) + " Hz"
                            color: K4.Tema.apagado
                            font.pixelSize: 8
                        }
                    }

                    TapHandler {
                        onTapped: view.plugin.seleccionado = screen.modelData.name
                    }

                    DragHandler {
                        id: screenDrag
                        target: null
                        property real startX: 0
                        property real startY: 0

                        onActiveChanged: {
                            if (active) {
                                const current = view.plugin.draft(screen.modelData.name)
                                startX = current ? current.x : 0
                                startY = current ? current.y : 0
                                layoutCanvas.beginDrag(screen.modelData.name)
                            } else if (layoutCanvas.dragging) {
                                layoutCanvas.endDrag(screen.modelData.name)
                            }
                        }
                        onTranslationChanged: {
                            if (!active || layoutCanvas.metrics.zoom <= 0)
                                return
                            view.plugin.setPosition(screen.modelData.name,
                                startX + translation.x / layoutCanvas.metrics.zoom,
                                startY + translation.y / layoutCanvas.metrics.zoom)
                        }
                    }
                }
            }

            K4.Etiqueta {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                property var current: view.plugin.draft(view.plugin.seleccionado)
                text: current ? K4.Idioma.f(K4.Idioma.t("Posición %1 × %2"),
                                             current.x, current.y) : ""
                color: K4.Tema.apagado
                font.pixelSize: 9
            }
        }

        K4.Rodillo {
            id: monitorSelector
            y: 244
            width: 274
            height: parent.height - 244

            Column {
                width: parent.width - 10
                spacing: 8

                Repeater {
                    model: view.plugin.monitores
                    delegate: K4.Baldosa {
                        id: monitorCard
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 66
                        activa: modelData.name === view.plugin.seleccionado
                        onPulsada: view.plugin.seleccionado = modelData.name

                        Rectangle {
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            radius: 9
                            color: monitorCard.activa ? K4.Tema.azul : K4.Tema.superficieAlta
                            K4.Etiqueta {
                                anchors.centerIn: parent
                                text: String(monitorCard.index + 1)
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                        }

                        Column {
                            x: 50
                            anchors.verticalCenter: parent.verticalCenter
                            width: 116
                            spacing: 2
                            K4.Etiqueta {
                                width: parent.width
                                text: monitorCard.modelData.model || monitorCard.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            K4.Etiqueta {
                                text: monitorCard.modelData.name
                                color: K4.Tema.apagado
                                font.pixelSize: 9
                            }
                        }

                        Chip {
                            x: monitorCard.width - width - 8
                            anchors.verticalCenter: parent.verticalCenter
                            label: view.plugin.principal === monitorCard.modelData.name
                                ? K4.Idioma.t("Principal") : K4.Idioma.t("Elegir")
                            selected: view.plugin.principal === monitorCard.modelData.name
                            minimumWidth: 58
                            onClicked: view.plugin.principal = monitorCard.modelData.name
                        }
                    }
                }
            }
        }

        Rectangle {
            x: 290
            y: 244
            width: parent.width - 290
            height: parent.height - 244
            radius: 16
            color: Qt.rgba(1, 1, 1, 0.025)

            Row {
                x: 14
                y: 14
                width: parent.width - 28
                height: parent.height - 28
                spacing: 12

                Dropdown {
                    key: "mode"
                    width: parent.width - 322
                    label: K4.Idioma.t("Resolución y refresco")
                    menuHeight: 182
                    openUpward: true
                    selectedValue: {
                        const draft = view.plugin.draft(view.plugin.seleccionado)
                        return draft ? draft.mode : ""
                    }
                    options: {
                        const monitor = view.plugin.monitor(view.plugin.seleccionado)
                        if (!monitor)
                            return []
                        return monitor.availableModes.map(function (mode) {
                            return { value: mode,
                                     label: String(mode).replace("@", "  ·  ").replace("Hz", " Hz") }
                        })
                    }
                    onPicked: function (value) { view.plugin.setDraft("mode", value) }
                }

                Dropdown {
                    key: "scale"
                    width: 142
                    label: K4.Idioma.t("Escala")
                    openUpward: true
                    selectedValue: {
                        const draft = view.plugin.draft(view.plugin.seleccionado)
                        return draft ? draft.scale : 1
                    }
                    options: [
                        { value: 1, label: "100%" }, { value: 1.25, label: "125%" },
                        { value: 1.5, label: "150%" }, { value: 1.75, label: "175%" },
                        { value: 2, label: "200%" }
                    ]
                    onPicked: function (value) { view.plugin.setDraft("scale", Number(value)) }
                }

                Dropdown {
                    key: "rotation"
                    width: 144
                    label: K4.Idioma.t("Orientación")
                    openUpward: true
                    selectedValue: {
                        const draft = view.plugin.draft(view.plugin.seleccionado)
                        return draft ? draft.transform : 0
                    }
                    options: [
                        { value: 0, label: K4.Idioma.t("Horizontal · 0°") },
                        { value: 1, label: K4.Idioma.t("Vertical · 90°") },
                        { value: 2, label: K4.Idioma.t("Horizontal · 180°") },
                        { value: 3, label: K4.Idioma.t("Vertical · 270°") }
                    ]
                    onPicked: function (value) { view.plugin.setDraft("transform", Number(value)) }
                }
            }
        }
    }

    // Reparto de escritorios: se arrastran entre pantallas.
    Item {
        id: workspacesPage
        x: 18
        y: 58
        width: parent.width - 36
        height: parent.height - 120
        visible: view.plugin.tab === "workspaces"

        K4.Etiqueta {
            id: workspaceIntro
            width: parent.width
            text: K4.Idioma.t("Arrastra cada escritorio a la pantalla donde quieres que viva")
            color: K4.Tema.apagado
            font.pixelSize: 11
        }

        Row {
            id: workspaceBoards
            y: 32
            width: parent.width
            height: parent.height - 58
            spacing: 14

            Repeater {
                model: view.plugin.monitores
                delegate: Rectangle {
                    id: workspaceBoard
                    required property var modelData
                    required property int index
                    readonly property string monitorName: modelData.name
                    width: (workspaceBoards.width
                            - workspaceBoards.spacing * Math.max(0, view.plugin.monitores.length - 1))
                           / Math.max(1, view.plugin.monitores.length)
                    height: workspaceBoards.height
                    radius: 18
                    color: boardDrop.containsDrag
                        ? Qt.rgba(0.04, 0.52, 1, 0.18) : K4.Tema.superficie
                    border.width: boardDrop.containsDrag ? 2 : 1
                    border.color: boardDrop.containsDrag ? K4.Tema.azul
                                                        : Qt.rgba(1, 1, 1, 0.05)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Rectangle {
                        x: 14
                        y: 14
                        width: 42
                        height: 30
                        radius: 7
                        color: workspaceBoard.index === 0
                            ? Qt.rgba(0.04, 0.52, 1, 0.24) : K4.Tema.superficieAlta
                        border.width: 1
                        border.color: workspaceBoard.index === 0 ? K4.Tema.azul : K4.Tema.tenue
                        K4.Etiqueta {
                            anchors.centerIn: parent
                            text: String(workspaceBoard.index + 1)
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }

                    Column {
                        x: 66
                        y: 12
                        width: parent.width - 150
                        spacing: 2
                        K4.Etiqueta {
                            width: parent.width
                            text: workspaceBoard.modelData.model || workspaceBoard.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        K4.Etiqueta {
                            text: workspaceBoard.modelData.name
                            color: K4.Tema.apagado
                            font.pixelSize: 9
                        }
                    }

                    Chip {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        y: 14
                        label: view.plugin.principal === workspaceBoard.monitorName
                            ? K4.Idioma.t("Principal") : K4.Idioma.t("Elegir")
                        selected: view.plugin.principal === workspaceBoard.monitorName
                        onClicked: view.plugin.principal = workspaceBoard.monitorName
                    }

                    Rectangle {
                        x: 12
                        y: 58
                        width: parent.width - 24
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.07)
                    }

                    Flow {
                        id: workspaceFlow
                        x: 14
                        y: 76
                        width: parent.width - 28
                        spacing: 10

                        Repeater {
                            model: view.plugin.workspacesFor(workspaceBoard.monitorName)
                            delegate: Rectangle {
                                id: workspaceChip
                                required property var modelData
                                readonly property int workspaceNumber: Number(modelData)
                                property real homeX: 0
                                property real homeY: 0

                                width: 62
                                height: 54
                                radius: 14
                                z: workspaceDrag.active ? 20 : 1
                                scale: workspaceDrag.active ? 1.08 : 1
                                color: workspaceDrag.active ? K4.Tema.superficieAlta
                                                           : Qt.rgba(1, 1, 1, 0.055)
                                border.width: 1
                                border.color: workspaceDrag.active ? K4.Tema.azul
                                                                  : Qt.rgba(1, 1, 1, 0.06)

                                Drag.active: workspaceDrag.active
                                Drag.source: workspaceChip
                                Drag.keys: ["k4-workspace"]
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2

                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 100 } }

                                K4.Etiqueta {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 8
                                    text: workspaceChip.workspaceNumber
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                }
                                K4.Etiqueta {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 34
                                    text: K4.Idioma.t("escritorio")
                                    color: K4.Tema.apagado
                                    font.pixelSize: 7
                                }

                                TapHandler {
                                    onTapped: view.plugin.cycleAssignment(workspaceChip.workspaceNumber)
                                }

                                DragHandler {
                                    id: workspaceDrag
                                    target: workspaceChip
                                    onActiveChanged: {
                                        if (active) {
                                            workspaceChip.homeX = workspaceChip.x
                                            workspaceChip.homeY = workspaceChip.y
                                        } else {
                                            workspaceChip.x = workspaceChip.homeX
                                            workspaceChip.y = workspaceChip.homeY
                                        }
                                    }
                                }
                            }
                        }
                    }

                    K4.Etiqueta {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 34
                        visible: view.plugin.workspacesFor(workspaceBoard.monitorName).length === 0
                        text: K4.Idioma.t("Suelta aquí un escritorio")
                        color: K4.Tema.apagado
                        font.pixelSize: 11
                    }

                    DropArea {
                        id: boardDrop
                        anchors.fill: parent
                        keys: ["k4-workspace"]
                        onDropped: function (drop) {
                            if (drop.source)
                                view.plugin.setAssignment(drop.source.workspaceNumber,
                                                          workspaceBoard.monitorName)
                        }
                    }
                }
            }
        }

        K4.Etiqueta {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: K4.Idioma.t("También puedes pulsar un escritorio para mandarlo a la siguiente pantalla")
            color: K4.Tema.apagado
            font.pixelSize: 9
        }
    }

    // Estado y acciones
    Row {
        id: footer
        x: 18
        y: parent.height - 50
        width: parent.width - 36
        height: 38
        spacing: 10

        Rectangle {
            width: 8
            height: 8
            radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: view.plugin.ocupado ? K4.Tema.amarillo
                : (view.plugin.mensajeError ? K4.Tema.rojo : K4.Tema.verde)
        }

        K4.Etiqueta {
            width: Math.max(200, footer.width - 340)
            anchors.verticalCenter: parent.verticalCenter
            text: view.plugin.mensaje
            elide: Text.ElideRight
            color: view.plugin.mensajeError ? K4.Tema.rojo : K4.Tema.apagado
            font.pixelSize: 10
        }

        Action {
            label: K4.Idioma.t("Aplicar ahora")
            enabled: !view.plugin.ocupado
            anchors.verticalCenter: parent.verticalCenter
            onClicked: view.plugin.apply(false)
        }

        Action {
            label: K4.Idioma.t("Guardar y aplicar")
            primary: true
            enabled: !view.plugin.ocupado
            anchors.verticalCenter: parent.verticalCenter
            onClicked: view.plugin.apply(true)
        }
    }
}
