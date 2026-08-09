//  La pantalla de casa: el bicho y sus dos medidores. Nada más.
//
//  Es lo que enseña un Digivice el 95 % del tiempo, y la contención es
//  justo lo que hace que valga la pena mirarlo.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    //  Lo llama la vista cuando una acción SÍ ha ocurrido.
    function reaccionar(simbolo) { bicho.reaccionar(simbolo) }

    //  En casa el paisaje está QUIETO: es el sitio donde vive, no un viaje.
    //  Mover el fondo aquí sería decir «estás explorando» cuando no lo estás.
    Paisaje {
        anchors.fill: parent
        tono: "#0d1f14"
        semilla: Digivice.indiceZona
        avance: 0
        opacity: 0.55
    }

    Criatura {
        id: bicho
        anchors.fill: parent
        anchors.bottomMargin: 16
        especie: Digivice.especie
        animo: Digivice.animo_
        saltoBaile: Digivice.caracter.baile.salto
        ritmoBaile: Digivice.caracter.baile.ritmo
        durmiendo: Digivice.durmiendo
        enfermo: Digivice.enfermo
        lado: Math.min(104, parent.height - 40)
    }

    //  Las cacas, repartidas por el suelo de la pantalla.
    //
    //  Dibujadas con rectángulos y no con un sprite: a este tamaño una caca
    //  son cuatro píxeles, y cuatro píxeles se dibujan antes que se buscan.
    //  Las posiciones son fijas y no aleatorias para que no salten de sitio
    //  en cada repintado.
    Repeater {
        model: Digivice.suciedad

        Item {
            required property int index
            width: 10
            height: 8
            x: 6 + index * 15
            y: self.height - 26

            Rectangle { x: 2; y: 0; width: 6; height: 2; color: "#6b5334" }
            Rectangle { x: 1; y: 2; width: 8; height: 2; color: "#7d613d" }
            Rectangle { x: 0; y: 4; width: 10; height: 3; color: "#6b5334" }

            //  Un temblorcillo lento: quieto parece parte del fondo.
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { to: self.height - 27; duration: 900 }
                NumberAnimation { to: self.height - 26; duration: 900 }
            }
        }
    }

    //  ── el pie de la pantalla ─────────────────────────────────────
    //
    //  Los medidores y el renglón de consejo, EN COLUMNA. Estaban los dos
    //  anclados al fondo por su cuenta y se pisaban: los cuadraditos salían
    //  encima del texto. Una columna no puede solaparse consigo misma, y
    //  además se encoge sola cuando no hay consejo que enseñar.
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        width: parent.width - 12
        spacing: 3

        //  Los corazones abajo, pequeños: en el aparato son unos cuadraditos.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Repeater {
                model: [
                    { val: Digivice.hambre, col: "#e8d86a" },
                    { val: Digivice.animo, col: "#7de08a" }
                ]

                //  Por `id` y no por `parent.parent`: dentro de dos Repeater
                //  anidados esa cadena es un campo de minas —ya falló con los
                //  corazones de la vista vieja y con las rutas de los sonidos— y
                //  cuando falla no da error, solo pinta mal.
                Row {
                    id: medidor
                    required property var modelData
                    spacing: 3

                    Repeater {
                        model: Digivice.maxCorazones

                        Rectangle {
                            required property int index
                            width: 5; height: 5
                            color: index < medidor.modelData.val
                                 ? medidor.modelData.col : "#24402e"
                        }
                    }
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            Repeater {
                model: Digivice.maxEnergia

                Rectangle {
                    required property int index
                    width: 4; height: 4
                    color: index < Digivice.energia ? "#8ad4f0" : "#12242c"
                }
            }
        }

        //  El renglón, dentro de la misma columna: así el hueco lo reparte
        //  el layout y no dos anclajes que no se conocen.
        K4.Etiqueta {
            id: renglon
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            visible: self._consejo !== ""
            text: self._consejo
            font.pixelSize: 11
            //  Apagado a propósito: es un susurro, no un aviso. Los avisos ya
            //  tienen su burbuja y la píldora.
            color: "#6f9a7c"
            elide: Text.ElideRight

            //  Se desvanece al cambiar: un texto que salta de golpe cada
            //  siete segundos se lee como un parpadeo.
            Behavior on text {
                SequentialAnimation {
                    NumberAnimation { target: renglon; property: "opacity"
                                      to: 0; duration: 160 }
                    PropertyAction {}
                    NumberAnimation { target: renglon; property: "opacity"
                                      to: 1; duration: 260 }
                }
            }
        }
    }

    //  ── lo que el aparato te cuenta ───────────────────────────────
    //
    //  Un renglón discreto, abajo del todo. Existe porque este juego tiene
    //  muchas reglas que solo se notan si alguien te las dice —que el
    //  sobrepeso quita velocidad, que el carácter cambia lo que pide, que la
    //  carretera está parada esperándote— y una regla invisible es
    //  indistinguible de un fallo.
    //
    //  Solo aparece si hay algo que decir: con todo en orden no está. Y va
    //  rotando entre lo que aplica, el más urgente primero, porque enseñar
    //  siempre el mismo esconde los demás.
    property int _iConsejo: 0

    readonly property var _consejos: Digivice.consejos
    readonly property string _consejo: _consejos.length > 0
            ? _consejos[_iConsejo % _consejos.length].texto : ""

    Timer {
        interval: 7000
        repeat: true
        running: self._consejos.length > 1
        onTriggered: self._iConsejo += 1
    }

}
