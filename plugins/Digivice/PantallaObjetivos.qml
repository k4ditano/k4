//  Objetivos: a qué jugar, y qué se saca de jugarlo.
//
//  El juego pedía cosas y no daba ninguna: se criaba porque sí y ganar un
//  combate solo movía un contador que nadie miraba. Los objetivos son la capa
//  que dice qué merece la pena hacer a continuación, y son de cuatro familias
//  —crianza, colección, combate y exploración— para que no haya una sola
//  manera de jugar.
//
//  El premio se COBRA a mano. Un premio que entra solo mientras miras otra
//  pantalla no se siente como un premio: se siente como un número que cambió.
//
//  ── por qué esto ya no es una lista ──────────────────────────────
//  Era cinco renglones con un «3/10» al final. Dos problemas de fondo:
//
//  - **«3/10» no es progreso, es una fracción.** Una barra que se llena dice
//    de un vistazo cuánto falta, y con quince objetivos a la vez eso es la
//    diferencia entre elegir el siguiente y rendirse. Ahora cada renglón
//    lleva su barra, del color de su familia.
//  - **Cobrar no se veía.** Sumaba bits y ya. Ahora el renglón se enciende en
//    dorado, cae un **sello** encima —lo que hace un objetivo cumplido es
//    quedarse marcado— y los bits **vuelan al contador** de la cabecera.
//
//  Y arriba hay un anillo con lo que llevas del total, porque el número de
//  cobrados sin nada al lado no dice si vas por el principio o por el final.
//
//  A recorre, B cobra el que esté listo.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    property int cursor: 0

    //  Los cobrables primero: es lo único que exige una acción, y hacerte
    //  buscarlo entre quince líneas sería esconder la recompensa.
    readonly property var lista: {
        const l = Digivice.objetivos.slice()
        l.sort(function (a, b) {
            if (a.cobrable !== b.cobrable) return a.cobrable ? -1 : 1
            if (a.cobrado !== b.cobrado) return a.cobrado ? 1 : -1
            //  Y entre los pendientes, el más cerca de cumplirse.
            return (b.hay / b.meta) - (a.hay / a.meta)
        })
        return l
    }
    readonly property int total: lista.length
    readonly property int indice: total > 0
                                ? ((cursor % total) + total) % total : 0
    readonly property var elegido: total > 0 ? lista[indice] : null

    readonly property int cobrados: Digivice.objetivos.filter(function (o) {
        return o.cobrado
    }).length
    readonly property int cuantos: Digivice.objetivos.length

    function elegir() {
        if (self.elegido)
            Digivice.cobrarObjetivo(self.elegido.obj.id)
    }

    readonly property var colorTipo: ({
        "crianza": "#9fd8ae", "coleccion": "#e8b45a", "combate": "#e0806b",
        "exploracion": "#8ab4e0"
    })

    //  ── el cobro ──────────────────────────────────────────────────
    property int _premio: 0
    property real _vuelo: 0
    property real _selloOp: 0
    //  A QUIÉN se le pone el sello. Por id y no «al renglón señalado»: en
    //  cuanto cobras, la lista se reordena —los cobrados se van al fondo— y
    //  el señalado pasa a ser otro objetivo. El sello caía sobre el de
    //  debajo, o sea marcaba como cumplido uno que no lo estaba.
    property string _sellado: ""

    Connections {
        target: Digivice
        function onObjetivoCobrado(id, bits, objeto) {
            self._premio = bits
            self._sellado = id
            vuelan.restart()
            sello.restart()
        }
    }

    SequentialAnimation {
        id: vuelan
        ScriptAction { script: self._vuelo = 0 }
        NumberAnimation { target: self; property: "_vuelo"; to: 1
                          duration: 620; easing.type: Easing.InQuad }
        ScriptAction { script: self._vuelo = 0 }
        //  El contador acusa la llegada: si no, las monedas aterrizan en un
        //  número que no se inmuta y el vuelo no ha servido de nada.
        NumberAnimation { target: hucha; property: "scale"; to: 1.35
                          duration: 110 }
        NumberAnimation { target: hucha; property: "scale"; to: 1.0
                          duration: 240; easing.type: Easing.OutBounce }
    }

    SequentialAnimation {
        id: sello
        ScriptAction { script: self._selloOp = 1 }
        PauseAnimation { duration: 620 }
        NumberAnimation { target: self; property: "_selloOp"; to: 0
                          duration: 320 }
        ScriptAction { script: self._sellado = "" }
    }

    Rectangle {
        anchors.fill: parent
        color: "#0b1410"
    }

    // ── la cabecera: el anillo y el monedero ──────────────────────
    Item {
        id: cabecera
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 4
        height: 20

        //  El avance total como barra de aro: cuántos de cuántos, pero VISTO.
        Rectangle {
            id: aro
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 74
            height: 7
            radius: 3
            color: "#16241b"

            Rectangle {
                width: parent.width * (self.cuantos > 0
                                     ? self.cobrados / self.cuantos : 0)
                height: parent.height
                radius: 3
                color: "#e8b45a"
                Behavior on width { NumberAnimation { duration: 380 } }
            }
        }

        K4.Etiqueta {
            anchors.left: aro.right
            anchors.leftMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            text: self.cobrados + "/" + self.cuantos
            font.pixelSize: 11
            font.weight: Font.Bold
            color: "#d8f0de"
        }

        Bits {
            id: hucha
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            valor: Digivice.bits
            tam: 12
        }
    }

    //  Las monedas del premio, volando del renglón cobrado al monedero. Es
    //  lo que convierte «has cobrado» en algo que ha PASADO.
    K4.Etiqueta {
        visible: self._vuelo > 0
        text: "+" + self._premio
        font.pixelSize: 13
        font.weight: Font.Bold
        color: "#e8b45a"
        z: 8
        x: (self.width * 0.5) + (hucha.x + hucha.width / 2 - self.width * 0.5)
              * self._vuelo - width / 2
        y: (marco.y + 24) + (cabecera.y + 4 - marco.y - 24) * self._vuelo
        opacity: 1 - self._vuelo * 0.4
    }

    // ── los renglones ─────────────────────────────────────────────
    //  Solo caben unos pocos a la vez: se enseña una ventana alrededor del
    //  señalado en vez de los quince, que no entran en un LCD y obligarían a
    //  un desplazamiento que este aparato no tiene.
    Column {
        id: marco
        anchors.top: cabecera.bottom
        anchors.topMargin: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 4
        spacing: 2

        Repeater {
            model: 5

            Item {
                id: fila
                required property int index
                width: parent.width
                height: 30

                readonly property int j: self.total > 0
                        ? (self.indice + fila.index - 1 + self.total) % self.total : 0
                readonly property var e: self.total > 0 ? self.lista[fila.j] : null
                readonly property bool activo: fila.index === 1
                readonly property color tinte: fila.e
                        ? (self.colorTipo[fila.e.obj.tipo] || "#8fbf9c") : "#8fbf9c"

                visible: fila.e !== null && (self.total >= 5 || fila.j < self.total)

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: fila.activo ? "#16281c" : "transparent"
                    border.width: fila.activo ? 1 : 0
                    border.color: fila.e && fila.e.cobrable ? "#e8b45a" : "#3f7a52"

                    //  Un objetivo listo para cobrar LATE. Es la única cosa de
                    //  esta pantalla que pide una pulsación.
                    SequentialAnimation on opacity {
                        running: fila.e !== null && fila.e.cobrable
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.55; duration: 620 }
                        NumberAnimation { to: 1.0; duration: 620 }
                    }
                }

                //  El sello de cobrado, que cae encima al cobrarlo.
                K4.Glifo {
                    visible: self._selloOp > 0 && fila.e !== null
                             && fila.e.obj.id === self._sellado
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F012C}"
                    font.pixelSize: 22
                    color: "#e8b45a"
                    opacity: self._selloOp
                    scale: 0.6 + self._selloOp * 0.9
                    z: 4
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Row {
                        width: parent.width
                        spacing: 4

                        //  Un punto del color de su familia: se lee de un
                        //  vistazo si lo que falta es criar, coleccionar,
                        //  pelear o explorar.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 5; height: 5; radius: 3
                            color: fila.tinte
                            opacity: fila.e && fila.e.cobrado ? 0.35 : 1
                        }

                        K4.Etiqueta {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 58
                            text: fila.e ? Idioma.t(fila.e.obj.texto) : ""
                            font.pixelSize: 11
                            font.weight: fila.activo ? Font.DemiBold : Font.Normal
                            color: fila.e && fila.e.cobrado ? "#4f7a5c" : "#d8f0de"
                            elide: Text.ElideRight
                        }

                        K4.Glifo {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: fila.e !== null && fila.e.cobrado
                            text: "\u{F012C}"
                            font.pixelSize: 11
                            color: "#4f7a5c"
                        }

                        Bits {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: fila.e !== null && !fila.e.cobrado
                            valor: fila.e ? fila.e.obj.bits : 0
                            apagado: fila.e !== null && !fila.e.cobrable
                        }
                    }

                    //  LA BARRA. Es lo que faltaba: «3/10» obliga a dividir
                    //  mentalmente quince veces seguidas.
                    //
                    //  Y la cifra AL LADO, no encima. Metida dentro de una
                    //  barra de 5 píxeles con una fuente de 9 se salía por
                    //  arriba y por abajo y se leía a medias sobre el relleno.
                    Row {
                        width: parent.width
                        height: 6
                        spacing: 4
                        visible: fila.e !== null && !fila.e.cobrado

                        Item {
                            width: parent.width - 34
                            height: parent.height
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: "#16241b"
                            }

                            Rectangle {
                                width: parent.width * (fila.e
                                     ? Math.min(1, fila.e.hay / Math.max(1, fila.e.meta)) : 0)
                                height: parent.height
                                radius: 3
                                color: fila.tinte
                                Behavior on width { NumberAnimation { duration: 320 } }
                            }
                        }

                        K4.Etiqueta {
                            width: 30
                            anchors.verticalCenter: parent.verticalCenter
                            text: fila.e ? fila.e.hay + "/" + fila.e.meta : ""
                            font.pixelSize: 9
                            color: fila.activo ? "#d8f0de" : "#6f9c7c"
                            font.weight: fila.activo ? Font.Bold : Font.Normal
                        }
                    }
                }
            }
        }
    }

    // ── el pie: qué da el señalado ────────────────────────────────
    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4
        visible: self.elegido !== null

        K4.Etiqueta {
            anchors.verticalCenter: parent.verticalCenter
            text: !self.elegido ? ""
                : self.elegido.cobrado ? Idioma.t("Ya cobrado")
                : self.elegido.cobrable ? Idioma.t("B lo cobra:")
                : Idioma.t("Da")
            font.pixelSize: 11
            color: self.elegido && self.elegido.cobrable ? "#e8b45a" : "#6f9c7c"
        }

        Bits {
            anchors.verticalCenter: parent.verticalCenter
            visible: self.elegido !== null && !self.elegido.cobrado
            valor: self.elegido ? self.elegido.obj.bits : 0
            apagado: self.elegido !== null && !self.elegido.cobrable
        }

        //  Y el objeto que regala, si regala alguno: es la mitad del premio
        //  en los cuatro que lo llevan.
        K4.Etiqueta {
            anchors.verticalCenter: parent.verticalCenter
            visible: self.elegido !== null && !self.elegido.cobrado
                     && self.elegido.obj.objeto !== undefined
            text: self.elegido && self.elegido.obj.objeto
                ? "+ " + Idioma.t(Digivice.nombreObjeto(self.elegido.obj.objeto))
                : ""
            font.pixelSize: 11
            color: "#9fd8ae"
            elide: Text.ElideRight
        }
    }
}
