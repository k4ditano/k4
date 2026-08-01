//  Qué se le puede añadir al vídeo, y las herramientas de línea entera.
//
//  Es lo que enseña la ficha del editor cuando no hay nada elegido, que es
//  justo cuando se va a añadir algo. Vivía dentro de CuerpoEditor (2.200
//  líneas); ahora es una pieza con nombre.
//
//  Aquí y no en el pie, y no es una preferencia: ocho botones con nombre
//  pedían 1207 píxeles en una island de 1000, y eso estiraba la columna
//  entera hasta empujar la ficha fuera del borde. Medido antes de moverlos.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

ColumnLayout {
    required property var view

    visible: Editor.tipoSel === ""
    Layout.fillWidth: true
    Layout.topMargin: 4
    spacing: 4

    IslandLabel {
        text: Idioma.t("Añadir")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    IslandLabel {
        visible: Editor.bandaSeleccionada >= Editor.primeraBandaLibre
        text: Idioma.t("Grupo seleccionado")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
    }

    Rectangle {
        visible: Editor.bandaSeleccionada >= Editor.primeraBandaLibre
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        radius: 7
        color: Theme.surface
        border.width: 1
        border.color: grupoNombre.activeFocus
            ? Theme.blue : Qt.rgba(1, 1, 1, 0.1)

        TextInput {
            id: grupoNombre
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.ink
            font.pixelSize: 11
            font.family: Theme.uiFont
            selectByMouse: true
            clip: true
            property int deQuien: Editor.bandaSeleccionada
            onDeQuienChanged: text = Editor.nombreBanda(
                Editor.bandaSeleccionada)
            onTextEdited: if (Editor.bandaSeleccionada >=
                              Editor.primeraBandaLibre)
                Editor.fijarBanda(Editor.bandaSeleccionada,
                                  { nombre: text })
            Component.onCompleted: text = Editor.bandaSeleccionada
                >= Editor.primeraBandaLibre
                ? Editor.nombreBanda(Editor.bandaSeleccionada)
                : ""
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 4
        rowSpacing: 4

        BotonAccion {
            texto: Idioma.t("Zoom")
            icono: 0xF1276                   // md-magnify_scan
            onPulsado: {
                //  Dos segundos desde donde estés, o lo que
                //  quepa si estás cerca del final.
                const a = Math.min(view.segundos,
                                   Math.max(0, view.total - 2))
                Editor.seleccionar("momento", Editor.crearMomento(
                    a, Math.min(view.total, a + 2)))
            }
        }

        BotonAccion {
            texto: Idioma.t("Imagen")
            icono: 0xF02E9                   // md-image
            onPulsado: view.plugin.pedirImagen(view.segundos)
        }

        BotonAccion {
            texto: Idioma.t("Texto")
            icono: 0xF0284                   // md-format_text
            onPulsado: Editor.crearTexto(view.segundos)
        }

        BotonAccion {
            texto: Idioma.t("Zona")
            icono: 0xF00B5                   // md-blur
            onPulsado: Editor.crearZona(view.segundos,
                                        "desenfoque")
        }

        BotonAccion {
            texto: Idioma.t("Audio")
            icono: 0xF075A                   // md-music
            onPulsado: view.plugin.pedirAudio(view.segundos)
        }

        BotonAccion {
            texto: Idioma.t("Vídeo")
            icono: 0xF0E57   // md-picture_in_picture_bottom_right
            onPulsado: view.plugin.pedirPip(view.segundos)
        }

        BotonAccion {
            texto: Idioma.t("Censurar")
            icono: 0xF075F                   // md-volume_mute
            onPulsado: Editor.crearCensura(view.segundos,
                                           "silencio")
        }

        BotonAccion {
            //  Solo si el vídeo trae rastro: uno abierto del
            //  disco no tiene clics que resaltar.
            visible: Editor.fuentes.length > 0
                && String(Editor.fuentes[0].rastro || "").length > 0
            texto: Idioma.t("Clics")
            icono: 0xF0CFD           // md-cursor_default_click
            activo: Editor.clicsActivos
            onPulsado: Editor.alternarClics()
        }

        BotonAccion {
            texto: Idioma.t("Marcador")
            icono: 0xF05A1
            onPulsado: Editor.crearMarcador(view.segundos)
        }
    }

    IslandLabel {
        text: Idioma.t("Herramientas")
        color: Theme.dim
        font.pixelSize: 9
        font.capitalization: Font.AllUppercase
        font.weight: Font.DemiBold
        Layout.topMargin: 4
    }

    BotonAccion {
        readonly property bool hay: Editor.cuantosSilencios > 0
        readonly property bool buscando:
            Editor.estadoSilencios === "buscando"

        texto: buscando ? Idioma.t("Escuchando…")
             : hay ? Idioma.t("Quitar ")
                     + Editor.cuantosSilencios
                     + Idioma.t(" silencios")
             : Editor.estadoSilencios === "fallo"
                     ? Idioma.t("No se pudo")
                     : Idioma.t("Buscar silencios")
        icono: 0xF057E                       // md-volume_high
        activo: hay
        peligro: true
        disponible: !buscando
        onPulsado: {
            if (hay)
                Editor.quitarSilencios()
            else
                Editor.buscarSilencios()
        }
    }
}
