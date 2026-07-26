import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
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
                        ? "Buscar paquetes para instalar" : "Buscar aplicaciones"
                    color: Theme.dim
                    font.pixelSize: 19
                }

                TextInput {
                    id: launcherInput
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
                    : view.plugin.aurSearching ? "buscando en AUR…" : "esc vuelve a apps"
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

                    IconImage {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        visible: appRow.modelData.isInstall !== true
                        source: appRow.modelData.icon.length > 0
                            ? Quickshell.iconPath(appRow.modelData.icon, true) : ""
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
                text: "Sin resultados"
                color: Theme.muted
                font.pixelSize: 13
            }
        }

        // ── resultados de paquetes
        ListView {
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
                                ? "Instalado · " + packageRow.modelData.description
                                : packageRow.modelData.description
                            color: packageRow.modelData.installed ? Theme.green : Theme.muted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    IslandLabel {
                        visible: packageRow.index === view.plugin.index
                        text: packageRow.modelData.installed ? "reinstalar ↵" : "instalar ↵"
                        color: Theme.muted
                        font.pixelSize: 10
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
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
                    ? "Escribe al menos dos letras"
                    : view.plugin.aurSearching ? "Buscando…" : "Ningún paquete coincide"
                color: Theme.muted
                font.pixelSize: 13
            }
        }
    }
}
