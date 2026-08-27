//  Una ventana sobre el plano.
//
//  No es una foto: `K4.Miniatura` es una copia VIVA de ese toplevel, así que
//  lo que se ve dentro es lo que está pasando ahí ahora — un vídeo sigue
//  corriendo, un compilado sigue escupiendo líneas. Eso importa más de lo que
//  parece: media razón para abrir esto es mirar si algo ha terminado ya.
//
//  ── se dibuja PLANA ──────────────────────────────────────────────
//
//  Ni giros ni perspectiva: de doblar se encarga la lente, que actúa sobre
//  todo el plano ya pintado (ver `Lienzo.qml`). Lo que aquí se decide es otra
//  cosa —de dónde viene la luz— y resulta que con eso basta para que se
//  levanten del fondo.
//
//  ── la luz sale del centro de la pantalla ────────────────────────
//
//  Por eso la sombra de cada tarjeta se aleja del centro: la de la izquierda
//  la tira hacia la izquierda, la de abajo hacia abajo. Es un detalle que casi
//  nadie sabría nombrar y que el ojo comprueba sin darse cuenta — con todas
//  las sombras cayendo hacia el mismo lado, esto parece una lista; con las
//  sombras huyendo del centro, parece un sitio.
//
//  ── lo que no se mira, no se copia ───────────────────────────────
//
//  Cada miniatura viva es una copia por cuadro de una ventana entera. Con
//  quince abiertas y el plano alejado, la mitad son sellos de treinta píxeles
//  fuera del encuadre — y copiarlas cuesta lo mismo que copiar la que estás
//  mirando. Así que `live` se apaga en cuanto la tarjeta sale del encuadre o
//  se hace diminuta, y el último cuadro se queda pegado: quieto, pero ahí.

import QtQuick
import K4 as K4

Item {
    id: tarjeta

    required property var lienzo
    //  Del modelo, y declaradas `required` a propósito: en Qt 6 el `index`
    //  heredado del contexto sigue funcionando y avisa por el log en cada
    //  delegate. Pedirlas es lo que hace callar al aviso y de paso deja escrito
    //  qué necesita esta tarjeta para existir.
    required property var modelData
    required property int index

    readonly property var ventana: modelData
    readonly property int indice: index

    readonly property var g: lienzo.geo(indice)
    readonly property bool elegida: lienzo.plugin.seleccion === indice
    readonly property bool pasa: lienzo.casa(indice)

    x: g.x
    y: g.y
    width: Math.max(1, g.w)
    height: Math.max(1, g.h)

    //  Lo que no casa con lo escrito no desaparece: se apaga. Desaparecer
    //  reordenaría el plano bajo el ratón mientras se escribe, y entonces
    //  buscar cambiaría de sitio lo que buscas.
    opacity: g.op * (pasa ? 1 : 0.08)
    visible: opacity > 0.01

    //  La elegida se levanta un poco. Poco: un salto grande la separaría de la
    //  rejilla y costaría volver a encontrar dónde estaba.
    scale: elegida ? 1.025 : 1
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    //  Dónde cae respecto al centro de la pantalla, de -1 a 1. Es lo que
    //  orienta la luz.
    readonly property real nx: Math.max(-1, Math.min(1,
        (g.x + g.w / 2 - lienzo.width / 2) / Math.max(1, lienzo.width / 2)))
    readonly property real ny: Math.max(-1, Math.min(1,
        (g.y + g.h / 2 - lienzo.height / 2) / Math.max(1, lienzo.height / 2)))

    //  ¿Merece la pena copiarla? Dentro del encuadre con un margen, y de un
    //  tamaño en el que se distinga algo.
    readonly property bool aLaVista:
        g.x + g.w > -240 && g.x < lienzo.width + 240
        && g.y + g.h > -240 && g.y < lienzo.height + 240
        && g.w > 26

    //  Todas nacen vivas y las que no se miran se apagan DESPUÉS.
    //
    //  Al revés no funciona: `captureFrame()` en `Component.onCompleted`
    //  contesta «no hay contexto de grabación todavía» —la copia aún no está
    //  montada en ese instante— y la tarjeta se queda en negro hasta que entra
    //  en el encuadre. Medio segundo de todas vivas cuesta un pestañeo y deja a
    //  cada una con su cuadro pegado, que es lo que hace que alejarse no vacíe
    //  el plano.
    property bool asentado: false
    Timer {
        interval: 600
        running: true
        onTriggered: tarjeta.asentado = true
    }

    // ── la sombra ─────────────────────────────────────────────────
    //
    //  Cuatro rectángulos, cada uno un poco más grande, más lejos y más tenue.
    //  No es un desenfoque de verdad y no hace falta que lo sea: a este tamaño
    //  cuatro escalones ya no se cuentan, y un desenfoque real por tarjeta
    //  serían quince pasadas más de dibujado por cuadro.
    Repeater {
        model: 4
        Rectangle {
            required property int index
            readonly property real p: (index + 1) / 4
            //  Huyendo del centro, y hacia abajo siempre un poco: la luz está
            //  en el medio de la pantalla, pero también algo por encima.
            x: -index * 1.5 + tarjeta.nx * 13 * p
            y: -index * 1.5 + tarjeta.ny * 13 * p + 7 * p
            width: tarjeta.width + index * 3
            height: tarjeta.height + index * 3
            color: "#000000"
            opacity: 0.20 * (1 - p * 0.6) * tarjeta.g.t
            z: -2
        }
    }

    // ── el halo de la elegida ─────────────────────────────────────
    Repeater {
        model: 3
        Rectangle {
            required property int index
            visible: tarjeta.elegida
            x: -(index + 1) * 3
            y: -(index + 1) * 3
            width: tarjeta.width + (index + 1) * 6
            height: tarjeta.height + (index + 1) * 6
            color: "transparent"
            border.width: 2
            border.color: K4.Tema.azul
            opacity: 0.20 / (index + 1)
            z: -1
        }
    }

    // El suelo, para mientras no haya cuadro y para lo que no llene la celda.
    Rectangle {
        anchors.fill: parent
        color: "#0b0e14"
    }

    K4.Miniatura {
        anchors.fill: parent
        direccion: tarjeta.ventana.dir
        live: tarjeta.aLaVista || !tarjeta.asentado
        paintCursor: false
    }

    //  El brillo del cristal: una caída de luz desde arriba, muy floja. Es lo
    //  que impide que una miniatura oscura se lea como un agujero en el plano.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.055) }
            GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.012) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
        }
    }

    //  Un filo oscuro por dentro, para despegar la miniatura de lo que tenga
    //  detrás.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.55)
    }

    //  Y el marco por fuera, PERO no del mismo color en los cuatro lados.
    //
    //  Con la luz en el centro de la pantalla, el canto que mira al centro
    //  está iluminado y el de fuera está a la sombra. Cuatro rectángulos de un
    //  píxel en vez de un `border`, y a cambio las tarjetas dejan de ser
    //  recortes pegados sobre el fondo: se ve de dónde viene la luz, que es lo
    //  único que el ojo necesita para creerse que hay volumen.
    //
    //  Y sobre negro esto se ve donde una sombra no se vería: en un fondo casi
    //  a cero, oscurecer no dibuja nada y alumbrar sí.
    Repeater {
        model: 4
        Rectangle {
            required property int index
            //  0 izquierda · 1 derecha · 2 arriba · 3 abajo
            readonly property real cara: {
                if (index === 0) return Math.max(0, tarjeta.nx)
                if (index === 1) return Math.max(0, -tarjeta.nx)
                if (index === 2) return Math.max(0, tarjeta.ny)
                return Math.max(0, -tarjeta.ny)
            }
            x: index === 1 ? tarjeta.width - 1 : -1
            y: index === 3 ? tarjeta.height - 1 : -1
            width: index < 2 ? 2 : tarjeta.width + 2
            height: index < 2 ? tarjeta.height + 2 : 2
            color: tarjeta.elegida
                ? K4.Tema.azul
                : Qt.rgba(1, 1, 1, 0.10 + 0.30 * cara)
        }
    }

    //  El escritorio del que viene. Se perdió al soltarlas todas sobre el
    //  mismo plano, y sin él no se sabe si ir a una ventana va a cambiarte de
    //  escritorio o no.
    Rectangle {
        visible: tarjeta.g.w > 110 && tarjeta.g.t > 0.5
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 7
        width: etiquetaWs.width + 13
        height: 19
        radius: 9
        color: Qt.rgba(0, 0, 0, 0.66)

        K4.Etiqueta {
            id: etiquetaWs
            anchors.centerIn: parent
            text: tarjeta.ventana.wsNombre.length > 0
                ? tarjeta.ventana.wsNombre
                : String(tarjeta.ventana.ws)
            font.pixelSize: 10
            color: tarjeta.elegida ? K4.Tema.tinta : K4.Tema.apagado
        }
    }

    //  El icono de la aplicación, abajo a la izquierda y grande.
    //
    //  Es lo que salva la vista alejada: a un tercio de tamaño la miniatura ya
    //  no se lee y el título tampoco, pero el icono de un navegador se conoce
    //  a treinta píxeles. Cuando todo lo demás deja de informar, esto sigue.
    Rectangle {
        readonly property real lado: Math.max(22, Math.min(46, tarjeta.g.w * 0.075))
        visible: tarjeta.g.w > 90 && icono.source.toString().length > 0
        width: lado
        height: lado
        radius: lado / 2
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 8
        color: Qt.rgba(0, 0, 0, 0.55)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)

        K4.Icono {
            id: icono
            anchors.centerIn: parent
            width: parent.lado * 0.62
            height: width
            source: K4.Apps.icono(tarjeta.ventana.clase)
        }
    }

    //  El nombre. Antes salía sólo en tarjetas muy grandes porque el rótulo
    //  de abajo ya cantaba el título de la señalada; al quitarse aquel, esta
    //  banda pasó a ser la única forma de distinguir dos ventanas del mismo
    //  navegador, así que aparece bastante antes.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 27
        visible: tarjeta.g.w > 190 && tarjeta.g.t > 0.6
        color: Qt.rgba(0, 0, 0, tarjeta.elegida ? 0.74 : 0.5)

        K4.Etiqueta {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 8 + Math.max(22, Math.min(46, tarjeta.g.w * 0.075)) + 8
            anchors.rightMargin: 10
            text: tarjeta.ventana.titulo.length > 0
                ? tarjeta.ventana.titulo
                : tarjeta.ventana.clase
            font.pixelSize: 11
            color: tarjeta.elegida ? K4.Tema.tinta : K4.Tema.apagado
            elide: Text.ElideRight
        }
    }
}
