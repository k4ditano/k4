//  Atalaya — todas tus ventanas, sobre un mismo plano.
//
//  El escritorio se aleja, las ventanas se despegan de donde estaban y se
//  reparten por un plano que se recorre con la rueda y el ratón. Siguen VIVAS
//  ahí dentro —un vídeo se sigue reproduciendo en su miniatura— y cuando te
//  acercas a una, caes en ella.
//
//  ── por qué no es un Alt+Tab con dibujitos ───────────────────────
//
//  Porque lo que falla del Alt+Tab no es la lista: es que hay que recordar el
//  orden para usarlo. Aquí no se recuerda nada, se MIRA. Y lo que se mira es
//  la ventana de verdad, no su título: tres terminales se llaman igual y no se
//  parecen en nada.
//
//  ── de dónde sale la imagen ──────────────────────────────────────
//
//  De `K4.Miniatura`, que por debajo es una captura viva de UN toplevel
//  (`hyprland-toplevel-export`). No es una foto del escritorio recortada: cada
//  ventana se copia por separado, así que salen también las que están en otro
//  escritorio o tapadas por completo. Eso es lo que hace que esto sea un mapa
//  y no un collage de lo que ya se veía.
//
//  ── y la geometría, de hyprctl ───────────────────────────────────
//
//  Un plugin no habla con el compositor: pide `hyprctl -j` por `K4.Process` y
//  lee JSON. Se piden monitores y clientes de una vez y en un solo proceso —no
//  dos— porque entre uno y otro te puede cambiar el escritorio activo debajo,
//  y entonces la mitad de las ventanas se dibujarían donde ya no están.

import QtQuick
import K4 as K4

K4.Plugin {
    id: raiz

    name: "atalaya"
    title: K4.Idioma.t("Atalaya")

    //  No ocupa la island: esto vive en su propia ventana, a pantalla
    //  completa. Nunca se activa. (Ver `teclas`, mismo caso.)
    active: false

    // ── estado ────────────────────────────────────────────────────
    property bool abierto: false

    //  Las ventanas ya masticadas: dirección, título, clase y los dos
    //  rectángulos que le hacen falta a cada tarjeta —dónde está de verdad y
    //  de qué tamaño es—.
    property var ventanas: []

    //  El monitor sobre el que se abre y su tamaño lógico. Lógico y no físico:
    //  lo que QML mide en una `K4.Ventana` son píxeles lógicos, y en una
    //  pantalla con escala los dos números no se parecen.
    property string monitor: ""
    property int monAncho: 1920
    property int monAlto: 1080

    property bool cargando: false
    property string error: ""

    //  Cerrándose. La ventana tiene que seguir existiendo mientras las
    //  tarjetas vuelven a su sitio: sin esto el `K4.Cargador` la destruye en
    //  el mismo cuadro en que se pulsa ESC y el escritorio reaparece de golpe,
    //  que es peor que no animar la entrada.
    property bool saliendo: false

    //  Lo que se está escribiendo para filtrar. Vive AQUÍ y no en la vista
    //  porque la vista se crea y se destruye con cada apertura, y perder lo
    //  escrito al parpadear una recarga es de las cosas que no se perdonan.
    property string filtro: ""
    property int seleccion: -1

    //  La vista, mientras exista. Se presenta ella al nacer.
    property var lienzo: null

    //  Hacia dónde acerca la rueda.
    //
    //  Es un ajuste y no una decisión mía porque no hay respuesta correcta: en
    //  un documento la rueda arriba sube el papel, en un mapa aparta la vista,
    //  y quien tenga el desplazamiento natural del sistema al revés recibe el
    //  signo cambiado antes de que este código lo vea. De fábrica va como en
    //  todo lo que hace zoom: arriba acerca.
    property bool ruedaAlReves: false

    // ── abrir y cerrar ────────────────────────────────────────────
    //
    //  `toggle()` y `close()` con esos nombres porque son los que llama el
    //  host: el centro de aplicaciones abre por `toggle()` y el ESC de la
    //  island cierra por `close()`. Los de dentro se llaman como se llaman
    //  aquí, y estos dos son la puerta.
    function toggle() { alternar() }
    function close() { cerrar() }

    function alternar() {
        if (abierto)
            cerrar()
        else
            abrir()
    }

    function abrir() {
        if (abierto)
            return
        filtro = ""
        seleccion = -1
        error = ""
        cargando = true
        //  La ventana se levanta YA, sin esperar a hyprctl: el velo entrando
        //  mientras se leen los clientes es la diferencia entre «responde» y
        //  «se ha quedado pensando». Las tarjetas llegan solas un cuadro
        //  después.
        abierto = true
        lector.running = false
        lector.running = true
    }

    function cerrar() {
        if (!abierto)
            return
        saliendo = true
        abierto = false
    }

    //  Sin despedida: la usa la caída sobre una ventana, donde lo que hay
    //  debajo ya es la ventana de verdad y la vista está a opacidad cero.
    function cerrarYa() {
        abierto = false
        saliendo = false
    }

    //  Ir a una ventana. El `focuswindow` sale ANTES de que termine la
    //  animación de caída a propósito: el compositor tarda en cambiar de
    //  escritorio, y lanzarlo al final deja un parpadeo del escritorio viejo
    //  justo cuando la miniatura ya ha ocupado la pantalla entera.
    function ir(direccion) {
        //  Sólo una dirección de Hyprland, comprobada. Va dentro de una orden
        //  de shell y viene de fuera del QML: aunque hoy la escriba `hyprctl`
        //  y no una persona, lo que se cuela por una comilla no se arregla
        //  luego.
        if (!/^0x[0-9a-fA-F]+$/.test(String(direccion || "")))
            return

        //  Las DOS formas de pedir el foco, en cascada.
        //
        //  Hyprland tiene dos configuraciones vivas: la de siempre y la de
        //  Lua. En la de Lua `hyprctl dispatch` NO recibe un dispatcher y unos
        //  argumentos, sino una expresión que evalúa —envuelta en
        //  `hl.dispatch(...)`— así que el `focuswindow address:0x…` de toda la
        //  vida se queda en «')' expected near 'address'» y no enfoca nada.
        //  Comprobado aquí: la clásica contesta ese error y la de Lua contesta
        //  «ok».
        //
        //  Se prueba la clásica y, si no contesta «ok», la de Lua. Mirando la
        //  RESPUESTA y no el código de salida, que en el caso que importa sale
        //  cero habiendo fallado.
        const a = "address:" + direccion
        salto.command = ["sh", "-c",
            "out=$(hyprctl dispatch focuswindow '" + a + "' 2>&1); " +
            "[ \"$out\" = ok ] && exit 0; " +
            "hyprctl dispatch \"hl.dsp.focus({ window = '" + a + "' })\""]
        salto.running = false
        salto.running = true
    }

    K4.Guardado {
        id: guardado
        plugin: "atalaya"
        nombre: "ajustes"
        onCargado: function (d) { raiz.ruedaAlReves = d.ruedaAlReves === true }
    }

    K4.Ajustes {
        plugin: "atalaya"
        grupo: K4.Idioma.t("Atalaya")
        desc: K4.Idioma.t("Todas las ventanas sobre un plano")
        glifo: 0xF0570
        opciones: [{
            id: "ruedaAlReves",
            nombre: K4.Idioma.t("Rueda al revés"),
            desc: K4.Idioma.t("Acercarse girando hacia abajo en vez de hacia arriba"),
            glifo: 0xF1552
        }]
        valores: ({ ruedaAlReves: raiz.ruedaAlReves })
        onCambiado: function (id, valor) {
            if (id === "ruedaAlReves") {
                raiz.ruedaAlReves = valor === true
                guardado.guardar({ ruedaAlReves: raiz.ruedaAlReves })
            }
        }
    }

    K4.Process {
        id: salto
        onTerminado: function (codigo) {
            if (codigo !== 0)
                raiz.error = K4.Idioma.t("No se ha podido ir a esa ventana")
        }
    }

    // ── leer el escritorio ────────────────────────────────────────
    K4.Process {
        id: lector

        //  Los dos en un `printf` y no con `jq`: sale JSON válido igual, y no
        //  añade una dependencia para pegar dos respuestas.
        command: ["sh", "-c",
            "printf '{\"monitores\":'; hyprctl -j monitors; " +
            "printf ',\"clientes\":'; hyprctl -j clients; printf '}'"]

        onSalida: function (texto) {
            raiz.cargando = false
            let d = null
            try {
                d = JSON.parse(texto)
            } catch (e) {
                raiz.error = K4.Idioma.t("No se entiende la respuesta de hyprctl")
                return
            }
            raiz.digerir(d)
        }

        onTerminado: function (codigo) {
            raiz.cargando = false
            if (codigo !== 0)
                raiz.error = "hyprctl " + codigo
        }
    }

    //  De la respuesta de Hyprland a lo que dibuja la vista.
    function digerir(d) {
        const mons = d.monitores || []
        const cls = d.clientes || []

        //  El monitor donde está el ratón, que es donde el usuario está
        //  mirando. Si no lo dice ninguno —pasa con la pantalla apagada— vale
        //  el primero antes que ninguno.
        let mon = null
        for (let i = 0; i < mons.length; ++i)
            if (mons[i].focused === true) {
                mon = mons[i]
                break
            }
        if (!mon && mons.length > 0)
            mon = mons[0]
        if (!mon) {
            error = K4.Idioma.t("Hyprland no da ningún monitor")
            return
        }

        const escala = mon.scale > 0 ? mon.scale : 1
        monitor = String(mon.name || "")
        monAncho = Math.round((mon.width || 1920) / escala)
        monAlto = Math.round((mon.height || 1080) / escala)

        const wsActivo = mon.activeWorkspace ? mon.activeWorkspace.id : -999
        const lista = []

        for (let j = 0; j < cls.length; ++j) {
            const c = cls[j]
            if (!c || c.mapped === false)
                continue
            const tam = c.size || [0, 0]
            if (!(tam[0] > 0 && tam[1] > 0))
                continue

            const en = c.at || [0, 0]
            const ws = c.workspace || {}
            //  «Está a la vista» es su monitor Y su escritorio Y que no la
            //  hayan escondido. Las tres: una ventana del escritorio activo en
            //  el OTRO monitor no está en esta pantalla, y salir volando desde
            //  su sitio la haría entrar por un borde donde no había nada.
            const aLaVista = String(c.monitor) === String(mon.id)
                && ws.id === wsActivo && c.hidden !== true

            lista.push({
                dir: String(c.address || ""),
                titulo: String(c.title || ""),
                clase: String(c.class || ""),
                ws: ws.id !== undefined ? ws.id : 0,
                wsNombre: String(ws.name || ""),
                ancho: tam[0],
                alto: tam[1],
                enPantalla: aLaVista,
                //  Dentro de MI monitor: hyprctl da la posición en el plano de
                //  todos los monitores juntos, y la ventana empieza en su
                //  esquina.
                rx: en[0] - (mon.x || 0),
                ry: en[1] - (mon.y || 0),
                flotante: c.floating === true,
                oculta: c.hidden === true
            })
        }

        //  Un orden ESTABLE, y por eso por escritorio y posición y no por lo
        //  último usado: si las tarjetas bailan de sitio entre una apertura y
        //  la siguiente, la memoria muscular no llega a formarse y hay que
        //  volver a leerlo todo cada vez.
        lista.sort(function (a, b) {
            if (a.ws !== b.ws)
                return a.ws - b.ws
            if (a.ry !== b.ry)
                return a.ry - b.ry
            return a.rx - b.rx
        })

        ventanas = lista
        seleccion = lista.length > 0 ? 0 : -1
        if (lista.length === 0)
            error = K4.Idioma.t("No hay ninguna ventana abierta")
    }

    // ── la vista ──────────────────────────────────────────────────
    //
    //  Con `K4.Cargador`: una ventana a pantalla completa con una captura viva
    //  por cada cosa que tengas abierta no puede existir mientras no se mira.
    K4.Cargador {
        active: raiz.abierto || raiz.saliendo
        Lienzo { plugin: raiz }
    }

    // ── por dónde se le llama ─────────────────────────────────────
    K4.Atajo {
        name: "atalaya"
        description: "Atalaya: todas las ventanas sobre un plano"
        onPressed: raiz.alternar()
    }

    K4.Ipc {
        target: "k4.atalaya"
        function alternar(): void { raiz.alternar() }
        function abrir(): void { raiz.abrir() }
        function cerrar(): void { raiz.cerrar() }
        //  Lo mismo que pulsar ↵ sobre la elegida. Va a la vista y no a una
        //  copia de su lógica: un segundo camino hacia «ir a esa ventana»
        //  sería un segundo sitio donde arreglar el primer fallo.
        function elegir(): void {
            if (raiz.lienzo)
                raiz.lienzo.caer(raiz.seleccion)
        }
        function estado(): string {
            return JSON.stringify({
                abierto: raiz.abierto,
                cargando: raiz.cargando,
                ventanas: raiz.ventanas.length,
                monitor: raiz.monitor,
                //  El zoom actual, para poder comprobar desde fuera qué hace
                //  la rueda sin tener que adivinarlo mirando una captura.
                escala: raiz.lienzo
                    ? Math.round(raiz.lienzo.escala * 1000) / 1000 : 0,
                ruedaAlReves: raiz.ruedaAlReves,
                error: raiz.error
            })
        }
    }
}
