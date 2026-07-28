//  La conversación con PAM, envuelta en algo que se pueda usar.
//
//  PAM no es «dame la contraseña y te digo sí o no»: abre una charla en la que
//  el sistema pregunta y tú contestas, y puede preguntar varias veces —o
//  soltarte un aviso sin preguntar nada, como cuando quedan dos intentos antes
//  de que la cuenta se bloquee sola. Aquí se recoge todo eso y se sirve como
//  una máquina de tres estados.
//
//  Lo usan dos sitios: la pantalla de bloqueo y el comprobador del menú. Que
//  sea el mismo objeto en los dos no es casualidad, es el objetivo: comprobar
//  la contraseña desde el menú prueba EXACTAMENTE lo que hará el bloqueo, así
//  que si el comprobador dice que sí, no te vas a quedar fuera.

import QtQuick
import Quickshell.Services.Pam
import "../../services"

QtObject {
    id: auth

    // "listo" · "verificando" · "correcto" · "fallo"
    property string estado: "listo"
    property string mensaje: ""
    property int fallos: 0

    readonly property bool ocupado: estado === "verificando"

    signal resuelto(bool correcto)

    function comprobar(clave) {
        if (ocupado || clave.length === 0)
            return
        pendiente = clave
        mensaje = ""
        estado = "verificando"
        if (!pam.start()) {
            estado = "fallo"
            mensaje = Idioma.t("No se pudo hablar con PAM")
            resuelto(false)
        }
    }

    function reiniciar() {
        estado = "listo"
        mensaje = ""
    }

    // La contraseña vive lo justo: desde que se pulsa Intro hasta que PAM la
    // pide. En cuanto se entrega, se borra.
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
                // Avisos sin pregunta: casi siempre pam_faillock contando los
                // intentos que quedan. Interesa verlos.
                auth.mensaje = message
            }
        }

        onCompleted: function (resultado) {
            auth.pendiente = ""
            if (resultado === PamResult.Success) {
                auth.estado = "correcto"
                auth.fallos = 0
                auth.mensaje = ""
                auth.resuelto(true)
            } else {
                auth.estado = "fallo"
                auth.fallos += 1
                if (resultado === PamResult.MaxTries)
                    auth.mensaje = Idioma.t("Demasiados intentos")
                else if (auth.mensaje.length === 0)
                    auth.mensaje = Idioma.t("Contraseña incorrecta")
                auth.resuelto(false)
            }
        }

        onError: function (e) {
            auth.pendiente = ""
            auth.estado = "fallo"
            auth.mensaje = PamError.toString(e)
            auth.resuelto(false)
        }
    }
}
