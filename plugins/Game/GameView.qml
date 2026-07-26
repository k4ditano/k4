import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    readonly property string spriteMonstruo: Game.enJefe
        ? "assets/jefes/b" + String(Game.spriteMonstruo).padStart(2, "0") + ".png"
        : "assets/monstruos/m" + String(Game.spriteMonstruo).padStart(2, "0") + ".png"

    readonly property real vidaFraccion: Game.vidaMaxima > 0
        ? Math.max(0, Math.min(1, Game.vidaActual / Game.vidaMaxima)) : 0

    // ── reacciones a la simulación ────────────────────────────────
    Connections {
        target: Game

        function onGolpeado(daño, critico) {
            destello.restart()
            retroceso.restart()
            numeros.lanzar(Game.cifra(daño), critico)
        }

        function onMuerto(oroGanado) {
            muerte.restart()
        }

        function onJefeFallado() {
            numeros.lanzar("¡se escapó!", true)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 16
        spacing: 10

        // ── cabecera
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 10

            IconGlyph {
                text: String.fromCodePoint(0xF04E5)      // md-sword
                color: Theme.muted
                font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Game.enJefe ? "Jefe de la zona " + Game.zona : "Zona " + Game.zona
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: Game.enJefe ? Theme.red : Theme.ink
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                visible: !Game.enJefe
                text: Game.muertes + "/" + Game.monstruosPorZona
                color: Theme.dim
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            IconGlyph {
                text: String.fromCodePoint(0xF0114)      // md-cash
                color: "#ffd60a"
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Game.cifra(Game.oro)
                font.pixelSize: 14
                font.weight: Font.DemiBold
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

        // ── aviso de lo ocurrido con la barra cerrada
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Game.resumenOffline ? 26 : 0
            visible: Game.resumenOffline !== null
            radius: 8
            color: Theme.surfaceHi

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 8

                IslandLabel {
                    Layout.fillWidth: true
                    text: Game.resumenOffline
                        ? "Mientras no estabas · " + Game.duracion(Game.resumenOffline.segundos)
                          + (Game.resumenOffline.tope ? " (tope)" : "")
                          + " · " + Game.cifra(Game.resumenOffline.oro) + " de oro y "
                          + Game.resumenOffline.muertes + " monstruos"
                        : ""
                    color: Theme.ink
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                MediaButton {
                    glyph: Theme.ico.close
                    glyphSize: 12
                    glyphColor: Theme.muted
                    onActivated: Game.resumenOffline = null
                }
            }
        }

        // ── cuerpo
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // ══ arena ══════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 300
                radius: 16
                color: Theme.surface
                clip: true

                // suelo, para que los bichos no floten en el vacío
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 52
                    color: Theme.surfaceHi
                    opacity: 0.5
                }

                MouseArea {
                    id: arena
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Game.golpear()
                }

                // ── el monstruo
                Item {
                    id: bicho
                    width: Game.enJefe ? 96 : 72
                    height: width
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 42

                    property real empuje: 0
                    property real aplastado: 1
                    transform: Translate { x: bicho.empuje }

                    // flotación en reposo
                    SequentialAnimation on anchors.bottomMargin {
                        running: true
                        loops: Animation.Infinite
                        NumberAnimation { to: 48; duration: 1200; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 42; duration: 1200; easing.type: Easing.InOutSine }
                    }

                    Image {
                        id: retrato
                        anchors.fill: parent
                        source: view.spriteMonstruo
                        fillMode: Image.PreserveAspectFit
                        smooth: false                 // pixel art: sin interpolar
                        mipmap: false
                        scale: bicho.aplastado
                        transformOrigin: Item.Bottom
                    }

                    // Destello al recibir el golpe. Va con MultiEffect sobre el
                    // propio sprite y no con un rectángulo encima: si no, lo
                    // que parpadea es el cuadro que lo contiene, no el bicho.
                    MultiEffect {
                        id: tinte
                        anchors.fill: parent
                        source: retrato
                        brightness: 0
                        saturation: -1
                        visible: brightness > 0
                        scale: bicho.aplastado
                        transformOrigin: Item.Bottom
                    }

                    NumberAnimation {
                        id: destello
                        target: tinte
                        property: "brightness"
                        from: 0.9
                        to: 0
                        duration: 150
                    }

                    SequentialAnimation {
                        id: retroceso
                        NumberAnimation { target: bicho; property: "empuje"; to: 5; duration: 45 }
                        NumberAnimation { target: bicho; property: "empuje"; to: 0; duration: 110
                            easing.type: Easing.OutCubic }
                    }

                    SequentialAnimation {
                        id: muerte
                        NumberAnimation { target: bicho; property: "aplastado"; to: 0.15
                            duration: 90; easing.type: Easing.InCubic }
                        NumberAnimation { target: bicho; property: "aplastado"; to: 1
                            duration: 180; easing.type: Easing.OutBack }
                    }
                }

                // ── números flotantes de daño
                Item {
                    id: numeros
                    anchors.fill: parent

                    property var plantilla: Qt.createComponent("NumeroFlotante.qml")

                    function lanzar(texto, critico) {
                        if (plantilla.status !== Component.Ready)
                            return
                        plantilla.createObject(numeros, {
                            texto: texto,
                            critico: critico === true,
                            x: numeros.width / 2 - 30 + (Math.random() * 50 - 25),
                            y: numeros.height - 130
                        })
                    }
                }

                // ── barra de vida
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true

                        IslandLabel {
                            text: Game.cifra(Game.vidaActual) + " / " + Game.cifra(Game.vidaMaxima)
                            color: Theme.muted
                            font.pixelSize: 10
                        }

                        Item { Layout.fillWidth: true }

                        IslandLabel {
                            visible: Game.enJefe
                            text: Math.ceil(Game.jefeRestante) + " s"
                            color: Game.jefeRestante < 8 ? Theme.red : Theme.muted
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        id: barra
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        radius: 4
                        color: Theme.islandBg

                        Rectangle {
                            width: parent.width * view.vidaFraccion
                            height: parent.height
                            radius: parent.radius
                            color: Game.enJefe ? Theme.red : Theme.green

                            Behavior on width { NumberAnimation { duration: 110 } }
                        }
                    }

                    // el tiempo del jefe, en su propia barra
                    Rectangle {
                        visible: Game.enJefe
                        Layout.fillWidth: true
                        Layout.preferredHeight: 3
                        radius: 2
                        color: Theme.islandBg

                        Rectangle {
                            width: parent.width * Math.max(0, Game.jefeRestante / Game.jefeSegundos)
                            height: parent.height
                            radius: parent.radius
                            color: "#ffd60a"
                        }
                    }
                }

                // ── el héroe, a la izquierda
                Image {
                    source: "assets/heroes/h00.png"
                    width: 56
                    height: 56
                    fillMode: Image.PreserveAspectFit
                    smooth: false
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 40

                    SequentialAnimation on anchors.bottomMargin {
                        running: true
                        loops: Animation.Infinite
                        NumberAnimation { to: 44; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 40; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
            }

            // ══ mejoras ════════════════════════════════════════════
            ColumnLayout {
                // sin fillWidth explícito se comería la arena: los layouts
                // anidados en otro layout lo traen activado por defecto
                Layout.fillWidth: false
                Layout.preferredWidth: 250
                Layout.fillHeight: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    IslandLabel { text: "Golpe"; color: Theme.muted; font.pixelSize: 10 }
                    IslandLabel {
                        text: Game.cifra(Game.dañoGolpe)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    IslandLabel { text: "Por segundo"; color: Theme.muted; font.pixelSize: 10 }
                    IslandLabel {
                        text: Game.cifra(Game.dps)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }

                Repeater {
                    model: Game.mejorasDef

                    delegate: Rectangle {
                        id: tarjeta
                        required property var modelData
                        readonly property bool asequible: Game.puedePagar(modelData.id)

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        color: compraMouse.containsMouse && asequible ? Theme.surfaceHi : Theme.surface
                        border.width: asequible ? 1 : 0
                        border.color: Theme.green

                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            IconGlyph {
                                text: String.fromCodePoint(tarjeta.modelData.glifo)
                                color: tarjeta.asequible ? Theme.ink : Theme.dim
                                font.pixelSize: 18
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    IslandLabel {
                                        text: tarjeta.modelData.nombre
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    IslandLabel {
                                        text: "nv " + Game.niveles[tarjeta.modelData.id]
                                        color: Theme.dim
                                        font.pixelSize: 10
                                    }
                                }

                                IslandLabel {
                                    text: tarjeta.modelData.desc
                                    color: Theme.muted
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            IslandLabel {
                                text: Game.cifra(Game.coste(tarjeta.modelData.id))
                                color: tarjeta.asequible ? "#ffd60a" : Theme.dim
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: compraMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: tarjeta.asequible ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: Game.comprar(tarjeta.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
