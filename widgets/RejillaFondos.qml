//  La rejilla de fondos de escritorio.
//
//  Vivía dentro de `HyprThemeView`, que es donde nació. Sale aquí porque ahora
//  la enseñan DOS sitios —la pantalla del tema y la sección Apariencia de
//  Ajustes— y dos copias de trescientas líneas divergen a la primera
//  corrección: se arregla una y la otra sigue mintiendo.
//
//  ── de dónde saca las cosas ──────────────────────────────────────
//
//  Lo de MIRAR, del servicio `Fondos`: qué hay, cómo se ve cada uno, cuál está
//  puesto. Eso no es de nadie en particular.
//
//  Lo de HACER, del `motor` que le pasen: aplicar, quitar, traer uno de fuera,
//  las transiciones. Hoy ese motor es el plugin del tema, que es quien habla
//  con awww/swww/swaybg. Se recibe como objeto y no se importa su carpeta: un
//  plugin no depende de otro, y si está apagado esto se queda en modo mirar sin
//  romperse.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../core"
import "../services"

ColumnLayout {
    id: rejilla

    //  Quien sabe aplicar un fondo. Sin él la rejilla se ve pero no toca nada.
    property var motor: null

    //  ── ¿se desplaza ella, o la desplaza la página? ──────────────
    //
    //  `true`: la rejilla renuncia a su propio desplazamiento y se dimensiona
    //  a sus filas, para que la página que la aloja lo desplace TODO como una
    //  sola cosa. Es lo que quiere Ajustes, donde debajo de la rejilla va el
    //  bloque del color: un scroll dentro de otro scroll deja lo de abajo
    //  inalcanzable con la rueda, y esa era la razón por la que el color vivía
    //  en una sección aparte.
    //
    //  `false` (lo de siempre): la rejilla se desplaza por dentro, que es lo
    //  que quiere una pantalla entera para ella — todo el hueco para
    //  miniaturas.
    property bool fitContent: false

    //  Los monitores, para el filtro de arriba. Los sabe el motor.
    readonly property var pantallas: rejilla.motor
        && typeof rejilla.motor.pantallasConocidas === "function"
        ? rejilla.motor.pantallasConocidas() : []

    //  Cuál está puesto AHORA en lo que se está mirando: el del monitor
    //  elegido si hay uno elegido, y si no el común. Es lo que marca en azul la
    //  miniatura, así que tiene que seguir al filtro de arriba.
    //  El rastreo se pide al enseñarse y solo si no hay nada: un `find` por
    //  siete carpetas en cada arranque de la barra sería pagar por una lista
    //  que casi nunca se mira. Y al enseñarse otra vez no se repite, que la
    //  lista ya está y el botón de refrescar existe para eso.
    function pedirLista() {
        if (Fondos.lista.length === 0 && !Fondos.rastreando)
            Fondos.rastrear()
    }

    Component.onCompleted: if (visible) pedirLista()
    onVisibleChanged: if (visible) pedirLista()

    readonly property string destinoActual: {
        if (!rejilla.motor)
            return Fondos.actualDe("")
        return rejilla.motor.pantallaElegida.length > 0
            ? rejilla.motor.fondoDe(rejilla.motor.pantallaElegida)
            : rejilla.motor.wallpaper
    }

    //  Sin `anchors.fill`: eso era de cuando esto vivía dentro de una pantalla
    //  propia. Aquí lo coloca la columna de la sección, y mezclar anchors con
    //  Layout deja el widget del tamaño equivocado.
    Layout.fillWidth: true
    spacing: 10

    //  ── en qué pantalla estamos trabajando ──────────
    //
    //  Con dos monitores, «poner este fondo» es ambiguo, y la
    //  rejilla de antes decidía por ti: uno para los dos. Aquí se
    //  elige primero el destino y luego la imagen, que es el orden
    //  en que se piensa.
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: [""].concat(rejilla.pantallas)

            delegate: Rectangle {
                id: chipPantalla
                required property var modelData
                readonly property bool puesta:
                    rejilla.motor.pantallaElegida === modelData

                Layout.preferredWidth: textoPantalla.implicitWidth + 22
                Layout.preferredHeight: 24
                radius: 12
                color: puesta ? Theme.blue
                    : (ratonPantalla.containsMouse ? Theme.surfaceHi
                                                   : Theme.surface)

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: textoPantalla
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: chipPantalla.modelData.length === 0
                        ? Idioma.t("Todas") : chipPantalla.modelData
                    color: chipPantalla.puesta ? Theme.ink : Theme.muted
                    font.pixelSize: 10
                    font.weight: chipPantalla.puesta
                        ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: ratonPantalla
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: rejilla.motor.pantallaElegida =
                        chipPantalla.modelData
                }
            }
        }

        Item { Layout.fillWidth: true }

        IslandLabel {
            text: Fondos.lista.length + Idioma.t(" fondos")
            color: Theme.dim
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter
        }

        //  ── traer uno de fuera ──────────────────────
        //
        //  El rastreo mira unas cuantas carpetas y ninguna tiene por
        //  qué ser la tuya: el fondo que te acabas de bajar a un
        //  sitio raro no aparece, y la única salida era moverlo.
        Rectangle {
            Layout.preferredWidth: textoAnadir.implicitWidth + 22
            Layout.preferredHeight: 24
            Layout.alignment: Qt.AlignVCenter
            radius: 12
            color: anadirRaton.containsMouse ? Theme.surfaceHi
                                             : Theme.surface

            Behavior on color { ColorAnimation { duration: 120 } }

            IslandLabel {
                id: textoAnadir
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: Idioma.t("Añadir…")
                color: Theme.muted
                font.pixelSize: 10
            }

            MouseArea {
                id: anadirRaton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: rejilla.motor.elegirFondo()
            }
        }

        MediaButton {
            glyph: Theme.ico.loading
            glyphSize: 14
            glyphColor: Theme.muted
            onActivated: Fondos.rastrear()
            Layout.alignment: Qt.AlignVCenter
        }
    }

    //  ── cómo se pasa de uno a otro ─────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        IslandLabel {
            text: Idioma.t("Transición")
            color: Theme.dim
            font.pixelSize: 10
            Layout.alignment: Qt.AlignVCenter
        }

        Repeater {
            model: rejilla.motor.transiciones

            delegate: Rectangle {
                id: chipTrans
                required property var modelData
                readonly property bool puesta:
                    rejilla.motor.transicion === modelData

                Layout.preferredWidth: textoTrans.implicitWidth + 20
                Layout.preferredHeight: 22
                radius: 11
                color: puesta ? Theme.blue
                    : (ratonTrans.containsMouse ? Theme.surfaceHi
                                                : Theme.track)

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: textoTrans
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: chipTrans.modelData
                    color: chipTrans.puesta ? Theme.ink : Theme.muted
                    font.pixelSize: 10
                }

                MouseArea {
                    id: ratonTrans
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        rejilla.motor.transicion = chipTrans.modelData
                        rejilla.motor.saveState()
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }
    }

    GridView {
        Layout.fillWidth: true
        Layout.fillHeight: !rejilla.fitContent
        //  Dimensionada al contenido: `contentHeight` son exactamente filas ×
        //  `cellHeight`, así que se enseñan todas y no le hace falta rueda
        //  propia. El suelo de dos celdas deja que «no hay fondos» siga siendo
        //  un sitio visible y no una rendija de alto cero.
        Layout.preferredHeight: rejilla.fitContent
            ? Math.max(contentHeight, cellHeight * 2) : 0
        //  Y fuera de su propio arrastre: en este modo la rueda es de la
        //  página, y un GridView no interactivo la deja pasar al Rodillo en
        //  vez de comérsela — que es la mitad del arreglo, porque un Flickable
        //  se queda la rueda aunque no tenga nada que recorrer.
        interactive: !rejilla.fitContent
        clip: true
        cellWidth: Math.floor(width / 4)
        cellHeight: Math.round(cellWidth * 0.6)
        model: Fondos.lista
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: wallCell
            required property var modelData
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight

            //  Lo puesto EN EL DESTINO elegido, no el fondo común:
            //  con «HDMI-A-1» seleccionado, lo que hay que marcar es
            //  lo de esa pantalla.
            readonly property bool current: rejilla.destinoActual === modelData
            readonly property bool mueve: !Fondos.esQuieto(modelData)
            //  ¿Lo has traído tú? Solo esos se pueden quitar.
            readonly property bool propio:
                Fondos.extras.indexOf(modelData) >= 0

            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 10
                color: Theme.islandBg
                border.width: wallCell.current ? 2
                    : (wallMouse.containsMouse ? 1 : 0)
                border.color: wallCell.current ? Theme.blue : Theme.surfaceHi
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: wallCell.current ? 2 : 0
                    //  De un vídeo o un GIF se enseña su póster, que
                    //  el plugin cocina de una tacada al escanear.
                    source: "file://"
                        + Fondos.miniaturaDe(wallCell.modelData)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 320
                }

                //  Que se mueve, y qué es. Sin esto, un vídeo y una
                //  foto se ven idénticos en la rejilla —el póster ES
                //  una foto— y no sabes lo que estás eligiendo.
                Rectangle {
                    visible: wallCell.mueve
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    width: etiquetaMueve.implicitWidth + 12
                    height: 16
                    radius: 8
                    color: "#cc000000"

                    IslandLabel {
                        id: etiquetaMueve
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: /\.(gif|apng)$/i.test(wallCell.modelData)
                            ? "GIF" : Idioma.t("vídeo")
                        color: Theme.ink
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                    }
                }

                // el nombre, legible sobre cualquier imagen
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 20
                    color: "#cc000000"
                    visible: wallMouse.containsMouse || wallCell.current

                    IslandLabel {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        verticalAlignment: Text.AlignVCenter
                        text: wallCell.modelData.substring(
                            wallCell.modelData.lastIndexOf("/") + 1)
                        font.pixelSize: 9
                        elide: Text.ElideMiddle
                    }
                }

                //  La cruz de quitar, solo en los que has traído
                //  tú: los que salen del rastreo no se pueden
                //  quitar de una lista en la que no están.
                Rectangle {
                    visible: wallCell.propio
                        && (wallMouse.containsMouse || quitarRaton.containsMouse)
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 6
                    width: 18
                    height: 18
                    radius: 9
                    color: quitarRaton.containsMouse
                        ? Theme.red : "#cc000000"

                    IslandLabel {
                        anchors.centerIn: parent
                        //  Por codepoint y no como literal: el extractor
                        //  de textos ve cualquier cadena en un `text:` y la
                        //  mete en la plantilla, y una aspa no se traduce.
                        text: String.fromCodePoint(0x00d7)
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: quitarRaton
                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rejilla.motor.quitarFondo(wallCell.modelData)
                    }
                }

                MouseArea {
                    id: wallMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    //  Debajo de la cruz a propósito: declarado
                    //  después iría encima y se comería su clic.
                    z: -1
                    onClicked: rejilla.motor.ponerEnElegida(wallCell.modelData)
                }
            }
        }

        IslandLabel {
            anchors.centerIn: parent
            visible: Fondos.lista.length === 0
            text: Idioma.t("No hay fondos en tus carpetas de imágenes ni en las del sistema")
            color: Theme.muted
            font.pixelSize: 12
        }

    }

    //  El estado, que viajó con la pantalla borrada y hace falta: sin
    //  herramienta instalada la rejilla se ve igual y no aplica nada, y sin
    //  esto eso parecía un fallo.
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 8

        readonly property bool hay: !!rejilla.motor
            && String(rejilla.motor.wallTool || "").length > 0
        readonly property bool puesto: !!rejilla.motor
            && String(rejilla.motor.wallpaper || "").length > 0

        IconGlyph {
            text: parent.hay && parent.puesto ? Theme.ico.check : Theme.ico.alert
            color: parent.hay && parent.puesto ? Theme.green : Theme.muted
            font.pixelSize: 12
            renderType: Text.NativeRendering
            Layout.alignment: Qt.AlignVCenter
        }

        IslandLabel {
            Layout.fillWidth: true
            text: !parent.hay
                ? Idioma.t("Instala awww, swww o swaybg para aplicar fondos")
                : (parent.puesto
                   ? Idioma.t("Fondo aplicado y guardado automáticamente")
                   : Idioma.t("Selecciona una imagen para cambiar el fondo"))
            color: Theme.muted
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
