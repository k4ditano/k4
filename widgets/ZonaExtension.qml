//  Las extensiones de flanco de la píldora: lo que los plugins han declarado
//  por `K4.Capsula`, pintado en la punta de la cápsula que ha crecido para
//  ellos. La vista de reposo pone una instancia en cada extremo de su fila, y
//  cada una pinta las extensiones registradas para su lado.
//
//  El ancho de la zona es el número del SERVICIO, no el del texto: la píldora
//  reservó exactamente eso, y el texto se recorta dentro. La medida se hizo en
//  el servicio con la misma fuente con la que se pinta aquí, así que lo
//  reservado y lo pintado son los mismos píxeles.
//
//  Hacia el borde de la pantalla: creciendo a la derecha, el nombre se pega al
//  extremo derecho de la extensión. Con el abrazo al texto la zona se llena de
//  todas formas; la alineación se nota cuando un `largoMaximo` ha capado un
//  nombre largo y sobra sitio.

import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

Item {
    id: zona

    property string lado: "derecha"

    readonly property var mias: {
        const fuera = []
        for (let i = 0; i < Extensiones.lista.length; ++i)
            if (Extensiones.lista[i].lado === lado
                    && Extensiones.lista[i].visible !== false
                    && Extensiones.anchoDe(Extensiones.lista[i]) > 28)
                fuera.push(Extensiones.lista[i])
        return fuera
    }

    //  ── los 8 px de separación con la píldora ────────────────────
    //
    //  Cada extensión lleva presupuestados 8 px para separarse de lo que la
    //  píldora ya tenía en ese flanco (van en `adornos`, en el servicio). Esos
    //  8 los pone normalmente la FILA, con su `spacing`, entre la zona y su
    //  vecino — así que la zona los descuenta de su ancho para no cobrarlos
    //  dos veces.
    //
    //  Pero si la zona se queda SOLA en su flanco no hay vecino y la fila no
    //  espacia nada: descontarlos entonces deja el flanco 8 px más estrecho de
    //  lo que dice el servicio, y como el host ancla la island con el número
    //  del servicio, el cuerpo de la píldora se corre 4 px al entrar la
    //  extensión. Pasa de verdad: en el flanco izquierdo, con nada sonando, la
    //  carátula y el visualizador están ocultos y aquí no queda nadie más.
    //
    //  Así que se descuentan solo cuando alguien los va a poner.
    readonly property bool sola: !parent || parent.visibleChildren.length <= 1

    readonly property int implicito: {
        let total = 0
        for (let i = 0; i < mias.length; ++i)
            total += Extensiones.anchoDe(mias[i])
        if (total <= 0)
            return 0
        return sola ? total : total - 8
    }

    visible: mias.length > 0
    implicitWidth: implicito
    implicitHeight: 18

    //  Pegada al borde que le toca: la zona es lo último de la fila y su
    //  contenido corre hacia el borde de la pantalla, no hacia el cuerpo de la
    //  píldora.
    RowLayout {
        anchors.left: zona.lado === "izquierda" ? zona.left : undefined
        anchors.right: zona.lado === "derecha" ? zona.right : undefined
        anchors.verticalCenter: zona.verticalCenter
        spacing: 8

        Repeater {
            model: zona.mias

            delegate: RowLayout {
                required property var modelData
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                IconGlyph {
                    text: String.fromCodePoint(modelData.glifo || 0xF030E)
                    color: modelData.color || Theme.blue
                    font.pixelSize: 11
                }

                IslandLabel {
                    text: modelData.texto
                    color: Theme.ink
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.maximumWidth: Math.max(0,
                        Extensiones.anchoDe(modelData) - 28)
                }
            }
        }
    }
}
