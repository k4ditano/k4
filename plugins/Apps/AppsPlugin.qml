//  El centro de aplicaciones: todo lo que la barra sabe abrir, en una rejilla.
//
//  La barra tiene once cosas que son aplicaciones —la mazmorra, el editor, el
//  portapapeles, los atajos…— y hasta ahora la única forma de llegar a ellas
//  era saberse el atajo o el nombre del comando. Eso está bien para quien la
//  configuró y es invisible para todos los demás, y sobre todo deja fuera a
//  los plugins instalados: un juego que te bajas no tiene atajo hasta que te
//  lo pones.
//
//  Es el cajón de aplicaciones del móvil, y a propósito: rejilla, buscador
//  arriba, escribes y filtras, Enter abre. Nadie tiene que aprender nada.
//
//  Qué sale aquí lo dice el catálogo (`aplicacion: true`), no el código: así
//  un plugin de fuera entra solo con declararlo en su manifiesto.

import QtQuick
import K4 as K4
import "../../services"

K4.Plugin {
    id: self

    name: "apps"
    title: "Aplicaciones"
    priority: 72
    active: abierto
    grabKeyboard: abierto
    islandWidth: 700
    islandHeight: 520

    property bool abierto: false
    property string busqueda: ""
    property int seleccion: 0

    //  Las de la barra, filtradas por lo que se escribe. Una apagada NO
    //  desaparece: sale en gris. Que algo se esfume al apagarlo obliga a
    //  adivinar dónde se fue; en gris se ve que está y por qué no se abre.
    readonly property var lista: {
        const todas = PluginManager.aplicaciones
        const q = busqueda.trim().toLowerCase()
        if (q.length === 0)
            return todas
        return todas.filter(function (a) {
            return a.nombre.toLowerCase().indexOf(q) >= 0
        })
    }

    readonly property int columnas: 5

    view: Component { AppsView { plugin: self } }

    // ── las actualizaciones del sistema ───────────────────────────
    //
    //  Cuántas esperan, de los repos y de AUR, mirado al abrir el centro con
    //  una caché de diez minutos: `checkupdates` monta una base temporal y
    //  tarda unos segundos, y preguntarlo a cada apertura sería castigo.
    //  Actualizar abre una terminal DE VERDAD, como instalar desde el
    //  lanzador y por lo mismo: hay que poder meter la clave de root y
    //  responder preguntas.
    property int pendientesRepo: -1          // -1 = aún sin mirar
    property int pendientesAur: -1
    property var nombresPendientes: []
    property real comprobadoEn: 0

    readonly property bool comprobando: repoUpd.running || aurUpd.running
    readonly property int pendientes:
        Math.max(0, pendientesRepo) + Math.max(0, pendientesAur)

    function comprobarActualizaciones(forzar) {
        if (comprobando)
            return
        if (!forzar && comprobadoEn > 0
                && Date.now() - comprobadoEn < 10 * 60 * 1000)
            return
        comprobadoEn = Date.now()
        pendientesRepo = -1
        pendientesAur = -1
        nombresPendientes = []
        repoUpd.running = true
        aurUpd.running = true
    }

    function apuntarPendientes(texto, esAur) {
        const lineas = texto.split("\n").filter(function (l) {
            return l.trim().length > 0
        })
        const nombres = nombresPendientes.slice()
        for (let i = 0; i < lineas.length; ++i)
            nombres.push(lineas[i].split(/\s+/)[0])
        nombresPendientes = nombres
        if (esAur)
            pendientesAur = lineas.length
        else
            pendientesRepo = lineas.length
    }

    K4.Process {
        id: repoUpd
        command: ["checkupdates"]
        onSalida: function (texto) { self.apuntarPendientes(texto, false) }
        //  checkupdates contesta 2 cuando NO hay nada pendiente: es su forma
        //  de decir «al día», no un fallo.
        onTerminado: function (codigo) {
            if (codigo === 2)
                self.pendientesRepo = Math.max(0, self.pendientesRepo)
        }
    }

    K4.Process {
        id: aurUpd
        command: ["yay", "-Qua"]
        onSalida: function (texto) { self.apuntarPendientes(texto, true) }
        onTerminado: function (codigo) {
            if (self.pendientesAur < 0)
                self.pendientesAur = 0
        }
    }

    //  Todo de una vez, en una terminal: root, preguntas y PKGBUILDs son
    //  cosas de una terminal, no de una barra. Al acabar avisa y se vuelve a
    //  mirar, para que el contador cuente la verdad.
    function actualizarTodo() {
        const script = "yay -Syu"
            + " && notify-send -a 'Actualizar' '"
            + Idioma.t("Sistema al día") + "'"
            + " || { notify-send -a 'Actualizar' -u critical '"
            + Idioma.t("La actualización falló") + "';"
            + " printf '\\nPulsa Enter para cerrar…'; read _; }"
        K4.Sistema.lanzar(["uwsm", "app", "--", "kitty", "-e", "sh", "-c",
                           script])
        comprobadoEn = 0
        cerrar()
    }

    function abrirse() {
        busqueda = ""
        seleccion = 0
        abierto = true
        comprobarActualizaciones(false)
    }

    function toggle() {
        if (abierto)
            cerrar()
        else
            abrirse()
    }

    function cerrar() { abierto = false }
    function close() { cerrar() }

    //  Abrir la elegida: se cierra ANTES, que si no las dos piden la island a
    //  la vez y gana la de más prioridad —que es esta— y parece que no ha
    //  pasado nada.
    function lanzar(id) {
        cerrar()
        PluginManager.abrirAplicacion(id)
    }

    function lanzarSeleccion() {
        if (seleccion >= 0 && seleccion < lista.length)
            lanzar(lista[seleccion].id)
    }

    function mover(dx, dy) {
        if (lista.length === 0)
            return
        let n = seleccion + dx + dy * columnas
        //  En los bordes se queda, no da la vuelta: saltar de la última a la
        //  primera con una flecha desorienta más de lo que ayuda.
        seleccion = Math.max(0, Math.min(lista.length - 1, n))
    }

    //  Y anunciarse en el lanzador de aplicaciones del escritorio.
    //
    //  Los dos cajones se quedan separados a propósito —son preguntas
    //  distintas: «abre un programa de mi ordenador» son cientos de entradas,
    //  «abre una parte de la barra» son once, y mezclarlas entierra las
    //  once—. Pero separarlos deja un agujero: escribir «portapapeles» en
    //  SUPER+Space y que no salga NADA es exactamente la sensación de que
    //  algo no funciona, aunque esté a un atajo de distancia.
    //
    //  Así que se anuncian: dos cajones, una sola búsqueda que encuentra
    //  todo. Y lo hace este módulo y no cada plugin, porque el que sabe qué
    //  es una «aplicación de la barra» es este.
    property var enElLanzador: K4.Lanzador {
        plugin: "apps"

        onBuscando: function (texto) {
            const q = texto.trim().toLowerCase()
            //  Con una letra sale medio mundo; a partir de dos ya es una
            //  intención.
            if (q.length < 2) {
                resultados = []
                return
            }
            resultados = PluginManager.aplicaciones
                .filter(function (a) {
                    return a.habilitado
                        && a.nombre.toLowerCase().indexOf(q) >= 0
                })
                .map(function (a) {
                    return { id: a.id, titulo: a.nombre,
                             desc: K4.Idioma.t("Aplicación de la barra"),
                             icono: a.imagen }
                })
        }

        onElegido: function (id) { PluginManager.abrirAplicacion(id) }
    }

    K4.Ipc {
        target: "k4.apps"
        function toggle(): void { self.toggle() }
        function open(): void { self.abrirse() }
        function close(): void { self.cerrar() }
    }
}
