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
            cursorDelegate: IslandCursor {}
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

        //  Arma el gesto en vez de crear el zoom a ciegas.
        //
        //  Antes lo creaba ahí mismo: dos segundos desde el cabezal y
        //  encuadrado al centro. Las tres cosas que importan —dónde, cuánto y
        //  cuándo— las adivinaba, así que después tocaba ir a la previa a
        //  apuntar y a la línea a cuadrar. Ahora dice qué vas a hacer y lo dices
        //  tú dibujándolo encima del vídeo.
        BotonAccion {
            texto: Editor.herramienta === "zoom"
                ? Idioma.t("Dibújalo en el vídeo")
                : Idioma.t("Zoom")
            icono: 0xF1276                   // md-magnify_scan
            activo: Editor.herramienta === "zoom"
            onPulsado: Editor.armar("zoom")
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

        //  Ponerle voz al montaje mirándolo: se abre el micro, la previa echa a
        //  andar desde donde esté el cabezal y lo que digas entra como una capa
        //  de audio más. El botón es el mismo para empezar y para parar, como
        //  el de grabar la pantalla: mientras hablas no hay otra cosa que
        //  quieras pulsar ahí.
        BotonAccion {
            texto: Editor.estadoVoz === "grabando"
                    ? Idioma.t("Parar la voz")
                 : Editor.estadoVoz !== ""
                    ? Idioma.t("Un momento…")
                    : Idioma.t("Grabar voz")
            icono: 0xF036C                   // md-microphone
            activo: Editor.estadoVoz !== ""
            onPulsado: Editor.grabarVozAlternar(view.segundos)
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

        BotonAccion {
            texto: Idioma.t("Señalar")
            icono: 0xF09C6              // md-arrow_top_right_thick
            onPulsado: Editor.crearForma(view.segundos, "flecha")
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

    //  El fotograma bajo el cabezal como miniatura del vídeo: PNG a
    //  resolución completa, con el zoom y las capas puestos, numerado si ya
    //  hay una. Quien hace miniaturas hace tres y se queda con la mejor.
    BotonAccion {
        texto: Idioma.t("Guardar miniatura")
        icono: 0xF02EB                       // md-image_area
        onPulsado: Editor.miniatura(view.segundos)
    }

    //  Los capítulos de YouTube, de los marcadores al portapapeles: una
    //  línea por marcador, listas para la descripción del vídeo.
    BotonAccion {
        visible: Editor.marcadores.length > 0
        texto: Idioma.f(Idioma.t("Copiar %1 capítulos"),
                        String(Editor.marcadores.length))
        icono: 0xF027B                       // md-format_list_numbered
        onPulsado: Editor.copiarCapitulos()
    }
}
