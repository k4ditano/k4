//  Evolucionar: qué falta y qué se puede fusionar.
//
//  Antes evolucionar era un temporizador invisible: aparecía un botón sin
//  avisar. Ahora los tres requisitos se ven siempre —tiempo, victorias y
//  experiencia— porque un requisito que no se ve no es una meta.
//
//  Y debajo, las fusiones posibles con lo que tienes en la guardería. Solo
//  las que PUEDES hacer: enseñar la tabla entera sería un catálogo.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    property int cursor: 0
    signal fusionar(int hueco)

    readonly property var fusiones: Digivice.fusionesPosibles
    readonly property int total: fusiones.length
    readonly property int indice: total > 0
                                ? ((cursor % total) + total) % total : 0

    //  Las vías que hay ABIERTAS ahora mismo, en orden de prioridad. Se
    //  recorren con A y se lanzan con B, igual que todo lo demás en este
    //  aparato: con cinco maneras de evolucionar —normal, Armor, X, Warp y
    //  Jogress— hacer que B «adivine» cuál querías sería jugar a la ruleta
    //  con un bicho que has criado durante horas.
    readonly property var vias: {
        const v = []
        if (Digivice.puedeEvolucionar())
            v.push({ via: "normal", texto: Idioma.t("Evolucionar"),
                     da: "", i: 0 })
        if (Digivice.puedeWarp)
            v.push({ via: "warp", texto: Idioma.t("¡WARP!  salta una etapa"),
                     da: Digivice.warpsPosibles[0], i: 0 })
        const ar = Digivice.armoresPosibles
        for (let k = 0; k < ar.length; ++k)
            v.push({ via: "armor",
                     texto: Idioma.t("Armor · Digimental de ") + ar[k].dig,
                     da: ar[k].da, i: k })
        if (Digivice.puedeX)
            v.push({ via: "x", texto: Idioma.t("Anticuerpo X"),
                     da: Digivice.formaX, i: 0 })
        for (let j = 0; j < self.fusiones.length; ++j)
            v.push({ via: "jogress",
                     texto: Idioma.t("Jogress con ")
                          + Digivice.nombreDe(self.fusiones[j].con),
                     da: self.fusiones[j].da, i: self.fusiones[j].hueco })
        return v
    }
    readonly property int totalVias: vias.length
    readonly property int iVia: totalVias > 0
                              ? ((cursor % totalVias) + totalVias) % totalVias : 0
    readonly property var via: totalVias > 0 ? vias[iVia] : null

    function elegir() {
        if (!self.via) {
            Digivice.aviso(Idioma.t("Todavía no puede evolucionar"))
            return
        }
        const v = self.via
        if (v.via === "normal") Digivice.evolucionar()
        else if (v.via === "warp") Digivice.evolucionarWarp(v.i)
        else if (v.via === "armor") Digivice.evolucionarArmor(v.i)
        else if (v.via === "x") Digivice.evolucionarX()
        else if (v.via === "jogress") self.fusionar(v.i)
    }

    Column {
        anchors.fill: parent
        anchors.margins: 5
        spacing: 2

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Digivice.puedeEvolucionar() ? Idioma.t("¡LISTO PARA EVOLUCIONAR!")
                : Digivice.enfermo ? Idioma.t("Enfermo: no puede evolucionar")
                : Idioma.t("Para evolucionar")
            font.pixelSize: 13
            font.weight: Font.Bold
            color: Digivice.puedeEvolucionar() ? "#e8b45a"
                 : Digivice.enfermo ? "#e0806b" : "#8fbf9c"

            SequentialAnimation on opacity {
                running: Digivice.puedeEvolucionar()
                loops: Animation.Infinite
                NumberAnimation { to: 0.4; duration: 520 }
                NumberAnimation { to: 1.0; duration: 520 }
            }
        }

        //  Los tres requisitos, con lo que llevas y lo que falta.
        Repeater {
            model: {
                const f = Digivice.falta
                if (!f) return []
                return [
                    { k: Idioma.t("Tiempo"), hay: Digivice.minutosEnEtapa,
                      pide: f.req.minutos, falta: f.minutos, u: " min" },
                    { k: Idioma.t("Victorias"), hay: Digivice.victorias,
                      pide: f.req.victorias, falta: f.victorias, u: "" },
                    { k: Idioma.t("Experiencia"), hay: Digivice.xp,
                      pide: f.req.xp, falta: f.xp, u: "" }
                ]
            }

            Row {
                id: linea
                required property var modelData
                width: parent.width

                K4.Glifo {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    text: linea.modelData.falta === 0 ? "\u{F012C}" : "\u{F0766}"
                    font.pixelSize: 12
                    color: linea.modelData.falta === 0 ? "#7de08a" : "#5f8f6c"
                }
                K4.Etiqueta {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.45
                    text: linea.modelData.k
                    font.pixelSize: 12
                    color: "#8fbf9c"
                }
                K4.Etiqueta {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.45 - 16
                    horizontalAlignment: Text.AlignRight
                    text: Math.min(linea.modelData.hay, linea.modelData.pide)
                        + " / " + linea.modelData.pide + linea.modelData.u
                    font.pixelSize: 12
                    font.weight: linea.modelData.falta === 0 ? Font.Bold : Font.Normal
                    color: linea.modelData.falta === 0 ? "#9fe8ac" : "#d8f0de"
                }
            }
        }

        K4.Etiqueta {
            width: parent.width
            visible: !Digivice.falta
            horizontalAlignment: Text.AlignHCenter
            text: Idioma.t("Ha llegado a la cima de su línea")
            font.pixelSize: 12
            color: "#8fbf9c"
        }

        Item { width: 1; height: 4 }

        // ── las vías abiertas ─────────────────────────────────────
        //
        //  Todas en la misma lista y con A se pasan: normal, Warp, Armor, X y
        //  Jogress. Antes solo estaba la normal y las fusiones, y las tres
        //  especiales existían en los datos sin que hubiera manera de usarlas.
        K4.Etiqueta {
            width: parent.width
            text: self.totalVias > 0
                ? Idioma.f(Idioma.t("Vía %1/%2 · A pasa"),
                           self.iVia + 1, self.totalVias)
                : Idioma.t("Ninguna vía abierta todavía")
            font.pixelSize: 12
            color: "#5f8f6c"
        }

        K4.Etiqueta {
            width: parent.width
            visible: self.via !== null
            text: self.via ? self.via.texto : ""
            font.pixelSize: 12
            font.weight: Font.Bold
            //  Cada vía con su color, para que se distingan de un vistazo sin
            //  tener que leer: la especial no puede parecerse a la de siempre.
            color: !self.via ? "#8fbf9c"
                 : self.via.via === "warp" ? "#e8d05a"
                 : self.via.via === "armor" ? "#9fd8ae"
                 : self.via.via === "x" ? "#c98ae0"
                 : self.via.via === "jogress" ? "#e8b45a" : "#7de08a"
            elide: Text.ElideRight
        }

        //  En qué te conviertes. La normal no lo enseña a propósito: la rama
        //  la elige lo bien que hayas criado y adelantarla quitaría la única
        //  sorpresa que le queda al juego.
        Row {
            width: parent.width
            height: 42
            spacing: 4
            visible: self.via !== null && self.via.via !== "normal"

            Retrato {
                anchors.verticalCenter: parent.verticalCenter
                especie: Digivice.especie
                lado: 34
            }
            K4.Glifo {
                anchors.verticalCenter: parent.verticalCenter
                text: self.via && self.via.via === "jogress" ? "\u{F0415}" : "\u{F0054}"
                font.pixelSize: 13
                color: "#8fbf9c"
            }
            //  El compañero, solo en el Jogress: en las demás no hay tercero.
            Retrato {
                anchors.verticalCenter: parent.verticalCenter
                visible: self.via !== null && self.via.via === "jogress"
                especie: {
                    if (!self.via || self.via.via !== "jogress") return ""
                    for (let i = 0; i < self.fusiones.length; ++i)
                        if (self.fusiones[i].hueco === self.via.i)
                            return self.fusiones[i].con
                    return ""
                }
                lado: 34
            }
            K4.Glifo {
                anchors.verticalCenter: parent.verticalCenter
                visible: self.via !== null && self.via.via === "jogress"
                text: "\u{F0054}"
                font.pixelSize: 13
                color: "#e8b45a"
            }
            Retrato {
                anchors.verticalCenter: parent.verticalCenter
                especie: self.via ? self.via.da : ""
                lado: 38
            }
        }

        K4.Etiqueta {
            width: parent.width
            visible: self.via !== null && self.via.via !== "normal"
            text: self.via ? Digivice.nombreDe(self.via.da) + "   ·   "
                             + Idioma.t("B lo hace") : ""
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: "#e8b45a"
            elide: Text.ElideRight
        }

        //  Lo que CUESTA cada vía. Es lo que no puede faltar: un Armor gasta
        //  el digimental que te costó un jefe, y un Jogress se lleva a los
        //  dos. Enterarse después no es enterarse.
        K4.Etiqueta {
            width: parent.width
            visible: self.via !== null
            text: {
                if (!self.via) return ""
                if (self.via.via === "jogress") return Idioma.t("Los dos se pierden")
                if (self.via.via === "armor") return Idioma.t("Gasta el Digimental")
                if (self.via.via === "x") return Idioma.t("Gasta el Anticuerpo X")
                if (self.via.via === "warp") return Idioma.t("Cero descuidos: se salta una etapa")
                return ""
            }
            font.pixelSize: 11
            color: "#c98a6b"
        }
    }
}
