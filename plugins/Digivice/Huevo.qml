//  El huevo, incubando.
//
//  Es lo PRIMERO que ve alguien que abre este plugin, así que no puede ser un
//  icono quieto. Se mueve como se mueve un huevo que va a romper: se ladea a
//  un lado y a otro, y a medida que se acerca la eclosión se ladea más fuerte
//  y más seguido, hasta que se raja.
//
//  La hoja de sprites tiene seis poses —quieto, ladeado a cada lado, primera
//  grieta, grieta abierta y partido—, y cuál se ve sale del PROGRESO, no de un
//  temporizador suelto: mirar el huevo tiene que decirte cuánto le queda sin
//  leer ningún número.
//
//  Si la hoja no está, se dibuja el glifo del huevo. El plugin no puede
//  quedarse en blanco por un asset que falte.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    //  De 0 a 1.
    property real progreso: 0
    property int lado: 72

    //  Con tamaño propio. Sin esto el componente medía 0×0 y dentro de una
    //  columna no ocupaba nada: la barra y el texto salían y el huevo no,
    //  que es exactamente lo que pasó la primera vez.
    implicitWidth: lado
    implicitHeight: lado
    width: lado
    height: lado
    //  Lo pone la vista al romper: dispara la pose de partido y el fogonazo.
    property bool rompiendo: false

    readonly property bool hayHoja: sprite.status === Image.Ready

    //  Qué pose toca. Las tres primeras son el meneo —van por el reloj— y las
    //  tres últimas por el progreso, que es lo que hace que el huevo CUENTE
    //  cuánto le falta.
    property int _meneo: 0

    readonly property int pose: {
        if (rompiendo) return 5
        if (progreso >= 0.92) return 4
        if (progreso >= 0.65) return 3
        return _meneo            // 0 quieto · 1 izquierda · 2 derecha
    }

    //  Cuanto más cerca de romper, más nervioso. De casi dos segundos entre
    //  meneos al principio a menos de medio al final.
    Timer {
        interval: Math.max(320, 1800 - self.progreso * 1500)
        repeat: true
        running: !self.rompiendo
        onTriggered: self._meneo = self._meneo === 0
                   ? (Math.random() < 0.5 ? 1 : 2) : 0
    }

    //  ── la hoja de sprites ────────────────────────────────────────
    //  Seis celdas en dos filas de tres. Se recorta con un contenedor que
    //  mueve la imagen: es lo más barato que hay, sin shaders ni capas.
    Item {
        anchors.centerIn: parent
        width: self.lado
        height: self.lado
        clip: true
        visible: self.hayHoja

        //  El ladeo del arte es muy sutil, así que se ayuda inclinando el
        //  huevo ENTERO. Esto sí se puede animar: mueve el objeto, no la
        //  ventana por la que se mira la hoja.
        rotation: self.pose === 1 ? -7 : self.pose === 2 ? 7 : 0
        Behavior on rotation { NumberAnimation { duration: 120 } }

        Image {
            id: sprite
            source: Qt.resolvedUrl("assets/huevo.png")
            //  Tres columnas de ancho y dos filas de alto.
            width: self.lado * 3
            height: self.lado * 2
            x: -self.lado * (self.pose % 3)
            y: -self.lado * Math.floor(self.pose / 3)
            //  Vecino más próximo: es pixel art y suavizarlo lo convierte en
            //  papilla, que es justo lo que se evita en todo este plugin.
            smooth: false
            fillMode: Image.PreserveAspectFit
            //  SIN `Behavior`. Lo tuve puesto y hacía justo lo contrario de
            //  suavizar: como lo que se mueve es el desplazamiento de la
            //  hoja, la animación arrastraba la imagen de lado y se veía el
            //  huevo cruzar la pantalla pasando por los fotogramas vecinos.
            //  Un fotograma salta; no se interpola. Es lo mismo que ya hacen
            //  el paseo y el respiro del bicho.
        }
    }

    //  El respaldo, por si el asset no está.
    K4.Glifo {
        anchors.centerIn: parent
        visible: !self.hayHoja
        text: "\u{F0AAF}"
        font.pixelSize: self.lado * 0.7
        color: "#e8dcc8"
        rotation: self.pose === 1 ? -10 : self.pose === 2 ? 10 : 0
        Behavior on rotation { NumberAnimation { duration: 110 } }
    }

    //  El fogonazo de la eclosión. Solo al romper, y corto: es un aparato de
    //  LCD, no unos fuegos artificiales.
    Rectangle {
        id: fogonazo
        anchors.centerIn: parent
        width: self.lado * 2
        height: width
        radius: width / 2
        color: "#e8f4ea"
        opacity: 0
        scale: 0.3

        ParallelAnimation {
            running: self.rompiendo
            NumberAnimation { target: fogonazo; property: "opacity"
                              from: 0.8; to: 0; duration: 700 }
            NumberAnimation { target: fogonazo; property: "scale"
                              from: 0.3; to: 1.6; duration: 700
                              easing.type: Easing.OutQuad }
        }
    }
}
