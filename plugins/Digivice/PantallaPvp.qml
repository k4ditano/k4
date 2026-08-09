//  Duelo por código: pelear contra el equipo de otra persona.
//
//  Los aparatos peleaban por cable o por infrarrojos. Aquí no hay cable ni
//  servidor, así que el equipo se empaqueta en un código y se pasa copiando y
//  pegando, como cualquier otra cosa entre dos personas.
//
//  El código se lee de un `TextInput` y NO de la API de portapapeles de k4:
//  esa pide el permiso `portapapeles` a propósito —lleva contraseñas y
//  tokens— y gastarlo en un juego sería desproporcionado. Un campo de texto
//  acepta Ctrl+V sin permiso ninguno, y de paso deja teclearlo.
//
//  Tu código sale en un campo de solo lectura pero SELECCIONABLE, que es la
//  otra mitad del asunto: sin poder copiarlo no hay nada que mandarle a nadie.

import QtQuick
import K4 as K4
import "../../services"

Item {
    id: self

    signal pelear()

    property int cursor: 0
    //  0 = mi código · 1 = el suyo
    readonly property int foco: ((cursor % 2) + 2) % 2

    //  Lo dice la vista para no robarle las teclas al menú cuando no toca.
    readonly property bool escribiendo: campo.activeFocus

    function elegir() {
        if (foco === 0) {
            //  Sobre tu código, B lo selecciona entero: es el gesto que
            //  precede a copiarlo, y hacerlo a mano en un campo de 29
            //  caracteres dentro de un LCD es un suplicio.
            mio.selectAll()
            mio.forceActiveFocus()
            return
        }
        if (campo.text.trim().length === 0) {
            campo.forceActiveFocus()
            return
        }
        if (Digivice.retar(campo.text))
            self.pelear()
    }

    Column {
        anchors.fill: parent
        anchors.margins: 5
        spacing: 3

        K4.Etiqueta {
            width: parent.width
            text: Idioma.t("Duelo por código")
            font.pixelSize: 12
            font.weight: Font.Bold
            color: "#d8f0de"
        }

        // ── mi código ─────────────────────────────────────────────
        K4.Etiqueta {
            width: parent.width
            text: Idioma.f(Idioma.t("Tu equipo (%1)"), Digivice.miEquipo.length)
            font.pixelSize: 11
            color: "#5f8f6c"
        }

        Rectangle {
            width: parent.width
            height: 24
            radius: 4
            color: "#12200f"
            border.width: self.foco === 0 ? 1 : 0
            border.color: "#7de08a"

            TextInput {
                id: mio
                anchors.fill: parent
                anchors.margins: 4
                text: Digivice.miCodigo
                readOnly: true
                selectByMouse: true
                font.family: K4.Tema.fuenteIconos
                font.pixelSize: 11
                color: "#9fe8ac"
                selectionColor: "#2f6a44"
                verticalAlignment: TextInput.AlignVCenter
                //  Sin recortar: un código a medias no sirve de nada, y es
                //  preferible que se salga a que se copie incompleto.
                clip: true
            }
        }

        //  Los tres bichos que van en tu código, para que se vea a quién
        //  estás mandando a pelear.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            height: 26

            Repeater {
                model: Digivice.miEquipo

                Retrato {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    especie: modelData.especie
                    lado: 24
                }
            }
        }

        // ── el suyo ───────────────────────────────────────────────
        K4.Etiqueta {
            width: parent.width
            text: Idioma.t("Pega el suyo")
            font.pixelSize: 11
            color: "#5f8f6c"
        }

        Rectangle {
            width: parent.width
            height: 24
            radius: 4
            color: "#12200f"
            border.width: self.foco === 1 || campo.activeFocus ? 1 : 0
            border.color: campo.activeFocus ? "#e8b45a" : "#7de08a"

            TextInput {
                id: campo
                anchors.fill: parent
                anchors.margins: 4
                selectByMouse: true
                //  Con el último puesto: casi siempre se duela contra la
                //  misma persona, y volver a pedirle el código para la
                //  revancha sería un peaje por jugar dos veces.
                text: Digivice.ultimoCodigo
                font.family: K4.Tema.fuenteIconos
                font.pixelSize: 11
                color: "#e8dcc8"
                selectionColor: "#6a5a2f"
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                //  Enter pelea: teniendo el foco aquí, obligar a volver al
                //  botón B sería un paso de más justo al final.
                onAccepted: self.elegir()
            }

            K4.Etiqueta {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: campo.text.length === 0 && !campo.activeFocus
                text: Idioma.t("clic aquí · Ctrl+V")
                font.pixelSize: 11
                color: "#4a5a4e"
            }
        }

        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: self.foco === 0 ? Idioma.t("B lo selecciona para copiar")
                                  : Idioma.t("B reta  ·  gana 2 de 3")
            font.pixelSize: 11
            color: "#5f8f6c"
            elide: Text.ElideRight
        }

        //  Cuántos equipos distintos has vencido. Es el poso del PVP: sin
        //  esto, ganar un duelo no dejaría ninguna huella.
        K4.Etiqueta {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: Object.keys(Digivice.codigosVencidos).length > 0
            text: Object.keys(Digivice.codigosVencidos).length === 1
                ? Idioma.t("1 equipo vencido")
                : Idioma.f(Idioma.t("%1 equipos vencidos"),
                           Object.keys(Digivice.codigosVencidos).length)
            font.pixelSize: 11
            color: "#8fbf9c"
        }
    }
}
