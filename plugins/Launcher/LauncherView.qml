import QtQuick
import QtQuick.Controls
import "../../services"
import QtQuick.Layouts
import K4 as K4
import "../../core"

FadeIn {
    id: view

    required property var plugin

    property int focusAttempts: 0

    Component.onCompleted: {
        view.plugin.rebuild()
        focusAttempts = 0
        focusTimer.start()
        Qt.callLater(function () { launcherInput.forceActiveFocus() })
    }

    // La layer surface tarda en recibir el foco: se reintenta unas cuantas
    // veces en vez de dar por hecho que llegó a la primera.
    Timer {
        id: focusTimer
        interval: 140
        onTriggered: {
            if (!view.plugin.open)
                return

            launcherInput.forceActiveFocus()
            if (!launcherInput.activeFocus && view.focusAttempts < 6) {
                view.focusAttempts += 1
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
                text: view.plugin.mode === "packages" ? Theme.ico.install : Theme.ico.search
                color: view.plugin.mode === "packages" ? Theme.blue : Theme.muted
                font.pixelSize: 20
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: view.plugin.query.length === 0
                    text: view.plugin.mode === "packages"
                        ? Idioma.t("Buscar paquetes para instalar") : Idioma.t("Buscar aplicaciones")
                    color: Theme.dim
                    font.pixelSize: 19
                }

                TextInput {
                    id: launcherInput
                    cursorDelegate: IslandCursor {}
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.ink
                    font.family: Theme.uiFont
                    font.pixelSize: 19
                    focus: true
                    activeFocusOnTab: true
                    clip: true
                    selectByMouse: true
                    cursorVisible: true
                    selectionColor: Theme.blue
                    text: view.plugin.query
                    onTextEdited: {
                        view.plugin.query = text
                        if (view.plugin.mode === "packages") {
                            view.plugin.index = 0
                            view.plugin.schedulePackageSearch()
                        } else {
                            view.plugin.rebuild()
                        }
                    }

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Escape) {
                            if (view.plugin.mode === "packages")
                                view.plugin.leavePackageMode()
                            else
                                view.plugin.close()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            view.plugin.launchSelected()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Delete
                                   && (event.modifiers & Qt.ControlModifier)
                                   && view.plugin.mode === "packages") {
                            view.plugin.uninstallSelected()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            view.plugin.moveSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            view.plugin.moveSelection(-1)
                            event.accepted = true
                        }
                    }
                }
            }

            IslandLabel {
                text: view.plugin.mode !== "packages" ? "esc"
                    : view.plugin.aurSearching ? Idioma.t("buscando en AUR…") : Idioma.t("esc vuelve a apps")
                color: Theme.dim
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter

                SequentialAnimation on opacity {
                    running: view.plugin.aurSearching
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 620; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.surfaceHi
        }

        // ── aplicaciones
        ListView {
            //  La barra de la casa: se ve solo si hay más de lo que cabe.
            ScrollBar.vertical: IslandScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: view.plugin.mode === "apps"
            clip: true
            spacing: 2
            model: view.plugin.matches
            currentIndex: view.plugin.index
            highlightMoveDuration: 140
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: appRow
                required property var modelData
                required property int index

                //  ¿Trae icono propio —imagen o códice— o hay que buscarle
                //  uno en el tema del escritorio por su nombre?
                readonly property bool propio: !!modelData._imagen
                                            || !!modelData._glifo

                width: ListView.view.width
                height: 42
                radius: 10
                color: index === view.plugin.index ? Theme.surfaceHi : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 12

                    //  Una aplicación del sistema trae un nombre de icono del
                    //  escritorio; un aporte de un plugin trae el suyo, que es
                    //  una imagen o un códice de la Nerd Font. Son dos cosas
                    //  distintas y por eso son dos piezas: la misma no sabe
                    //  pintar las dos. Manda quien tenga icono propio.
                    K4.Icono {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        visible: appRow.modelData.isInstall !== true
                            && !appRow.propio
                        source: appRow.modelData.icon.length > 0
                            ? K4.Apps.icono(appRow.modelData.icon, true) : ""
                    }

                    K4.IconoPlugin {
                        visible: appRow.propio
                        imagen: appRow.modelData._imagen || ""
                        glifo: appRow.modelData._glifo || 0
                        tamano: 22
                        color: Theme.ink
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                    }

                    IconGlyph {
                        visible: appRow.modelData.isInstall === true
                        text: Theme.ico.install
                        color: Theme.blue
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
                            color: Theme.muted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    IconGlyph {
                        text: Theme.ico.enter
                        color: Theme.muted
                        font.pixelSize: 14
                        visible: appRow.index === view.plugin.index
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: view.plugin.index = appRow.index
                    onClicked: {
                        view.plugin.index = appRow.index
                        view.plugin.launchSelected()
                    }
                }
            }

            IslandLabel {
                anchors.centerIn: parent
                visible: view.plugin.matches.length === 0
                text: Idioma.t("Sin resultados")
                color: Theme.muted
                font.pixelSize: 13
            }
        }

        // ── resultados de paquetes
        ListView {
            //  La barra de la casa: se ve solo si hay más de lo que cabe.
            ScrollBar.vertical: IslandScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: view.plugin.mode === "packages"
            clip: true
            spacing: 2
            model: view.plugin.packageMatches
            currentIndex: view.plugin.index
            boundsBehavior: Flickable.StopAtBounds
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: packageRow
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 48
                radius: 10
                color: index === view.plugin.index ? Theme.surfaceHi : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    IconGlyph {
                        text: packageRow.modelData.installed ? Theme.ico.installed : Theme.ico.package
                        color: packageRow.modelData.installed ? Theme.green : Theme.muted
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
                                color: packageRow.modelData.repo === "aur" ? "#3a2a12" : Theme.surfaceHi

                                IslandLabel {
                                    id: repoLabel
                                    anchors.centerIn: parent
                                    text: packageRow.modelData.repo
                                    color: packageRow.modelData.repo === "aur" ? "#ff9f0a" : Theme.muted
                                    font.pixelSize: 9
                                }
                            }

                            IslandLabel {
                                text: packageRow.modelData.version
                                color: Theme.dim
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Item { Layout.fillWidth: true }
                        }

                        IslandLabel {
                            Layout.fillWidth: true
                            text: packageRow.modelData.installed
                                ? Idioma.t("Instalado · ") + packageRow.modelData.description
                                : packageRow.modelData.description
                            color: packageRow.modelData.installed ? Theme.green : Theme.muted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    IslandLabel {
                        visible: packageRow.index === view.plugin.index
                        text: packageRow.modelData.installed
                            ? Idioma.t("actualizar ↵") : Idioma.t("instalar ↵")
                        color: Theme.muted
                        font.pixelSize: 10
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Rectangle {
                        id: uninstallAction
                        visible: packageRow.modelData.installed
                            && packageRow.index === view.plugin.index
                        Layout.preferredWidth: uninstallContent.implicitWidth + 18
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        radius: 13
                        color: uninstallMouse.containsMouse ? "#3a1518" : "#2a0f12"
                        border.width: 1
                        border.color: Theme.red

                        RowLayout {
                            id: uninstallContent
                            anchors.centerIn: parent
                            spacing: 5

                            IconGlyph {
                                text: Theme.ico.uninstall
                                color: Theme.red
                                font.pixelSize: 11
                            }

                            IslandLabel {
                                text: Idioma.t("desinstalar")
                                color: Theme.red
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: uninstallMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.plugin.uninstallPackage(packageRow.modelData)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    // Dejar el botón rojo fuera del clic general: el resto de
                    // la fila actualiza/instala; este extremo desinstala.
                    anchors.rightMargin: uninstallAction.visible
                        ? uninstallAction.width + 12 : 0
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: view.plugin.index = packageRow.index
                    onClicked: {
                        view.plugin.index = packageRow.index
                        view.plugin.launchSelected()
                    }
                }
            }

            IslandLabel {
                anchors.centerIn: parent
                visible: view.plugin.packageMatches.length === 0
                text: view.plugin.packageQuery().length < 2
                    ? Idioma.t("Escribe al menos dos letras")
                    : view.plugin.aurSearching ? Idioma.t("Buscando…") : Idioma.t("Ningún paquete coincide")
                color: Theme.muted
                font.pixelSize: 13
            }
        }

        // ── las actualizaciones, de camino ────────────────────────
        //
        //  El lanzador es la puerta de cada día, así que el aviso vive
        //  aquí — y SOLO cuando hay algo que hacer: un pie permanente en
        //  un lanzador estilo Spotlight es un mueble que estorba.
        Rectangle {
            visible: Paquetes.pendientes > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: 10
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                spacing: 8

                IconGlyph {
                    text: String.fromCodePoint(0xF06B0)   // md-update
                    color: Theme.yellow
                    font.pixelSize: 13
                }

                IslandLabel {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Idioma.f(Idioma.t("%1 actualizaciones del sistema (%2)"),
                                   String(Paquetes.pendientes),
                                   Math.max(0, Paquetes.pendientesRepo)
                                       + " repos · "
                                       + Math.max(0, Paquetes.pendientesAur)
                                       + " AUR")
                    color: Theme.muted
                    font.pixelSize: 11
                }

                //  Elegir cuáles: salta al centro de aplicaciones, que es
                //  donde cabe una lista con un interruptor por paquete. El
                //  lanzador avisa; la elección fina vive en la otra puerta.
                Rectangle {
                    Layout.preferredWidth: elegirTexto.implicitWidth + 20
                    Layout.preferredHeight: 24
                    radius: 12
                    color: "transparent"
                    border.width: 1
                    border.color: elegirRaton.containsMouse ? Theme.muted
                                                            : Theme.dim

                    IslandLabel {
                        id: elegirTexto
                        anchors.centerIn: parent
                        text: Idioma.t("Elegir")
                        font.pixelSize: 10
                        color: elegirRaton.containsMouse ? Theme.ink
                                                         : Theme.muted
                    }

                    MouseArea {
                        id: elegirRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.plugin.close()
                            const apps = PluginManager.instancia("apps")
                            if (apps)
                                apps.abrirActualizaciones()
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: subirTexto.implicitWidth + 20
                    Layout.preferredHeight: 24
                    radius: 12
                    color: subirRaton.containsMouse
                        ? Qt.lighter(Theme.blue, 1.15) : Theme.blue

                    IslandLabel {
                        id: subirTexto
                        anchors.centerIn: parent
                        text: Idioma.t("Actualizar")
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: subirRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Paquetes.actualizarTodo()
                            view.plugin.close()
                        }
                    }
                }
            }
        }
    }
}
