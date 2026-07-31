//  Snake en la island: la prueba de que con la API pública se hacen juegos.
//
//  Todo el juego está escrito contra K4 y QtQuick, nada más: el tablero es un
//  estado en el plugin, el tick un Timer, el control las flechas —con el
//  teclado en exclusiva solo mientras se juega— y el récord un K4.Guardado.
//
//      cp -r ejemplos/snake ~/.config/k4/plugins/
//      quickshell ipc -p …/shell.qml call k4 pluginEnable snake
//      quickshell ipc -p …/shell.qml call k4.snake toggle

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "snake"
    title: "Snake"
    priority: 66
    active: abierto
    //  El teclado entero, pero solo mientras el juego está en marcha: en la
    //  pantalla de inicio basta el opcional, y así ESC sigue siendo del
    //  escritorio hasta que empiezas.
    grabKeyboard: abierto && enMarcha
    tecladoOpcional: abierto
    islandWidth: 460
    islandHeight: 420

    property bool abierto: false

    // ── el tablero ────────────────────────────────────────────────
    //  17×14 casillas: cabe en la island con celdas de 24 y deja sitio al
    //  marcador. La serpiente es una lista de índices (x + y*ancho), la cabeza
    //  la primera.
    readonly property int ancho: 17
    readonly property int alto: 14

    property var serpiente: []
    property int comida: -1
    property int dx: 1
    property int dy: 0
    //  El giro pendiente se aplica en el TICK, no al pulsar: dos giros entre
    //  dos ticks permitirían darse la vuelta sobre uno mismo y morder el
    //  cuello, que es la muerte más injusta del snake.
    property int pdx: 1
    property int pdy: 0
    property bool enMarcha: false
    property bool muerto: false
    property int puntos: 0
    property int record: 0

    view: Component { SnakeView { plugin: self } }

    property var guardado: K4.Guardado {
        plugin: "snake"
        onCargado: function (d) { self.record = d.record || 0 }
    }

    function empezar() {
        const c = Math.floor(alto / 2) * ancho + 3
        serpiente = [c + 2, c + 1, c]
        dx = 1; dy = 0; pdx = 1; pdy = 0
        puntos = 0
        muerto = false
        enMarcha = true
        soltarComida()
    }

    function soltarComida() {
        //  En una casilla libre. Con el tablero casi lleno esto podría dar
        //  vueltas; a 238 casillas no es un problema real.
        let sitio = -1
        do {
            sitio = Math.floor(Math.random() * ancho * alto)
        } while (serpiente.indexOf(sitio) >= 0)
        comida = sitio
    }

    function girar(gx, gy) {
        if (!enMarcha)
            return
        // Nada de invertir el sentido: la serpiente no camina hacia atrás.
        if (gx === -dx && gy === -dy)
            return
        pdx = gx
        pdy = gy
    }

    function tick() {
        dx = pdx
        dy = pdy
        const cabeza = serpiente[0]
        const x = cabeza % ancho + dx
        const y = Math.floor(cabeza / ancho) + dy

        //  Chocar con el borde o con uno mismo es morir. La cola no cuenta si
        //  este mismo tick la va a soltar, pero esa fineza no compensa el lío:
        //  aquí la cola cuenta, como en el Nokia.
        const nueva = y * ancho + x
        if (x < 0 || x >= ancho || y < 0 || y >= alto
                || serpiente.indexOf(nueva) >= 0) {
            enMarcha = false
            muerto = true
            if (puntos > record) {
                record = puntos
                guardado.guardar({ record: record })
            }
            return
        }

        let s = [nueva].concat(serpiente)
        if (nueva === comida) {
            puntos += 1
            soltarComida()
            // No se corta la cola: comer es crecer.
        } else {
            s.pop()
        }
        serpiente = s
    }

    //  El tick, algo más vivo con cada pieza: empieza tranquilo y a 30 puntos
    //  va al doble. Es la curva del original.
    property var reloj: Timer {
        interval: Math.max(90, 180 - self.puntos * 3)
        repeat: true
        running: self.enMarcha && self.abierto
        onTriggered: self.tick()
    }

    K4.Ipc {
        target: "k4.snake"
        function toggle(): void { self.abierto = !self.abierto }
        function close(): void { self.abierto = false; self.enMarcha = false }
        //  Para poder probar el juego sin ratón ni ventana: empezar, girar y
        //  leer el estado por IPC.
        function empezar(): void { self.empezar() }
        function girar(gx: int, gy: int): void { self.girar(gx, gy) }
        function estado(): string {
            return JSON.stringify({
                enMarcha: self.enMarcha, muerto: self.muerto,
                puntos: self.puntos, record: self.record,
                largo: self.serpiente.length,
                cabeza: self.serpiente[0], comida: self.comida,
                ancho: self.ancho })
        }
    }
}
