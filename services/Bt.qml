pragma Singleton

//  Bluetooth vía bluez. Mismo trato que el Wi‑Fi: el descubrimiento solo se
//  enciende mientras alguien mira la lista.

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
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
        //  El emparejamiento lo lleva bluetoothctl, así que su estado no
        //  llega por `pairing`: lo dice el servicio.
        if (emparejando === device.address)
            return "Emparejando…"
        if (falloEmparejar === device.address && !device.paired)
            return "No se pudo emparejar"
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

        //  Uno nuevo: emparejar CON AGENTE, que es lo que faltaba.
        //
        //  `device.pair()` sale por la API de Quickshell, y esa API no
        //  registra ningún agente de emparejamiento: solo publica el estado.
        //  Sin agente que atienda la negociación, bluez abre el enlace, el
        //  bonding no llega a cuajar y a los dos segundos él mismo cierra y
        //  desempareja. En el volcado del HCI se ve enterito: `Disconnect`
        //  salido de aquí, y detrás un `Unpair Device` que el kernel contesta
        //  con «Not Paired» —nunca hubo clave de enlace—. Por eso el aparato
        //  hacía su ruido de conexión y se caía solo, y por eso tampoco
        //  volvía al sacarlo del estuche: sin clave no hay a qué volver.
        //
        //  bluetoothctl SÍ registra su agente al arrancar, así que el
        //  emparejamiento inicial se le encarga a él. Lo demás —conectar,
        //  desconectar, confiar— sigue por la API, que para eso vale.
        emparejar(device)
    }

    //  ── el emparejamiento, por bluetoothctl ──────────────────────

    //  A quién estamos emparejando ahora mismo, para que la fila lo diga.
    property string emparejando: ""
    property string falloEmparejar: ""

    function emparejar(device) {
        if (!device || _agente.running)
            return
        //  La dirección se mete en una orden de shell: se comprueba que sea
        //  una MAC y nada más. Viene de bluez, pero un servicio no da por
        //  bueno lo que le llega solo porque el remitente sea de casa.
        const mac = String(device.address || "")
        if (!/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(mac))
            return

        _reciente = device
        emparejando = mac
        falloEmparejar = ""

        //  La sesión entera por la entrada de bluetoothctl, y no `pair` a
        //  secas, porque hace falta el ESCANEO: sin descubrimiento bluez no
        //  tiene el aparato en su árbol y contesta «not available» —con
        //  código 0, para más señas—. Es la misma secuencia que se comprobó
        //  a mano: buscar, emparejar, confiar y conectar, con sus esperas.
        //
        //  `--agent KeyboardDisplay` es lo que trae de verdad bluetoothctl a
        //  esta historia: cubre el «just works» de unos auriculares y el
        //  código en pantalla de un teclado o un móvil.
        _agente.command = ["sh", "-c",
            "{ echo 'scan on'; sleep 4;"
            + " echo 'pair " + mac + "'; sleep 9;"
            + " echo 'trust " + mac + "'; sleep 1;"
            + " echo 'connect " + mac + "'; sleep 7;"
            + " echo quit; } | bluetoothctl --agent KeyboardDisplay"]
        _agente.running = true
    }

    property Process _agente: Process {
        running: false

        stdout: StdioCollector { }
        stderr: StdioCollector { }

        onExited: function (code, status) {
            const d = bt._reciente
            bt.emparejando = ""
            if (!d) {
                bt._reciente = null
                return
            }
            //  Emparejado: confiar y conectar. Si no, decirlo —callarse un
            //  fallo aquí deja al usuario tocando una fila que no responde.
            if (d.paired || d.bonded) {
                if (!d.trusted)
                    d.trusted = true
                bt._vigilancia.vueltas = 0
                bt._vigilancia.restart()
            } else {
                bt.falloEmparejar = d.address
                bt._reciente = null
            }
        }
    }

    //  A quién seguimos: SOLO al que se acaba de tocar. Vigilar a todos los
    //  emparejados conectaría solo el móvil o la tele en cuanto pasaran por
    //  el radio, y eso no lo ha pedido nadie.
    property var _reciente: null

    //  Insistir un rato, porque la primera conexión NO es la buena.
    //
    //  Bluez abre una conexión mientras empareja, y con estos auriculares esa
    //  se cae sola un par de segundos después de terminar —medido: conecta,
    //  empareja, y a los dos segundos se cae—. Un `connect()` disparado al
    //  ver `paired` llega cuando todavía está la conexión del emparejamiento
    //  en pie, no hace nada, y cuando se cae ya no queda nadie mirando: el
    //  aparato se quedaba muerto justo después de decir «Conectado», que es
    //  exactamente lo que se veía.
    //
    //  Así que después de emparejar se vigila unos segundos y se reconecta
    //  cada vez que se caiga. Se suelta al agotar las vueltas y no al primer
    //  «conectado»: darlo por bueno antes es el fallo que arregla esto.
    property Timer _vigilancia: Timer {
        property int vueltas: 0

        interval: 1500
        repeat: true

        onTriggered: {
            const d = bt._reciente
            vueltas++
            if (!d || !(d.paired || d.bonded) || vueltas > 6) {
                stop()
                bt._reciente = null
                return
            }
            if (!d.connected)
                d.connect()
        }
    }

    Binding {
        target: Bluetooth.defaultAdapter
        property: "discovering"
        value: bt.discovering
        when: Bluetooth.defaultAdapter !== null
    }
}
