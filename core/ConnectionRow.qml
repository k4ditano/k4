// Fila de una red Wi‑Fi o de un dispositivo Bluetooth

import QtQuick
import "../services"
import QtQuick.Layouts

Rectangle {
    id: row

    property string glyph
    property string title
    property string subtitle
    property bool active: false
    property bool busy: false
    property bool secure: false
    property bool forgettable: false
    signal activated()
    signal forgotten()

    height: 46
    radius: 12
    color: rowMouse.containsMouse ? Theme.surfaceHi : "transparent"

    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.activated()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 12

        IconGlyph {
            text: row.glyph
            color: row.active ? Theme.blue : Theme.ink
            font.pixelSize: 17
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 6

                IslandLabel {
                    text: row.title
                    font.pixelSize: 13
                    font.weight: row.active ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                IconGlyph {
                    visible: row.secure
                    text: Theme.ico.lock
                    color: Theme.dim
                    font.pixelSize: 10
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            IslandLabel {
                text: row.subtitle
                color: row.active ? Theme.green : Theme.muted
                font.pixelSize: 10
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        IslandLabel {
            visible: rowMouse.containsMouse && !row.busy
            text: row.active ? Idioma.t("Desconectar") : Idioma.t("Conectar")
            color: Theme.muted
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter
        }

        IconGlyph {
            visible: row.busy
            text: Theme.ico.loading
            color: Theme.muted
            font.pixelSize: 14
            Layout.alignment: Qt.AlignVCenter

            RotationAnimation on rotation {
                running: row.busy
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
            }
        }

        Rectangle {
            visible: row.forgettable && rowMouse.containsMouse
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            Layout.alignment: Qt.AlignVCenter
            radius: 13
            color: forgetMouse.containsMouse ? Theme.track : "transparent"

            IconGlyph {
                anchors.centerIn: parent
                text: Theme.ico.linkOff
                color: forgetMouse.containsMouse ? Theme.ink : Theme.dim
                font.pixelSize: 13
            }

            MouseArea {
                id: forgetMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: row.forgotten()
            }
        }
    }
}
