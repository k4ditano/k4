//  Una tarjeta por agente, una fila por límite.
//
//  Lo que uno quiere saber son dos números: por dónde va y cuándo se le
//  perdona. Así que cada fila es el nombre de la ventana, su barra, su
//  porcentaje y cuándo reinicia —y nada más.
//
//  El reinicio va con las dos formas de decirlo, una encima de otra: el día y
//  la hora arriba y la cuenta atrás debajo. No sobra ninguna. «En 3 h 25 min»
//  no se cruza con la agenda de nadie, y «hoy a las 19:59» no dice si te da
//  tiempo a acabar lo que tienes abierto.
//
//  La ventana que está contando ahora mismo va en tinta y las demás en gris:
//  las cinco horas y la semana no aprietan a la vez, y distinguirlas de un
//  vistazo es media pregunta contestada.

import QtQuick
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    //  El reloj de la casa, a minutos. Se pasa como argumento a las funciones
    //  que lo necesitan para que el enlace se entere de que depende de él: una
    //  cuenta atrás que no se reevalúa se queda congelada en la hora de abrir.
    readonly property date ahora: Clock.date

    //  Verde hasta bien entrado, ámbar cuando queda menos de la mitad y rojo
    //  cuando ya conviene medir. Los cortes son los mismos para todos los
    //  agentes: si cada uno tuviera el suyo, el color dejaría de significar.
    function tono(pct) {
        if (pct >= 85) return Theme.red
        if (pct >= 60) return Theme.yellow
        return Theme.green
    }

    function cuanto(segundos, reloj) {
        if (!segundos)
            return ""

        const falta = segundos * 1000 - reloj.getTime()
        if (falta <= 0)
            return Idioma.t("reiniciando")

        const min = Math.round(falta / 60000)
        if (min < 60)
            return Idioma.f("en %1 min", min)

        const horas = Math.floor(min / 60)
        if (horas < 24) {
            const resto = min % 60
            return resto
                ? Idioma.f("en %1 h %2 min", horas, resto)
                : Idioma.f("en %1 h", horas)
        }

        const dias = Math.round(horas / 24)
        return dias === 1 ? Idioma.t("en 1 día")
                          : Idioma.f("en %1 días", dias)
    }

    //  Los días por su nombre, y en el idioma de la barra. `Qt.formatDate` los
    //  saca en el del sistema, que aquí ponía «Sun» en medio de una interfaz
    //  en español. Empieza en domingo porque así los numera `getDay()`.
    readonly property var nombresDia: [
        Idioma.t("dom"), Idioma.t("lun"), Idioma.t("mar"), Idioma.t("mié"),
        Idioma.t("jue"), Idioma.t("vie"), Idioma.t("sáb")
    ]

    //  El día y la hora del reinicio. Se dice como lo diría uno: «hoy» y
    //  «mañana» tienen nombre, la semana que viene se nombra por el día, y más
    //  allá ya hace falta la fecha.
    function cuando(segundos, reloj) {
        if (!segundos)
            return ""

        const d = new Date(segundos * 1000)
        const hora = Qt.formatTime(d, "HH:mm")

        //  Los días se cuentan de medianoche a medianoche, no por las horas
        //  que faltan: a las once de la noche, algo que reinicia dentro de tres
        //  horas es mañana, y decir «hoy» ahí sería mentira.
        const suyo = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const nuestro = new Date(reloj.getFullYear(), reloj.getMonth(), reloj.getDate())
        const dias = Math.round((suyo.getTime() - nuestro.getTime()) / 86400000)

        if (dias <= 0)
            return Idioma.f("hoy %1", hora)
        if (dias === 1)
            return Idioma.f("mañana %1", hora)
        if (dias < 7)
            return view.nombresDia[d.getDay()] + " " + hora
        //  Tan lejos no llega ninguna ventana de hoy, pero si mañana aparece
        //  una de un mes, la fecha en números no depende de ningún idioma.
        return Qt.formatDate(d, "d/M") + " " + hora
    }

    //  De cuándo es el dato. Sale siempre, también cuando es de hace un
    //  momento: quien lo lee tiene que saber que esto es una foto, no un
    //  contador en vivo.
    function frescura(segundos, reloj) {
        if (!segundos)
            return Idioma.t("sin fecha")

        const min = Math.round((reloj.getTime() - segundos * 1000) / 60000)
        if (min < 1)
            return Idioma.t("ahora mismo")
        if (min < 60)
            return Idioma.f("hace %1 min", min)

        const horas = Math.round(min / 60)
        if (horas < 24)
            return horas === 1 ? Idioma.t("hace 1 h")
                               : Idioma.f("hace %1 h", horas)

        const dias = Math.round(horas / 24)
        return dias === 1 ? Idioma.t("hace 1 día")
                          : Idioma.f("hace %1 días", dias)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 11
        anchors.bottomMargin: 12
        spacing: 8

        // ── cabecera ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF06A9)
                color: Theme.muted
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Idioma.t("Agentes")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Idioma.t("lo que llevas gastado de cada cupo")
                color: Theme.dim
                font.pixelSize: 10
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 14
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── una tarjeta por agente ────────────────────────────────
        Repeater {
            model: view.plugin.agentes

            delegate: Rectangle {
                id: tarjeta
                required property var modelData

                readonly property var limites: modelData.limites || []

                Layout.fillWidth: true
                Layout.preferredHeight: 40 + 28 * Math.max(1, limites.length)
                radius: 11
                color: Theme.surface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        spacing: 7

                        IslandLabel {
                            text: tarjeta.modelData.nombre
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        IslandLabel {
                            visible: !!tarjeta.modelData.plan
                            text: tarjeta.modelData.plan || ""
                            color: Theme.muted
                            font.pixelSize: 10
                        }

                        IslandLabel {
                            visible: !!tarjeta.modelData.creditos
                            text: Idioma.t("créditos ") + (tarjeta.modelData.creditos || "")
                            color: Theme.dim
                            font.pixelSize: 9
                        }

                        Item { Layout.fillWidth: true }

                        //  De dónde salió la cifra. Solo se dice cuando es de
                        //  la caché de la herramienta, que es cuando puede
                        //  llevar horas de retraso: preguntado al servidor,
                        //  «hace un momento» ya lo dice todo y añadir «en
                        //  vivo» sería ruido en la fila.
                        IslandLabel {
                            visible: tarjeta.modelData.fuente === "cache"
                            text: Idioma.t("caché")
                            color: Theme.dim
                            font.pixelSize: 9
                        }

                        IslandLabel {
                            text: view.frescura(tarjeta.modelData.actualizado, view.ahora)
                            color: Theme.dim
                            font.pixelSize: 9
                        }
                    }

                    //  Instalado pero sin haber hablado nunca con el servidor:
                    //  no hay porcentaje que enseñar y decirlo es la respuesta.
                    IslandLabel {
                        visible: !tarjeta.limites.length
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        text: Idioma.t("Sin datos todavía — úsalo una vez y aparecerán")
                        color: Theme.dim
                        font.pixelSize: 10
                        verticalAlignment: Text.AlignVCenter
                    }

                    Repeater {
                        model: tarjeta.limites

                        delegate: RowLayout {
                            id: fila
                            required property var modelData

                            readonly property real pct: Math.max(0, Math.min(100, modelData.pct || 0))

                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            spacing: 9

                            IslandLabel {
                                text: fila.modelData.nombre
                                //  La que cuenta ahora, en tinta; las demás, apagadas.
                                color: fila.modelData.activo ? Theme.ink : Theme.muted
                                font.pixelSize: 10
                                font.weight: fila.modelData.activo ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.preferredWidth: 78
                            }

                            K4.Medidor {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                valor: fila.pct
                                maximo: 100
                                grosor: 6
                                tono: view.tono(fila.pct)
                                //  Un cupo recién tocado sigue siendo un cupo
                                //  tocado: sin mínimo, un 0,4% no se ve y
                                //  parece que no has gastado nada.
                                minimo: 3
                            }

                            IslandLabel {
                                text: (fila.pct < 10 && fila.pct > 0
                                       ? fila.pct.toFixed(1) : Math.round(fila.pct)) + "%"
                                color: view.tono(fila.pct)
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 40
                            }

                            //  Cuándo se le perdona, en las dos formas. Sin
                            //  hueco entre las dos líneas: son el mismo dato
                            //  dicho dos veces, no dos cosas distintas.
                            ColumnLayout {
                                spacing: 0
                                Layout.preferredWidth: 92
                                Layout.alignment: Qt.AlignVCenter

                                IslandLabel {
                                    text: view.cuando(fila.modelData.reinicia, view.ahora)
                                    color: Theme.muted
                                    font.pixelSize: 10
                                    horizontalAlignment: Text.AlignRight
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 13
                                }

                                IslandLabel {
                                    text: view.cuanto(fila.modelData.reinicia, view.ahora)
                                    color: Theme.dim
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignRight
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 11
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // ── mientras no hay nada que enseñar ──────────────────────
        IslandLabel {
            visible: !view.plugin.cargado || !view.plugin.agentes.length
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: !view.plugin.cargado
                ? Idioma.t("Mirando…")
                : Idioma.t("No hay ningún CLI de agentes instalado")
            color: Theme.dim
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
