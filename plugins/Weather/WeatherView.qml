import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    // Los glifos del tiempo son de la familia weather-*, que en esta fuente
    // tiene el trazo más fino: piden un punto más de tamaño que el resto.
    component Glyph: Text {
        textFormat: Text.PlainText
        color: Theme.ink
        font.family: Theme.iconFont
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    function weekday(iso, index) {
        if (index === 0)
            return "Hoy"
        // mediodía, para que el huso no lo mueva de día
        return new Date(iso + "T12:00:00").toLocaleDateString(Idioma.locale, "ddd")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 16
        spacing: 12

        // ── cabecera
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 30
            spacing: 10

            IconGlyph {
                text: Theme.ico.place
                color: Theme.muted
                font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Weather.place.length > 0 ? Weather.place : Idioma.t("Sin ubicación")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Weather.region
                color: Theme.muted
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.maximumWidth: 220
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            IslandLabel {
                visible: Weather.updated.length > 0 && !Weather.loading
                text: Idioma.t("actualizado ") + Weather.updated
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                visible: Weather.loading
                text: Idioma.t("cargando…")
                color: Theme.dim
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter

                SequentialAnimation on opacity {
                    running: Weather.loading
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 620; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 620; easing.type: Easing.InOutSine }
                }
            }

            MediaButton {
                glyph: Theme.ico.search
                glyphSize: 15
                glyphColor: view.plugin.searchOpen ? Theme.ink : Theme.muted
                onActivated: view.plugin.searchOpen
                    ? view.plugin.closeSearch() : view.plugin.openSearch()
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.loading
                glyphSize: 15
                glyphColor: Theme.muted
                onActivated: Weather.refresh()
                Layout.alignment: Qt.AlignVCenter
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 16
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ══ BUSCADOR ═══════════════════════════════════════════════
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: Theme.surface
            visible: view.plugin.searchOpen

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    IconGlyph {
                        text: Theme.ico.search
                        color: Theme.muted
                        font.pixelSize: 18
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28

                        IslandLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: view.plugin.query.length === 0
                            text: Idioma.t("Escribe una ciudad…")
                            color: Theme.dim
                            font.pixelSize: 17
                        }

                        TextInput {
                            id: cityInput
                            cursorDelegate: IslandCursor {}
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.ink
                            font.family: Theme.uiFont
                            font.pixelSize: 17
                            //  Atado al buscador, y no un `true` fijo: un
                            //  TextInput NO suelta el foco al ocultarse —
                            //  medido, la ventana lo seguía dando por
                            //  enfocado—, así que se quedaba con él para
                            //  siempre y se tragaba todos los ESC ahí abajo.
                            focus: view.plugin.searchOpen
                            clip: true
                            selectByMouse: true
                            cursorVisible: true
                            selectionColor: Theme.blue
                            text: view.plugin.query
                            onTextEdited: {
                                view.plugin.query = text
                                debounce.restart()
                            }

                            //  El foco, solo cuando el buscador está DELANTE.
                            //
                            //  Este campo se instancia siempre —el bloque de
                            //  arriba se oculta con `visible`, no se destruye—,
                            //  así que pedirlo al completarse se lo llevaba
                            //  nada más abrir el tiempo, con el buscador
                            //  cerrado y el campo invisible. Y entonces se
                            //  tragaba todos los ESC en su `Keys.onPressed`
                            //  —cerrar un buscador ya cerrado no hace nada,
                            //  pero marca la tecla como atendida—, así que el
                            //  ESC que cierra el módulo no llegaba nunca.
                            //  Invisible y mudo, pero se lo quedaba todo.
                            onVisibleChanged: if (visible)
                                Qt.callLater(function () { cityInput.forceActiveFocus() })

                            Keys.onPressed: function (event) {
                                if (event.key === Qt.Key_Escape) {
                                    view.plugin.closeSearch()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (Weather.matches.length > 0)
                                        view.plugin.choose(Weather.matches[0])
                                    event.accepted = true
                                }
                            }

                            // no se consulta en cada tecla: se espera a que pares
                            Timer {
                                id: debounce
                                interval: 350
                                onTriggered: Weather.search(view.plugin.query)
                            }
                        }
                    }

                    IslandLabel {
                        text: Weather.searching ? Idioma.t("buscando…") : "esc"
                        color: Theme.dim
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.surfaceHi }

                ListView {
                    //  La barra de la casa: sale sola si hay más de lo que cabe.
                    ScrollBar.vertical: IslandScrollBar {}
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: Weather.matches
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: cityRow
                        required property var modelData
                        width: ListView.view.width
                        height: 44
                        radius: 10
                        color: cityMouse.containsMouse ? Theme.surfaceHi : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            IconGlyph {
                                text: Theme.ico.place
                                color: Theme.muted
                                font.pixelSize: 15
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0

                                IslandLabel {
                                    text: cityRow.modelData.name
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }

                                IslandLabel {
                                    text: cityRow.modelData.region
                                    color: Theme.muted
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            IconGlyph {
                                visible: cityMouse.containsMouse
                                text: Theme.ico.enter
                                color: Theme.muted
                                font.pixelSize: 14
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: cityMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.plugin.choose(cityRow.modelData)
                        }
                    }

                    IslandLabel {
                        anchors.centerIn: parent
                        visible: Weather.matches.length === 0
                        text: view.plugin.query.length < 2
                            ? Idioma.t("Escribe al menos dos letras")
                            : Weather.searching ? Idioma.t("Buscando…") : Idioma.t("Ninguna ciudad coincide")
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
            }
        }

        // ══ EL TIEMPO ══════════════════════════════════════════════
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            visible: !view.plugin.searchOpen

            // ── ahora
            Rectangle {
                Layout.preferredWidth: 270
                Layout.fillHeight: true
                radius: 16
                color: Theme.surface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 2

                    Glyph {
                        text: Weather.current
                            ? Weather.icon(Weather.current.code, Weather.current.isDay)
                            : String.fromCodePoint(0xE374)
                        font.pixelSize: 54
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredHeight: 62
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 0

                        IslandLabel {
                            text: Weather.current ? Weather.current.temp : "—"
                            font.pixelSize: 46
                            font.weight: Font.Light
                        }

                        IslandLabel {
                            text: "°"
                            color: Theme.muted
                            font.pixelSize: 30
                            font.weight: Font.Light
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 6
                        }
                    }

                    IslandLabel {
                        text: Weather.current ? Weather.describe(Weather.current.code) : Weather.error
                        color: Weather.error.length > 0 && !Weather.current ? Theme.red : Theme.ink
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    IslandLabel {
                        visible: Weather.current !== null
                        text: Idioma.t("sensación de ") + (Weather.current ? Weather.current.feels : 0) + "°"
                        color: Theme.muted
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Item { Layout.fillHeight: true }

                    // humedad · viento · lluvia
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        visible: Weather.current !== null

                        Repeater {
                            model: Weather.current ? [
                                { g: 0xE373, v: Weather.current.humidity + "%", l: "humedad" },
                                { g: 0xE34B, v: Weather.current.wind + "", l: "km/h" },
                                { g: 0xE37C, v: Weather.current.precip + "", l: "mm" }
                            ] : []

                            // Cada columna acota su ancho y centra el texto dentro:
                            // dejándolo al implicitWidth, las etiquetas se pisan.
                            delegate: ColumnLayout {
                                id: stat
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 1

                                Glyph {
                                    text: String.fromCodePoint(stat.modelData.g)
                                    color: Theme.muted
                                    font.pixelSize: 15
                                    Layout.fillWidth: true
                                }

                                IslandLabel {
                                    text: stat.modelData.v
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                }

                                IslandLabel {
                                    text: stat.modelData.l
                                    color: Theme.dim
                                    font.pixelSize: 9
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }

            // ── por horas y por días
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 116
                    radius: 16
                    color: Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 0

                        Repeater {
                            model: Weather.hourly

                            delegate: ColumnLayout {
                                id: hourCell
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 3

                                IslandLabel {
                                    text: hourCell.modelData.hour
                                    color: Theme.muted
                                    font.pixelSize: 10
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Glyph {
                                    text: Weather.icon(hourCell.modelData.code, hourCell.modelData.isDay)
                                    font.pixelSize: 20
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredHeight: 26
                                }

                                IslandLabel {
                                    text: hourCell.modelData.temp + "°"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                IslandLabel {
                                    // el 0 % no aporta nada: solo estorba
                                    visible: hourCell.modelData.rain > 0
                                    text: hourCell.modelData.rain + "%"
                                    color: Theme.blue
                                    font.pixelSize: 9
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        IslandLabel {
                            visible: Weather.hourly.length === 0
                            text: Idioma.t("Sin previsión horaria")
                            color: Theme.muted
                            font.pixelSize: 12
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Theme.surface

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 0

                        Repeater {
                            model: Weather.daily

                            delegate: RowLayout {
                                id: dayRow
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 10

                                IslandLabel {
                                    text: view.weekday(dayRow.modelData.date, dayRow.index)
                                    color: dayRow.index === 0 ? Theme.ink : Theme.muted
                                    font.pixelSize: 12
                                    font.weight: dayRow.index === 0 ? Font.DemiBold : Font.Normal
                                    font.capitalization: Font.Capitalize
                                    Layout.preferredWidth: 46
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Glyph {
                                    text: Weather.icon(dayRow.modelData.code, true)
                                    font.pixelSize: 16
                                    Layout.preferredWidth: 24
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                IslandLabel {
                                    text: Weather.describe(dayRow.modelData.code)
                                    color: Theme.muted
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                IslandLabel {
                                    text: dayRow.modelData.min + "°"
                                    color: Theme.dim
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: 30
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // barra del rango del día, situada dentro del
                                // mínimo y el máximo de toda la semana
                                Item {
                                    Layout.preferredWidth: 90
                                    Layout.preferredHeight: 4
                                    Layout.alignment: Qt.AlignVCenter

                                    readonly property real lo: Weather.daily.length > 0
                                        ? Math.min.apply(null, Weather.daily.map(function (d) { return d.min })) : 0
                                    readonly property real hi: Weather.daily.length > 0
                                        ? Math.max.apply(null, Weather.daily.map(function (d) { return d.max })) : 1
                                    readonly property real span: Math.max(1, hi - lo)

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 2
                                        color: Theme.surfaceHi
                                    }

                                    Rectangle {
                                        x: parent.width * (dayRow.modelData.min - parent.lo) / parent.span
                                        width: Math.max(4, parent.width
                                            * (dayRow.modelData.max - dayRow.modelData.min) / parent.span)
                                        height: parent.height
                                        radius: 2
                                        color: Theme.ink
                                    }
                                }

                                IslandLabel {
                                    text: dayRow.modelData.max + "°"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: 30
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }

                        IslandLabel {
                            visible: Weather.daily.length === 0
                            text: Weather.error.length > 0 ? Weather.error : Idioma.t("Sin previsión")
                            color: Weather.error.length > 0 ? Theme.red : Theme.muted
                            font.pixelSize: 12
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
