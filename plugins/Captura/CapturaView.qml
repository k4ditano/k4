//  Captura: el menú y el asomo de después.
//
//  El menú son tres tarjetas grandes —lo que vas a capturar— y debajo una fila
//  fina con el destino, que es un ajuste que se cambia poco y no merece el
//  mismo peso visual.

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    MediaPlayer {
        id: videoPreview
        source: view.plugin.modo === "video" && Captura.rutaVideo.length > 0
            ? "file://" + Captura.rutaVideo : ""
        videoOutput: videoPreviewOutput
        audioOutput: AudioOutput { muted: true }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia
                    || mediaStatus === MediaPlayer.BufferedMedia)
                play()
        }
    }

    focus: true

    Component.onCompleted: if (plugin.modo === "menu") forceActiveFocus()

    Keys.onPressed: function (ev) {
        if (view.plugin.modo !== "menu")
            return

        if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Tab) {
            view.plugin.avanzar(); ev.accepted = true
        } else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Backtab) {
            view.plugin.retroceder(); ev.accepted = true
        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter
                   || ev.key === Qt.Key_Space) {
            view.plugin.elegir(); ev.accepted = true
        }
    }

    // ── el menú ───────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8
        visible: view.plugin.modo === "menu"

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            spacing: 8

            IslandLabel {
                text: Idioma.t("Capturar")
                color: Theme.muted
                font.pixelSize: 11
            }

            Item { Layout.fillWidth: true }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
            }
        }

        // ── qué capturar ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            Repeater {
                model: view.plugin.ambitos

                delegate: IslandTile {
                    id: casilla
                    required property var modelData
                    required property int index

                    readonly property bool elegida: index === view.plugin.index

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    activa: elegida

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        visible: casilla.elegida
                        border.width: 1
                        border.color: Theme.blue
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        spacing: 7

                        IconGlyph {
                            Layout.alignment: Qt.AlignHCenter
                            text: String.fromCodePoint(casilla.modelData.icono)
                            color: casilla.elegida ? Theme.ink : Theme.muted
                            font.pixelSize: 28
                        }

                        IslandLabel {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: casilla.modelData.texto
                            font.pixelSize: 12
                            font.weight: casilla.elegida ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    onPulsada: view.plugin.disparar(casilla.modelData.clave)
                    onHoveredChanged: if (hovered) view.plugin.index = index
                }
            }
        }

        // ── a dónde va ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 6

            IslandLabel {
                text: Idioma.t("Destino")
                color: Theme.dim
                font.pixelSize: 9
                Layout.rightMargin: 2
            }

            Repeater {
                model: view.plugin.destinos

                delegate: Rectangle {
                    id: chip
                    required property var modelData

                    readonly property bool puesto: Captura.destino === modelData.clave

                    Layout.preferredWidth: chipFila.implicitWidth + 16
                    Layout.preferredHeight: 22
                    radius: 11
                    color: puesto ? Theme.blue
                        : (chipRaton.containsMouse ? Theme.surfaceHi : Theme.surface)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        id: chipFila
                        anchors.centerIn: parent
                        spacing: 5

                        IconGlyph {
                            text: String.fromCodePoint(chip.modelData.icono)
                            color: chip.puesto ? Theme.ink : Theme.muted
                            font.pixelSize: 12
                        }

                        IslandLabel {
                            text: chip.modelData.texto
                            color: chip.puesto ? Theme.ink : Theme.muted
                            font.pixelSize: 10
                            font.weight: chip.puesto ? Font.DemiBold : Font.Normal
                        }
                    }

                    MouseArea {
                        id: chipRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.poner("capturaDestino",
                                                  chip.modelData.clave)
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Grabar vive aquí y no como una cuarta tarjeta arriba: es otra
            // cosa —empieza algo que dura— y mezclarlo con las tres de foto
            // invita a pulsarlo por error.
            Rectangle {
                Layout.preferredWidth: grabarFila.implicitWidth + 18
                Layout.preferredHeight: 24
                radius: 12
                color: grabarRaton.containsMouse ? "#3a1416" : Theme.surface
                border.width: 1
                border.color: Qt.rgba(1, 0.27, 0.23, 0.35)

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    id: grabarFila
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 9
                        Layout.preferredHeight: 9
                        radius: 4.5
                        color: Theme.red
                    }

                    IslandLabel {
                        text: Idioma.t("Grabar")
                        color: Theme.ink
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: grabarRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function (raton) {
                        view.plugin.close()
                        // Clic derecho para grabar solo un trozo: pasa por el
                        // mismo selector que las fotos.
                        if (raton.button === Qt.RightButton)
                            Captura.grabarRegion()
                        else
                            Captura.grabar("")
                    }
                }
            }

            IslandLabel {
                text: Idioma.t("← → elige · intro captura")
                color: Theme.dim
                font.pixelSize: 9
            }
        }
    }

    // ── la cuenta atrás ───────────────────────────────────────────
    //
    //  Ocurre antes de arrancar wf-recorder, así que el 3-2-1 no sale en el
    //  vídeo. Sirve para colocar la ventana y apartar el ratón.
    Item {
        anchors.fill: parent
        visible: view.plugin.modo === "cuenta"

        IslandLabel {
            id: numero
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -8
            text: Captura.cuentaAtras
            color: Theme.ink
            font.pixelSize: 72
            font.weight: Font.Light

            // Un salto por segundo: sin él no se distingue un 3 de un 2 con el
            // rabillo del ojo, que es como se mira una cuenta atrás.
            scale: 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            onTextChanged: { scale = 1.35; rebote.restart() }

            Timer {
                id: rebote
                interval: 40
                onTriggered: numero.scale = 1
            }
        }

        IslandLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            text: Idioma.t("esc cancela")
            color: Theme.dim
            font.pixelSize: 10
        }
    }

    // ── el asomo de después ───────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        visible: view.plugin.modo === "hecha"

        // La miniatura de verdad, no un icono: es lo que confirma de un
        // vistazo que has capturado lo que querías y no el escritorio vacío.
        Rectangle {
            Layout.preferredWidth: 160
            Layout.preferredHeight: 90
            radius: 8
            color: Theme.surface
            clip: true

            Image {
                anchors.fill: parent
                anchors.margins: 1
                // El sello de fecha ya hace único cada nombre, así que la
                // caché de Qt no puede devolver una imagen vieja.
                source: Captura.ultimaRuta.length > 0
                    ? "file://" + Captura.ultimaRuta : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                mipmap: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            IslandLabel {
                text: {
                    if (Captura.ultimaCopiada && Captura.ultimaRuta.length > 0)
                        return Idioma.t("Copiada y guardada")
                    if (Captura.ultimaCopiada)
                        return Idioma.t("Copiada")
                    return Idioma.t("Guardada")
                }
                color: Theme.ink
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            IslandLabel {
                Layout.fillWidth: true
                text: Captura.ultimaAncho + " × " + Captura.ultimaAlto
                    + (Captura.ultimaRuta.length > 0
                       ? " · " + Captura.ultimaRuta.split("/").pop() : "")
                color: Theme.dim
                font.pixelSize: 10
                elide: Text.ElideMiddle
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                spacing: 6

                Repeater {
                    model: [
                        { texto: Idioma.t("Anotar"),  icono: 0xF03EB, accion: "anotar" },
                        { texto: Idioma.t("Abrir"),   icono: 0xF03CC, accion: "abrir" },
                        { texto: Idioma.t("Carpeta"), icono: 0xF024B, accion: "carpeta" },
                        { texto: Idioma.t("Copiar"),  icono: 0xF018F, accion: "copiar" }
                    ]

                    delegate: Rectangle {
                        id: boton
                        required property var modelData

                        // Sin fichero en disco no hay nada que anotar ni que
                        // abrir: solo quedaría en el portapapeles.
                        readonly property bool util: Captura.ultimaRuta.length > 0

                        Layout.preferredWidth: botonFila.implicitWidth + 16
                        Layout.preferredHeight: 24
                        radius: 12
                        opacity: util ? 1 : 0.35
                        color: botonRaton.containsMouse && util
                            ? Theme.surfaceHi : Theme.surface

                        RowLayout {
                            id: botonFila
                            anchors.centerIn: parent
                            spacing: 5

                            IconGlyph {
                                text: String.fromCodePoint(boton.modelData.icono)
                                color: Theme.muted
                                font.pixelSize: 12
                            }

                            IslandLabel {
                                text: boton.modelData.texto
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: botonRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: boton.util
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const a = boton.modelData.accion
                                if (a === "anotar")       Captura.anotar(Captura.ultimaRuta)
                                else if (a === "abrir")   Captura.abrir(Captura.ultimaRuta)
                                else if (a === "carpeta") Captura.abrirCarpeta()
                                else if (a === "copiar")  Captura.copiar(Captura.ultimaRuta)
                                view.plugin.close()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── el asomo de después de grabar un vídeo ────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        visible: view.plugin.modo === "video"

        Rectangle {
            Layout.preferredWidth: 200
            Layout.preferredHeight: 112
            Layout.alignment: Qt.AlignVCenter
            radius: 8
            color: Theme.surface
            clip: true

            VideoOutput {
                id: videoPreviewOutput
                anchors.fill: parent
                anchors.margins: 1
                fillMode: VideoOutput.PreserveAspectFit
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            IslandLabel {
                text: Idioma.t("Grabación guardada")
                color: Theme.ink
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            IslandLabel {
                Layout.fillWidth: true
                text: Captura.rutaVideo.length > 0
                    ? Captura.rutaVideo.split("/").pop() : ""
                color: Theme.dim
                font.pixelSize: 10
                elide: Text.ElideMiddle
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                spacing: 6

                Repeater {
                    model: [
                        { texto: Idioma.t("Editor"),  icono: 0xF1122, accion: "editor" },
                        { texto: Idioma.t("Abrir"),   icono: 0xF03CC, accion: "abrir" },
                        { texto: Idioma.t("Carpeta"), icono: 0xF024B, accion: "carpeta" }
                    ]

                    delegate: Rectangle {
                        id: videoBoton
                        required property var modelData
                        readonly property bool util: Captura.rutaVideo.length > 0

                        Layout.preferredWidth: videoBotonFila.implicitWidth + 16
                        Layout.preferredHeight: 24
                        radius: 12
                        opacity: util ? 1 : 0.35
                        color: videoBotonRaton.containsMouse && util
                            ? Theme.surfaceHi : Theme.surface

                        RowLayout {
                            id: videoBotonFila
                            anchors.centerIn: parent
                            spacing: 5

                            IconGlyph {
                                text: String.fromCodePoint(videoBoton.modelData.icono)
                                color: Theme.muted
                                font.pixelSize: 12
                            }

                            IslandLabel {
                                text: videoBoton.modelData.texto
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: videoBotonRaton
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: videoBoton.util
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const a = videoBoton.modelData.accion
                                if (a === "editor")       view.plugin.editarUltimaGrabacion()
                                else if (a === "abrir")   Captura.abrir(Captura.rutaVideo)
                                else if (a === "carpeta") Captura.abrirCarpetaVideos()
                                if (a !== "editor") view.plugin.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
