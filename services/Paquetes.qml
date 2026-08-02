pragma Singleton

//  Las actualizaciones del sistema, contadas una vez para toda la barra.
//
//  Nació en el centro de aplicaciones y se subió a servicio el mismo día:
//  el usuario abre las cosas por el LANZADOR, y un contador que solo vive en
//  la rejilla es un contador que no se ve. Aquí lo comparten los dos.
//
//  `checkupdates` monta una base temporal y tarda unos segundos, así que se
//  mira al abrir cualquiera de las dos superficies con una caché de diez
//  minutos, y quien quiera frescura tiene su botón de volver a mirar.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: paquetes

    property int pendientesRepo: -1          // -1 = aún sin mirar
    property int pendientesAur: -1
    property var nombresPendientes: []
    //  El detalle, para poder elegir: [{nombre, de, a, aur}].
    property var detalles: []
    //  Lo que el usuario ha dejado FUERA de esta tanda, por nombre. Vive en
    //  memoria a propósito: excluir es una decisión de hoy, no una política.
    property var excluidos: ({})
    property real comprobadoEn: 0

    readonly property bool comprobando: repoUpd.running || aurUpd.running
    readonly property int pendientes:
        Math.max(0, pendientesRepo) + Math.max(0, pendientesAur)

    readonly property int marcadas: {
        let n = 0
        for (let i = 0; i < detalles.length; ++i)
            if (!excluidos[detalles[i].nombre])
                ++n
        return n
    }

    function alternarExcluida(nombre) {
        const e = Object.assign({}, excluidos)
        if (e[nombre])
            delete e[nombre]
        else
            e[nombre] = true
        excluidos = e
    }

    function comprobar(forzar) {
        if (comprobando)
            return
        if (!forzar && comprobadoEn > 0
                && Date.now() - comprobadoEn < 10 * 60 * 1000)
            return
        comprobadoEn = Date.now()
        pendientesRepo = -1
        pendientesAur = -1
        nombresPendientes = []
        detalles = []
        excluidos = ({})
        repoUpd.running = true
        aurUpd.running = true
    }

    function apuntar(texto, esAur) {
        const lineas = texto.split("\n").filter(function (l) {
            return l.trim().length > 0
        })
        const nombres = nombresPendientes.slice()
        const lista = detalles.slice()
        for (let i = 0; i < lineas.length; ++i) {
            const partes = lineas[i].trim().split(/\s+/)
            nombres.push(partes[0])
            //  «nombre 1.2-1 -> 1.3-1», el mismo formato en los dos mundos.
            lista.push({ nombre: partes[0], de: partes[1] || "",
                         a: partes[3] || "", aur: esAur })
        }
        nombresPendientes = nombres
        detalles = lista
        if (esAur)
            pendientesAur = lineas.length
        else
            pendientesRepo = lineas.length
    }

    Process {
        id: repoUpd
        command: ["checkupdates"]
        stdout: StdioCollector {
            onStreamFinished: paquetes.apuntar(this.text, false)
        }
        //  checkupdates contesta 2 cuando NO hay nada pendiente: es su forma
        //  de decir «al día», no un fallo.
        onExited: function (codigo) {
            if (paquetes.pendientesRepo < 0)
                paquetes.pendientesRepo = 0
        }
    }

    Process {
        id: aurUpd
        command: ["yay", "-Qua"]
        stdout: StdioCollector {
            onStreamFinished: paquetes.apuntar(this.text, true)
        }
        onExited: function (codigo) {
            if (paquetes.pendientesAur < 0)
                paquetes.pendientesAur = 0
        }
    }

    //  Todo de una vez, en una terminal DE VERDAD: la clave de root, las
    //  preguntas y los PKGBUILDs son cosas de una terminal, no de una barra.
    //  Al acabar avisa, y el contador se olvida para volver a contar la
    //  verdad la próxima vez.
    //  La tanda elegida: actualización COMPLETA menos lo excluido, que en
    //  Arch es la única forma sana de elegir — subir paquetes sueltos sobre
    //  un sistema viejo es la receta clásica de romperlo; dejar algunos
    //  quietos con --ignore es lo que pacman contempla de fábrica.
    function actualizarMarcadas() {
        const fuera = []
        for (let i = 0; i < detalles.length; ++i)
            if (excluidos[detalles[i].nombre])
                fuera.push(detalles[i].nombre)
        if (fuera.length === 0) {
            actualizarTodo()
            return
        }
        const script = "yay -Syu --ignore=" + fuera.join(",")
            + " && notify-send -a 'Actualizar' '"
            + Idioma.t("Sistema al día") + " ("
            + fuera.length + " " + Idioma.t("dejadas para luego") + ")'"
            + " || { notify-send -a 'Actualizar' -u critical '"
            + Idioma.t("La actualización falló") + "';"
            + Consola.cierre + " }"
        Consola.ejecutar(script)
        comprobadoEn = 0
    }

    function actualizarTodo() {
        const script = "yay -Syu"
            + " && notify-send -a 'Actualizar' '"
            + Idioma.t("Sistema al día") + "'"
            + " || { notify-send -a 'Actualizar' -u critical '"
            + Idioma.t("La actualización falló") + "';"
            + Consola.cierre + " }"
        Consola.ejecutar(script)
        comprobadoEn = 0
    }
}
