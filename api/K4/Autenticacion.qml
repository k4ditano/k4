//  Comprobar que quien está delante es quien dice ser.
//
//  Por debajo es PAM, que no es «dame la contraseña y te digo sí o no»: abre
//  una conversación en la que el sistema pregunta y tú contestas, y puede
//  preguntar varias veces —o soltar un aviso sin preguntar nada, como cuando
//  quedan dos intentos antes de que la cuenta se bloquee sola—. Aquí se recoge
//  todo eso y se sirve como una máquina de tres estados.
//
//  Los motivos son CLAVES, no frases: esta capa no traduce. El mensaje del
//  sistema sí viene ya en el idioma del equipo y se pasa tal cual, porque lo
//  escribe PAM y suele decir algo útil.

import QtQuick
import Quickshell.Services.Pam

QtObject {
    id: auth

    // "listo" · "verificando" · "correcto" · "fallo"
    property string estado: "listo"

    // Clave del motivo del último fallo: "" · "sin-pam" · "incorrecta" ·
    // "demasiados-intentos" · "error"
    property string motivo: ""

    // Lo que haya dicho el sistema, ya en su idioma. Puede venir vacío.
    property string mensaje: ""

    property int fallos: 0

    readonly property bool ocupado: estado === "verificando"

    signal resuelto(bool correcto)

    function comprobar(clave) {
        if (ocupado || !clave || clave.length === 0)
            return
        pendiente = clave
        mensaje = ""
        motivo = ""
        estado = "verificando"
        if (!pam.start()) {
            estado = "fallo"
            motivo = "sin-pam"
            resuelto(false)
        }
    }

    function reiniciar() {
        estado = "listo"
        motivo = ""
        mensaje = ""
    }

    // La contraseña vive lo justo: desde que se pide hasta que PAM la reclama.
    property string pendiente: ""

    property PamContext pam: PamContext {
        // El mismo montón de reglas que usa iniciar sesión en la máquina, que
        // es lo que uno espera de un bloqueo: la contraseña de tu usuario.
        config: "login"
        configDirectory: "/etc/pam.d"

        onPamMessage: {
            if (responseRequired) {
                respond(auth.pendiente)
                auth.pendiente = ""
            } else if (message.length > 0) {
                // Avisos sin pregunta: casi siempre el contador de intentos que
                // quedan. Interesa verlos.
                auth.mensaje = message
            }
        }

        onCompleted: function (resultado) {
            auth.pendiente = ""
            if (resultado === PamResult.Success) {
                auth.estado = "correcto"
                auth.fallos = 0
                auth.motivo = ""
                auth.mensaje = ""
                auth.resuelto(true)
            } else {
                auth.estado = "fallo"
                auth.fallos += 1
                auth.motivo = resultado === PamResult.MaxTries
                    ? "demasiados-intentos" : "incorrecta"
                auth.resuelto(false)
            }
        }

        onError: function (e) {
            auth.pendiente = ""
            auth.estado = "fallo"
            auth.motivo = "error"
            auth.mensaje = PamError.toString(e)
            auth.resuelto(false)
        }
    }
}
