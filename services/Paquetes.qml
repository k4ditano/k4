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
    property real comprobadoEn: 0

    readonly property bool comprobando: repoUpd.running || aurUpd.running
    readonly property int pendientes:
        Math.max(0, pendientesRepo) + Math.max(0, pendientesAur)

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
        repoUpd.running = true
        aurUpd.running = true
    }

    function apuntar(texto, esAur) {
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
    function actualizarTodo() {
        const script = "yay -Syu"
            + " && notify-send -a 'Actualizar' '"
            + Idioma.t("Sistema al día") + "'"
            + " || { notify-send -a 'Actualizar' -u critical '"
            + Idioma.t("La actualización falló") + "';"
            + " printf '\\nPulsa Enter para cerrar…'; read _; }"
        Quickshell.execDetached(["uwsm", "app", "--", "kitty", "-e", "sh",
                                 "-c", script])
        comprobadoEn = 0
    }
}
