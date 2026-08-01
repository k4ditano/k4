//  El digivice abierto: marco de aparato con botonera decorativa, pantalla
//  de fósforo con rejilla, la criatura respirando en el centro y el panel
//  de crianza a la derecha. La vista pregunta al servicio y no decide nada.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    property real ahora: Date.now() / 1000
    property bool alterno: false
    Timer {
        interval: 800
        repeat: true
        running: view.visible
        onTriggered: {
            view.ahora = Date.now() / 1000
            view.alterno = !view.alterno
        }
    }

    readonly property color acento: Kmon.formaActual.color || "#5ac8fa"
    //  La paleta del fósforo: cristal claro, tinta oscura — la estética de
    //  las pantallas de tamer de los 90.
    readonly property color fosforo: "#a9b39c"
    readonly property color tinta: "#2e332a"

    // ── el aparato ────────────────────────────────────────────────
    Rectangle {
        id: aparato
        anchors.fill: parent
        anchors.margins: 12
        radius: 18
        gradient: Gradient {
            GradientStop { position: 0; color: "#33363c" }
            GradientStop { position: 1; color: "#23252a" }
        }
        border.width: 1
        border.color: "#4a4e56"

        //  Botonera decorativa del lateral: un digivice tiene botones.
        Column {
            anchors.right: parent.right
            anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                model: 3
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: "#191b1e"
                    border.width: 1
                    border.color: "#54585f"
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 26
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            spacing: 16

            // ── la pantalla ───────────────────────────────────────
            Rectangle {
                id: pantalla
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                radius: 12
                color: view.fosforo
                border.width: 3
                border.color: "#23251f"
                clip: true

                //  La matriz de celdas del LCD, visible en TODA la pantalla:
                //  es lo que hace que el cristal parezca un aparato de verdad
                //  y no un rectángulo pintado. Líneas en las dos direcciones,
                //  paso 7 — baratas y suficientes.
                Repeater {
                    model: Math.ceil(pantalla.width / 7)
                    Rectangle {
                        required property int index
                        x: index * 7; y: 0
                        width: 1; height: pantalla.height
                        color: view.tinta
                        opacity: 0.055
                    }
                }
                Repeater {
                    model: Math.ceil(pantalla.height / 7)
                    Rectangle {
                        required property int index
                        x: 0; y: index * 7
                        width: pantalla.width; height: 1
                        color: view.tinta
                        opacity: 0.055
                    }
                }

                //  La sombra de la criatura, pegada a sus pies.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: criatura.bottom
                    anchors.topMargin: -14
                    width: criatura.width * 0.6; height: 10; radius: 5
                    color: view.tinta
                    opacity: 0.15
                }

                //  La criatura (o el huevo), respirando.
                Image {
                    id: criatura
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -8
                    source: {
                        view.ahora
                        return Qt.resolvedUrl("assets/"
                                              + Kmon.spriteLcd(view.alterno))
                    }
                    //  A lo GRANDE y con vecino próximo: los píxeles gruesos
                    //  del sprite son la estética, no un defecto. sourceSize
                    //  nativo — escalar decodificando emborrona.
                    width: 190
                    height: 190
                    fillMode: Image.PreserveAspectFit
                    smooth: false

                    SequentialAnimation on scale {
                        running: view.visible
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: Kmon.etapa === "huevo" ? 1.06 : 0.96
                            duration: Kmon.etapa === "huevo" ? 600 : 1500
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            to: 1.0
                            duration: Kmon.etapa === "huevo" ? 600 : 1500
                            easing.type: Easing.InOutQuad
                        }
                    }

                    //  Tocar la pantalla es tocar a la criatura.
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Kmon.tocar()
                            if (Kmon.etapa === "huevo")
                                latido.start()
                        }
                    }

                    SequentialAnimation {
                        id: latido
                        NumberAnimation { target: criatura; property: "scale"; to: 1.18; duration: 90; easing.type: Easing.OutQuad }
                        NumberAnimation { target: criatura; property: "scale"; to: 1.0; duration: 220; easing.type: Easing.OutBounce }
                    }
                }

                //  Scanlines del cristal, suaves sobre claro.
                Column {
                    anchors.fill: parent
                    spacing: 5
                    Repeater {
                        model: Math.ceil(pantalla.height / 6)
                        Rectangle {
                            width: pantalla.width
                            height: 1
                            color: view.tinta
                            opacity: 0.07
                        }
                    }
                }

                //  Estado en la esquina, tinta sobre fósforo.
                IslandLabel {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 9
                    text: Kmon.estadoTexto
                    color: view.tinta
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }

                //  Con el huevo: el contador de incubación.
                IslandLabel {
                    visible: Kmon.etapa === "huevo"
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 9
                    text: Math.round(Kmon.incubacion * 100) + "%"
                    color: view.tinta
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                //  El flash de los momentos grandes.
                Rectangle {
                    id: flash
                    anchors.fill: parent
                    color: "#ffffff"
                    opacity: 0

                    SequentialAnimation {
                        id: fogonazo
                        NumberAnimation { target: flash; property: "opacity"; to: 0.95; duration: 120 }
                        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 700; easing.type: Easing.OutQuad }
                    }
                }

                Connections {
                    target: Kmon
                    function onEclosion() { fogonazo.start() }
                    function onDigievolucion(desde, hacia) { fogonazo.start() }
                }
            }

            // ── el panel de crianza ───────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    IslandLabel {
                        text: Kmon.formaActual.nombre
                        font.pixelSize: 17
                        font.weight: Font.Bold
                    }

                    Rectangle {
                        Layout.preferredWidth: etiquetaEtapa.implicitWidth + 14
                        Layout.preferredHeight: 17
                        radius: 9
                        color: Qt.rgba(Qt.color(view.acento).r,
                            Qt.color(view.acento).g, Qt.color(view.acento).b, 0.25)

                        IslandLabel {
                            id: etiquetaEtapa
                            anchors.centerIn: parent
                            text: Kmon.etapa === "huevo" ? Idioma.t("huevo")
                                : Kmon.etapa === "bebe" ? Idioma.t("bebé")
                                : Idioma.t("niño")
                            color: view.acento
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }

                    Item { Layout.fillWidth: true }

                    MediaButton {
                        glyph: Theme.ico.close
                        glyphSize: 15
                        glyphColor: Theme.muted
                        onActivated: view.plugin.close()
                    }
                }

                IslandLabel {
                    visible: Kmon.etapa !== "huevo"
                    text: Idioma.f(Idioma.t("edad %1 h · %2 kg · %3 comidas"),
                                   Math.floor(Kmon.edadHoras), Kmon.peso,
                                   Kmon.comidas)
                    color: Theme.dim
                    font.pixelSize: 10
                }

                IslandLabel {
                    visible: Kmon.etapa === "huevo"
                    text: Idioma.t("Tócalo para animarlo a salir")
                    color: Theme.dim
                    font.pixelSize: 10
                }

                Item { Layout.preferredHeight: 2 }

                //  Barras segmentadas, de aparato de los 2000.
                Repeater {
                    model: [
                        { nombre: Idioma.t("Hambre"), valor: Kmon.hambre, color: Theme.yellow },
                        { nombre: Idioma.t("Energía"), valor: Kmon.energia, color: Theme.green },
                        { nombre: Idioma.t("Disciplina"), valor: Kmon.disciplina, color: Theme.blue }
                    ]

                    delegate: RowLayout {
                        id: barra
                        required property var modelData
                        visible: Kmon.etapa !== "huevo"
                        Layout.fillWidth: true
                        spacing: 8

                        IslandLabel {
                            text: barra.modelData.nombre
                            color: Theme.muted
                            font.pixelSize: 10
                            Layout.preferredWidth: 64
                        }

                        Row {
                            spacing: 3
                            Repeater {
                                model: 10
                                Rectangle {
                                    required property int index
                                    width: 13; height: 8; radius: 2
                                    color: index < Math.round(barra.modelData.valor / 10)
                                        ? barra.modelData.color : Theme.track
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                //  Acciones.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: Kmon.etapa === "huevo"
                            ? [{ t: Idioma.t("Tocar"), a: "tocar" }]
                            : [{ t: Idioma.t("Dar de comer"), a: "comer" },
                               { t: Idioma.t("Jugar"), a: "tocar" }]

                        delegate: Rectangle {
                            id: boton
                            required property var modelData
                            Layout.preferredWidth: textoBoton.implicitWidth + 30
                            Layout.preferredHeight: 30
                            radius: 15
                            color: botonRaton.containsMouse
                                ? Qt.rgba(Qt.color(view.acento).r,
                                    Qt.color(view.acento).g,
                                    Qt.color(view.acento).b, 0.35)
                                : Theme.surface
                            border.width: 1
                            border.color: botonRaton.containsMouse
                                ? view.acento : Theme.track

                            Behavior on color { ColorAnimation { duration: 120 } }

                            IslandLabel {
                                id: textoBoton
                                anchors.centerIn: parent
                                text: boton.modelData.t
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: botonRaton
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Kmon[boton.modelData.a]()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    //  Lo que viene, sin mentir: apagado hasta su fase.
                    Repeater {
                        model: [Idioma.t("Entrenar"), Idioma.t("Digitario")]
                        IslandLabel {
                            required property var modelData
                            text: modelData
                            color: Theme.dim
                            font.pixelSize: 10
                            opacity: 0.5
                        }
                    }
                }
            }
        }
    }
}
