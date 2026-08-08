//  Tira de notificaciones recientes.
//
//  Aparece bajo el reloj y bajo el reproductor al pasar el ratón por la
//  island, que es cuando ya la estás mirando: así se llega a lo que acaba de
//  llegar sin abrir el panel. Pulsar una lleva a su aplicación igual que en el
//  toast; la ✕ la descarta.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

ColumnLayout {
    id: strip

    // cuántas caben sin que la island se convierta en una pared
    property int max: 3

    readonly property int shown: Math.min(Notifs.recent.length, max)
    readonly property int rowHeight: 34

    // alto que necesita quien la incruste, cabecera incluida; la fórmula está
    // en el servicio porque los plugins la usan para dimensionar la island
    readonly property int neededHeight: Settings.notificacionesAlPasar
        ? Notifs.stripHeight(max) : 0

    visible: Notifs.recent.length > 0 && Settings.notificacionesAlPasar
    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 14
        spacing: 6

        IconGlyph {
            text: Theme.ico.bell
            color: Theme.muted
            font.pixelSize: 11
            Layout.alignment: Qt.AlignVCenter
        }

        IslandLabel {
            text: Notifs.recent.length === 1
                ? Idioma.t("1 notificación")
                : Notifs.recent.length + Idioma.t(" notificaciones")
            color: Theme.muted
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        IslandLabel {
            visible: Notifs.recent.length > strip.shown
            text: "+" + (Notifs.recent.length - strip.shown) + Idioma.t(" más")
            color: Theme.dim
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter
        }

        // Vaciar de golpe. Aquí es donde más falta hacía: la tira sale al
        // pasar el ratón por la island, y sin esto había que abrir el panel
        // entero solo para quitarse de encima cuatro avisos leídos.
        Rectangle {
            Layout.preferredWidth: vaciarFila.implicitWidth + 12
            Layout.preferredHeight: 15
            Layout.alignment: Qt.AlignVCenter
            radius: 7
            color: vaciarRaton.containsMouse ? Theme.red : Theme.surfaceHi

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                id: vaciarFila
                anchors.centerIn: parent
                spacing: 3

                IconGlyph {
                    text: Theme.ico.clearAll
                    color: vaciarRaton.containsMouse ? Theme.ink : Theme.muted
                    font.pixelSize: 10
                }

                IslandLabel {
                    text: Idioma.t("Borrar todas")
                    color: vaciarRaton.containsMouse ? Theme.ink : Theme.muted
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }
            }

            MouseArea {
                id: vaciarRaton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Notifs.clear()
            }
        }
    }

    Repeater {
        model: Notifs.recent.slice(0, strip.shown)

        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property string icon: Notifs.iconFor(modelData)

            Layout.fillWidth: true
            Layout.preferredHeight: strip.rowHeight
            radius: 9
            color: rowMouse.containsMouse ? Theme.surfaceHi : Theme.surface

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 4
                spacing: 8

                Image {
                    source: row.icon
                    sourceSize.width: 32
                    sourceSize.height: 32
                    fillMode: Image.PreserveAspectFit
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    Layout.alignment: Qt.AlignVCenter
                    visible: status === Image.Ready
                }

                IconGlyph {
                    visible: row.icon.length === 0
                    text: Theme.ico.bell
                    color: Theme.muted
                    font.pixelSize: 13
                    Layout.preferredWidth: 16
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    //  Una línea cada uno, pase lo que pase.
                    //
                    //  `elide` recorta lo ANCHO, y de lo alto no dice nada: un
                    //  cuerpo con saltos de línea —los cronjobs mandan varias,
                    //  «respuesta \n (job_id: …) \n ---»— se pintaba entero
                    //  hacia abajo y se salía del recuadro, que tiene la altura
                    //  fija de `rowHeight`. El aviso pisaba lo que hubiera
                    //  debajo y la tarjeta parecía rota.
                    //
                    //  Los saltos se sustituyen por espacios en vez de cortar
                    //  por el primero: la primera línea de un cronjob suele ser
                    //  el «Cronjob Response» genérico y lo que dice de verdad
                    //  viene detrás. Así se lee corrido y elide remata.
                    IslandLabel {
                        text: row.modelData.summary.replace(/\s*\n\s*/g, " ")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.fillWidth: true
                    }

                    IslandLabel {
                        text: (row.modelData.body.length > 0
                                ? row.modelData.body : row.modelData.appName)
                              .replace(/\s*\n\s*/g, " ")
                        color: Theme.muted
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.fillWidth: true
                    }
                }

                MediaButton {
                    glyph: Theme.ico.close
                    glyphSize: 12
                    glyphColor: rowMouse.containsMouse ? Theme.ink : Theme.dim
                    onActivated: row.modelData.dismiss()
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // el botón de cerrar va por encima y se queda su propio clic
                onClicked: Notifs.activate(row.modelData)
            }
        }
    }
}
