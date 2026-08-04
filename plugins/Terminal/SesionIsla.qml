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
import "../../services"

QtObject {
    id: sesion

    //  Una sesión que ya existe esperando en ese socket: viene de una ventana
    //  que la devuelve. Con esto el binario no abre ninguna shell — adopta la
    //  que hay, con lo que estuviera corriendo dentro.
    property string heredar: ""

    //  A qué servidor está conectada ahora mismo, si lo está. Lo apunta el
    //  plugin al mandar el `ssh` y lo borra cuando ese mandato termina.
    property string conectadoA: ""

    //  Un número que no se repite, para poder referirse a ella aunque se
    //  cierren otras por el medio. No se llama `id` porque en QML esa palabra
    //  está cogida.
    property int numero: 0

    //  Lo último que ha mandado.
    property var marco: null
    property int estela: 8
    //  Si el binario que hay enfrente sabe teclear contraseñas. Lo dice él al
    //  arrancar; uno anterior no dice nada y se queda en false.
    property bool sabeClaves: false
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

    //  Lo que la aplicación de dentro ha pedido copiar (OSC 52). Aquí no hay
    //  portapapeles: lo tiene la barra, así que se le pasa a ella.
    signal portapapeles(string texto)

    //  Un trozo del historial que se pidió con `texto_de`. Vuelve con el
    //  motivo por el que se pidió, que es lo que distingue copiar de mandar a
    //  una nota — si no, la respuesta no diría a qué venía.
    signal texto(string contenido, string motivo)

    //  Dónde cayó una búsqueda, y si cayó en algo.
    signal buscado(bool hay, int fila)

    //  Un recado suelto para el usuario: aquí dentro no hay sitio para
    //  decirle «guardado» sin taparse a sí misma.
    signal aviso(string texto)

    //  «Ahí queda la sesión»: por ese socket se la puede llevar una ventana.
    //  Hasta que alguien la coja, aquí no se ha soltado nada.
    signal emigrando(string socket)

    //  Se murió sola —un `exit`, la shell cerrada—, para que el plugin la
    //  quite de la lista en vez de dejar un hueco muerto.
    signal difunta()

    property bool viva: true

    function mandar(orden) {
        if (viva)
            proceso.escribir(JSON.stringify(orden) + "\n")
    }

    property K4.Process proceso: K4.Process {
        command: sesion.heredar ? ["k4term-isla", "--heredar", sesion.heredar]
                                : ["k4term-isla"]
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
                //  Qué sabe hacer el binario que hay enfrente. Un k4term
                //  anterior a las contraseñas no manda esto, y entonces no se
                //  le mandan: mejor decirlo que quedarse esperando una
                //  contraseña que nadie va a teclear.
                sesion.sabeClaves = m.claves === true
            } else if (m.que === "donde") {
                sesion.donde(m.ruta || "")
            } else if (m.que === "trabajo") {
                sesion.trabajo(m.estado, m.mandato || "", m.salida || 0, m.segundos || 0)
            } else if (m.que === "campana") {
                sesion.campana(m.titulo || "")
            } else if (m.que === "portapapeles") {
                sesion.portapapeles(m.texto || "")
            } else if (m.que === "texto") {
                sesion.texto(m.texto || "", m.motivo || "")
            } else if (m.que === "buscado") {
                sesion.buscado(m.hay === true, m.fila || 0)
            } else if (m.que === "aviso") {
                sesion.aviso(m.texto || "")
            } else if (m.que === "emigrando") {
                sesion.emigrando(m.socket || "")
            }
        }

        onTerminado: {
            //  Muerta sin haber pintado NADA: o el binario ya no está, o no
            //  arranca. En los dos casos la respuesta es la misma —volver a
            //  mirar qué hay instalado—, y así el plugin se apaga solo con su
            //  motivo en vez de intentarlo una y otra vez.
            if (!sesion.marco)
                Consola.revisar()
            sesion.viva = false
            sesion.marco = null
            sesion.difunta()
        }
    }
}
