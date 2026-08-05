//  Elegir un vídeo del disco para editarlo.
//
//  Busca con el mismo motor que el buscador de ficheros —tools/buscar.py sobre
//  `fd`— pero con su propio proceso y no a través del singleton `Archivos`: ese
//  lo comparte el módulo de ficheros, y escribir ahí le borraría a alguien la
//  búsqueda que tenía a medias.
//
//  Y un botón para abrir el diálogo del sistema, porque buscar por nombre
//  supone que te acuerdas del nombre, y la mitad de las veces no.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    required property var plugin

    // Lo que se puede editar. Sin esto la lista se llena de .qml y de .py con
    // la palabra «video» dentro.
    //
    //  `k4v` va en la lista porque un proyecto guardado también se abre desde
    //  aquí. Faltaba, y era raro de la peor manera: guardabas un montaje, ibas a
    //  buscarlo por su nombre y no aparecía, así que parecía que no se había
    //  guardado. Estaba, solo que este buscador no lo miraba.
    readonly property string extensiones: "mp4,mkv,mov,webm,avi,m4v,k4v"

    property var lista: []
    property int index: 0
    property bool buscando: false

    // Sin esto hay que hacer clic antes de poder escribir: la raíz de la island
    // se queda el foco y la superficie tarda en recibirlo.
    FocoInicial { id: foco; objetivo: entrada }
    Component.onCompleted: foco.reclamar()

    function mover(d) {
        if (lista.length === 0)
            return
        index = Math.max(0, Math.min(lista.length - 1, index + d))
    }

    function elegir() {
        if (index < 0 || index >= lista.length)
            return
        view.plugin.abrirVideo(lista[index].ruta)
    }

    // ── buscar ────────────────────────────────────────────────────
    //
    //  Con rebote, como el buscador de ficheros: escribir «grabacion» son nueve
    //  pulsaciones y nueve recorridas de 187.000 ficheros no las quiere nadie.
    Timer {
        id: rebote
        interval: 160
        onTriggered: {
            if (entrada.text.trim().length < 2) {
                view.lista = []
                return
            }
            view.buscando = true
            buscador.running = false
            buscador.command = ["python3", K4.Paths.guion("buscar.py"),
                                entrada.text, "--solo", "archivo",
                                "--ext", view.extensiones, "--tope", "40"]
            buscador.running = true
        }
    }

    K4.Process {
        id: buscador
        onSalida: function (texto) {
            view.buscando = false
            let d = null
            try { d = JSON.parse(texto) } catch (e) { return }
            //  Se descarta la respuesta que no sea de lo último escrito: las
            //  búsquedas no vuelven en orden y una lenta de hace dos letras
            //  pisaría a la que ya está bien.
            if (d.consulta !== entrada.text)
                return
            view.lista = d.resultados || []
            view.index = 0
        }
    }

    // ── el diálogo del sistema ────────────────────────────────────
    //
    //  zenity y no un FileDialog de Qt: meter una ventana de diálogo dentro de
    //  una capa de layer-shell es justo donde aparecen los líos de foco que ya
    //  se pelean en la island. Por debajo zenity habla con el portal, así que
    //  sale el mismo selector que en cualquier otra aplicación.
    //
    //  Y lo lanza el PLUGIN, no esta vista: mientras el diálogo está abierto la
    //  island se aparta, y si la vista se destruyera con el proceso dentro, el
    //  aviso de «ha terminado» no llegaría y la barra no volvería nunca.
    function examinar() { view.plugin.pedirVideoDelDisco() }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        // ── cabecera ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF11D3)   // md-movie_search_outline
                color: Theme.blue
                font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter
            }

            TextInput {
                id: entrada
                cursorDelegate: IslandCursor {}
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                onTextEdited: rebote.restart()

                color: Theme.ink
                font.pixelSize: 15
                font.family: Theme.uiFont
                selectByMouse: true
                selectionColor: Theme.blue
                cursorVisible: true
                verticalAlignment: TextInput.AlignVCenter
                focus: true
                clip: true

                IslandLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: entrada.text.length === 0
                    text: Idioma.t("Buscar un vídeo o un proyecto…")
                    color: Theme.dim
                    font.pixelSize: 15
                }

                Keys.onPressed: function (ev) {
                    if (ev.key === Qt.Key_Down) {
                        view.mover(1); ev.accepted = true
                    } else if (ev.key === Qt.Key_Up) {
                        view.mover(-1); ev.accepted = true
                    } else if (ev.key === Qt.Key_PageDown) {
                        view.mover(6); ev.accepted = true
                    } else if (ev.key === Qt.Key_PageUp) {
                        view.mover(-6); ev.accepted = true
                    } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                        view.elegir(); ev.accepted = true
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: examinarTexto.implicitWidth + 30
                Layout.preferredHeight: 26
                radius: 13
                color: examinarRaton.containsMouse ? Theme.surfaceHi : Theme.surface

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    IconGlyph {
                        text: String.fromCodePoint(0xF0770)   // md-folder_open
                        color: Theme.muted
                        font.pixelSize: 13
                    }

                    IslandLabel {
                        id: examinarTexto
                        text: Idioma.t("Examinar…")
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: examinarRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.examinar()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(1, 1, 1, 0.07)
        }

        // ── los resultados ────────────────────────────────────────
        ListView {
            //  La barra de la casa: se ve solo si hay más de lo que cabe.
            ScrollBar.vertical: IslandScrollBar {}
            id: listado
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: view.lista
            currentIndex: view.index
            boundsBehavior: Flickable.StopAtBounds

            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: fila
                required property var modelData
                required property int index

                readonly property bool elegida: index === view.index

                width: ListView.view.width
                height: 48
                radius: 9
                color: elegida ? Theme.surfaceHi
                    : (filaRaton.containsMouse ? Theme.surface : "transparent")

                Behavior on color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 9

                    IconGlyph {
                        text: String.fromCodePoint(Archivos.glifo(fila.modelData))
                        color: Archivos.tono(fila.modelData)
                        font.pixelSize: 18
                        Layout.preferredWidth: 22
                        Layout.alignment: Qt.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        IslandLabel {
                            text: fila.modelData.nombre
                            font.pixelSize: 14
                            font.weight: fila.elegida ? Font.DemiBold : Font.Normal
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }

                        IslandLabel {
                            text: Archivos.dondeEsta(fila.modelData.carpeta)
                            color: Theme.dim
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }

                    IslandLabel {
                        text: Archivos.tamaño(fila.modelData.bytes)
                        color: Theme.muted
                        font.pixelSize: 11
                        Layout.preferredWidth: 70
                        horizontalAlignment: Text.AlignRight
                    }

                    IslandLabel {
                        text: Archivos.hace(fila.modelData.cuando)
                        color: Theme.dim
                        font.pixelSize: 11
                        Layout.preferredWidth: 60
                        horizontalAlignment: Text.AlignRight
                    }
                }

                MouseArea {
                    id: filaRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        view.index = fila.index
                        view.elegir()
                    }
                }
            }
        }

        // ── qué está pasando ──────────────────────────────────────
        IslandLabel {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: view.lista.length === 0
            text: view.buscando ? Idioma.t("Buscando…")
                : (entrada.text.trim().length < 2
                   ? Idioma.t("Escribe parte del nombre, o pulsa «Examinar…»")
                   : Idioma.t("Nada con ese nombre"))
            color: Theme.dim
            font.pixelSize: 12
        }
    }
}
