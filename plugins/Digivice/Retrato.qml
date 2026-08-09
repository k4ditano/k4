//  La cara de un Digimon.
//
//  La imagen no viene empaquetada: es de Bandai y se pide a digi-api la
//  primera vez que hace falta, quedándose en la caché del usuario. Por eso
//  esto tiene DOS estados y no uno: mientras no está, se dibuja la silueta
//  con la inicial. Un hueco vacío parecería un fallo; la silueta dice
//  "todavía no", que es la verdad.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    property string especie: ""
    property real lado: 96

    implicitWidth: lado
    implicitHeight: lado

    readonly property var ficha: especie ? Digivice.datoDe(especie) : null
    readonly property string archivo: especie ? Digivice.rutaImagen(especie) : ""
    readonly property bool esSprite: especie ? Digivice.esSprite(especie) : false

    //  Se pide una vez por especie, no en cada repintado.
    onEspecieChanged: if (especie) Digivice.pedirImagen(especie)

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: K4.Tema.superficieAlta
        visible: retrato.status !== Image.Ready

        K4.Etiqueta {
            anchors.centerIn: parent
            text: self.ficha ? self.ficha.n.charAt(0) : "?"
            font.pixelSize: self.lado * 0.4
            font.weight: Font.Bold
            color: K4.Tema.tenue
        }
    }

    Image {
        id: retrato
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        //  Sin caché y recargando a mano: el fichero puede no existir cuando
        //  se pide y aparecer un segundo después. Colgarle un `?v=` a una ruta
        //  file:// no vale —QML se lo traga como parte del nombre— así que se
        //  vacía y se vuelve a poner, que es lo único que fuerza la relectura.
        cache: false
        //  Suavizar o no NO depende de si es sprite o ilustración: depende de
        //  si la imagen se está AGRANDANDO o REDUCIENDO.
        //
        //  Agrandando, interpolar es justo lo que estropea el pixel art: un
        //  sprite de 36 px estirado a 64 tiene que salir a cuadros. Pero
        //  reduciendo pasa lo contrario, y esa mitad faltaba: los sprites de
        //  los aparatos en color (`dark color`, `dv color`, `d3 color`) son
        //  arte de 64x64 subido a 3x —192x192— y meterlos a 48 sin filtrar
        //  hace que se salte tres de cada cuatro píxeles y el bicho aparezca
        //  desdentado.
        //
        //  El margen de 1.2 evita que un sprite casi del tamaño justo se
        //  suavice por dos píxeles de diferencia.
        smooth: retrato.sourceSize.width > self.lado * 1.2
        mipmap: false

        function recargar() {
            source = ""
            if (self.archivo)
                source = "file://" + self.archivo
        }

        Component.onCompleted: recargar()
    }

    onArchivoChanged: retrato.recargar()

    Connections {
        target: Digivice
        function onImagenesListasChanged() { retrato.recargar() }
    }
}
