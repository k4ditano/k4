//  La ficha: el bicho a la izquierda y sus números a la derecha.
//
//  En columna no cabía nada y había que elegir qué enseñar. Partida en dos
//  caben las siete estadísticas Y el retrato, que es lo que uno quiere ver
//  cuando abre la ficha de su criatura.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    Row {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 8

        // ── el bicho ──────────────────────────────────────────────
        Column {
            width: parent.width * 0.42
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Criatura {
                width: parent.width
                height: 76
                especie: Digivice.especie
                durmiendo: Digivice.durmiendo
                enfermo: Digivice.enfermo
                lado: 68
                quieto: true
            }

            K4.Etiqueta {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Digivice.ficha ? Digivice.ficha.n : ""
                font.pixelSize: 13
                font.weight: Font.Bold
                color: "#d8f0de"
                elide: Text.ElideRight
            }

            K4.Etiqueta {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Digivice.etapa
                font.pixelSize: 12
                color: "#8fbf9c"
            }

            K4.Etiqueta {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Digivice.ficha ? (Digivice.ficha.a || "") : ""
                font.pixelSize: 12
                color: "#8fbf9c"
            }

            //  El carácter, que es SUYO: sale de su semilla y decide cuánto
            //  pide de comer, cuánto de mimo y qué le sienta mejor. Sin
            //  enseñarlo aquí sería una diferencia invisible, y una regla que
            //  no se ve no se puede jugar en contra.
            K4.Etiqueta {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Idioma.t(Digivice.caracter.nombre)
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: "#e8b45a"
            }

            K4.Etiqueta {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Idioma.t(Digivice.caracter.nota)
                font.pixelSize: 11
                color: "#5f8f6c"
            }
        }

        // ── los números ───────────────────────────────────────────
        Column {
            width: parent.width * 0.52
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Repeater {
                model: {
                    const st = Digivice.statsDe(Digivice.especie)
                    return [
                        { k: "PV",  v: st.vida },
                        { k: "ATQ", v: st.atq },
                        { k: "DEF", v: st.def },
                        { k: "VEL", v: st.vel },
                        { k: Idioma.t("ENT"), v: Digivice.entrenoTotal },
                        { k: Idioma.t("PESO"),
                          v: Digivice.peso + "/" + Digivice.pesoMinimo,
                          //  Rojo si le sobra: es el único número que puede
                          //  estar mal y conviene que se note sin leerlo.
                          mal: Digivice.excesoPeso >= 10 },
                        { k: Idioma.t("ENER"),
                          v: Digivice.energia + "/" + Digivice.maxEnergia }
                    ]
                }

                Row {
                    id: linea
                    required property var modelData
                    width: parent.width

                    K4.Etiqueta {
                        width: parent.width * 0.55
                        text: linea.modelData.k
                        font.pixelSize: 13
                        color: "#8fbf9c"
                    }
                    K4.Etiqueta {
                        width: parent.width * 0.45
                        horizontalAlignment: Text.AlignRight
                        text: linea.modelData.v
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: linea.modelData.mal ? "#e0806b" : "#d8f0de"
                    }
                }
            }

            Item { width: 1; height: 5 }

            K4.Etiqueta {
                width: parent.width
                text: Digivice.victorias + "V / " + Digivice.derrotas + "D"
                font.pixelSize: 12
                color: "#8fbf9c"
            }
            K4.Etiqueta {
                width: parent.width
                text: Idioma.t("desc") + " " + Digivice.errores
                    + "   ·   " + self.edadTexto
                font.pixelSize: 12
                color: "#5f8f6c"
            }

            //  Las técnicas que ha aprendido, que es lo que se gana
            //  entrenando además del número.
            K4.Etiqueta {
                width: parent.width
                visible: Digivice.ficha && Digivice.ficha.sk
                      && Digivice.ficha.sk.length > 0
                text: {
                    const f = Digivice.ficha
                    if (!f || !f.sk || !f.sk.length) return ""
                    const n = Digivice.tecnicasAbiertas(Digivice.especie)
                    return "▸ " + f.sk.slice(0, n).join("\n▸ ")
                }
                font.pixelSize: 11
                color: "#9fd8ae"
                wrapMode: Text.WordWrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }
        }
    }

    readonly property string edadTexto: {
        const s = Date.now() / 1000 - Digivice.nacidoEn
        const h = Math.floor(s / 3600)
        if (h < 1) return Math.floor(s / 60) + " min"
        if (h < 48) return h + " h"
        return Math.floor(h / 24) + " d"
    }
}
