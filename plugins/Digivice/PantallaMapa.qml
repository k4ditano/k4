//  La expedición: la carretera de la zona, andada de verdad.
//
//  Esto era un sitio quieto, y encima por un fallo tonto: el paisaje se movía
//  desde un `Connections` a `onPasosChanged` de un `pasos` que dejó de
//  existir cuando la exploración pasó a ser un cuentakilómetros por zona. El
//  handler no casaba con ninguna señal, así que `avance` valía 0 desde que se
//  abría el aparato hasta que se cerraba. El fondo NUNCA se movió.
//
//  Arreglarlo era una línea, pero una línea no hace una expedición. Lo que
//  hay ahora es un tramo de mundo en coordenadas de carretera: `unidad` dice
//  cuántos píxeles mide UNA unidad de distancia, y todo —los matojos, el
//  hito que viene, el jefe del final— se coloca en `x` a partir de dónde
//  estás. Andar no es «que se desplace un fondo»: es que el mundo entero
//  pase por delante a la velocidad que le toca a cada capa.
//
//  La regla de la Mazmorra sigue en pie: **nada de deriva en reposo**. El
//  mundo se mueve cuando la carretera avanza —o sea cuando has estado usando
//  el ordenador— y ni un píxel más. Lo que sí es continuo es el bicho: en
//  reposo respira, andando trota. Un muñeco quieto sobre un suelo quieto es
//  una foto; un muñeco vivo sobre un suelo quieto es alguien esperando.
//
//  Y el encuentro pasa a ser un CARA A CARA: el enemigo entra por la derecha
//  y se planta en la carretera. Antes tapaba la escena con un retrato en el
//  centro, que es justo la parte que no parecía un sitio.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    signal pelear(string enemigo)

    readonly property int indiceZona: Digivice.indiceZona
    readonly property var zonaActual: Digivice.zonas[indiceZona]

    // ── el mundo ──────────────────────────────────────────────────
    //  Dónde está el bicho en la carretera, en unidades. Persigue a
    //  `Digivice.distanciaZona` con una animación: el salto de golpe se lee
    //  como un corte de plano y no como un paso.
    property real mostrada: 0

    //  Cuántos píxeles mide una unidad de camino. Con 24 unidades de ancho
    //  visible, un cambio de ventana —zancada 1— mueve el mundo unos diez
    //  píxeles: se ve. Y como los hitos caen cada 30 de media, el que viene
    //  asoma por la derecha con tiempo de verlo llegar.
    readonly property real unidad: width / 24
    //  El bicho no va en el centro: va en el primer tercio, para que quede
    //  mundo POR DELANTE. Un protagonista centrado tiene tanto detrás como
    //  delante y eso no se lee como ir a algún sitio.
    readonly property real xBicho: width * 0.30
    //  La línea del suelo. Va alta a propósito: por debajo tienen que caber
    //  la barra de la zona, el botón y los puntos sin pisar la carretera.
    readonly property real suelo: height - 76

    function xEn(en) { return xBicho + (en - mostrada) * unidad }

    //  La tinta del LCD. Los matojos y las piedras van OSCUROS y no claros:
    //  en un cristal de puntos lo que se dibuja son píxeles apagados sobre el
    //  verde, igual que el sprite del bicho. Pintados en verde claro —que fue
    //  el primer intento— no parecían plantas, parecían niebla.
    readonly property color tono: "#0d1f14"
    readonly property color tinta: Qt.darker(tono, 2.1)
    readonly property color tintaFloja: Qt.darker(tono, 1.55)

    //  Saltar sin andar: al abrir la pantalla y al cambiar de zona. Andar
    //  490 unidades en una animación sería un viaje en el tiempo.
    function _saltar() {
        transito.enabled = false
        mostrada = Digivice.distanciaZona
        transito.enabled = true
    }

    Behavior on mostrada {
        id: transito
        enabled: false
        NumberAnimation { id: tranco; duration: 900; easing.type: Easing.InOutQuad }
    }

    readonly property bool andando: tranco.running

    Component.onCompleted: _saltar()

    Connections {
        target: Digivice
        //  `distancias` es la property que de verdad cambia al dar un paso.
        function onDistanciasChanged() {
            const d = Digivice.distanciaZona
            const salto = Math.abs(d - self.mostrada)
            //  Un salto enorme no es un paso: es una zona nueva o un camino
            //  rehecho. Eso se corta, no se anda.
            if (salto > 40) { self._saltar(); return }
            if (salto < 0.01) return
            //  La duración con la zancada: abrir una aplicación son cinco
            //  unidades y tiene que costar más que cambiar de ventana.
            tranco.duration = Math.min(1700, 340 + salto * 220)
            self.mostrada = d
        }
        function onZonaChanged() { self._saltar() }
        function onCaminoRehecho(zonaId, vuelta) { self._saltar() }
    }

    //  El pseudoaleatorio de los adornos: estable por posición, para que un
    //  matojo no cambie de forma cada vez que se repinta la escena.
    function _r(n) {
        const x = Math.sin(n * 12.9898 + self.indiceZona * 78.233) * 43758.5453
        return x - Math.floor(x)
    }

    // ── el fondo lejano ───────────────────────────────────────────
    Paisaje {
        id: paisaje
        anchors.fill: parent
        tono: "#0d1f14"
        semilla: self.indiceZona
        //  En píxeles: Paisaje se queda con su parte (0,55) para que quede
        //  detrás de todo lo demás.
        avance: self.mostrada * self.unidad
        //  Un pelín más presente que antes: con el velo que lleva dentro, a
        //  0,8 el cielo de la zona se quedaba en un fantasma y no se
        //  distinguía una isla flotante de una mancha.
        opacity: 0.92
    }

    // ── la carretera ──────────────────────────────────────────────
    Item {
        id: mundo
        anchors.fill: parent
        clip: true

        //  Los matojos de LEJOS: más pequeños, más apagados y a la mitad de
        //  velocidad. Es la capa que da profundidad; sin ella el suelo se
        //  desliza solo y parece una cinta de correr.
        Repeater {
            model: 8

            Rectangle {
                id: lejano
                required property int index
                //  Uno cada 9 unidades, con desvío: en fila de a uno se ve
                //  el truco. La ventana empieza 15 unidades por detrás
                //  porque a media velocidad entra en pantalla el doble de
                //  carretera que en la capa de cerca.
                readonly property int n: Math.floor((self.mostrada - 15) / 9) + lejano.index
                readonly property real en: lejano.n * 9 + self._r(lejano.n * 3.7) * 7

                //  Media velocidad: es la distancia AL BICHO la que se
                //  encoge, no la posición, o al abrir saldría descolocado.
                x: self.xBicho + (lejano.en - self.mostrada) * self.unidad * 0.5
                y: self.suelo - height - 4 - self._r(lejano.n * 5.1) * 7
                width: 5 + self._r(lejano.n * 8.3) * 8
                height: 3 + self._r(lejano.n * 2.9) * 5
                radius: 2
                color: self.tintaFloja
                opacity: 0.4
            }
        }

        //  La raya del suelo: es lo que separa el sitio del cielo.
        Rectangle {
            y: self.suelo
            width: parent.width
            height: 2
            color: self.tinta
            opacity: 0.7
        }

        //  Una franja de tierra, no todo lo que queda hasta abajo: por debajo
        //  va el pie del aparato y un fondo oscuro ahí lo ensuciaría.
        Rectangle {
            y: self.suelo + 2
            width: parent.width
            height: 12
            color: self.tinta
            opacity: 0.5
        }

        //  Las marcas del camino, a velocidad entera. Son las que hacen
        //  VISIBLE el movimiento: el paisaje de fondo es demasiado uniforme
        //  para que se note que se mueve.
        Row {
            y: self.suelo + 5
            spacing: 12
            //  Los paréntesis de fuera NO sobran: el menos unario aprieta más
            //  que el módulo, y sin ellos el resto se calcula sobre el número
            //  ya negado y las marcas dan un salto al cruzar el cero.
            x: -((((self.mostrada * self.unidad) % 22) + 22) % 22)

            Repeater {
                model: Math.ceil(mundo.width / 22) + 3

                Rectangle {
                    width: 10; height: 2; radius: 1
                    //  Estas SÍ van claras: son roderas sobre la tierra, y la
                    //  tierra ya es la parte oscura de la escena.
                    color: Qt.lighter(self.tono, 2.0)
                    opacity: 0.45
                }
            }
        }

        //  Los matojos de CERCA, plantados en el suelo.
        Repeater {
            model: 8

            Item {
                id: cerca
                required property int index
                //  Ocho unidades por detrás: si la ventana empieza justo
                //  donde estás, el borde izquierdo de la pantalla se queda
                //  pelado y se ve el corte.
                readonly property int n: Math.floor((self.mostrada - 8) / 4) + cerca.index
                readonly property real en: cerca.n * 4 + self._r(cerca.n * 1.3) * 3.4
                readonly property int tipo: Math.floor(self._r(cerca.n * 7.7) * 3)
                readonly property real talla: 0.7 + self._r(cerca.n * 4.4) * 0.6

                x: self.xEn(cerca.en) - width / 2
                y: self.suelo - height + 2
                width: 16 * cerca.talla
                height: 12 * cerca.talla
                opacity: 0.7

                //  Una piedra.
                Rectangle {
                    visible: cerca.tipo === 0
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.7
                    height: parent.height * 0.45
                    radius: height / 2
                    color: self.tinta
                }

                //  Una mata.
                Item {
                    visible: cerca.tipo === 1
                    anchors.fill: parent

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.8
                        height: parent.height * 0.6
                        radius: width / 2
                        color: self.tinta
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: parent.height * 0.35
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: -parent.width * 0.15
                        width: parent.width * 0.5
                        height: parent.height * 0.5
                        radius: width / 2
                        color: self.tinta
                    }
                }

                //  Tres hierbajos.
                Row {
                    visible: cerca.tipo === 2
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 2

                    Repeater {
                        model: 3

                        Rectangle {
                            required property int index
                            width: 1
                            height: cerca.height * (0.5 + (index === 1 ? 0.4 : 0))
                            color: self.tinta
                        }
                    }
                }
            }
        }

        //  EL HITO QUE VIENE. Se ve el poste, no lo que hay detrás: si el
        //  icono delatara si es un bicho o comida, cruzarlo dejaría de tener
        //  gracia. Es el mismo criterio que las huellas de la cacería.
        Item {
            id: poste
            readonly property var hito: Digivice.siguienteHito
            visible: hito !== null && !hito.jefe
            x: hito ? self.xEn(hito.en) : 0
            y: self.suelo - 26
            width: 12; height: 26

            Rectangle {
                x: 5
                width: 2; height: parent.height
                color: "#8fbf9c"
                opacity: 0.7
            }

            Rectangle {
                width: 11; height: 11; radius: 2
                color: "#12200f"
                border.width: 1
                border.color: "#8fbf9c"

                K4.Etiqueta {
                    anchors.centerIn: parent
                    text: "?"
                    font.pixelSize: 9
                    color: "#8fbf9c"
                }
            }
        }

        //  Y el jefe, al final del camino y en su sitio de verdad. Estuvo
        //  clavado en el borde derecho para que se viera siempre, y no: a 490
        //  de distancia una torre pegada al canto de la pantalla no es un
        //  horizonte, es una caja pálida que parece un fallo de dibujo. Lo
        //  que hay que ver desde lejos ya lo dice la barra de abajo; la torre
        //  aparece cuando de verdad la tienes cerca, y entonces significa
        //  algo.
        Item {
            id: torre
            readonly property real falta: Digivice.distanciaJefeZona - self.mostrada
            visible: falta < 30
            x: self.xEn(Digivice.distanciaJefeZona)
            y: self.suelo - 34
            width: 20; height: 34
            //  Cuanto más cerca, más nítida.
            opacity: Math.max(0.35, Math.min(0.95, (30 - falta) / 22))

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: 14; height: 28
                color: self.tinta
                border.width: 1
                border.color: Digivice.jefeVencido(Digivice.zona) ? "#e8b45a" : "#3f7a52"
            }

            K4.Glifo {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                text: String.fromCodePoint(0xF01A5)
                font.pixelSize: 12
                color: Digivice.jefeVencido(Digivice.zona) ? "#e8b45a" : "#5f8f6c"
            }
        }

        // ── el bicho, andando ─────────────────────────────────────
        Item {
            id: caminante
            x: self.xBicho - width / 2
            //  La caja mide lo que el sprite y no un palmo más: `Criatura`
            //  centra el retrato dentro de su alto, así que con la caja más
            //  alta que el bicho el muñeco quedaba flotando sobre la raya del
            //  suelo. Y un poco por debajo, que los sprites traen su propio
            //  margen transparente.
            y: self.suelo - height + 5
            width: 60; height: 52

            //  El trote: dos botes cortos por segundo mientras el mundo pasa.
            //  Va sobre un desplazamiento aparte y no sobre `y`, que es un
            //  enlace: animarlo directamente lo rompería para siempre.
            transform: Translate { id: bote }

            SequentialAnimation {
                running: self.andando
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { target: bote; property: "y"; to: -4
                                  duration: 150; easing.type: Easing.OutQuad }
                NumberAnimation { target: bote; property: "y"; to: 0
                                  duration: 150; easing.type: Easing.InQuad }
            }

            Criatura {
                anchors.fill: parent
                especie: Digivice.especie
                durmiendo: Digivice.durmiendo
                enfermo: Digivice.enfermo
                lado: 52
                //  Quieto de sprite: aquí no pasea de un lado a otro de la
                //  pantalla, que el que se mueve es el mundo. Mirando a donde
                //  va, que es a la derecha.
                quieto: true
                mirandoDerecha: true
            }
        }

        //  El polvo que levanta. Tres motas que salen de los pies hacia atrás
        //  y se apagan: es el detalle que dice «esto anda» aunque el bicho
        //  esté clavado en su sitio de la pantalla.
        Repeater {
            model: 3

            Rectangle {
                id: mota
                required property int index
                width: 3; height: 3; radius: 1.5
                color: self.tinta
                opacity: 0
                y: self.suelo - 3

                SequentialAnimation {
                    running: self.andando
                    loops: Animation.Infinite
                    PauseAnimation { duration: mota.index * 190 }
                    ParallelAnimation {
                        NumberAnimation { target: mota; property: "x"
                                          from: self.xBicho - 6; to: self.xBicho - 30
                                          duration: 520 }
                        SequentialAnimation {
                            NumberAnimation { target: mota; property: "opacity"
                                              to: 0.55; duration: 90 }
                            NumberAnimation { target: mota; property: "opacity"
                                              to: 0; duration: 430 }
                        }
                    }
                    PauseAnimation { duration: 570 - mota.index * 190 }
                }
            }
        }

        // ── el que te ha salido al paso ───────────────────────────
        //  En la carretera y mirándote, no en un cartel en medio de la
        //  pantalla. Entra por la derecha la primera vez que aparece.
        Item {
            id: rival
            visible: Digivice.encuentroPendiente
            y: self.suelo - height + 4
            width: 66; height: 58
            x: mundo.width * 0.68

            onVisibleChanged: if (visible) entrada.restart()

            //  La entrada va sobre un desplazamiento y no sobre `x`: animar
            //  `x` rompería su enlace y el rival se quedaría clavado en el
            //  píxel donde acabó la primera animación.
            transform: Translate { id: llegada }

            NumberAnimation {
                id: entrada
                target: llegada
                property: "x"
                from: mundo.width * 0.4
                to: 0
                duration: 620
                easing.type: Easing.OutCubic
            }

            Retrato {
                anchors.fill: parent
                especie: Digivice.enemigoPendiente
                lado: 58
            }

            //  Un temblor corto y repetido: está esperando, no posando.
            SequentialAnimation on scale {
                running: Digivice.encuentroPendiente
                loops: Animation.Infinite
                NumberAnimation { to: 1.05; duration: 520; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutQuad }
            }
        }
    }

    // ── el rótulo de arriba ───────────────────────────────────────
    Column {
        anchors.top: parent.top
        anchors.topMargin: 2
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0
        width: parent.width

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: self.zonaActual.nombre
            font.pixelSize: 14
            font.weight: Font.Bold
            color: "#e8f4ea"
            elide: Text.ElideRight
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: !Digivice.encuentroPendiente
            text: Digivice.jefeVencido(Digivice.zona)
                ? "★ " + Idioma.t("conquistada")
                : Idioma.f(Idioma.t("jefe: %1"),
                           Digivice.nombreDe(Digivice.jefeDe(Digivice.zona)))
            font.pixelSize: 12
            color: Digivice.jefeVencido(Digivice.zona) ? "#e8b45a" : "#8fbf9c"
            elide: Text.ElideRight
        }

        //  Con alguien delante, el rótulo dice QUIÉN.
        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: Digivice.encuentroPendiente
            text: (Digivice.jefePendiente ? "★ " : "")
                  + Digivice.nombreDe(Digivice.enemigoPendiente)
                  + (Digivice.jefePendiente ? " ★" : "")
            font.pixelSize: 13
            font.weight: Font.Bold
            color: Digivice.jefePendiente ? "#e8b45a" : "#d8f0de"
            elide: Text.ElideRight

            SequentialAnimation on opacity {
                running: Digivice.jefePendiente
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 420 }
                NumberAnimation { to: 1.0; duration: 420 }
            }
        }
    }

    // ── el pie: cuánto llevas y a dónde puedes irte ───────────────
    Column {
        id: pie
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: cambiar.top
        anchors.bottomMargin: 5
        width: parent.width - 24
        spacing: 2
        visible: !Digivice.encuentroPendiente

        //  La carretera entera de un vistazo. El mundo de arriba enseña los
        //  próximos veinte metros; esto enseña la zona, que es lo que no
        //  cabe en una pantalla.
        Item {
            width: parent.width
            height: 8

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 3
                radius: 1.5
                color: "#1a2f20"
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * Math.min(1, self.mostrada
                        / Math.max(1, Digivice.distanciaJefeZona))
                height: 3
                radius: 1.5
                color: Digivice.jefeVencido(Digivice.zona) ? "#e8b45a" : "#7de08a"
            }

            Rectangle {
                x: parent.width * Math.min(1, self.mostrada
                        / Math.max(1, Digivice.distanciaJefeZona)) - 1.5
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 8; radius: 1.5
                color: "#d8f0de"
            }
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: {
                if (Digivice.caminoAcabado)
                    return Idioma.t("camino terminado  ·  B lo rehace")
                if (Digivice.distanciaZona >= Digivice.distanciaJefeZona)
                    return Idioma.t("el jefe te espera al final")
                const v = Digivice.vueltaDe(Digivice.zona)
                return Idioma.f(Idioma.t("%1 de %2 al jefe"),
                                Digivice.distanciaZona, Digivice.distanciaJefeZona)
                     + (v > 0 ? "  ·  " + Idioma.f(Idioma.t("vuelta %1"), v + 1) : "")
            }
            font.pixelSize: 11
            color: Digivice.caminoAcabado ? "#e8b45a" : "#5f8f6c"
            elide: Text.ElideRight
        }
    }

    // ── el botón de abajo ─────────────────────────────────────────
    //  Con alguien delante es «¡Pelear!» y si no, «Cambiar zona». Es el mismo
    //  sitio a propósito: en la carretera solo hay una cosa que hacer cada
    //  vez.
    Rectangle {
        id: cambiar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 13
        width: Digivice.encuentroPendiente ? 96 : 150
        height: 22
        radius: 11
        color: Digivice.encuentroPendiente
            ? "#8a3b2e"
            : (raton.containsMouse ? "#3f8a56" : "#2f6b40")
        border.width: 1
        border.color: Digivice.encuentroPendiente ? "#c96a52" : "#7de08a"

        Behavior on width { NumberAnimation { duration: 200 } }

        Row {
            anchors.centerIn: parent
            spacing: 6

            K4.Glifo {
                anchors.verticalCenter: parent.verticalCenter
                visible: !Digivice.encuentroPendiente
                text: "\u{F004D}"
                font.pixelSize: 12
                color: "#d8f0de"
            }
            K4.Etiqueta {
                anchors.verticalCenter: parent.verticalCenter
                text: Digivice.encuentroPendiente ? Idioma.t("¡Pelear!")
                                                  : Idioma.t("Cambiar zona")
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            K4.Glifo {
                anchors.verticalCenter: parent.verticalCenter
                visible: !Digivice.encuentroPendiente
                text: "\u{F0054}"
                font.pixelSize: 12
                color: "#d8f0de"
            }
        }

        MouseArea {
            id: raton
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (Digivice.encuentroPendiente) {
                    self.pelear(Digivice.enemigoPendiente)
                    return
                }
                //  Salta las cerradas: un botón que no hace nada parece roto.
                let n = self.indiceZona
                for (let i = 0; i < Digivice.zonas.length; ++i) {
                    n = (n + 1) % Digivice.zonas.length
                    if (Digivice.zonaAbierta(Digivice.zonas[n].id)) {
                        Digivice.cambiarZona(Digivice.zonas[n].id)
                        return
                    }
                }
            }
        }
    }

    //  Las nueve zonas de un vistazo: cuáles llevas conquistadas.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        spacing: 3

        Repeater {
            model: Digivice.zonas

            Rectangle {
                required property var modelData
                required property int index
                width: 7; height: 7
                radius: 1
                color: !Digivice.zonaAbierta(modelData.id) ? "#1a2a20"
                     : Digivice.jefeVencido(modelData.id) ? "#e8b45a"
                     : index === self.indiceZona ? "#d8f0de" : "#3f7a52"
            }
        }
    }
}
