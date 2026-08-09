//  El mercado: dónde acaban los bits.
//
//  Una moneda sin nada que comprar es un contador. La comida entra aquí
//  aunque también se cace porque es lo que le da sentido a los bits el primer
//  día: un jugador nuevo tiene que poder gastar antes de tener guardería,
//  jefes ni objetivos cumplidos.
//
//  Y el Anticuerpo X vale 400 a propósito. Es la única compra que hay que
//  proponerse, y por eso es la que convierte «ir ganando bits» en una meta en
//  vez de en un goteo.
//
//  ── por qué esto ya no es una lista ──────────────────────────────
//  Era seis renglones y un total. Comprar movía dos números y no pasaba nada
//  más: ni sabías si había funcionado, salvo mirando el contador antes y
//  después. Un mercado es un SITIO al que vas, y ahora se parece a uno:
//
//  - hay **mostrador**, y sobre él el artículo señalado, grande y meciéndose;
//  - **tu bicho ha venido contigo** —no un tendero inventado: el que compra
//    es él, y lo que compras es para él—, y reacciona: da un salto con lo que
//    acabas de comprar encima de la cabeza, o agacha las orejas si no llega;
//  - al comprar, el artículo **cae del mostrador a sus manos** y el contador
//    de bits **se sacude** con lo que acabas de pagar;
//  - y lo que no te puedes permitir tiembla en rojo ANTES de que insistas.
//
//  A recorre, B compra.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    property int cursor: 0

    readonly property var lista: Digivice.alaVenta
    readonly property int total: lista.length
    readonly property int indice: total > 0
                                ? ((cursor % total) + total) % total : 0
    readonly property var elegido: total > 0 ? lista[indice] : null
    readonly property bool alcanza: elegido && Digivice.bits >= elegido.precio

    function elegir() {
        if (self.elegido)
            Digivice.comprar(self.elegido.id)
    }

    //  ── lo que pasa al comprar ────────────────────────────────────
    property string _cayendo: ""      // glifo del artículo que baja
    property int _pagado: 0

    Connections {
        target: Digivice

        function onComprado(id, nombre, precio) {
            const f = Digivice.alaVenta
            for (let i = 0; i < f.length; ++i)
                if (f[i].id === id) { self._cayendo = f[i].glifo; break }
            self._pagado = precio
            cae.restart()
            sacude.restart()
            seVa.restart()
            bicho.reaccionar(self._cayendo)
        }

        //  Un intento que no cuela también tiene que verse. El aviso de texto
        //  ya salía arriba, pero el sitio donde miras es el precio.
        function onAviso(texto) { tiembla.restart() }
    }

    property real _caidaY: 0
    property real _caidaOp: 0

    SequentialAnimation {
        id: cae
        ScriptAction { script: { self._caidaY = 0; self._caidaOp = 1 } }
        ParallelAnimation {
            //  Hasta la línea del mostrador y ni un píxel más: con 54 se
            //  colaba por debajo y acababa encima del texto del pie.
            NumberAnimation { target: self; property: "_caidaY"; to: 30
                              duration: 380; easing.type: Easing.OutQuad }
            SequentialAnimation {
                PauseAnimation { duration: 220 }
                NumberAnimation { target: self; property: "_caidaOp"
                                  to: 0; duration: 160 }
            }
        }
    }

    SequentialAnimation {
        id: sacude
        NumberAnimation { target: monedero; property: "scale"; to: 1.35
                          duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: monedero; property: "scale"; to: 1.0
                          duration: 220; easing.type: Easing.OutBounce }
    }

    SequentialAnimation {
        id: tiembla
        loops: 3
        NumberAnimation { target: precioGrande; property: "x"
                          to: precioGrande.x + 3; duration: 45 }
        NumberAnimation { target: precioGrande; property: "x"
                          to: precioGrande.x - 3; duration: 45 }
        NumberAnimation { target: precioGrande; property: "x"
                          to: precioGrande.x; duration: 45 }
    }

    // ── el sitio ──────────────────────────────────────────────────
    //  Tono cálido y no el verde de campo: dentro de un local la luz es otra.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#12180f" }
            GradientStop { position: 1.0; color: "#1c1a10" }
        }
    }

    // ── la cabecera y el monedero ─────────────────────────────────
    Row {
        id: cabecera
        anchors.top: parent.top
        anchors.topMargin: 3
        anchors.left: parent.left
        anchors.leftMargin: 5
        spacing: 8

        K4.Etiqueta {
            anchors.verticalCenter: parent.verticalCenter
            text: Idioma.t("Mercado")
            font.pixelSize: 12
            font.weight: Font.Bold
            color: "#e8dcc8"
        }

        Bits {
            id: monedero
            anchors.verticalCenter: parent.verticalCenter
            valor: Digivice.bits
            tam: 12
        }

        //  Lo que acabas de pagar, apagándose junto al monedero. Es la única
        //  manera de ver un gasto: el total nuevo no cuenta cuánto ha bajado,
        //  solo dónde ha quedado.
        //
        //  Se dispara desde `onComprado` y NO con `running:` atado al estado
        //  de la caída: una animación que arranca y para por binding se queda
        //  congelada donde la pillen, y el «−10» se quedaba puesto para
        //  siempre en la cabecera.
        K4.Etiqueta {
            id: gasto
            anchors.verticalCenter: parent.verticalCenter
            text: "−" + self._pagado
            font.pixelSize: 11
            font.weight: Font.Bold
            color: "#e0806b"
            opacity: 0

            NumberAnimation {
                id: seVa
                target: gasto; property: "opacity"
                from: 1; to: 0; duration: 900
            }
        }
    }

    // ── el escaparate: seis huecos ────────────────────────────────
    //  En fila y no en renglones: seis artículos con icono se leen de un
    //  vistazo, y así queda sitio para el mostrador y para el bicho, que es
    //  lo que hace que esto sea una tienda.
    Row {
        id: estante
        anchors.top: cabecera.bottom
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 3

        Repeater {
            model: self.lista

            Rectangle {
                id: hueco
                required property var modelData
                required property int index
                readonly property bool activo: hueco.index === self.indice
                readonly property bool puedo: Digivice.bits >= hueco.modelData.precio

                width: 36
                height: 34
                radius: 4
                color: hueco.activo ? "#2a2416" : "#141a12"
                border.width: 1
                border.color: hueco.activo ? "#e8b45a" : "#26301f"

                K4.Glifo {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -4
                    text: hueco.modelData.glifo
                    font.pixelSize: 16
                    color: hueco.puedo ? "#e8dcc8" : "#4a5040"
                }

                //  Cuántos llevas ya, en la esquina: sin esto se compra a
                //  ciegas y se acaba con seis cintas de correr.
                K4.Etiqueta {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: hueco.modelData.tengo > 0
                        ? "×" + hueco.modelData.tengo : "—"
                    font.pixelSize: 9
                    color: hueco.modelData.tengo > 0 ? "#9fd8ae" : "#4a5040"

                    //  El recuento pega un bote al subir: es la prueba de que
                    //  la compra ha entrado en la despensa.
                    onTextChanged: if (hueco.modelData.tengo > 0) bote.restart()
                    SequentialAnimation {
                        id: bote
                        NumberAnimation { target: parent; property: "scale"
                                          to: 1.7; duration: 110 }
                        NumberAnimation { target: parent; property: "scale"
                                          to: 1.0; duration: 240
                                          easing.type: Easing.OutBounce }
                    }
                }
            }
        }
    }

    // ── el mostrador ──────────────────────────────────────────────
    //  La línea del mostrador va a media pantalla y no pegada abajo: entre el
    //  estante y ella es donde vive la escena —el artículo grande y el
    //  bicho—, y sin ese hueco quedaban noventa píxeles de nada en el centro.
    Rectangle {
        id: mostrador
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 44
        height: 5
        color: "#3a3320"
    }

    //  El artículo señalado, grande sobre el mostrador y meciéndose. Es el
    //  que tienes «en la mano» antes de decidir.
    Item {
        id: escaparate
        width: 60
        height: 62
        x: parent.width * 0.22 - width / 2
        anchors.bottom: mostrador.top

        K4.Glifo {
            id: piezaGrande
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - 2
            text: self.elegido ? self.elegido.glifo : ""
            font.pixelSize: 38
            color: self.alcanza ? "#e8dcc8" : "#5a6050"

            SequentialAnimation on y {
                running: true
                loops: Animation.Infinite
                NumberAnimation { to: piezaGrande.y - 4; duration: 900
                                  easing.type: Easing.InOutQuad }
                NumberAnimation { to: piezaGrande.y; duration: 900
                                  easing.type: Easing.InOutQuad }
            }
        }

        //  La copia que CAE al comprar. Dentro del escaparate y no suelta en
        //  la pantalla: colgada de `escaparate.x/y` desde fuera salía por
        //  donde no era, porque esas coordenadas se resuelven por anclas y no
        //  están puestas todavía cuando se evalúa el binding.
        K4.Glifo {
            visible: self._caidaOp > 0
            text: self._cayendo
            font.pixelSize: 24
            color: "#e8b45a"
            z: 5
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 30 + self._caidaY
            opacity: self._caidaOp
        }
    }

    //  ── tu bicho, que ha venido a comprar ─────────────────────────
    //  No hay tendero inventado: el que compra es él, y lo que compras es
    //  para él. De pie AL OTRO LADO del mostrador y apoyado en su línea.
    Criatura {
        id: bicho
        width: 84
        height: 60
        x: parent.width * 0.68 - width / 2
        anchors.bottom: mostrador.top
        anchors.bottomMargin: -6
        especie: Digivice.especie
        durmiendo: Digivice.durmiendo
        enfermo: Digivice.enfermo
        lado: 50
        quieto: true
        mirandoDerecha: false
        //  Mirando al mostrador, y decaído si no llega el dinero: el bicho
        //  es el termómetro más barato que hay de si esto se puede o no.
        opacity: self.alcanza ? 1 : 0.55
        Behavior on opacity { NumberAnimation { duration: 220 } }
    }

    // ── el pie: nombre, nota y precio ─────────────────────────────
    Column {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        anchors.left: parent.left
        anchors.leftMargin: 5
        anchors.right: parent.right
        anchors.rightMargin: 5
        spacing: 0

        K4.Etiqueta {
            width: parent.width
            text: self.elegido ? Idioma.t(self.elegido.nombre) : ""
            font.pixelSize: 12
            font.weight: Font.Bold
            color: "#e8dcc8"
            elide: Text.ElideRight
        }

        K4.Etiqueta {
            width: parent.width
            text: self.elegido ? Idioma.t(self.elegido.nota) : ""
            font.pixelSize: 10
            color: "#9a9a80"
            elide: Text.ElideRight
        }

        Row {
            spacing: 6

            Bits {
                id: precioGrande
                anchors.verticalCenter: parent.verticalCenter
                valor: self.elegido ? self.elegido.precio : 0
                apagado: !self.alcanza
                tam: 12
            }

            K4.Etiqueta {
                anchors.verticalCenter: parent.verticalCenter
                text: self.alcanza
                    ? Idioma.t("B lo compra")
                    : Idioma.f(Idioma.t("te faltan %1"),
                               self.elegido ? self.elegido.precio - Digivice.bits : 0)
                font.pixelSize: 10
                color: self.alcanza ? "#9fd8ae" : "#c98a6b"
            }
        }
    }
}
