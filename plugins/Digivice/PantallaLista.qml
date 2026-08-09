//  La enciclopedia: cada bicho EN SU SITIO.
//
//  Era una ficha de texto con un retrato pegado en un marco. La información
//  estaba toda, y aun así la pantalla no contaba nada: quince especies
//  distintas se veían exactamente igual, un recuadro negro y cuatro líneas.
//
//  Lo que la convierte en un sitio es que cada especie tiene HÁBITAT. El
//  índice trae el campo `f` —«Nature Spirits», «Dragon's Roar»…— y de esos
//  campos ya teníamos nueve fondos dibujados para el mapa. Así que aquí se
//  ve al bicho paseando por el suyo, con el nombre de la zona puesto: mirar
//  la ficha de Airdramon y la de Numemon deja de ser mirar dos rectángulos.
//
//  Y el bicho PASEA, no posa: es el mismo `Criatura` de casa, con su respiro
//  y su vuelta al llegar al borde. Un retrato quieto delata que dentro no
//  hay nadie.
//
//  A recorre; la ficha entra deslizándose por el lado hacia el que vas, que
//  es lo que hace que se lea como pasar páginas y no como un texto que se
//  sustituye solo.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    property int cursor: 0

    //  Las descripciones son medio megabyte y se cargan solo aquí.
    Component.onCompleted: Digivice.cargarDescripciones()

    readonly property var vistos: {
        const out = []
        for (const k in Digivice.descubiertos) {
            const d = Digivice.datoDe(k)
            if (d) out.push({ id: k, d: d })
        }
        out.sort(function (a, b) { return parseInt(a.id, 10) - parseInt(b.id, 10) })
        return out
    }

    readonly property int total: vistos.length
    readonly property int indice: total > 0
                                ? ((cursor % total) + total) % total : 0
    readonly property var ficha: total > 0 ? vistos[indice] : null
    readonly property bool criado: ficha && Digivice.estaCriado(ficha.id)

    //  ── el hábitat ────────────────────────────────────────────────
    //  De los campos de la especie, el primero que sea una zona del juego.
    //  Muchas especies están en varios; se coge uno y se dice cuántos más
    //  hay, que es más honesto que enseñar solo el primero como si fuera el
    //  único.
    readonly property int zonaFicha: {
        if (!ficha || !ficha.d.f) return -1
        for (let i = 0; i < ficha.d.f.length; ++i) {
            for (let z = 0; z < Digivice.zonas.length; ++z)
                if (Digivice.zonas[z].id === ficha.d.f[i])
                    return z
        }
        return -1
    }
    readonly property int cuantosCampos: {
        if (!ficha || !ficha.d.f) return 0
        let n = 0
        for (let i = 0; i < ficha.d.f.length; ++i)
            for (let z = 0; z < Digivice.zonas.length; ++z)
                if (Digivice.zonas[z].id === ficha.d.f[i]) { n += 1; break }
        return n
    }

    //  Hacia dónde entra la ficha nueva. A siempre suma, así que en la
    //  práctica entra por la derecha; se guarda el signo igualmente por si
    //  algún día se pasa hacia atrás.
    property int _sentido: 1
    property int _anterior: 0
    onCursorChanged: {
        _sentido = cursor >= _anterior ? 1 : -1
        _anterior = cursor
        if (total > 0)
            entra.restart()
    }

    property real _desliz: 0

    SequentialAnimation {
        id: entra
        ScriptAction { script: self._desliz = self._sentido * 26 }
        ParallelAnimation {
            NumberAnimation { target: self; property: "_desliz"; to: 0
                              duration: 210; easing.type: Easing.OutCubic }
            NumberAnimation { target: hoja; property: "opacity"
                              from: 0.25; to: 1; duration: 210 }
        }
    }

    //  ── el fondo: la zona donde vive ──────────────────────────────
    Paisaje {
        anchors.fill: parent
        visible: self.zonaFicha >= 0
        semilla: Math.max(0, self.zonaFicha)
        tono: "#0d1f14"
        avance: 0
        opacity: 0.55
    }

    //  Sin hábitat conocido no hay paisaje que pintar, pero tampoco puede
    //  quedarse el cristal desnudo: un fondo liso oscuro es el «no consta».
    Rectangle {
        anchors.fill: parent
        visible: self.zonaFicha < 0
        color: "#0a1410"
    }

    Item {
        id: hoja
        anchors.fill: parent
        visible: self.ficha !== null
        x: self._desliz

        //  ── la cabecera ───────────────────────────────────────────
        Row {
            id: cabecera
            anchors.top: parent.top
            anchors.topMargin: 3
            anchors.left: parent.left
            anchors.leftMargin: 5
            anchors.right: parent.right
            anchors.rightMargin: 5

            K4.Etiqueta {
                width: parent.width * 0.42
                text: self.ficha ? "N.º " + ("000" + self.ficha.id).slice(-3) : ""
                font.pixelSize: 12
                color: "#8fbf9c"
            }

            //  Criado se marca con estrella y la estrella ASOMA al cambiar de
            //  ficha: es la diferencia entre un registro y una colección, y
            //  una colección tiene que celebrarse aunque sea un poco.
            K4.Etiqueta {
                id: sello
                width: parent.width * 0.58
                horizontalAlignment: Text.AlignRight
                text: self.criado ? "★ " + Idioma.t("criado") : Idioma.t("visto")
                font.pixelSize: 12
                font.weight: self.criado ? Font.Bold : Font.Normal
                color: self.criado ? "#e8b45a" : "#6f9c7c"

                SequentialAnimation on scale {
                    running: self.criado
                    NumberAnimation { from: 1.6; to: 1.0; duration: 260
                                      easing.type: Easing.OutBack }
                }
            }
        }

        //  ── la ficha, sobre panel ─────────────────────────────────
        //  El panel no es decoración: encima de un paisaje dibujado, un texto
        //  tenue no se lee. Es lo mismo que el cartel del contador.
        Rectangle {
            id: panel
            anchors.top: cabecera.bottom
            anchors.topMargin: 2
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: parent.right
            anchors.rightMargin: 4
            height: datos.implicitHeight + 8
            radius: 5
            color: "#08120c"
            opacity: 0.82
        }

        Column {
            id: datos
            anchors.left: panel.left
            anchors.leftMargin: 5
            anchors.right: panel.right
            anchors.rightMargin: 5
            anchors.top: panel.top
            anchors.topMargin: 4
            spacing: 0

            K4.Etiqueta {
                width: parent.width
                text: self.ficha ? self.ficha.d.n : ""
                font.pixelSize: 15
                font.weight: Font.Bold
                color: "#e8f4ea"
                elide: Text.ElideRight
            }

            //  Etapa, atributo y familia en UNA línea: en tres ocupaban tres
            //  renglones para decir tres palabras.
            K4.Etiqueta {
                width: parent.width
                text: {
                    if (!self.ficha) return ""
                    const p = [self.ficha.d.l]
                    if (self.ficha.d.a) p.push(self.ficha.d.a)
                    if (self.ficha.d.t) p.push(self.ficha.d.t)
                    return p.join("  ·  ")
                }
                font.pixelSize: 11
                color: "#9fd8ae"
                elide: Text.ElideRight
            }

            K4.Etiqueta {
                width: parent.width
                visible: self.ficha && self.ficha.d.sk && self.ficha.d.sk.length > 0
                text: self.ficha && self.ficha.d.sk && self.ficha.d.sk.length
                    ? "▸ " + self.ficha.d.sk[0] : ""
                font.pixelSize: 11
                color: "#e8b45a"
                elide: Text.ElideRight
            }

            //  La descripción entera, no un renglón cortado. Antes tenía 24
            //  de alto para una fuente de 10 —o sea, sitio para una línea y
            //  tres cuartos— y siempre acababa en «…» al final de la primera,
            //  con el tercio de abajo del cristal vacío.
            K4.Etiqueta {
                width: parent.width
                text: self.ficha ? (Digivice.descripciones[self.ficha.id] || "") : ""
                font.pixelSize: 10
                color: "#8fbf9c"
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 4
            }
        }

        //  El nombre de la zona: pie de foto entre la ficha y el suelo.
        K4.Etiqueta {
            id: pie
            anchors.top: panel.bottom
            anchors.topMargin: 2
            anchors.right: panel.right
            text: {
                if (self.zonaFicha < 0) return Idioma.t("hábitat no consta")
                const n = Digivice.zonas[self.zonaFicha].nombre
                return self.cuantosCampos > 1
                     ? n + "  +" + (self.cuantosCampos - 1) : n
            }
            font.pixelSize: 10
            color: "#9fd8ae"
        }

        //  ── el bicho, paseando por el suelo de su zona ────────────
        //  Abajo y no flotando a media altura: el paisaje tiene suelo dibujado
        //  y un bicho a media pantalla parece recortado y pegado encima.
        Criatura {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: pie.bottom
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            especie: self.ficha ? self.ficha.id : ""
            lado: 52
        }
    }

    //  El contador, abajo del todo y sobre una tira oscura: encima del
    //  paisaje, un texto tenue sin fondo no se lee.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        visible: self.ficha !== null
        width: cuenta.implicitWidth + 12
        height: 14
        radius: 7
        color: "#0a1410"
        opacity: 0.75

        K4.Etiqueta {
            id: cuenta
            anchors.centerIn: parent
            text: (self.indice + 1) + " / " + self.total
                + "   ·   ★ " + Digivice.cuantosCriados
            font.pixelSize: 10
            color: "#8fbf9c"
        }
    }

    K4.Etiqueta {
        anchors.centerIn: parent
        width: parent.width - 20
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: self.ficha === null
        text: Idioma.t("Aún no has visto ninguno")
        font.pixelSize: 13
        color: "#8fbf9c"
    }
}
