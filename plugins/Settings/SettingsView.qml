import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import K4 as K4
import "../../core"
import "../../services"

FadeIn {
    id: view

    //  Los dispositivos de sonido se refrescan al abrir: enchufar unos
    //  auriculares a mitad de sesión es lo normal, y la lista tiene que
    //  enseñarlos sin reiniciar nada.
    Component.onCompleted: Captura.buscarAudios()

    required property var plugin





    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 12
        // Más margen abajo que arriba: la fila de herramientas es lo último
        // y con 14 quedaba pegada al borde.
        anchors.bottomMargin: 22
        spacing: 10

        // ── cabecera
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 24
            spacing: 9

            IconGlyph {
                text: Theme.ico.cog
                color: Theme.muted
                font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter
            }

            IslandLabel {
                text: Idioma.t("Ajustes")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignVCenter
            }

            // ── qué versión llevas, y si hay otra ────────────────
            //
            //  El commit va pegado al título y en gris: es la respuesta a «¿qué
            //  tengo?», que hasta ahora no estaba escrita en ninguna parte de la
            //  barra, pero no es una noticia y no tiene que competir con nada.
            IslandLabel {
                visible: view.plugin.version.commit.length > 0
                text: view.plugin.version.commit
                color: Theme.dim
                font.pixelSize: 9
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 2
            }

            Item { Layout.fillWidth: true }

            //  Y la novedad SÍ es una noticia, así que se pone azul y se pulsa.
            //
            //  Con cambios sin guardar no se ofrece el botón: `./instalar` no
            //  toca el código con el árbol sucio —a propósito— así que sería un
            //  botón que no hace lo que dice. Se dice lo que pasa y se deja que
            //  quien lo lea decida, que es de quien es el trabajo sin guardar.
            Rectangle {
                id: novedad
                visible: view.plugin.version.hayNovedad
                Layout.preferredWidth: textoNovedad.implicitWidth + 22
                Layout.preferredHeight: 22
                Layout.alignment: Qt.AlignVCenter
                radius: 11

                readonly property bool ofrece: !view.plugin.version.sucio

                color: !ofrece ? Theme.track
                    : (ratonNovedad.containsMouse ? "#4a9eff" : Theme.blue)

                Behavior on color { ColorAnimation { duration: 120 } }

                IslandLabel {
                    id: textoNovedad
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: novedad.ofrece
                        ? Idioma.f(Idioma.t("%1 nuevos · Actualizar"),
                                   view.plugin.version.detras)
                        : Idioma.f(Idioma.t("%1 nuevos · guarda tus cambios"),
                                   view.plugin.version.detras)
                    color: novedad.ofrece ? Theme.ink : Theme.muted
                    font.pixelSize: 10
                    font.weight: novedad.ofrece ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    id: ratonNovedad
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: novedad.ofrece
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        view.plugin.version.actualizar()
                        view.plugin.close()
                    }
                }
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 15
                glyphColor: Theme.muted
                onActivated: view.plugin.close()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        //  ── grupos de opciones, dentro de algo que se pueda recorrer
        //
        //  Antes eran hijos directos del reparto, con el alto de la island fijo
        //  en 516. Funcionaba mientras hubo tres grupos; al añadir los de
        //  captura, grabación y editor el contenido pasó de novecientos píxeles y
        //  el reparto lo aplastó: las últimas filas quedaban pegadas al borde y
        //  el grupo del editor no llegaba a verse. Un ajuste al que no se puede
        //  llegar es peor que no tenerlo.
        //
        //  La cabecera y la zona peligrosa se quedan FUERA, así que cerrar y el
        //  botón de borrar la partida están siempre a la vista y no hay que
        //  buscarlos desplazando.
        Flickable {
            id: rodillo
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: grupos.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            //  Con barra: sin nada que lo diga, un panel que se desplaza parece
            //  un panel al que le falta la mitad.
            ScrollBar.vertical: IslandScrollBar {}

            //  La rueda, en un área que solo escucha la rueda.
            //
            //  Sin esto la lista solo se movía arrastrando: cada fila lleva su
            //  MouseArea con hover y un MouseArea acepta la rueda tenga o no
            //  manejador, así que el Flickable no la veía nunca. Es la misma
            //  trampa —y el mismo arreglo— que la línea de tiempo del editor.
            MouseArea {
                anchors.fill: parent
                z: 10
                acceptedButtons: Qt.NoButton
                onWheel: function (ev) {
                    const paso = ev.angleDelta.y
                    rodillo.contentY = Math.max(0, Math.min(
                        rodillo.contentHeight - rodillo.height,
                        rodillo.contentY - paso))
                    ev.accepted = true
                }
            }

        ColumnLayout {
            id: grupos
            width: rodillo.width
            spacing: 10

                // ── grupos de opciones
                Repeater {
                    model: Settings.definicion

                    delegate: ColumnLayout {
                        id: seccion
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 4

                        IslandLabel {
                            text: seccion.modelData.grupo
                            color: Theme.dim
                            font.pixelSize: 9
                            font.capitalization: Font.AllUppercase
                            Layout.leftMargin: 2
                        }

                        Repeater {
                            model: seccion.modelData.opciones

                            delegate: FilaOpcion {}
                        }
                    }
                }
            }
        }

        // Estado del cargador: distinguir «desactivado por el usuario» de
        // «falló al cargar» evita diagnosticar a ciegas desde la terminal.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            spacing: 7

            IconGlyph {
                text: String.fromCodePoint(0xF06A0)
                color: Object.keys(PluginManager.errores).length > 0
                    ? Theme.red : Theme.green
                font.pixelSize: 13
            }

            //  Abre la aplicación en vez de tapar los ajustes con ella. Los
            //  interruptores de arriba siguen aquí, que sí son ajustes; traer,
            //  actualizar y quitar se ha mudado a lo suyo.
            K4.Baldosa {
                Layout.preferredWidth: 78
                Layout.preferredHeight: 24
                radius: 12
                onPulsada: PluginManager.abrirAplicacion("tienda")

                IslandLabel {
                    anchors.centerIn: parent
                    text: Idioma.t("Plugins")
                    textFormat: Text.PlainText
                    color: Theme.muted
                    font.pixelSize: 10
                }
            }

            IslandLabel {
                Layout.fillWidth: true
                text: PluginManager.catalogo.length + Idioma.t(" plugins · ")
                    + PluginManager.catalogo.filter(function (m) {
                        return PluginManager.estaHabilitado(m.id)
                    }).length + Idioma.t(" habilitados")
                    + (Object.keys(PluginManager.errores).length > 0
                       ? " · " + Object.keys(PluginManager.errores).length
                         + Idioma.t(" con errores") : "")
                color: Theme.dim
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }


        // ── herramientas del sistema
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 30
            spacing: 8

            IslandLabel {
                text: Idioma.t("Herramientas del sistema")
                color: Theme.dim
                font.pixelSize: 9
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    { nombre: Idioma.t("Redes"), glifo: 0xF05A9, orden: ["nm-connection-editor"] },
                    { nombre: Idioma.t("Sonido"), glifo: 0xF057E, orden: ["pavucontrol"] }
                ]

                delegate: Rectangle {
                    id: herramienta
                    required property var modelData

                    Layout.preferredWidth: contenido.implicitWidth + 22
                    Layout.preferredHeight: 26
                    radius: 13
                    color: herramientaMouse.containsMouse ? Theme.surfaceHi : Theme.surface

                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        id: contenido
                        anchors.centerIn: parent
                        spacing: 6

                        IconGlyph {
                            text: String.fromCodePoint(herramienta.modelData.glifo)
                            color: Theme.muted
                            font.pixelSize: 12
                        }

                        IslandLabel {
                            text: herramienta.modelData.nombre
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: herramientaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            K4.Sistema.lanzar(herramienta.modelData.orden)
                            view.plugin.close()
                        }
                    }
                }
            }
        }
    }
}
