//  El golpe que cruza la pantalla, con la pinta del bicho que lo tira.
//
//  Antes todos los golpes eran el mismo punto de color con una estela: daba
//  igual que pegara un dragón, una planta o una máquina. Con 1488 especies
//  eso tiraba por la borda lo único que las distingue aparte del sprite.
//
//  La forma sale del ARQUETIPO y el halo del ATRIBUTO —los decide
//  `Reglas.golpeVistaDe`, que es donde se puede probar—; aquí solo se
//  dibujan. Doce dibujos, todos con rectángulos y círculos: nada de shaders
//  ni de imágenes, porque esto se pinta doce veces por combate y tiene que
//  leerse a diez píxeles.
//
//  El halo va DETRÁS y más grande, para que se vea el atributo sin que tape
//  la forma. Así «una hoja con halo morado» se lee como planta virus.

pragma ComponentBehavior: Bound

import QtQuick
import K4 as K4

Item {
    id: self

    //  bola · rayo · roca · luz · sombra · pluma · aguja · hoja · gota ·
    //  garra · filo · chispa
    property string forma: "chispa"
    property color color: "#e8dcc8"
    property color aura: "#d8d8d8"
    //  Cuánto se ha cargado: 0 normal, 1..3 cargado. Un golpe cargado no es
    //  otro dibujo, es el MISMO más grande y con el halo encendido: tiene que
    //  seguir reconociéndose de quién es.
    property int carga: 0
    //  Hacia dónde va, para orientar lo que tiene punta.
    property bool haciaDerecha: true
    property real lado: 12

    readonly property real _tam: lado * (1 + carga * 0.28)

    implicitWidth: _tam * 2
    implicitHeight: _tam * 2

    //  El halo del atributo.
    Rectangle {
        anchors.centerIn: parent
        width: self._tam * (self.carga > 0 ? 2.0 : 1.5)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: self.carga > 0 ? 2 : 1
        border.color: self.aura
        opacity: self.carga > 0 ? 0.75 : 0.4

        SequentialAnimation on scale {
            running: self.carga > 0
            loops: Animation.Infinite
            NumberAnimation { to: 1.18; duration: 200 }
            NumberAnimation { to: 0.95; duration: 200 }
        }
    }

    //  ── los doce dibujos ──────────────────────────────────────────

    //  BOLA · dragones, dinosaurios y llamas. Núcleo claro dentro.
    Item {
        anchors.centerIn: parent
        visible: self.forma === "bola"
        width: self._tam; height: self._tam

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: self.color
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.45
            height: width
            radius: width / 2
            color: Qt.lighter(self.color, 1.8)
        }
    }

    //  RAYO · máquinas y cyborgs. Zigzag de dos tramos.
    Item {
        anchors.centerIn: parent
        visible: self.forma === "rayo"
        width: self._tam * 1.3; height: self._tam * 1.3

        Rectangle {
            x: parent.width * 0.1; y: parent.height * 0.1
            width: parent.width * 0.6; height: 3
            color: self.color
            rotation: 38
            antialiasing: true
        }
        Rectangle {
            x: parent.width * 0.3; y: parent.height * 0.5
            width: parent.width * 0.6; height: 3
            color: self.color
            rotation: -38
            antialiasing: true
        }
    }

    //  ROCA · minerales, corazas y hielo. Rombo de bordes duros.
    Rectangle {
        anchors.centerIn: parent
        visible: self.forma === "roca"
        width: self._tam * 0.85; height: width
        color: self.color
        rotation: 45
        antialiasing: true
    }

    //  LUZ · ángeles y dioses. Estrella de cuatro puntas.
    Item {
        anchors.centerIn: parent
        visible: self.forma === "luz"
        width: self._tam * 1.5; height: self._tam * 1.5

        Rectangle {
            anchors.centerIn: parent
            width: parent.width; height: 3
            color: self.color
        }
        Rectangle {
            anchors.centerIn: parent
            width: 3; height: parent.height
            color: self.color
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.42; height: width
            radius: width / 2
            color: Qt.lighter(self.color, 1.4)
        }
    }

    //  SOMBRA · demonios, no-muertos y oscuridad. Bola hueca de borde grueso.
    Item {
        anchors.centerIn: parent
        visible: self.forma === "sombra"
        width: self._tam; height: self._tam

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#150a1c"
            border.width: 3
            border.color: self.color
        }
    }

    //  PLUMA · pájaros y hadas. Óvalo inclinado.
    Rectangle {
        anchors.centerIn: parent
        visible: self.forma === "pluma"
        width: self._tam * 0.5; height: self._tam * 1.25
        radius: width / 2
        color: self.color
        rotation: self.haciaDerecha ? 34 : -34
        antialiasing: true
    }

    //  AGUJA · insectos y larvas. Alargada y con punta hacia donde va.
    Item {
        anchors.centerIn: parent
        visible: self.forma === "aguja"
        width: self._tam * 1.6; height: self._tam * 0.5

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: self.haciaDerecha ? 0 : parent.width * 0.28
            width: parent.width * 0.72; height: 3
            color: self.color
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: self.haciaDerecha ? parent.width * 0.66 : 0
            width: parent.height * 0.7; height: width
            color: self.color
            rotation: 45
            antialiasing: true
        }
    }

    //  HOJA · plantas. Rombo con dos puntas y dos lados redondos.
    Rectangle {
        anchors.centerIn: parent
        visible: self.forma === "hoja"
        width: self._tam * 0.72; height: self._tam * 1.1
        radius: width / 2
        topLeftRadius: 0
        bottomRightRadius: 0
        color: self.color
        rotation: self.haciaDerecha ? 45 : -45
        antialiasing: true
    }

    //  GOTA · acuáticos y limos. Redonda con cola hacia atrás.
    Item {
        anchors.centerIn: parent
        visible: self.forma === "gota"
        width: self._tam * 1.2; height: self._tam

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: self.haciaDerecha ? parent.width - width : 0
            width: parent.height; height: parent.height
            radius: width / 2
            color: self.color
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: self.haciaDerecha ? 0 : parent.width * 0.55
            width: parent.width * 0.45; height: 3
            color: self.color
            opacity: 0.7
        }
    }

    //  GARRA · bestias, mamíferos y reptiles. Tres zarpazos paralelos.
    Item {
        anchors.centerIn: parent
        visible: self.forma === "garra"
        width: self._tam * 1.2; height: self._tam * 1.2

        Repeater {
            model: 3

            Rectangle {
                required property int index
                x: index * (parent.width * 0.3)
                y: index * 2
                width: 3; height: parent.height * 0.8
                radius: 1.5
                color: self.color
                rotation: self.haciaDerecha ? 20 : -20
                antialiasing: true
            }
        }
    }

    //  FILO · guerreros, muñecos y armas. Una cuchilla.
    Rectangle {
        anchors.centerIn: parent
        visible: self.forma === "filo"
        width: self._tam * 1.5; height: 4
        radius: 2
        color: self.color
        rotation: self.haciaDerecha ? -25 : 25
        antialiasing: true
    }

    //  CHISPA · el respaldo, con dibujo PROPIO y no la bola del dragón. Un
    //  cuadradito girado con cuatro puntos alrededor: se ve que es un golpe
    //  y se ve que no es de nadie en particular, que es la verdad.
    Item {
        anchors.centerIn: parent
        visible: self.forma === "chispa"
        width: self._tam * 1.2; height: self._tam * 1.2

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.45; height: width
            color: self.color
            rotation: 45
            antialiasing: true
        }

        Repeater {
            model: 4

            Rectangle {
                required property int index
                anchors.centerIn: parent
                anchors.horizontalCenterOffset:
                    (index === 0 ? -1 : index === 1 ? 1 : 0) * parent.width * 0.42
                anchors.verticalCenterOffset:
                    (index === 2 ? -1 : index === 3 ? 1 : 0) * parent.height * 0.42
                width: 2; height: 2
                color: self.color
                opacity: 0.8
            }
        }
    }
}
