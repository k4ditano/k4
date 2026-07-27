//  Fila de iconos de bandeja.
//
//  Va en la píldora y también en las vistas de hover (reloj y reproductor), y
//  ese doble sitio no es capricho: al acercar el ratón la island cambia de
//  vista, así que unos iconos que solo estuvieran en la píldora desaparecen
//  justo antes de que puedas pulsarlos. En la píldora son indicadores; donde
//  se puede pinchar de verdad es en la vista ya desplegada, que no se mueve
//  mientras mantengas el ratón encima.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: row

    // cuántos iconos se enseñan antes de resumir el resto como "+n"
    property int max: 4
    property int iconSize: 14
    // en la píldora no: los objetivos son diminutos y un fallo lanzaría una
    // aplicación cuando lo que querías era el centro de control
    property bool interactive: false

    // se emite al pedir la bandeja entera (clic derecho)
    signal menuRequested()

    readonly property int shown: Math.min(Tray.count, max)

    visible: Tray.count > 0 && (interactive || Settings.bandejaEnPildora)
    spacing: 4

    Repeater {
        model: Tray.sorted.slice(0, row.shown)

        delegate: Item {
            id: cell
            required property var modelData

            Layout.preferredWidth: row.iconSize + (row.interactive ? 8 : 0)
            Layout.preferredHeight: row.iconSize + (row.interactive ? 6 : 0)
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.fill: parent
                radius: 6
                visible: row.interactive && cellMouse.containsMouse
                color: Theme.surfaceHi
            }

            Image {
                anchors.centerIn: parent
                width: row.iconSize
                height: row.iconSize
                source: cell.modelData.icon
                sourceSize.width: row.iconSize * 2
                sourceSize.height: row.iconSize * 2
                fillMode: Image.PreserveAspectFit
                opacity: cell.modelData.status === 2 ? 1 : 0.85

                // NeedsAttention: late, que para eso lo pide
                SequentialAnimation on opacity {
                    running: cell.modelData.status === 2
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            MouseArea {
                id: cellMouse
                anchors.fill: parent
                enabled: row.interactive
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                onClicked: function (mouse) {
                    if (mouse.button === Qt.RightButton)
                        row.menuRequested()          // el menú vive en el módulo
                    else if (mouse.button === Qt.MiddleButton)
                        Tray.secondary(cell.modelData)
                    else if (!Tray.primary(cell.modelData))
                        row.menuRequested()          // solo tiene menú: enséñalo
                }

                onWheel: function (wheel) {
                    cell.modelData.scroll(wheel.angleDelta.y, false)
                }
            }
        }
    }

    IslandLabel {
        visible: Tray.count > row.shown
        text: "+" + (Tray.count - row.shown)
        color: Theme.muted
        font.pixelSize: 10
        Layout.alignment: Qt.AlignVCenter

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            enabled: row.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: row.menuRequested()
        }
    }
}
