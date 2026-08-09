//  El sitio donde está el bicho.
//
//  Nueve fondos, uno por zona, generados con la herramienta de imágenes y
//  ya en el verde del LCD: bosque, fondo marino, cielo, jungla, volcán,
//  ciudad de metal, bosque muerto, templo y abismo. Sustituyen a los
//  rectángulos que había antes, que cumplían pero eran cuatro palos.
//
//  Y la regla de siempre, que la Mazmorra dejó escrita en su `Fondo.qml`:
//  **nada de deriva en reposo**. El paisaje solo se mueve cuando se da un
//  paso. En una pantalla de 250 píxeles un fondo que nunca para no deja
//  mirar nada más.
//
//  Se dibuja DOS VECES, una al lado de otra, y se desplaza con módulo: es
//  lo que hace el bucle infinito sin cargar nada y sin costuras.

import QtQuick
import K4 as K4

Item {
    id: self
    clip: true

    //  El color de la pantalla: el paisaje se pinta en tonos de ESE verde
    //  para que parezca dibujado por el mismo LCD y no pegado encima.
    property color tono: "#0d1f14"
    //  Cuánto se ha recorrido, en píxeles. Lo mueve quien lo use.
    property real avance: 0
    //  Qué zona se pinta. El índice es el de `Digivice.zonas`.
    property int semilla: 0

    readonly property var _ficheros: [
        "nature", "deep", "wind", "jungle", "dragon",
        "metal", "nightmare", "virus", "dark"
    ]
    readonly property string fuente: Qt.resolvedUrl(
        "fondos/" + _ficheros[Math.max(0, Math.min(_ficheros.length - 1, semilla))] + ".png")

    readonly property color lejos: Qt.lighter(tono, 1.28)
    readonly property color cerca: Qt.lighter(tono, 1.7)
    readonly property color suelo: Qt.lighter(tono, 2.1)

    //  Un pseudoaleatorio de bolsillo, estable: el mismo perfil siempre para
    //  la misma zona. Con Math.random() el paisaje cambiaría en cada
    //  repintado, que es peor que no tener paisaje.
    function _r(i) {
        const x = Math.sin((i + 1) * 12.9898 + semilla * 78.233) * 43758.5453
        return x - Math.floor(x)
    }

    //  Las dos copias del fondo, desplazándose.
    Repeater {
        model: 2

        Image {
            required property int index
            source: self.fuente
            height: parent.height
            //  Ancho proporcional para no deformar el dibujo.
            width: height * (sourceSize.width / Math.max(1, sourceSize.height))
            fillMode: Image.PreserveAspectFit
            //  Suavizar o no depende de si la imagen se AGRANDA o se REDUCE,
            //  que es la misma regla que ya estaba escrita en `Retrato.qml` y
            //  que aquí faltaba. Estos fondos son de 512x288 y en una pantalla
            //  de 250 se dibujan a menos de su tamaño: sin filtrar, el
            //  escalado se salta uno de cada cuatro píxeles y las islas
            //  flotantes salían con los bordes rotos, como recortes de papel
            //  medio dobladas. Agrandando sigue sin suavizarse, que ahí lo
            //  que hay que respetar es el pixel art.
            smooth: sourceSize.width > width
            mipmap: false
            asynchronous: true
            opacity: 0.9

            x: {
                const w = Math.max(1, width)
                const d = ((self.avance * 0.55) % w + w) % w
                return index * w - d
            }
        }
    }

    //  Un velo del tono de la pantalla por encima: es lo que funde el dibujo
    //  con el cristal en vez de dejarlo pegado como una calcomanía.
    Rectangle {
        anchors.fill: parent
        color: self.tono
        opacity: 0.35
    }
}
