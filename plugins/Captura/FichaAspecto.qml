//  El aspecto de una capa: lo que se le hace por ser ella.
//
//  Los efectos de entrada y salida dicen CÓMO llega y CÓMO se va; esto dice
//  cómo se ve mientras está. Vale igual para una imagen, un vídeo incrustado y
//  una forma —las tres pasan por la misma tubería al renderizar—, y por eso
//  está en un fichero y no repetido en la ficha de cada una.
//
//  Sin título propio: va dentro de la sección «Aspecto» de la ficha, y dos
//  cabeceras seguidas diciendo lo mismo es una de más.
//
//  Cada control escribe un campo del plan y ya está: `filtro`, `mascara`,
//  `marco`, `colorMarco`, `espejo`. Python los traduce a filtros de ffmpeg y la
//  previa hace la misma cuenta, que es la regla de la casa.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    id: aspecto

    //  Un rótulo no entra aquí: su aspecto son los estilos —caja, contorno,
    //  sombra— que tiene más arriba, y darle además un marco y una máscara
    //  sería ofrecer dos maneras de lo mismo. Una forma tampoco: es un trazo
    //  de un color, y redondearle las esquinas a una flecha no quiere decir
    //  nada.
    readonly property bool aplica: Editor.capaSel
        && (Editor.capaSel.tipo === "imagen"
            || Editor.capaSel.tipo === "video")

    visible: aplica
    Layout.fillWidth: true
    spacing: 4

    //  Las dos filas de chips: el color y la forma. Se pintan con el mismo
    //  molde porque son lo mismo —elegir uno de varios— y así una fila nueva
    //  es una línea de datos, no otro bloque de QML.
    Repeater {
        model: [
            { campo: "filtro", porDefecto: "",
              opciones: [{ id: "", nombre: Idioma.t("Normal") },
                         { id: "gris", nombre: Idioma.t("B/N") },
                         { id: "sepia", nombre: Idioma.t("Sepia") },
                         { id: "vivo", nombre: Idioma.t("Vivo") },
                         { id: "frio", nombre: Idioma.t("Frío") },
                         { id: "calido", nombre: Idioma.t("Cálido") }] },
            { campo: "mascara", porDefecto: "",
              opciones: [{ id: "", nombre: Idioma.t("Recta") },
                         { id: "redonda", nombre: Idioma.t("Redondeada") },
                         { id: "circulo", nombre: Idioma.t("Círculo") }] }
        ]

        delegate: Flow {
            id: fila
            required property var modelData

            readonly property string puesto: Editor.capaSel
                ? String(Editor.capaSel[fila.modelData.campo]
                         || fila.modelData.porDefecto) : ""

            Layout.fillWidth: true
            spacing: 3

            Repeater {
                model: fila.modelData.opciones

                delegate: Rectangle {
                    id: chip
                    required property var modelData

                    readonly property bool puesta: fila.puesto === chip.modelData.id

                    //  A lo ancho por contenido y no repartidos: seis chips
                    //  repartidos a partes iguales dejan «Redondeada» partida.
                    width: etiqueta.implicitWidth + 16
                    height: 24
                    radius: 12
                    color: chip.puesta ? Theme.blue
                         : chipRaton.containsMouse ? Theme.surfaceHi
                                                   : Theme.surface

                    IslandLabel {
                        id: etiqueta
                        anchors.centerIn: parent
                        text: chip.modelData.nombre
                        color: chip.puesta ? "#ffffff" : Theme.muted
                        font.pixelSize: 10
                        font.weight: chip.puesta ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: chipRaton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const campos = {}
                            campos[fila.modelData.campo] = chip.modelData.id
                            Editor.fijarCapa(Editor.idSel, campos)
                        }
                    }
                }
            }
        }
    }

    //  El marco: cuánto y de qué color. El grosor va en fracción del ancho de
    //  la capa para que un logo pequeño no se lleve un marco de vídeo entero, y
    //  los tres escalones son los que se usan —fino de adorno, medio de
    //  cámara, grueso de recuadro que grita—.
    RowLayout {
        Layout.fillWidth: true
        spacing: 3

        readonly property real puesto: Editor.capaSel
            && Editor.capaSel.marco !== undefined ? Editor.capaSel.marco : 0

        IslandLabel {
            text: Idioma.t("Marco")
            color: Theme.dim
            font.pixelSize: 9
            font.capitalization: Font.AllUppercase
            font.weight: Font.DemiBold
            Layout.rightMargin: 4
        }

        Repeater {
            model: [{ v: 0, nombre: Idioma.t("Sin") },
                    { v: 0.02, nombre: Idioma.t("Fino") },
                    { v: 0.05, nombre: Idioma.t("Medio") },
                    { v: 0.09, nombre: Idioma.t("Grueso") }]

            delegate: Rectangle {
                id: chipMarco
                required property var modelData

                readonly property bool puesta:
                    Math.abs(parent.puesto - chipMarco.modelData.v) < 0.005

                Layout.fillWidth: true
                Layout.preferredHeight: 24
                radius: 12
                color: chipMarco.puesta ? Theme.blue
                     : marcoRaton.containsMouse ? Theme.surfaceHi : Theme.surface

                IslandLabel {
                    anchors.centerIn: parent
                    text: chipMarco.modelData.nombre
                    color: chipMarco.puesta ? "#ffffff" : Theme.muted
                    font.pixelSize: 10
                    font.weight: chipMarco.puesta ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: marcoRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Editor.fijarCapa(Editor.idSel,
                        { marco: chipMarco.modelData.v })
                }
            }
        }
    }

    //  La sombra: la capa se separa del fondo. Cae hacia abajo y a la
    //  derecha, difuminada, y con la silueta que tenga puesta —una capa
    //  redonda proyecta una sombra redonda—.
    RowLayout {
        Layout.fillWidth: true
        spacing: 3

        readonly property real puesta: Editor.capaSel
            && Editor.capaSel.sombra !== undefined ? Editor.capaSel.sombra : 0

        IslandLabel {
            text: Idioma.t("Sombra")
            color: Theme.dim
            font.pixelSize: 9
            font.capitalization: Font.AllUppercase
            font.weight: Font.DemiBold
            Layout.rightMargin: 4
        }

        Repeater {
            model: [{ v: 0, nombre: Idioma.t("Sin") },
                    { v: 0.35, nombre: Idioma.t("Suave") },
                    { v: 0.6, nombre: Idioma.t("Media") },
                    { v: 0.9, nombre: Idioma.t("Fuerte") }]

            delegate: Rectangle {
                id: chipSombra
                required property var modelData

                readonly property bool elegida:
                    Math.abs(parent.puesta - chipSombra.modelData.v) < 0.05

                Layout.fillWidth: true
                Layout.preferredHeight: 24
                radius: 12
                color: chipSombra.elegida ? Theme.blue
                     : sombraRaton.containsMouse ? Theme.surfaceHi
                                                 : Theme.surface

                IslandLabel {
                    anchors.centerIn: parent
                    text: chipSombra.modelData.nombre
                    color: chipSombra.elegida ? "#ffffff" : Theme.muted
                    font.pixelSize: 10
                    font.weight: chipSombra.elegida ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: sombraRaton
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Editor.fijarCapa(Editor.idSel,
                        { sombra: chipSombra.modelData.v })
                }
            }
        }
    }

    //  El color del marco, con las mismas seis muestras que el resto del
    //  editor. Solo cuando hay marco: elegirle color a algo que no está es
    //  ofrecer un botón que no hace nada.
    RowLayout {
        visible: Editor.capaSel && (Editor.capaSel.marco || 0) > 0.001
        Layout.fillWidth: true
        spacing: 4

        Repeater {
            model: ["#ffffff", "#000000", "#ffd60a",
                    "#ff453a", "#32d74b", "#0a84ff"]

            delegate: Rectangle {
                id: muestra
                required property var modelData

                readonly property bool puesta: Editor.capaSel
                    && String(Editor.capaSel.colorMarco || "#ffffff")
                       .toLowerCase() === muestra.modelData

                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 11
                color: muestra.modelData
                border.width: puesta ? 2 : 1
                border.color: puesta ? Theme.blue : Qt.rgba(1, 1, 1, 0.2)

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Editor.fijarCapa(Editor.idSel,
                        { colorMarco: muestra.modelData })
                }
            }
        }

        Item { Layout.fillWidth: true }
    }

    //  El espejo. Es un interruptor y no un chip más porque no compite con
    //  nada: se puede tener a la vez que cualquier filtro y cualquier forma.
    BotonAccion {
        texto: Editor.capaSel && Editor.capaSel.espejo
            ? Idioma.t("Del revés") : Idioma.t("Voltear")
        icono: 0xF10E7                          // md-flip_horizontal
        activo: Editor.capaSel && !!Editor.capaSel.espejo
        onPulsado: Editor.fijarCapa(Editor.idSel,
            { espejo: !Editor.capaSel.espejo })
    }
}
