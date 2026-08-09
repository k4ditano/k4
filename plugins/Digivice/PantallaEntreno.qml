//  Elegir QUÉ entrenar, que es de lo que iba todo esto.
//
//  Antes había un icono «Entrenar» que subía un número. Ahora eliges entre
//  cuatro estadísticas —cada una con su minijuego— y con qué dificultad, así
//  que entrenar pasa a ser decidir qué clase de Digimon quieres: un tanque de
//  PV y DEF juega distinto a un veloz que lo esquiva todo.
//
//  A recorre las cuatro, B empieza el entrenamiento y la dificultad se cambia
//  pinchándola.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    property int cursor: 0
    signal empezar(string stat)
    property var zumbador: null

    readonly property int indice: {
        const n = Digivice.estadisticas.length
        return ((cursor % n) + n) % n
    }
    readonly property string elegida: Digivice.estadisticas[indice]

    function elegir() { self.empezar(self.elegida) }

    //  Qué entrena cada una y con qué juego, para que se sepa a qué se juega.
    readonly property var descripcion: ({
        "pv":  { nombre: Idioma.t("Vida"),     juego: Idioma.t("aguante"),  glifo: 0xF02D1 },
        "atq": { nombre: Idioma.t("Ataque"),   juego: Idioma.t("puntería"), glifo: 0xF04E5 },
        "def": { nombre: Idioma.t("Defensa"),  juego: Idioma.t("bloqueo"),  glifo: 0xF0498 },
        "vel": { nombre: Idioma.t("Velocidad"), juego: Idioma.t("pelota"),  glifo: 0xF04B8 }
    })

    Column {
        anchors.fill: parent
        anchors.margins: 5
        spacing: 3

        //  Las cuatro, con su nivel y su tope: es la hoja de entrenamiento.
        Repeater {
            model: Digivice.estadisticas

            Rectangle {
                id: fila
                required property string modelData
                required property int index
                width: parent.width
                height: 30
                radius: 5
                color: index === self.indice ? "#1f4a2f" : "transparent"
                border.width: index === self.indice ? 1 : 0
                border.color: "#7de08a"

                readonly property int valor: Digivice.entrenoDe(modelData)
                readonly property bool alTope: valor >= Digivice.topeEntreno

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    K4.Glifo {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(self.descripcion[fila.modelData].glifo)
                        font.pixelSize: 13
                        color: fila.alTope ? "#e8b45a" : "#9fd8ae"
                    }

                    K4.Etiqueta {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 74
                        text: self.descripcion[fila.modelData].nombre
                        font.pixelSize: 13
                        font.weight: fila.index === self.indice ? Font.Bold : Font.Normal
                        color: "#d8f0de"
                    }

                    //  El progreso en puntos, que es un LCD.
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Repeater {
                            model: 6

                            Rectangle {
                                required property int index
                                width: 7; height: 7
                                //  Seis puntos para todo el tope, sea cual sea.
                                readonly property real tramo:
                                    Digivice.topeEntreno / 6
                                color: fila.valor >= (index + 1) * tramo
                                     ? (fila.alTope ? "#e8b45a" : "#7de08a")
                                     : "#24402e"
                            }
                        }
                    }
                }

                K4.Etiqueta {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: fila.valor + "/" + Digivice.topeEntreno
                    font.pixelSize: 12
                    color: fila.alTope ? "#e8b45a" : "#5f8f6c"
                }
            }
        }

        Item { width: 1; height: 2 }

        //  La dificultad, que es la otra decisión: cuánto te juegas.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 168; height: 28; radius: 14
            color: raton.containsMouse ? "#3f8a56" : "#2f6b40"
            border.width: 1
            border.color: "#7de08a"

            K4.Etiqueta {
                anchors.centerIn: parent
                text: Idioma.t("Dificultad") + ": " + self.nombreDificultad
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            MouseArea {
                id: raton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                //  Con su clic: cambiar la dificultad decide cuánto ganas y
                //  qué te juegas, así que no puede ser el único mando del
                //  aparato que se acciona en silencio.
                onClicked: {
                    Digivice.cambiarDificultad()
                    if (self.zumbador) self.zumbador.sonar("boton")
                }
            }
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Idioma.f(Idioma.t("B: %1  ·  ×%2"),
                           self.descripcion[self.elegida].juego,
                           self.factorDificultad)
            font.pixelSize: 12
            color: "#5f8f6c"
        }
    }

    readonly property string nombreDificultad: {
        for (let i = 0; i < Digivice.dificultades.length; ++i)
            if (Digivice.dificultades[i].id === Digivice.dificultad)
                return Digivice.dificultades[i].nombre
        return ""
    }
    readonly property int factorDificultad: {
        for (let i = 0; i < Digivice.dificultades.length; ++i)
            if (Digivice.dificultades[i].id === Digivice.dificultad)
                return Digivice.dificultades[i].factor
        return 1
    }
}
