//  El icono de un plugin, sea lo que sea: su imagen si trae una, y si no su
//  códice de la Nerd Font.
//
//  Existe porque el mismo icono se pinta en tres sitios —la fila de Ajustes,
//  la rejilla del centro de aplicaciones y la franja del centro de control— y
//  el «si tiene imagen, Image; si no, texto» ya se estaba copiando. Copiado
//  tres veces, el cuarto sitio se olvida de una de las dos ramas.

import QtQuick

Item {
    id: control

    //  Ruta file:// a la imagen, o "" si no hay.
    property string imagen: ""
    //  El códice, que se usa cuando no hay imagen.
    property int glifo: 0
    property int tamano: 20
    property color color: Tema.tinta

    implicitWidth: tamano
    implicitHeight: tamano

    Image {
        id: pintura
        anchors.fill: parent
        source: control.imagen
        visible: control.imagen.length > 0 && status === Image.Ready
        //  A la resolución de la pantalla y no a la del fichero: sin esto un
        //  PNG de 512 se escala en el momento de pintar y se ve pastoso.
        sourceSize.width: control.tamano * 2
        sourceSize.height: control.tamano * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }

    Glifo {
        anchors.centerIn: parent
        //  También si la imagen falló al cargar: mejor el icono genérico que
        //  un hueco, que un hueco parece que el plugin está roto.
        visible: !pintura.visible
        text: control.glifo > 0 ? String.fromCodePoint(control.glifo) : ""
        color: control.color
        font.pixelSize: control.tamano
    }
}
