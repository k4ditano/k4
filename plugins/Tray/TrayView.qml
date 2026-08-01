import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    readonly property var selected: plugin.selected

    // Abre el menú DBus de la aplicación seleccionada y expone sus entradas.
    K4.MenuBandeja {
        id: opener
        menu: view.selected && view.selected.hasMenu ? view.selected.menu : null
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
            Layout.preferredHeight: 28
            spacing: 10

            IconGlyph {
                text: Theme.ico.devices
                color: Theme.muted
                font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Idioma.t("Bandeja del sistema")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Tray.count === 0 ? "" : Tray.count + (Tray.count === 1 ? Idioma.t(" aplicación") : Idioma.t(" aplicaciones"))
                color: Theme.muted
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 16
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── cuerpo
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // ── aplicaciones
            Rectangle {
                Layout.preferredWidth: 250
                Layout.fillHeight: true
                radius: 16
                color: Theme.surface

                ListView {
                    //  La barra de la casa: sale sola si hay más de lo que cabe.
                    ScrollBar.vertical: IslandScrollBar {}
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    spacing: 2
                    model: Tray.sorted
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        readonly property bool current: view.selected === modelData

                        width: ListView.view.width
                        height: 46
                        radius: 10
                        color: appRow.current ? Theme.surfaceHi
                            : (appMouse.containsMouse ? "#26262a" : "transparent")

                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Image {
                                source: appRow.modelData.icon
                                sourceSize.width: 44
                                sourceSize.height: 44
                                fillMode: Image.PreserveAspectFit
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                Layout.alignment: Qt.AlignVCenter

                                // NeedsAttention: el icono late para que se note
                                SequentialAnimation on opacity {
                                    running: appRow.modelData.status === 2
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0

                                IslandLabel {
                                    text: Tray.label(appRow.modelData)
                                    font.pixelSize: 12
                                    font.weight: appRow.current ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                IslandLabel {
                                    text: Tray.statusText(appRow.modelData)
                                    color: appRow.modelData.status === 2 ? Theme.red : Theme.muted
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            IconGlyph {
                                visible: appRow.modelData.hasMenu
                                text: Theme.ico.forward
                                color: appRow.current ? Theme.ink : Theme.dim
                                font.pixelSize: 13
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: appMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: function (mouse) {
                                view.plugin.select(appRow.modelData)
                                if (mouse.button === Qt.MiddleButton)
                                    Tray.secondary(appRow.modelData)
                            }
                            onDoubleClicked: Tray.primary(appRow.modelData)

                            // la rueda se la pasamos a la aplicación, que es lo
                            // que espera un icono de bandeja (volumen, etc.)
                            onWheel: function (wheel) {
                                appRow.modelData.scroll(wheel.angleDelta.y, false)
                            }
                        }
                    }

                    IslandLabel {
                        anchors.centerIn: parent
                        anchors.margins: 12
                        width: parent.width - 24
                        visible: Tray.count === 0
                        text: Idioma.t("Ninguna aplicación en la bandeja")
                        color: Theme.muted
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ── menú de la seleccionada
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: Theme.surface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    visible: view.selected !== null

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Image {
                            source: view.selected ? view.selected.icon : ""
                            sourceSize.width: 52
                            sourceSize.height: 52
                            fillMode: Image.PreserveAspectFit
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            IslandLabel {
                                text: Tray.label(view.selected)
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            IslandLabel {
                                text: Tray.detail(view.selected)
                                color: Theme.muted
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // abrir la aplicación: las que solo traen menú no
                        // responden a activate(), así que ahí no se ofrece
                        Rectangle {
                            visible: view.selected !== null && !view.selected.onlyMenu
                            Layout.preferredWidth: openLabel.implicitWidth + 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            radius: 12
                            color: openMouse.containsMouse ? Theme.blue : Theme.surfaceHi

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IslandLabel {
                                id: openLabel
                                anchors.centerIn: parent
                                text: Idioma.t("Abrir")
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: openMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Tray.primary(view.selected)
                                    view.plugin.close()
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.surfaceHi }

                    ListView {
                        //  La barra de la casa: sale sola si hay más de lo que cabe.
                        ScrollBar.vertical: IslandScrollBar {}
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 1
                        model: opener.children
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            id: entryRow
                            required property var modelData
                            width: ListView.view.width
                            height: entryRow.modelData.isSeparator ? 9 : 30

                            // separador
                            Rectangle {
                                visible: entryRow.modelData.isSeparator
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                height: 1
                                color: Theme.surfaceHi
                            }

                            Rectangle {
                                visible: !entryRow.modelData.isSeparator
                                anchors.fill: parent
                                radius: 8
                                color: entryMouse.containsMouse && entryRow.modelData.enabled
                                    ? Theme.surfaceHi : "transparent"

                                Behavior on color { ColorAnimation { duration: 100 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    // casilla o radio, si la entrada lo es
                                    IconGlyph {
                                        visible: entryRow.modelData.buttonType !== 0
                                        text: entryRow.modelData.checkState === Qt.Checked
                                            ? Theme.ico.check : ""
                                        color: Theme.green
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 14
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Image {
                                        visible: entryRow.modelData.icon.length > 0
                                        source: entryRow.modelData.icon
                                        sourceSize.width: 32
                                        sourceSize.height: 32
                                        fillMode: Image.PreserveAspectFit
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    IslandLabel {
                                        text: entryRow.modelData.text
                                        color: entryRow.modelData.enabled ? Theme.ink : Theme.dim
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    IconGlyph {
                                        visible: entryRow.modelData.hasChildren
                                        text: Theme.ico.forward
                                        color: Theme.dim
                                        font.pixelSize: 12
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                MouseArea {
                                    id: entryMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: entryRow.modelData.enabled
                                        ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: entryRow.modelData.enabled
                                        && !entryRow.modelData.hasChildren
                                    onClicked: {
                                        entryRow.modelData.triggered()
                                        view.plugin.close()
                                    }
                                }
                            }
                        }

                        IslandLabel {
                            anchors.centerIn: parent
                            width: parent.width - 24
                            visible: opener.children.values.length === 0
                            text: view.selected && !view.selected.hasMenu
                                ? Idioma.t("Esta aplicación no ofrece menú")
                                : Idioma.t("Cargando menú…")
                            color: Theme.muted
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                IslandLabel {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    visible: view.selected === null
                    text: Idioma.t("Las aplicaciones que arrancaron antes que la barra puede que no aparezcan hasta reiniciarlas")
                    color: Theme.muted
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
