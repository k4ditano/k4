//  El crisol de fusión.
//
//  Se arrastran piezas iguales a los huecos y se funden en una. La regla de
//  tres —tres entran, una sale— no es estética: cada grado vale el triple que
//  el anterior, así que fundir nunca puede fabricar valor, solo concentrarlo.
//
//  El botón central solo se enciende cuando los huecos están llenos y todas las
//  piezas son del mismo grupo; mezclar una espada con unas botas no funde nada,
//  y decirlo antes de pulsar es mejor que fallar después.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: crisol

    // Piezas colocadas, por referencia. Siguen contando en la bolsa hasta que
    // se funden: sacarlas antes obligaría a devolverlas si te arrepientes.
    property var puestas: []
    property var resultado: null
    property string cambio: ""

    readonly property int huecos: Game.huecosCrisol
    readonly property bool lleno: puestas.length >= huecos

    // Todas del mismo grupo, que es lo que se puede fundir.
    readonly property bool compatible: {
        if (puestas.length < 2)
            return true
        const k = Game.claveDe(puestas[0])
        for (let i = 1; i < puestas.length; ++i) {
            if (Game.claveDe(puestas[i]) !== k)
                return false
        }
        return true
    }

    readonly property bool listo: lleno && compatible && resultado === null

    signal devuelto()

    function yaPuesta(o) {
        for (let i = 0; i < puestas.length; ++i) {
            if (puestas[i].id === o.id)
                return true
        }
        return false
    }

    function meter(objeto) {
        if (!objeto || resultado !== null || puestas.length >= huecos)
            return
        if (yaPuesta(objeto))
            return
        puestas = puestas.concat([objeto])
    }

    // De un grupo entra la PEOR que quede libre: así al fundir te quedas con
    // el mejor ejemplar y gastas los repetidos, que es lo que uno quiere.
    function meterDelGrupo(clave) {
        if (resultado !== null || puestas.length >= huecos)
            return
        const grupo = Game.grupos.filter(function (g) { return g.clave === clave })[0]
        if (!grupo)
            return

        const libres = grupo.piezas.filter(function (o) { return !yaPuesta(o) })
        if (libres.length === 0)
            return

        libres.sort(function (a, b) {
            return Items.puntuacion(a) - Items.puntuacion(b)
        })
        meter(libres[0])
    }

    function sacar(i) {
        if (resultado !== null)
            return
        const copia = puestas.slice()
        copia.splice(i, 1)
        puestas = copia
    }

    function vaciar() {
        puestas = []
        resultado = null
        cambio = ""
    }

    function fundir() {
        if (!listo)
            return
        giro.restart()
    }

    function rematar() {
        const r = Game.fundirPiezas(puestas)
        if (!r) {
            vaciar()
            return
        }
        resultado = r.objeto
        cambio = r.cambio
        puestas = []
        estallido.restart()
    }

    // Soltar vale en cualquier parte del crisol. Acertar en un hueco de 30
    // píxeles arrastrando es pedir puntería que nadie tiene por qué tener.
    DropArea {
        anchors.fill: parent
        z: -1
        onDropped: function (caida) {
            if (!caida.source)
                return
            if (caida.source.grupoClave)
                crisol.meterDelGrupo(caida.source.grupoClave)
            else if (caida.source.objetoRef)
                crisol.meter(caida.source.objetoRef)
        }
    }

    // ── el aparato ────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        IslandLabel {
            text: Idioma.t("Crisol")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.alignment: Qt.AlignHCenter
        }

        // ── los huecos
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 96

            Image {
                id: yunque
                anchors.centerIn: parent
                width: 96
                height: 96
                source: "assets/crisol/c" + String(crisol.cuadro).padStart(2, "0") + ".png"
                fillMode: Image.PreserveAspectFit
                smooth: false
                rotation: crisol.vuelta
            }

            // Los huecos van encima del dibujo, repartidos en arco: así el
            // aparato sirve igual con tres que con cinco.
            Repeater {
                model: crisol.huecos

                delegate: Rectangle {
                    id: hueco
                    required property int index

                    readonly property real angulo: Math.PI
                        * (0.15 + 0.7 * (crisol.huecos === 1 ? 0.5
                            : index / (crisol.huecos - 1)))
                    readonly property var pieza: index < crisol.puestas.length
                        ? crisol.puestas[index] : null

                    width: 30
                    height: 30
                    radius: 8
                    // Sobre los engastes del dibujo: el arco es estrecho
                    // porque los huecos del sprite están en la cara de arriba,
                    // no repartidos por todo el borde.
                    x: parent.width / 2 - 15 - Math.cos(angulo) * 27
                    y: parent.height / 2 - 15 - Math.sin(angulo) * 13 - 12
                    color: pieza ? "#22ffffff" : "#66000000"
                    border.width: 1
                    border.color: pieza
                        ? (crisol.compatible ? Theme.blue : Theme.red)
                        : "#33ffffff"

                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    Image {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        visible: hueco.pieza !== null
                        source: hueco.pieza
                            ? "assets/objetos/i"
                              + String(hueco.pieza.icono).padStart(2, "0") + ".png"
                            : ""
                        smooth: false
                    }

                    DropArea {
                        anchors.fill: parent
                        onDropped: function (caida) {
                            if (caida.source && caida.source.objetoRef)
                                crisol.meter(caida.source.objetoRef)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: hueco.pieza !== null && crisol.resultado === null
                        cursorShape: Qt.PointingHandCursor
                        onClicked: crisol.sacar(hueco.index)
                    }
                }
            }

            // ── lo que ha salido
            Item {
                anchors.centerIn: parent
                visible: crisol.resultado !== null
                width: 64
                height: 64
                scale: crisol.brote

                Image {
                    anchors.fill: parent
                    source: crisol.resultado
                        ? "assets/objetos/i"
                          + String(crisol.resultado.icono).padStart(2, "0") + ".png"
                        : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: false
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function (mouse) {
                        if (mouse.button === Qt.RightButton)
                            Game.tirarFundido(crisol.resultado)
                        else
                            Game.guardarFundido(crisol.resultado)
                        crisol.vaciar()
                        crisol.devuelto()
                    }
                }
            }
        }

        // ── qué ha pasado
        IslandLabel {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 10
            font.weight: Font.DemiBold
            color: crisol.cambio === "mejor" ? Theme.green
                : crisol.cambio === "peor" ? Theme.red : Theme.muted
            text: crisol.resultado
                ? (crisol.cambio === "mejor" ? Idioma.t("¡Ha subido de grado!")
                   : crisol.cambio === "peor" ? Idioma.t("Ha bajado de grado")
                   : Idioma.t("Se ha quedado igual"))
                : ""
        }

        IslandLabel {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: crisol.resultado !== null
            text: crisol.resultado ? crisol.resultado.nombre : ""
            color: crisol.resultado
                ? Items.rarezaDe(crisol.resultado.rareza).color : Theme.ink
            font.pixelSize: 10
            elide: Text.ElideRight
        }

        IslandLabel {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: crisol.resultado !== null
            text: Idioma.t("izquierdo la guarda · derecho la desguaza")
            color: Theme.dim
            font.pixelSize: 8
        }

        Item { Layout.fillHeight: true }

        // ── el botón
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 14
            color: crisol.listo
                ? (fundirRaton.containsMouse ? "#4aa3ff" : Theme.blue)
                : Theme.surface
            opacity: crisol.resultado !== null ? 0.4 : 1

            Behavior on color { ColorAnimation { duration: 140 } }

            IslandLabel {
                anchors.centerIn: parent
                text: {
                    if (crisol.resultado !== null)
                        return Idioma.t("recoge lo que ha salido")
                    if (!crisol.compatible)
                        return Idioma.t("no son iguales")
                    if (!crisol.lleno)
                        return Idioma.f("faltan %1",
                                        crisol.huecos - crisol.puestas.length)
                    return Idioma.t("FUNDIR")
                }
                color: crisol.listo ? Theme.ink : Theme.muted
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            MouseArea {
                id: fundirRaton
                anchors.fill: parent
                hoverEnabled: true
                enabled: crisol.listo
                cursorShape: Qt.PointingHandCursor
                onClicked: crisol.fundir()
            }
        }

        // ── las probabilidades, a la vista
        //  Un sistema de azar que no enseña sus números invita a pensar que
        //  está trucado. Con ellos delante, cada quien decide.
        IslandLabel {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: crisol.puestas.length > 0 && crisol.resultado === null
            text: {
                const r = crisol.puestas.length > 0 ? crisol.puestas[0].rareza : 0
                return Idioma.t("sube ") + Math.round(Items.probMejora(r) * 100)
                    + "% · " + Idioma.t("baja ") + Math.round(Items.probEmpeora(r) * 100) + "%"
            }
            color: Theme.dim
            font.pixelSize: 9
        }
    }

    // ── animación ─────────────────────────────────────────────────
    property int cuadro: resultado !== null ? 3
        : (giro.running ? 2 : (puestas.length > 0 ? 1 : 0))
    property real vuelta: 0
    property real brote: 0

    SequentialAnimation {
        id: giro

        NumberAnimation {
            target: crisol; property: "vuelta"
            from: 0; to: 1080; duration: 900; easing.type: Easing.InQuad
        }
        ScriptAction { script: { crisol.vuelta = 0; crisol.rematar() } }
    }

    SequentialAnimation {
        id: estallido

        NumberAnimation {
            target: crisol; property: "brote"
            from: 0; to: 1.35; duration: 260; easing.type: Easing.OutBack
        }
        NumberAnimation {
            target: crisol; property: "brote"
            to: 1; duration: 160
        }
    }
}
