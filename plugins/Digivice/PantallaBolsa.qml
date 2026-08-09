//  La bolsa: todo lo que llevas encima, comida y objetos.
//
//  Había un botón «comer» y ya está: +1 de hambre, +1 de peso, sin elección.
//  Un sistema de cuidado con un solo verbo no tiene decisiones dentro, que es
//  lo que le pasaba a casi todo este juego.
//
//  Ahora cada comida es un trato distinto —llenar, engordar, dar vigor,
//  curar o envenenarte— y los objetos entran en la MISMA lista, porque el
//  jugador no piensa «comida» y «objeto»: piensa «qué llevo encima». Dos
//  pantallas para eso serían dos iconos más en un menú que ya va lleno.
//
//  La ración sale siempre y no se cuenta: que un fallo de la caza pueda dejar
//  a un bicho sin nada que llevarse a la boca sería un bug con forma de
//  hambruna.
//
//  A recorre, B lo usa —se lo come o lo aplica, según lo que sea—.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    property int cursor: 0

    readonly property var lista: Digivice.bolsa
    readonly property int total: lista.length
    readonly property int indice: total > 0
                                ? ((cursor % total) + total) % total : 0
    readonly property var elegida: total > 0 ? lista[indice] : null

    function elegir() {
        if (!self.elegida)
            return
        //  Un solo botón para las dos clases: dárselo de comer o usarlo. La
        //  vitamina va sobre la estadística más floja, que es lo que haría
        //  cualquiera y evita una pregunta más en un aparato de tres botones.
        if (self.elegida.clase === "comida")
            Digivice.alimentarCon(self.elegida.id)
        else
            Digivice.usarObjeto(self.elegida.id, self.masFloja())
    }

    //  La estadística con menos entreno, para la vitamina. Con empate gana el
    //  orden de siempre —PV, ATQ, DEF, VEL—, que es estable entre partidas.
    function masFloja() {
        let cual = "pv", min = 1e9
        for (let i = 0; i < Digivice.estadisticas.length; ++i) {
            const k = Digivice.estadisticas[i]
            const v = Digivice.entrenoDe(k)
            if (v < min) { min = v; cual = k }
        }
        return cual
    }

    Column {
        anchors.fill: parent
        anchors.margins: 5
        spacing: 2

        //  El estado que justifica venir aquí: cuánta hambre tiene y si lleva
        //  algo encima. Sin esto, elegir comida sería a ciegas.
        Row {
            width: parent.width
            spacing: 4

            //  Sin icono de etiqueta delante: era otro corazón igual que los
            //  del hambre y se leía como un quinto corazón lleno.
            Repeater {
                model: Digivice.maxCorazones

                K4.Glifo {
                    id: corazon
                    required property int index
                    anchors.verticalCenter: parent.verticalCenter
                    text: corazon.index < Digivice.hambre ? "\u{F02D1}" : "\u{F02D5}"
                    font.pixelSize: 11
                    color: corazon.index < Digivice.hambre ? "#e0806b" : "#4a3a34"
                }
            }

            Item { width: 4; height: 1 }

            //  Lo que lleva puesto: veneno del que hay que curarse y vigor
            //  que se está gastando. Si no se vieran aquí, comer carne sería
            //  fe y comer basura sería un misterio.
            K4.Glifo {
                anchors.verticalCenter: parent.verticalCenter
                visible: Digivice.envenenado
                text: "\u{F00A7}"
                font.pixelSize: 12
                color: "#9fe07a"
            }

            K4.Etiqueta {
                anchors.verticalCenter: parent.verticalCenter
                visible: Digivice.vigor > 0
                text: "\u{F141F}×" + Digivice.vigor
                font.pixelSize: 11
                color: "#e8b45a"
            }

            Item { width: 1; height: 1 }

            //  Los bits, aquí también: es donde se mira antes de ir al
            //  mercado, y un contador de dinero escondido en otra pantalla se
            //  consulta a ciegas.
            Bits {
                anchors.verticalCenter: parent.verticalCenter
                valor: Digivice.bits
            }
        }

        Repeater {
            model: self.lista

            Rectangle {
                id: fila
                required property var modelData
                required property int index
                width: parent.width
                //  La fila señalada crece: lleva la nota debajo del nombre y
                //  con una altura fija los dos textos se pisaban.
                height: fila.index === self.indice ? 36 : 26
                radius: 5
                color: fila.index === self.indice ? "#1f4a2f" : "transparent"
                border.width: fila.index === self.indice ? 1 : 0
                border.color: "#7de08a"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    spacing: 5

                    K4.Glifo {
                        anchors.verticalCenter: parent.verticalCenter
                        text: fila.modelData.glifo
                        font.pixelSize: 15
                        //  La que sienta mal, en su color: el aviso tiene que
                        //  estar ANTES de dársela, no después.
                        color: fila.modelData.malo ? "#c98a6b"
                             : fila.modelData.clase === "objeto" ? "#9fd8ae"
                             : "#e8dcc8"
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 52

                        K4.Etiqueta {
                            width: parent.width
                            text: Idioma.t(fila.modelData.nombre)
                            font.pixelSize: 12
                            font.weight: fila.index === self.indice
                                       ? Font.Bold : Font.Normal
                            color: "#d8f0de"
                            elide: Text.ElideRight
                        }

                        K4.Etiqueta {
                            width: parent.width
                            visible: fila.index === self.indice
                            text: Idioma.t(fila.modelData.nota)
                            font.pixelSize: 11
                            color: "#8fbf9c"
                            elide: Text.ElideRight
                        }
                    }

                    K4.Etiqueta {
                        anchors.verticalCenter: parent.verticalCenter
                        //  −1 es «infinita»: la ración no se cuenta.
                        text: fila.modelData.cuantas < 0
                            ? "\u{221E}" : "×" + fila.modelData.cuantas
                        font.pixelSize: 12
                        color: "#5f8f6c"
                    }
                }
            }
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: self.elegida && self.elegida.clase === "objeto"
                ? Idioma.t("B lo usa")
                : Idioma.t("B se lo da  ·  caza para tener más")
            font.pixelSize: 11
            color: "#5f8f6c"
        }
    }
}
