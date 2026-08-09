//  La carcasa: el Digivice como objeto, y ahora la island ENTERA.
//
//  Antes esto era un rectángulo dibujado dentro de un panel: una caja dentro
//  de otra caja. Ya no. La island se abre estrecha y alta y el aparato la
//  llena, así que lo que cuelga de la barra ES el aparato.
//
//  Por eso aquí no se pinta ningún cuerpo: el fondo de la island hace de
//  carcasa. Es lo que evita el único defecto posible —dos juegos de esquinas
//  que no encajan—, porque la silueta de la island no es un rectángulo
//  redondeado: abajo tiene radio 32 y arriba unas «alas» invertidas que se
//  funden con el borde de la barra. Cualquier cuerpo mío se saldría por ahí.
//
//  Los tres botones son los de siempre: A recorre los iconos, B elige, C
//  vuelve. En el aparato de verdad no hay nada más, y aquí tampoco.

import QtQuick
import K4 as K4

Item {
    id: self

    property alias pantalla: hueco.contenido
    property color tinteLcd: "#0d1f14"
    property bool encendida: true

    property var iconos: []
    //  Acciones del menú que llevan aviso: se pintan en ámbar y con un punto
    //  rojo latiendo. Por `accion` y no por índice: el menú ha cambiado de
    //  orden dos veces y un índice a mano habría marcado el icono de al lado.
    property var alertas: []
    property int iconoActivo: -1
    //  Señalado y parpadeando (estás recorriendo el menú) frente a señalado y
    //  fijo (ya has entrado en esa pantalla). Sin esta diferencia no hay
    //  manera de saber si A va a pasar al icono siguiente o a moverse por
    //  dentro de lo que estás mirando.
    property bool iconoFijo: false

    //  Lo que señala el menú, escrito bajo la pantalla. Es chapa del aparato
    //  y por eso vive aquí y no en la vista.
    property string leyenda: ""

    //  Lo que mide el aparato de arriba abajo. La island se ajusta a ESTO:
    //  antes la altura era un número puesto a mano y sobraban 80 px de
    //  cuerpo vacío entre la pantalla y los botones.
    readonly property real altoNecesario: 4 + bisel.height + 18 + 10 + 50 + 12 + 9 + 12

    signal pulsadoA()
    signal pulsadoB()
    signal pulsadoC()

    //  El zumbador, para que los botones suenen al pulsarse. Lo pone la
    //  vista, que es quien lo tiene.
    property var zumbador: null
    function _pitar(n) { if (zumbador) zumbador.sonar(n) }

    // ── el bisel que rodea la pantalla ────────────────────────────
    Rectangle {
        id: bisel
        x: 14
        anchors.top: parent.top
        anchors.topMargin: 4
        width: parent.width - 28
        //  Casi cuadrada, como la de los aparatos: una pantalla muy alta
        //  parecería un móvil, y esto no es un móvil.
        height: width * 0.95
        radius: 14
        color: "#1a1d23"
        border.width: 1
        border.color: "#40454f"
    }

    // ── la fila de iconos, como el menú del aparato ───────────────
    Flow {
        anchors.horizontalCenter: bisel.horizontalCenter
        y: bisel.y + 5
        width: bisel.width - 16
        spacing: 7
        z: 3

        Repeater {
            model: self.iconos

            K4.Glifo {
                id: icono
                required property var modelData
                required property int index
                readonly property bool avisa:
                    self.alertas.indexOf(modelData.accion) >= 0
                text: String.fromCodePoint(modelData.glifo)
                font.pixelSize: 13
                color: index === self.iconoActivo ? K4.Tema.amarillo
                     : avisa ? "#e8b45a" : "#4c5561"

                //  El icono elegido parpadea, como el cursor del aparato.
                SequentialAnimation on opacity {
                    running: index === self.iconoActivo && !self.iconoFijo
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 520 }
                    NumberAnimation { to: 1.0; duration: 520 }
                }

                //  El punto de «aquí te espera algo». El aviso de pantalla
                //  dura dos segundos y se va; esto se queda hasta que vayas,
                //  que es lo que hace que avisar sin sacarte de donde estás
                //  funcione: si no, quien no llegue a leer el cartel se queda
                //  sin saber que hay algo.
                Rectangle {
                    visible: icono.avisa && icono.index !== self.iconoActivo
                    x: parent.width - 2
                    y: -1
                    width: 5; height: 5; radius: 2.5
                    color: "#e05a4a"

                    SequentialAnimation on opacity {
                        running: parent.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 460 }
                        NumberAnimation { to: 1.0; duration: 460 }
                    }
                }
            }
        }
    }

    // ── la pantalla ───────────────────────────────────────────────
    Pantalla {
        id: hueco
        x: bisel.x + 9
        //  Justo debajo de los iconos y no 28 px más abajo: la fila mide 12
        //  de alto y se le daba el doble de sitio, así que el cristal
        //  arrancaba a media carcasa.
        y: bisel.y + 22
        width: bisel.width - 18
        height: bisel.height - 30
        tinte: self.tinteLcd
        encendida: self.encendida
    }

    //  La leyenda, pegada bajo la pantalla.
    K4.Etiqueta {
        id: leyendaTexto
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: bisel.bottom
        anchors.topMargin: 4
        text: self.leyenda
        font.pixelSize: 12
        color: K4.Tema.apagado
    }

    // ── los tres botones ──────────────────────────────────────────
    //  Colgados del bisel y no del fondo de la island: así el cuerpo mide lo
    //  que tiene que medir y no queda aire entre la pantalla y los botones.
    Row {
        id: botones
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: leyendaTexto.bottom
        anchors.topMargin: 10
        spacing: 20

        Repeater {
            model: ["A", "B", "C"]

            Item {
                id: boton
                required property var modelData
                required property int index
                width: 50
                height: 50

                //  La sombra, que es lo que lo levanta del cuerpo.
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 3
                    radius: width / 2
                    color: "#15181d"
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: raton.pressed ? "#4a5160" : "#39404d"
                    border.width: 1
                    border.color: raton.containsMouse ? "#6d7789" : "#232830"

                    //  Se hunde de verdad: el desplazamiento vende el botón
                    //  físico mejor que cualquier sombra pintada.
                    y: raton.pressed ? 3 : 0
                    Behavior on y { NumberAnimation { duration: 60 } }

                    K4.Etiqueta {
                        anchors.centerIn: parent
                        text: boton.modelData
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: raton.containsMouse ? K4.Tema.tinta : "#98a2b3"
                    }
                }

                MouseArea {
                    id: raton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (boton.index === 0) { self._pitar("boton"); self.pulsadoA() }
                        else if (boton.index === 1) { self._pitar("elegir"); self.pulsadoB() }
                        else { self._pitar("atras"); self.pulsadoC() }
                    }
                }
            }
        }
    }

    //  El enganche de la correa, abajo del todo: es lo que remata la
    //  silueta y lo que dice «esto se cuelga».
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: botones.bottom
        anchors.topMargin: 12
        width: 34
        height: 9
        radius: 4.5
        color: "#1a1d23"
        border.width: 1
        border.color: "#40454f"
    }
}
