//  Un proceso externo.
//
//  Envuelve el de Quickshell y de paso resuelve la parte incómoda: elegir cómo
//  se lee la salida. En k4 hay dos formas y solo dos —una línea JSON por
//  muestra, o todo de golpe al terminar—, así que en vez de obligar a montar un
//  SplitParser o un StdioCollector a mano, se dice `porLineas` y ya.
//
//      K4.Process {
//          command: ["python3", K4.Paths.guion("sistema.py")]
//          running: mirando
//          porLineas: true
//          onLinea: function (l) { ... }
//      }

import QtQuick
import Quickshell.Io as Qs

QtObject {
    id: self

    property list<string> command: []
    property bool running: false
    property string workingDirectory: ""

    // Variables extra para el proceso. El caso típico es LC_ALL=C, para que la
    // salida de un mandato venga en inglés y se pueda parsear igual en
    // cualquier idioma.
    property var environment: ({})

    // Una señal `linea` por cada línea, en vez de `salida` con todo al final.
    // Para un proceso que va informando mientras trabaja es la diferencia entre
    // ver el progreso y esperar a que acabe.
    property bool porLineas: false

    // Poder escribirle por la entrada estándar. Apagado por defecto: si nadie
    // va a hablarle, dejarle la entrada abierta solo sirve para que no se
    // entere de que ya no hay nada que leer.
    property bool entradaAbierta: false

    signal arrancado()
    signal linea(string texto)
    signal salida(string texto)
    signal terminado(int codigo)

    // La salida de error, siempre por líneas: es como sale y como se lee.
    signal lineaError(string texto)

    function escribir(texto) { _proc.write(texto) }

    //  Parar por las buenas. El 2 es SIGINT, que es lo que hay que mandarle a
    //  cualquier cosa que esté escribiendo un fichero: matarlo a secas deja el
    //  fichero a medias. Un grabador de vídeo sin su índice no lo abre nadie.
    function parar(senal) { _proc.signal(senal === undefined ? 2 : senal) }

    // Vale 0 cuando no está corriendo: `processId` es nulo entonces, y Qt se
    // queja en cada evaluación de que no puede meter un nulo en un entero.
    readonly property int pid: _proc.processId || 0

    // ── por debajo ────────────────────────────────────────────────
    property Qs.SplitParser _lineas: Qs.SplitParser {
        onRead: function (l) { self.linea(l) }
    }

    property Qs.StdioCollector _todo: Qs.StdioCollector {
        onStreamFinished: self.salida(this.text)
    }

    property Qs.SplitParser _error: Qs.SplitParser {
        onRead: function (l) { self.lineaError(l) }
    }

    property Qs.Process _proc: Qs.Process {
        command: self.command
        running: self.running
        workingDirectory: self.workingDirectory
        environment: self.environment
        stdinEnabled: self.entradaAbierta
        stdout: self.porLineas ? self._lineas : self._todo
        stderr: self._error

        onStarted: self.arrancado()
        onExited: function (codigo) {
            // Devolver la bandera es cosa nuestra: si no, quien nos usa cree
            // que sigue corriendo y no vuelve a lanzarlo nunca.
            self.running = false
            self.terminado(codigo)
        }
    }
}
