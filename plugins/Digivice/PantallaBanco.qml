//  La guardería: los que has criado y no llevas encima.
//
//  Es la estantería, y es lo que le faltaba al juego. Antes evolucionar
//  borraba al anterior y criar no dejaba poso: llegabas a Perfect y lo único
//  que quedaba era un número. Con esto, cada bicho que has sacado adelante
//  sigue estando.
//
//  ── por qué esto ya no es una ficha suelta ───────────────────────
//  Enseñaba UNO cada vez, en el centro, quieto. Y ahí está el fallo: el
//  premio de la guardería es tener VARIOS. Con uno en pantalla, doce criados
//  se ven exactamente igual que uno, y la colección —que es lo que hace que
//  criar deje poso— no aparece por ningún lado.
//
//  Ahora es una sala:
//
//  - **están todos**, moviéndose por el fondo, cada uno a su ritmo;
//  - el señalado **da un paso al frente**, se ilumina y es el único con
//    nombre y ficha, así que se sabe de quién se habla sin perder a los otros;
//  - al sacarlo, **cruza la sala** hacia delante y el que llevabas **entra
//    por el lado a ocupar su hueco**, que es literalmente lo que hace el
//    cambio: nadie se pierde, se relevan.
//
//  Uno cada vez se pasan con A. B se lo cambia al que lleva.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    //  Lo mueve la vista con el botón A.
    property int cursor: 0

    readonly property int total: Digivice.banco.length
    readonly property int indice: total > 0
                                ? ((cursor % total) + total) % total : 0
    readonly property var entrada: total > 0 ? Digivice.banco[indice] : null
    readonly property var ficha: entrada ? Digivice.datoDe(entrada.especie) : null

    //  Los guardados viejos traen `fuerza`; los nuevos, `entrenos`.
    function entrenoDe(c) {
        if (!c) return 0
        if (c.entrenos)
            return (c.entrenos.pv || 0) + (c.entrenos.atq || 0)
                 + (c.entrenos.def || 0) + (c.entrenos.vel || 0)
        return c.fuerza || 0
    }

    function cambiar() {
        if (self.total > 0) {
            _saliendo = self.indice
            releva.restart()
            Digivice.cambiarA(self.indice)
        }
    }

    //  Quién está saliendo, para animar el relevo.
    property int _saliendo: -1
    property real _relevo: 0

    SequentialAnimation {
        id: releva
        ScriptAction { script: self._relevo = 0 }
        NumberAnimation { target: self; property: "_relevo"; to: 1
                          duration: 420; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 120 }
        ScriptAction { script: { self._relevo = 0; self._saliendo = -1 } }
    }

    // ── la sala ───────────────────────────────────────────────────
    //  Interior y no campo: aquí no se explora, se guarda. Suelo marcado con
    //  una línea para que los bichos se apoyen en algo.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0d1a16" }
            GradientStop { position: 1.0; color: "#132420" }
        }
    }

    Rectangle {
        id: suelo
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 42
        height: 1
        color: "#2a4a3e"
        opacity: 0.7
        visible: self.total > 0
    }

    // ── la cabecera ───────────────────────────────────────────────
    Row {
        id: cabecera
        anchors.top: parent.top
        anchors.topMargin: 3
        anchors.left: parent.left
        anchors.leftMargin: 5
        spacing: 6
        visible: self.total > 0

        K4.Glifo {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F0827}"
            font.pixelSize: 13
            color: "#7de08a"
        }

        K4.Etiqueta {
            anchors.verticalCenter: parent.verticalCenter
            text: Idioma.f(Idioma.t("Guardería  ·  %1 dentro"), self.total)
            font.pixelSize: 12
            font.weight: Font.Bold
            color: "#d8f0de"
        }
    }

    // ── los del fondo ─────────────────────────────────────────────
    //  Todos menos el señalado, en una fila AL FONDO de la sala. Repartidos
    //  por hueco y no por azar: colocados con un pseudoaleatorio se apelotonan
    //  —salieron los seis amontonados a la derecha, unos encima de otros— y
    //  además dejan calvas. Un reparto por índice llena la sala siempre.
    //
    //  El bote va sobre un desplazamiento aparte y NO sobre `y`: animar `y`
    //  rompe su enlace con el suelo para siempre. Es la misma trampa que ya
    //  está anotada en `Criatura.qml` y que allí costó dejar al bicho tieso.
    Repeater {
        model: Digivice.banco

        Item {
            id: vecino
            required property var modelData
            required property int index
            readonly property bool esElegido: vecino.index === self.indice
            //  Un pseudoaleatorio estable, solo para el desfase del bote.
            readonly property real r: {
                const x = Math.sin((vecino.index + 1) * 78.233) * 43758.5453
                return x - Math.floor(x)
            }
            property real bote: 0

            visible: !esElegido && vecino.index !== self._saliendo
            width: 46
            height: 40
            x: {
                const n = Math.max(1, self.total)
                const paso = (self.width - 46) / Math.max(1, n - 1)
                return n === 1 ? (self.width - 46) / 2 : vecino.index * paso
            }
            //  Al fondo: por encima de la línea del suelo, para que el
            //  señalado quede claramente DELANTE y no mezclado con ellos.
            y: suelo.y - height - 26 + (vecino.index % 2) * 9 - vecino.bote
            opacity: 0.4
            z: 1

            Retrato {
                anchors.fill: parent
                especie: vecino.modelData.especie
                lado: 32
            }

            //  Respiran a destiempo: si todos botaran a la vez se vería el
            //  bucle y la sala parecería un salvapantallas.
            SequentialAnimation {
                running: vecino.visible
                loops: Animation.Infinite
                PauseAnimation { duration: Math.round(vecino.r * 900) }
                NumberAnimation { target: vecino; property: "bote"; to: 3
                                  duration: 620; easing.type: Easing.InOutQuad }
                NumberAnimation { target: vecino; property: "bote"; to: 0
                                  duration: 620; easing.type: Easing.InOutQuad }
            }
        }
    }

    // ── el señalado, un paso al frente ────────────────────────────
    Item {
        id: destacado
        visible: self.entrada !== null
        width: 78
        height: 62
        x: self.width / 2 - width / 2 + self._relevo * (self.width * 0.42)
        //  Con los pies EN la línea del suelo. Estaba seis píxeles por
        //  debajo y su nombre, que va pegado abajo, le cruzaba las patas.
        y: suelo.y - height + 2
        z: 3
        opacity: 1 - self._relevo * 0.7

        //  Un halo bajo los pies: es lo que dice «este» sin escribirlo.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -3
            width: 52
            height: 7
            radius: 4
            color: "#7de08a"
            opacity: 0.22
        }

        Criatura {
            anchors.fill: parent
            especie: self.entrada ? self.entrada.especie : ""
            lado: 52
            quieto: true
            mirandoDerecha: true
        }
    }

    //  El que llevabas, entrando por el lado a ocupar el hueco. Solo durante
    //  el relevo: el resto del tiempo está contigo, no aquí.
    Item {
        visible: self._relevo > 0 && Digivice.especie !== ""
        width: 78
        height: 62
        x: self.width / 2 - width / 2 - (1 - self._relevo) * (self.width * 0.55)
        y: suelo.y - height + 2
        z: 2
        opacity: self._relevo

        Retrato {
            anchors.fill: parent
            especie: Digivice.especie
            lado: 52
        }
    }

    // ── la ficha del señalado ─────────────────────────────────────
    Column {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        anchors.left: parent.left
        anchors.leftMargin: 5
        anchors.right: parent.right
        anchors.rightMargin: 5
        spacing: 0
        visible: self.ficha !== null

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: self.ficha ? self.ficha.n : ""
            font.pixelSize: 14
            font.weight: Font.Bold
            color: "#e8f4ea"
            elide: Text.ElideRight
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            //  Lo que de verdad interesa de uno que está en la banca: en qué
            //  escalón se quedó y cuánto esfuerzo lleva encima.
            text: !self.ficha || !self.entrada ? ""
                : self.ficha.l + "  ·  " + Idioma.t("ENT") + " "
                  + self.entrenoDe(self.entrada)
            font.pixelSize: 11
            color: "#9fd8ae"
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: (self.indice + 1) + " / " + self.total
                + "   ·   " + Idioma.t("B lo saca")
            font.pixelSize: 10
            color: "#6f9c7c"
        }
    }

    // ── vacía ─────────────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 6
        visible: self.ficha === null

        K4.Glifo {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "\u{F0827}"
            font.pixelSize: 30
            color: "#2f5a3c"
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: Idioma.t("La guardería está vacía.\nAl evolucionar o abrir otro huevo, el anterior se queda aquí.")
            font.pixelSize: 12
            color: "#8fbf9c"
        }
    }
}
