pragma Singleton

//  Estado del equipo: CPU, RAM, GPU, red, disco y quién se lo está comiendo.
//
//  El muestreo lo hace tools/sistema.py, que publica una línea JSON cada dos
//  segundos. Podría leerse /proc desde aquí, pero acabaría en media docena de
//  FileView releyendo ficheros y calculando diferencias a mano: casi todo lo
//  que interesa —el uso de CPU, el tráfico de red, lo que come cada proceso—
//  no es un valor, es un ritmo, y hace falta comparar dos muestras.
//
//  Solo se muestrea mientras alguien mira. Un monitor que sondea el sistema
//  las veinticuatro horas para nadie es justo el tipo de cosa que hace que una
//  barra se gane su fama de pesada.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: sistema

    // Cuántas muestras guarda cada gráfica. A dos segundos por muestra son
    // unos dos minutos de historia, que es lo que se lee de un vistazo.
    readonly property int historia: 45

    property bool mirando: false        // lo enciende el módulo al abrirse
    property bool cargado: false

    // ── últimas lecturas ──────────────────────────────────────────
    property real cpuUso: 0
    property real cpuTemp: 0
    property int cpuHilos: 0

    property real ramUsada: 0
    property real ramTotal: 0
    property real ramPct: 0
    property real swapUsada: 0
    property real swapTotal: 0

    property string gpuNombre: ""
    property real gpuUso: 0
    property real gpuTemp: 0
    property real gpuMemUsada: 0
    property real gpuMemTotal: 0
    readonly property bool hayGpu: gpuNombre.length > 0

    property string redIface: ""
    property real redRx: 0
    property real redTx: 0

    property real discoUsado: 0
    property real discoTotal: 0
    property real discoPct: 0
    property real tempNvme: 0

    property var procesos: []

    // ── historia para las gráficas ────────────────────────────────
    property var cpuHist: []
    property var ramHist: []
    property var gpuHist: []
    property var redHist: []            // rx+tx por segundo

    function empujar(lista, valor) {
        const salida = lista.slice()
        salida.push(valor)
        while (salida.length > historia)
            salida.shift()
        return salida
    }

    // ── texto ─────────────────────────────────────────────────────
    function tasa(bytes) {
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB/s"
        if (bytes >= 1024) return Math.round(bytes / 1024) + " KB/s"
        return Math.round(bytes) + " B/s"
    }

    function grados(t) { return t > 0 ? Math.round(t) + "°" : "—" }

    function matar(pid) {
        verdugo.command = ["kill", String(pid)]
        verdugo.running = true
    }

    Process { id: verdugo }

    // ── el muestreador ────────────────────────────────────────────
    Process {
        //  La voz de error, que antes se tiraba: si esto
        //  falla, el motivo queda en el log de la barra.
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("sistema:", l)
            }
        }
        id: muestreo
        command: ["python3", Quickshell.shellPath("tools/sistema.py")]
        running: sistema.mirando

        stdout: SplitParser {
            onRead: function (linea) {
                let d = null
                try {
                    d = JSON.parse(linea)
                } catch (e) {
                    return
                }
                sistema.aplicar(d)
            }
        }
    }

    function aplicar(d) {
        if (d.cpu) {
            cpuUso = d.cpu.uso
            cpuTemp = d.cpu.temp || 0
            cpuHilos = d.cpu.hilos || 0
            cpuHist = empujar(cpuHist, cpuUso)
        }

        if (d.ram) {
            ramUsada = d.ram.usada
            ramTotal = d.ram.total
            ramPct = d.ram.pct
            swapUsada = d.ram.swapUsada
            swapTotal = d.ram.swapTotal
            ramHist = empujar(ramHist, ramPct)
        }

        if (d.gpu) {
            gpuNombre = d.gpu.nombre
            gpuUso = d.gpu.uso
            gpuTemp = d.gpu.temp
            gpuMemUsada = d.gpu.memUsada
            gpuMemTotal = d.gpu.memTotal
            gpuHist = empujar(gpuHist, gpuUso)
        }

        if (d.red) {
            redIface = d.red.iface
            redRx = d.red.rx
            redTx = d.red.tx
            redHist = empujar(redHist, redRx + redTx)
        }

        if (d.disco) {
            discoUsado = d.disco.usado
            discoTotal = d.disco.total
            discoPct = d.disco.pct
        }

        tempNvme = d.tempNvme || 0
        procesos = d.procesos || []
        cargado = true
    }
}
