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

    //  Emparejar NO es conectar, y sin confianza no dura.
    //
    //  Esto solo emparejaba, y con unos auriculares pasaba lo peor: bluez
    //  los conecta un momento al terminar el emparejamiento —así que la fila
    //  llegaba a decir «Conectado»—, pero sin `trusted` no autoriza los
    //  perfiles de audio, el aparato se cae a los pocos segundos y, como no
    //  está emparejado del todo ni hay descubrimiento al cerrar la pestaña,
    //  bluez lo borra de su árbol: la fila DESAPARECÍA de la lista. Parecía
    //  que la barra los perdía y en realidad nunca llegaban a asentarse.
    //
    //  La confianza va antes de conectar: es lo que hace que mañana, al
    //  sacarlos del estuche, vuelvan solos sin abrir esto.
    function activate(device) {
        if (!device)
            return

        if (device.connected) {
            device.disconnect()
            return
        }

        if (device.paired || device.bonded) {
            if (!device.trusted)
                device.trusted = true
            device.connect()
            return
        }

        //  Uno nuevo: emparejar y, cuando bluez conteste, seguir solo. Un
        //  segundo toque para conectar es una pregunta que nadie quiere
        //  responder —quien pulsa unos auriculares quiere oírlos—.
        _reciente = device
        device.pair()
    }

    //  A quién seguimos: SOLO al que se acaba de tocar. Vigilar a todos los
    //  emparejados conectaría solo el móvil o la tele en cuanto pasaran por
    //  el radio, y eso no lo ha pedido nadie.
    property var _reciente: null

    property Connections _trasEmparejar: Connections {
        target: bt._reciente

        function _rematar() {
            const d = bt._reciente
            if (!d || d.pairing || !(d.paired || d.bonded))
                return
            if (!d.trusted)
                d.trusted = true
            if (!d.connected)
                d.connect()
            bt._reciente = null
        }

        function onPairedChanged() { _rematar() }
        function onBondedChanged() { _rematar() }
        function onPairingChanged() { _rematar() }
    }

    Binding {
        target: Bluetooth.defaultAdapter
        property: "discovering"
        value: bt.discovering
        when: Bluetooth.defaultAdapter !== null
    }
}
