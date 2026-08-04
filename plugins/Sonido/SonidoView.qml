//  El módulo de Sonido: la lista de aparatos con su cabecera y su pie.
//
//  La lista en sí es `AparatosDeSonido` de `core`, compartida con el detalle
//  del centro de control: lo mismo se llega desde el lanzador y desde donde se
//  llega al Wi‑Fi y al Bluetooth, y llegue por donde llegue es la misma cosa.

import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../services"

Item {
    id: vista

    required property var plugin

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        // ── cabecera ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconGlyph {
                text: String.fromCodePoint(0xF057E)   // md-volume_high
                color: Theme.ink
                font.pixelSize: 15
            }

            IslandLabel {
                text: Idioma.t("Sonido")
                color: Theme.ink
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            IslandLabel {
                Layout.fillWidth: true
                text: Idioma.t("por dónde sale y por dónde entra")
                color: Theme.dim
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            MediaButton {
                glyph: Theme.ico.close
                glyphSize: 13
                glyphColor: Theme.muted
                onActivated: vista.plugin.close()
            }
        }

        AparatosDeSonido {
            Layout.fillWidth: true
        }

        Item { Layout.fillHeight: true }

        IslandLabel {
            Layout.fillWidth: true
            text: Idioma.t("La marca del deslizador es el nivel natural del aparato: por encima se amplifica")
            color: Theme.dim
            font.pixelSize: 9
            wrapMode: Text.WordWrap
        }
    }
}
