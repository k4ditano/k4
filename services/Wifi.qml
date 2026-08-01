pragma Singleton

//  Wi‑Fi vía NetworkManager.
//
//  El escáner solo se enciende mientras alguien mira la lista: dejarlo puesto
//  gasta radio y batería para nada. Quien enseñe las redes pone `scanning`.
//
//  Aquí sondeaba antes un `nmcli` cada cuatro segundos solo para saber el
//  nombre de la red — novecientos procesos por hora para un dato que
//  `Networking` ya tiene y notifica. El nombre es ahora un cálculo reactivo
//  sobre las mismas señales que ya alimentaban la lista de redes.

import QtQuick
import Quickshell
import Quickshell.Networking
import "../core"

Singleton {
    id: wifi

    //  El interruptor de la radio.
    //
    //  Vive aquí y no en la vista porque `Networking` es de Quickshell, y un
    //  plugin no debe importarlo: los servicios son implementación y sí pueden,
    //  la superficie pública no.
    property alias activada: interruptorWifi.encendida

    readonly property string name: {
        const devices = Networking.devices.values
        for (let i = 0; i < devices.length; ++i) {
            const dev = devices[i]
            if (dev.type !== DeviceType.Wifi || !dev.connected)
                continue
            const list = dev.networks.values
            for (let j = 0; j < list.length; ++j)
                if (list[j].connected)
                    return list[j].name
        }
        return Networking.wifiEnabled ? "Buscando Wi‑Fi…" : "Wi‑Fi apagada"
    }
    property var pskTarget: null        // red esperando contraseña
    property string pskInput: ""
    property string notice: ""

    // Lo pone la vista que esté enseñando la lista de redes.
    property bool scanning: false

    readonly property var device: {
        const devices = Networking.devices.values
        for (let i = 0; i < devices.length; ++i) {
            if (devices[i].type === DeviceType.Wifi)
                return devices[i]
        }
        return null
    }

    readonly property var networks: {
        if (!device)
            return []

        const list = device.networks.values.slice()
        list.sort(function (a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1
            if (a.known !== b.known)
                return a.known ? -1 : 1
            return (b.signalStrength || 0) - (a.signalStrength || 0)
        })
        return list
    }

    function strengthIcon(network) {
        const strength = network && network.signalStrength ? network.signalStrength : 0
        if (strength >= 0.75) return Theme.ico.wifi4
        if (strength >= 0.5) return Theme.ico.wifi3
        if (strength >= 0.25) return Theme.ico.wifi2
        if (strength > 0) return Theme.ico.wifi1
        return Theme.ico.wifi0
    }

    function isSecure(network) {
        if (!network)
            return false

        // Open y Owe (Enhanced Open) no piden credenciales
        return network.security !== WifiSecurityType.Open
            && network.security !== WifiSecurityType.Owe
    }

    // connectWithPsk solo vale para estas; en EAP/empresa hay que tirar de
    // perfil de NetworkManager, así que ahí se intenta connect() a secas.
    function needsPsk(network) {
        if (!network)
            return false

        return network.security === WifiSecurityType.WpaPsk
            || network.security === WifiSecurityType.Wpa2Psk
            || network.security === WifiSecurityType.Sae
    }

    function status(network) {
        if (!network)
            return ""
        if (network.stateChanging)
            return network.connected ? "Desconectando…" : "Conectando…"
        if (network.connected)
            return "Conectada"
        if (network.known)
            return "Guardada"
        return isSecure(network) ? "Protegida" : "Abierta"
    }

    function activate(network) {
        if (!network)
            return

        notice = ""

        if (network.connected) {
            network.disconnect()
            return
        }

        if (network.known || !needsPsk(network)) {
            network.connect()
            return
        }

        // red protegida y sin credenciales guardadas: hace falta la contraseña
        pskInput = ""
        pskTarget = network
    }

    function submitPsk() {
        const network = pskTarget
        if (!network)
            return

        if (pskInput.length > 0)
            network.connectWithPsk(pskInput)

        pskInput = ""
        pskTarget = null
    }

    function cancelPsk() {
        pskInput = ""
        pskTarget = null
    }

    Binding {
        target: wifi.device
        property: "scannerEnabled"
        value: wifi.scanning
        when: wifi.device !== null
    }

    QtObject {
        id: interruptorWifi
        property bool encendida: Networking.wifiEnabled
        onEncendidaChanged: if (Networking.wifiEnabled !== encendida)
                                Networking.wifiEnabled = encendida
    }
}
