pragma Singleton

//  Bluetooth vía bluez. Mismo trato que el Wi‑Fi: el descubrimiento solo se
//  enciende mientras alguien mira la lista.

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../core"

Singleton {
    id: bt

    // Lo pone la vista que esté enseñando la lista de dispositivos.
    property bool discovering: false

    readonly property var adapter: Bluetooth.defaultAdapter

    readonly property var devices: {
        if (!adapter)
            return []

        const list = adapter.devices.values.slice()
        list.sort(function (a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1
            if (a.paired !== b.paired)
                return a.paired ? -1 : 1
            return a.name.localeCompare(b.name)
        })
        return list
    }

    function deviceIcon(device) {
        const icon = device && device.icon ? device.icon : ""
        if (icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1) return Theme.ico.headphones
        if (icon.indexOf("phone") !== -1) return Theme.ico.cellphone
        if (icon.indexOf("mouse") !== -1) return Theme.ico.mouse
        if (icon.indexOf("keyboard") !== -1) return Theme.ico.keyboard
        if (icon.indexOf("speaker") !== -1 || icon.indexOf("audio") !== -1) return Theme.ico.speaker
        if (icon.indexOf("watch") !== -1) return Theme.ico.watch
        if (icon.indexOf("gaming") !== -1 || icon.indexOf("joystick") !== -1) return Theme.ico.gamepad
        if (icon.indexOf("computer") !== -1 || icon.indexOf("laptop") !== -1) return Theme.ico.laptop
        if (icon.indexOf("printer") !== -1) return Theme.ico.printer
        if (icon.indexOf("video") !== -1 || icon.indexOf("tv") !== -1) return Theme.ico.television
        return Theme.ico.devices
    }

    function deviceStatus(device) {
        if (!device)
            return ""
        if (device.pairing)
            return "Emparejando…"
        if (device.connected)
            return device.batteryAvailable
                ? "Conectado · " + Math.round(device.battery * 100) + "%"
                : "Conectado"
        if (device.paired || device.bonded)
            return "Emparejado"
        return "Disponible"
    }

    function activate(device) {
        if (!device)
            return

        if (device.connected)
            device.disconnect()
        else if (device.paired || device.bonded)
            device.connect()
        else
            device.pair()
    }

    Binding {
        target: Bluetooth.defaultAdapter
        property: "discovering"
        value: bt.discovering
        when: Bluetooth.defaultAdapter !== null
    }
}
