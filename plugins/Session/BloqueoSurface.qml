//  La pantalla de bloqueo.
//
//  El compositor crea una de estas por monitor y les da el teclado en
//  exclusiva: nada de lo que haya detrás puede pintar encima ni escuchar lo
//  que escribes. A cambio, mientras esto viva no hay escritorio, así que
//  conviene que sea simple y que no dependa de nada que pueda tardar.
//
//  Negro entero y a propósito: es lo que menos consume en OLED, lo que menos
//  molesta si te levantas de noche y lo que menos enseña de tu escritorio a
//  quien pase por delante.

import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4.SuperficieBloqueo {
    id: pantalla

    color: "black"

    K4.Autenticacion {
        id: auth
        onResuelto: function (correcto) {
            if (correcto) {
                clave.text = ""
                Sesion.desbloquear()
            } else {
                clave.text = ""
                tiritona.restart()
                clave.forceActiveFocus()
            }
        }
    }

    // Al montarse hay que pedir el foco a mano: la superficie lo tiene, pero
    // dentro nadie lo ha reclamado y el primer carácter se perdería.
    Component.onCompleted: clave.forceActiveFocus()

    Item {
        anchors.fill: parent

        // ── la hora, arriba y grande ──────────────────────────────
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.22
            spacing: 2

            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Clock.date.toLocaleTimeString(Idioma.locale, "HH:mm")
                color: Theme.ink
                font.pixelSize: 92
                font.weight: Font.Light
            }

            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Clock.date.toLocaleDateString(Idioma.locale, "dddd, d 'de' MMMM")
                color: Theme.muted
                font.pixelSize: 17
            }
        }

        // ── quién eres y la contraseña ────────────────────────────
        Column {
            id: acceso
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: parent.height * 0.11
            spacing: 14

            // El zarandeo del cuadro cuando la contraseña no vale. Se entiende
            // sin leer nada, que es de lo que se trata cuando acabas de
            // escribir a ciegas.
            SequentialAnimation {
                id: tiritona
                NumberAnimation { target: acceso; property: "x"; to: -9; duration: 45 }
                NumberAnimation { target: acceso; property: "x"; to: 9; duration: 90 }
                NumberAnimation { target: acceso; property: "x"; to: -6; duration: 90 }
                NumberAnimation { target: acceso; property: "x"; to: 0; duration: 60 }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 76
                height: 76
                radius: 38
                color: Theme.surface
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)

                IslandLabel {
                    anchors.centerIn: parent
                    text: Sesion.inicial
                    color: Theme.ink
                    font.pixelSize: 34
                    font.weight: Font.Light
                }
            }

            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Sesion.visible
                color: Theme.ink
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            // ── el cuadro de la contraseña ────────────────────────
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300
                height: 42
                radius: 21
                color: Theme.surface
                border.width: 1
                border.color: auth.estado === "fallo" ? Theme.red
                    : (clave.activeFocus ? Theme.blue : Qt.rgba(1, 1, 1, 0.1))

                Behavior on border.color { ColorAnimation { duration: 160 } }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 15
                    anchors.rightMargin: 15
                    spacing: 10

                    IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(auth.estado === "correcto"
                                                   ? 0xF033F : 0xF033E)
                        color: auth.estado === "fallo" ? Theme.red
                            : (auth.estado === "correcto" ? Theme.green : Theme.muted)
                        font.pixelSize: 16
                    }

                    TextInput {
                        id: clave
                        cursorDelegate: IslandCursor {}
                        width: parent.width - 60
                        anchors.verticalCenter: parent.verticalCenter

                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        passwordMaskDelay: 0
                        enabled: !auth.ocupado
                        color: Theme.ink
                        font.pixelSize: 15
                        font.family: Theme.uiFont
                        selectByMouse: true
                        selectionColor: Theme.blue
                        clip: true

                        onAccepted: auth.comprobar(text)
                        onTextChanged: if (auth.estado === "fallo") auth.reiniciar()

                        IslandLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: clave.text.length === 0 && !auth.ocupado
                            text: Idioma.t("Contraseña")
                            color: Theme.dim
                            font.pixelSize: 15
                        }
                    }

                    // Mientras PAM piensa. No es instantáneo: pam_unix mete a
                    // propósito un retardo de un par de segundos tras un fallo
                    // para que no se pueda probar a lo bruto, y sin señal
                    // ninguna parece que se ha colgado.
                    IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: auth.ocupado
                        text: String.fromCodePoint(0xF051F)
                        color: Theme.muted
                        font.pixelSize: 15

                        RotationAnimation on rotation {
                            running: auth.ocupado
                            loops: Animation.Infinite
                            from: 0; to: 360; duration: 1600
                        }
                    }
                }
            }

            // ── qué ha pasado ─────────────────────────────────────
            IslandLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 340
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: auth.mensaje.length > 0 ? auth.mensaje
                    : (auth.motivo === "demasiados-intentos" ? Idioma.t("Demasiados intentos")
                       : auth.motivo === "sin-pam" ? Idioma.t("No se pudo hablar con PAM")
                       : auth.motivo.length > 0 ? Idioma.t("Contraseña incorrecta") : "")
                color: Theme.red
                font.pixelSize: 12
                opacity: auth.mensaje.length > 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
        }

        // ── la salida de emergencia ───────────────────────────────
        //
        //  Tras varios fallos seguidos deja de ser «me he equivocado» y empieza
        //  a ser «esto no me deja entrar». Antes de que cunda el pánico, por
        //  dónde se sale: un tty sigue estando ahí detrás.
        IslandLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 34
            horizontalAlignment: Text.AlignHCenter
            visible: auth.fallos >= 3
            text: Idioma.t("¿No entras? Ctrl+Alt+F2 abre una consola de texto donde iniciar sesión.")
            color: Theme.dim
            font.pixelSize: 11
        }
    }
}
