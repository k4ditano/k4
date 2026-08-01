pragma Singleton

//  La huella: datos personales del usuario, agregados y con doble llave.
//
//  Regla primera: TODO apagado de fábrica. Un plugin que quiera leer una
//  fuente necesita las dos llaves — declarar `datos-personales` en su
//  manifiesto Y que el usuario haya encendido ESA fuente en Ajustes →
//  «Datos personales». Sin las dos, recibe un objeto vacío y `activa()`
//  contesta false: nunca rompe, nunca ve.
//
//  Regla segunda: agregados, jamás crudos. Los lectores viven en
//  tools/huella.py y condensan en python, antes de tocar QML. Aquí solo
//  llega el resumen, vive en memoria como mucho un día, y `olvidar()` lo
//  borra en el acto (memoria y la carpeta de estado, por si algún día se
//  cachea ahí).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: huella

    readonly property string carpeta:
        Quickshell.env("HOME") + "/.local/state/k4/huella"

    //  Lo que cada fuente contestó (el JSON del lector, ya agregado).
    property var steam: ({})
    property var paquetes: ({})

    function activa(fuente) {
        if (!Settings.huellaActiva)
            return false
        if (fuente === "steam")
            return Settings.huellaSteam
        if (fuente === "paquetes")
            return Settings.huellaPaquetes
        return false
    }

    //  Cada fuente se lee al encenderse y como mucho una vez al día: la
    //  huella es un retrato, no una vigilancia.
    property string _diaLeido: ""

    property var _relee: Timer {
        interval: 3600000
        repeat: true
        running: Settings.huellaActiva
        onTriggered: huella._leerTodo()
    }

    property var _alEncender: Connections {
        target: Settings
        function onHuellaActivaChanged() { huella._leerTodo() }
        function onHuellaSteamChanged() { huella._leerTodo() }
        function onHuellaPaquetesChanged() { huella._leerTodo() }
    }

    Component.onCompleted: _leerTodo()

    function _leerTodo() {
        const dia = new Date().toISOString().slice(0, 10)
        const otraVez = dia !== _diaLeido
        if (activa("steam") && (otraVez || !steam.ok))
            _lectorSteam.running = true
        if (activa("paquetes") && (otraVez || !paquetes.ok))
            _lectorPaquetes.running = true
        if (!Settings.huellaActiva) {
            steam = {}
            paquetes = {}
        }
        _diaLeido = dia
    }

    //  Olvidar es olvidar: memoria y disco, en el acto.
    function olvidar() {
        steam = {}
        paquetes = {}
        _diaLeido = ""
        Quickshell.execDetached(["rm", "-rf", carpeta])
    }

    property var _lectorSteam: Process {
        command: ["python3", Quickshell.shellPath("tools/huella.py"), "steam"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { huella.steam = JSON.parse(this.text) } catch (e) { }
            }
        }
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("huella:", l)
            }
        }
    }

    property var _lectorPaquetes: Process {
        command: ["python3", Quickshell.shellPath("tools/huella.py"), "paquetes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { huella.paquetes = JSON.parse(this.text) } catch (e) { }
            }
        }
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("huella:", l)
            }
        }
    }
}
