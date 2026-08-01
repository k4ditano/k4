//  El detalle de Bluetooth del centro de control. Vivía dentro de
//  PanelView (870 líneas, siete secciones); ahora es una pieza con nombre.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

IslandTile {
    required property var view

    Layout.fillWidth: true
    Layout.fillHeight: true
    pulsable: false
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
                text: !Bt.adapter ? Idioma.t("Sin adaptador")
                    : !Bt.adapter.enabled ? Idioma.t("Bluetooth desactivado")
                    : Bt.adapter.discovering ? Idioma.t("Buscando dispositivos…")
                    : Idioma.t("Dispositivos")
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
            //  La barra de la casa: sale sola si hay más de lo que cabe.
            ScrollBar.vertical: IslandScrollBar {}
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
                    ? Idioma.t("Buscando dispositivos…") : Idioma.t("Activa el Bluetooth para buscar")
                color: Theme.muted
                font.pixelSize: 12
            }
        }
    }
}
