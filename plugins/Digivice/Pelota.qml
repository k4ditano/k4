//  Jugar a la pelota, FUERA del aparato.
//
//  Esto es lo que no puede hacer un llavero: coges la pelota con el ratón,
//  la sueltas donde quieras de la pantalla, y el bicho SALE de la carcasa,
//  cruza el escritorio por encima de tus ventanas, la recoge y vuelve.
//
//  Se apoya en `K4.Ventana`, que es una capa transparente a pantalla
//  completa —la barra la usa para el selector de captura— y en
//  `K4.Isla.rect`, que dice dónde está la island para que el bicho salga
//  justo de ella y no de un punto cualquiera.
//
//  Es entrenamiento de verdad: cada carrera cansa y da esfuerzo, y la
//  distancia decide cuánto. Tirarla lejos entrena más.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    signal terminado(int aciertos)

    //  Cuántas carreras se juegan.
    readonly property int rondas: 3
    property int ronda: 0
    property int logrados: 0
    property real distanciaTotal: 0

    //  dormido · agarrando · corriendo · volviendo · fin
    property string fase: "espera"

    //  `rect` da { x, y, ancho, alto } — con esos nombres y no `width`/
    //  `height`. Usar los de QML devuelve `undefined` y toda la escena se
    //  coloca en NaN: el cartel salía cortado en la esquina y la pelota no
    //  aparecía.
    readonly property var isla: K4.Isla.rect
    readonly property real casaX: isla ? isla.x + isla.ancho / 2 : 400
    readonly property real casaY: isla ? isla.y + isla.alto : 60

    //  Lo llama la vista con el botón B, por si prefieres no usar el ratón:
    //  tira la pelota a un sitio al azar.
    function tirar() {
        if (fase !== "espera")
            return
        lanzar(casaX + (Math.random() - 0.5) * 700,
               casaY + 120 + Math.random() * 380)
    }

    function lanzar(x, y) {
        if (fase !== "espera")
            return
        pelota.x = x - pelota.width / 2
        pelota.y = y - pelota.height / 2
        distanciaTotal += Math.abs(x - casaX) + Math.abs(y - casaY)
        fase = "corriendo"
        corre.restart()
    }

    function _recogida() {
        fase = "volviendo"
        vuelve.restart()
    }

    function _envuelta() {
        ronda += 1
        logrados += 1
        if (ronda >= rondas) {
            fase = "fin"
            cierre.restart()
        } else {
            fase = "espera"
        }
    }

    Timer { id: cierre; interval: 700; onTriggered: self.terminado(self.logrados) }

    // ── la capa que cubre la pantalla ─────────────────────────────
    K4.Ventana {
        nombre: "digivice-pelota"
        //  Sin teclado: esto se juega con el ratón y robarle las teclas al
        //  escritorio para tirar una pelota sería excesivo.
        conTeclado: false

        Item {
            anchors.fill: parent

            //  Una veladura muy tenue: sin ella no se entiende que la pantalla
            //  entera es ahora el patio de juego, y con más taparía tu
            //  trabajo, que sigue ahí debajo.
            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 0.12
            }

            //  El aviso, pegado bajo la island para que se lea sin buscarlo.
            Rectangle {
                x: self.casaX - width / 2
                y: self.casaY + 8
                width: texto.implicitWidth + 24
                height: 30
                radius: 15
                color: K4.Tema.superficie
                border.width: 1
                border.color: K4.Tema.carril

                K4.Etiqueta {
                    id: texto
                    anchors.centerIn: parent
                    text: self.fase === "espera"
                            ? Idioma.f(Idioma.t("Tira la pelota  ·  %1 de %2"),
                                       self.ronda + 1, self.rondas)
                        : self.fase === "corriendo" ? Idioma.t("¡Va a por ella!")
                        : self.fase === "volviendo" ? Idioma.t("Volviendo…")
                        : Idioma.t("¡Buen chico!")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            //  ── la pelota ─────────────────────────────────────────
            Rectangle {
                id: pelota
                width: 26
                height: 26
                radius: 13
                x: self.casaX - 13
                y: self.casaY + 54
                color: "#e05a4a"
                border.width: 2
                border.color: "#ffd0c4"
                z: 2

                //  La costura, para que parezca una pelota y no un punto.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 6
                    height: 2
                    color: "#ffd0c4"
                    opacity: 0.8
                }

                //  Bota en el sitio mientras espera a que la cojas.
                SequentialAnimation on scale {
                    running: self.fase === "espera"
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.12; duration: 420 }
                    NumberAnimation { to: 1.0; duration: 420 }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: self.fase === "espera"
                    cursorShape: Qt.OpenHandCursor
                    drag.target: pelota
                    drag.axis: Drag.XAndYAxis
                    //  Soltar = tirar. Arrastrar y soltar es el gesto natural
                    //  aquí, y además deja elegir la distancia, que es lo que
                    //  decide cuánto entrena.
                    onReleased: self.lanzar(pelota.x + pelota.width / 2,
                                            pelota.y + pelota.height / 2)
                }
            }

            //  ── el bicho, fuera de casa ───────────────────────────
            Item {
                id: corredor
                width: 64
                height: 64
                x: self.casaX - 32
                y: self.casaY - 10
                z: 3
                visible: self.fase === "corriendo" || self.fase === "volviendo"

                Retrato {
                    anchors.fill: parent
                    especie: Digivice.especie
                }

                //  Mira hacia donde corre. Con el signo cambiado: los sprites
                //  de Wikimon vienen mirando a la izquierda, así que correr
                //  hacia la derecha es el caso que hay que espejar. Aquí
                //  corría de espaldas a la pelota.
                transform: Scale {
                    origin.x: corredor.width / 2
                    xScale: pelota.x > corredor.x ? -1 : 1
                }

                //  El trote: dos posiciones, sin interpolar.
                SequentialAnimation on y {
                    running: self.fase === "corriendo" || self.fase === "volviendo"
                    loops: Animation.Infinite
                    NumberAnimation { to: corredor.y - 5; duration: 150 }
                    NumberAnimation { to: corredor.y; duration: 150 }
                }
            }

            //  Ir: la velocidad sale de la del bicho, así que criarlo importa
            //  también aquí.
            ParallelAnimation {
                id: corre
                NumberAnimation {
                    target: corredor; property: "x"
                    to: pelota.x + pelota.width / 2 - 32
                    duration: Math.max(500, 1500 - Digivice.statsDe(Digivice.especie).vel * 20)
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: corredor; property: "y"
                    to: pelota.y + pelota.height / 2 - 32
                    duration: Math.max(500, 1500 - Digivice.statsDe(Digivice.especie).vel * 20)
                    easing.type: Easing.InOutQuad
                }
                onFinished: self._recogida()
            }

            //  Volver, con la pelota a cuestas.
            ParallelAnimation {
                id: vuelve
                NumberAnimation {
                    target: corredor; property: "x"
                    to: self.casaX - 32; duration: 900; easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: corredor; property: "y"
                    to: self.casaY - 10; duration: 900; easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: pelota; property: "x"
                    to: self.casaX - 13; duration: 900; easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: pelota; property: "y"
                    to: self.casaY + 54; duration: 900; easing.type: Easing.InOutQuad
                }
                onFinished: self._envuelta()
            }
        }
    }

    //  Lo que se ve DENTRO del aparato mientras se juega fuera: la carcasa
    //  no puede quedarse en negro mientras su bicho corre por la pantalla.
    Column {
        anchors.centerIn: parent
        width: parent.width - 16
        spacing: 6

        K4.Glifo {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String.fromCodePoint(0xF04B8)
            font.pixelSize: 30
            color: "#9fd8ae"

            SequentialAnimation on rotation {
                running: true
                loops: Animation.Infinite
                NumberAnimation { to: 12; duration: 500 }
                NumberAnimation { to: -12; duration: 500 }
            }
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: Idioma.t("Ha salido a jugar.\nArrastra la pelota por la pantalla.")
            font.pixelSize: 13
            color: "#8fbf9c"
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: (self.ronda + 1) + " / " + self.rondas
            font.pixelSize: 12
            color: "#5f8f6c"
        }
    }

    Component.onCompleted: fase = "espera"
}
