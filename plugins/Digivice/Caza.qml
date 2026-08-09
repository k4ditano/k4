//  Cazar: tres rastros y eliges uno.
//
//  `obj_Hunt_Food` del emulador busca comida por el mapa. Aquí eso se paga
//  con lo único que este juego tiene de moneda honesta —el rastro que dejas
//  andando, o sea haber estado usando el ordenador— y así comer bien queda
//  atado a explorar en vez de salir de un botón infinito.
//
//  Y no es una tirada: detrás de cada rastro hay algo distinto, siempre uno
//  bueno y uno que sienta mal. Con la velocidad entrenada se marca un rastro
//  malo antes de elegir, así que criar rápido se nota también aquí. Nunca se
//  marcan los dos: entonces dejaría de haber una decisión.
//
//  A recorre los rastros, B lo sigue, C se va —y devuelve el rastro gastado,
//  porque si irse a mitad costara doce pasos nadie abriría esto dos veces.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    signal terminado()

    property int cursor: 0
    //  eligiendo · andando · resultado
    property string fase: "eligiendo"
    property var hallazgo: null

    //  Dónde está el bicho. Al elegir camina hasta el rastro antes de que se
    //  sepa qué había: la cacería es SEGUIR una huella, y el resultado que
    //  aparece de golpe se salta justo esa parte.
    property bool andando: false
    property real _xCazador: 10
    //  El sitio de cada rastro en la fila, para poder ir hasta él.
    property real _anchoFila: self.total > 0
            ? self.total * 46 + (self.total - 1) * 5 : 0
    function _xDe(i) {
        return (self.width - _anchoFila) / 2 + i * 51 + 1
    }

    property var zumbador: null
    function _pitar(n) { if (zumbador) zumbador.sonar(n) }

    readonly property var caceria: Digivice.caceria
    readonly property var rastros: caceria ? caceria.rastros : []
    readonly property int total: rastros.length

    //  Si la cacería desaparece por debajo —se resuelve desde fuera, la
    //  carretera la cancela— esta pantalla se quedaba abierta con CERO
    //  rastros: título, subtítulo, la leyenda de los botones y un hueco. Y
    //  sin nada que pulsar, porque elegir sobre una lista vacía no hace nada.
    //  Un sitio del que no se puede salir es peor que uno feo.
    onCaceriaChanged: if (!caceria && fase === "eligiendo") terminado()
    readonly property int indice: total > 0
                                ? ((cursor % total) + total) % total : 0

    function pasar() {
        if (fase !== "eligiendo" || andando)
            return
        cursor += 1
        _pitar("boton")
        husmeo.restart()
    }

    function elegir() {
        if (fase === "resultado") { self.terminado(); return }
        if (fase !== "eligiendo")
            return
        //  Primero VA hasta el rastro; lo que había detrás se sabe al llegar.
        const i = indice
        andando = true
        _xCazador = _xDe(i)
        _pitar("boton")
        llegada.restart()
    }

    Timer {
        id: llegada
        interval: 460
        onTriggered: {
            const r = Digivice.elegirRastro(self.indice)
            self.andando = false
            if (!r) { self.terminado(); return }
            self.hallazgo = r
            self.fase = "resultado"
            self._pitar(r.malo ? "fallo" : "acierto")
            if (!r.malo)
                K4.Tema.tintar("digivice", K4.Tema.verde, 0.2, 700)
            self.cierre.restart()
        }
    }

    function salir() {
        if (fase === "eligiendo")
            Digivice.cancelarCaza()
        self.terminado()
    }

    property alias cierre: cierreT

    Timer {
        id: cierreT
        interval: 1900
        onTriggered: { K4.Tema.destintar("digivice"); self.terminado() }
    }

    Paisaje {
        anchors.fill: parent
        tono: "#101f14"
        semilla: Digivice.indiceZona
        avance: 0
        opacity: 0.35
    }

    //  El bicho, olfateando. No salía, y la cacería es algo que HACE él: sin
    //  la criatura en pantalla esto eran cuatro recuadros y un texto.
    //
    //  Se coloca por `x` y no en la columna porque tiene que poder CAMINAR
    //  hasta el rastro que elijas antes de que se sepa qué había detrás.
    Item {
        id: cazador
        width: 44
        height: 44
        //  Bajo la fila de huellas, que es por donde camina. A media
        //  altura se comía la leyenda de los botones.
        y: parent.height - 52
        x: self._xCazador
        z: 3
        visible: self.fase !== "resultado" || self.andando

        Behavior on x {
            NumberAnimation { id: caminata; duration: 420
                              easing.type: Easing.InOutQuad }
        }

        Retrato {
            anchors.fill: parent
            especie: Digivice.especie
        }

        //  Mirando hacia donde huele. Los sprites vienen mirando a la
        //  izquierda, de ahí el espejo.
        transform: Scale {
            origin.x: cazador.width / 2
            xScale: -1
        }

        //  El husmeo: un cabeceo corto y seco, como un bicho que olisquea.
        SequentialAnimation {
            id: husmeo
            NumberAnimation { target: cazador; property: "y"
                              to: self.height - 47; duration: 110 }
            NumberAnimation { target: cazador; property: "y"
                              to: self.height - 52; duration: 140
                              easing.type: Easing.OutBack }
        }

        //  Y husmea solo, de vez en cuando, mientras decides.
        Timer {
            interval: 2400
            repeat: true
            running: self.fase === "eligiendo" && !self.andando
            onTriggered: husmeo.restart()
        }
    }

    // ── eligiendo ─────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        anchors.margins: 5
        spacing: 4
        visible: self.fase === "eligiendo"

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: self.andando ? Idioma.t("Siguiendo el rastro…")
                               : Idioma.t("Sigue un rastro")
            font.pixelSize: 13
            font.weight: Font.Bold
            color: "#d8f0de"
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: self.caceria && self.caceria.pistas > 0
                ? Idioma.t("Su olfato descarta uno")
                : Idioma.t("Entrena velocidad para olerlos")
            font.pixelSize: 11
            color: "#5f8f6c"
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 5

            Repeater {
                model: self.rastros

                Rectangle {
                    id: huella
                    required property var modelData
                    required property int index
                    width: 46
                    height: 58
                    radius: 6
                    color: huella.index === self.indice ? "#1f4a2f" : "#12200f"
                    border.width: huella.index === self.indice ? 2 : 1
                    border.color: huella.index === self.indice ? "#7de08a" : "#2f4a38"

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        K4.Glifo {
                            anchors.horizontalCenter: parent.horizontalCenter
                            //  Todos iguales mientras no se sepa qué hay: si
                            //  el icono delatara el contenido, no habría nada
                            //  que decidir.
                            text: "\u{F03E9}"
                            font.pixelSize: 24
                            color: huella.modelData.marcado ? "#8a5a4a" : "#c8dcc0"
                            opacity: huella.modelData.marcado ? 0.6 : 1
                        }

                        //  La pista: una cruz sobre un rastro malo. Marca los
                        //  MALOS y no el bueno, porque señalar el premio
                        //  sería resolver la cacería en vez de ayudarte.
                        K4.Glifo {
                            id: cruz
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: huella.modelData.marcado === true
                            text: "\u{F0159}"
                            font.pixelSize: 13
                            color: "#e0806b"

                            //  Entra con un rebote: descartar una huella es
                            //  algo que PASA, y pasar sin animación se lee
                            //  como que ya estaba así desde el principio.
                            onVisibleChanged: if (visible) aparece.restart()
                            NumberAnimation {
                                id: aparece
                                target: cruz; property: "scale"
                                from: 2.2; to: 1; duration: 260
                                easing.type: Easing.OutBack
                            }
                        }

                        K4.Etiqueta {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: huella.modelData.marcado !== true
                            text: "?"
                            font.pixelSize: 13
                            color: "#5f8f6c"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            self.cursor = huella.index
                            self.elegir()
                        }
                    }

                    SequentialAnimation on scale {
                        running: huella.index === self.indice
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.06; duration: 620 }
                        NumberAnimation { to: 1.0; duration: 620 }
                    }
                }
            }
        }

        //  Olfatear: gasta el rastro que llevas acumulado andando en
        //  descartar una huella mala más. Es una chapa y no un botón porque
        //  los tres del aparato ya están ocupados —A pasa, B sigue, C se va—
        //  y es el mismo patrón que la llamada del aliado en el combate.
        Rectangle {
            id: chapaOlfato
            anchors.horizontalCenter: parent.horizontalCenter
            visible: self.fase === "eligiendo" && Digivice.caceria !== null
            width: 118
            height: 20
            radius: 10
            color: "#12200f"
            border.width: 1
            border.color: Digivice.puedeOlfatear ? "#e8b45a" : "#2f4a38"
            opacity: Digivice.puedeOlfatear ? 1 : 0.45

            Row {
                anchors.centerIn: parent
                spacing: 3

                K4.Glifo {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F03E9}"
                    font.pixelSize: 12
                    color: Digivice.puedeOlfatear ? "#e8b45a" : "#6a7a6e"
                }

                K4.Etiqueta {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Idioma.t("Olfatear") + "  " + Digivice.costeOlfato
                    font.pixelSize: 11
                    color: Digivice.puedeOlfatear ? "#e8b45a" : "#6a7a6e"
                }
            }

            //  Sin `enabled: false` cuando no se puede: pulsarlo tiene que
            //  decir POR QUÉ no, y un botón muerto no dice nada.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (Digivice.olfatear()) {
                        self._pitar("acierto")
                        husmeo.restart()
                    }
                }
            }
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Idioma.f(Idioma.t("A pasa · B lo sigue · C se va   (%1 de rastro)"),
                           Digivice.rastro)
            font.pixelSize: 11
            color: "#5f8f6c"
        }
    }

    // ── lo que había detrás ───────────────────────────────────────
    Column {
        anchors.centerIn: parent
        width: parent.width - 16
        spacing: 4
        visible: self.fase === "resultado" && self.hallazgo !== null

        K4.Glifo {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                if (!self.hallazgo) return ""
                const c = Digivice.comidaPorId(self.hallazgo.comida)
                return c ? c.glifo : ""
            }
            font.pixelSize: 34
            color: self.hallazgo && self.hallazgo.malo ? "#c98a6b" : "#9fe8ac"

            SequentialAnimation on scale {
                running: self.fase === "resultado"
                NumberAnimation { from: 0.4; to: 1.15; duration: 220
                                  easing.type: Easing.OutBack }
                NumberAnimation { to: 1.0; duration: 160 }
            }
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: {
                if (!self.hallazgo) return ""
                const c = Digivice.comidaPorId(self.hallazgo.comida)
                return c ? Idioma.t(c.nombre) : ""
            }
            font.pixelSize: 14
            font.weight: Font.Bold
            color: self.hallazgo && self.hallazgo.malo ? "#c98a6b" : "#e8b45a"
            elide: Text.ElideRight
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: self.hallazgo && self.hallazgo.malo
                ? Idioma.t("Se ha echado a perder.\nDársela le sentará mal.")
                : Idioma.t("A la despensa.")
            font.pixelSize: 11
            color: "#8fbf9c"
        }
    }
}
