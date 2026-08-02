//  Una sesión de terminal dentro de la barra.
//
//  Es un `k4term-isla` y lo que hace falta para hablarle: se le mandan órdenes
//  en JSON por líneas y él devuelve marcos con la rejilla ya resuelta. Nada
//  más — quién se enseña, en qué orden y con qué teclas se cambia es asunto
//  del plugin.
//
//  Está en su propio fichero justamente para que haya VARIAS: antes esto vivía
//  suelto dentro del plugin y por eso solo podía existir una.

import QtQuick
import K4 as K4

QtObject {
    id: sesion

    //  Un número que no se repite, para poder referirse a ella aunque se
    //  cierren otras por el medio. No se llama `id` porque en QML esa palabra
    //  está cogida.
    property int numero: 0

    //  Lo último que ha mandado.
    property var marco: null
    property int estela: 8
    property string fuente: "MesloLGS Nerd Font Mono"
    property int cuerpo: 13

    //  Cómo llamarla en el selector: lo que diga la aplicación de dentro, y si
    //  no ha dicho nada, dónde está.
    readonly property string titulo: marco && marco.titulo ? marco.titulo : ""
    readonly property string cwd: marco && marco.cwd ? marco.cwd : ""

    //  Se pide y se contesta: el plugin la usa para saber dónde sacar una
    //  ventana con esta misma sesión dentro.
    signal donde(string ruta)

    //  Lo que se está cociendo aquí dentro. La sesión cuenta hechos; qué se
    //  enseña y cuándo lo decide el plugin, que es el único que sabe si estás
    //  mirando esta terminal ahora mismo.
    signal trabajo(string estado, string mandato, int salida, int segundos)
    signal campana(string titulo)

    //  Se murió sola —un `exit`, la shell cerrada—, para que el plugin la
    //  quite de la lista en vez de dejar un hueco muerto.
    signal difunta()

    property bool viva: true

    function mandar(orden) {
        if (viva)
            proceso.escribir(JSON.stringify(orden) + "\n")
    }

    property K4.Process proceso: K4.Process {
        command: ["k4term-isla"]
        running: sesion.viva
        porLineas: true
        entradaAbierta: true

        onLinea: function (linea) {
            let m = null
            try {
                m = JSON.parse(linea)
            } catch (e) {
                return
            }
            if (!m)
                return
            if (m.que === "marco") {
                sesion.marco = m
            } else if (m.que === "config") {
                sesion.estela = m.estela
                if (m.fuente)
                    sesion.fuente = m.fuente
                if (m.tamano)
                    sesion.cuerpo = Math.round(m.tamano)
            } else if (m.que === "donde") {
                sesion.donde(m.ruta || "")
            } else if (m.que === "trabajo") {
                sesion.trabajo(m.estado, m.mandato || "", m.salida || 0, m.segundos || 0)
            } else if (m.que === "campana") {
                sesion.campana(m.titulo || "")
            }
        }

        onTerminado: {
            sesion.viva = false
            sesion.marco = null
            sesion.difunta()
        }
    }
}
