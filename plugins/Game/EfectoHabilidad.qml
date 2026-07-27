//  Una habilidad, dibujada sobre el campo.
//
//  Los ataques normales ya tienen su forma (EfectoGolpe); esto es para lo
//  otro: el meteoro que cae sobre toda la oleada, la cadena que salta de bicho
//  en bicho, la bendición que sube desde el grupo. Antes todas ellas eran el
//  mismo fogonazo blanco sobre el héroe, así que daba igual cuál se lanzara.
//
//  Recibe la zona que tiene que cubrir —la de los enemigos o la del grupo— y
//  se destruye solo al acabar.

import QtQuick

Item {
    id: efecto

    property string forma: "onda"
    property color tono: "#ffffff"

    // zona a cubrir, en coordenadas del campo
    property real zonaX: 0
    property real zonaY: 0
    property real zonaAncho: 100
    property real zonaAlto: 60

    anchors.fill: parent

    function arrancar() {
        if (forma === "cadena") cadena.start()
        else if (forma === "nube") nube.start()
        else if (forma === "motas") motas.start()
        else if (forma === "aura") aura.start()
        else onda.start()
    }

    // ── onda: barre la zona de lado a lado ────────────────────────
    Rectangle {
        id: frente
        visible: efecto.forma === "onda"
        x: efecto.zonaX
        y: efecto.zonaY
        width: 7
        height: efecto.zonaAlto
        radius: 3
        color: efecto.tono
        opacity: 0
    }

    SequentialAnimation {
        id: onda

        ParallelAnimation {
            NumberAnimation {
                target: frente; property: "x"
                from: efecto.zonaX - 10; to: efecto.zonaX + efecto.zonaAncho
                duration: 340; easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: frente; property: "width"
                from: 7; to: 26; duration: 340
            }
            SequentialAnimation {
                NumberAnimation { target: frente; property: "opacity"; to: 0.85; duration: 90 }
                NumberAnimation { target: frente; property: "opacity"; to: 0; duration: 250 }
            }
        }

        ScriptAction { script: efecto.destroy() }
    }

    // ── cadena: saltos rectos de un punto al siguiente ────────────
    Item {
        id: eslabones
        visible: efecto.forma === "cadena"
        anchors.fill: parent
        opacity: 0

        Repeater {
            model: 4

            delegate: Rectangle {
                required property int index
                readonly property real paso: efecto.zonaAncho / 4

                x: efecto.zonaX + index * paso
                y: efecto.zonaY + efecto.zonaAlto * (index % 2 === 0 ? 0.34 : 0.58)
                width: paso
                height: 2
                color: efecto.tono
                rotation: index % 2 === 0 ? 11 : -11
                antialiasing: true
            }
        }
    }

    SequentialAnimation {
        id: cadena

        NumberAnimation { target: eslabones; property: "opacity"; to: 1; duration: 70 }
        NumberAnimation { target: eslabones; property: "opacity"; to: 0.35; duration: 80 }
        NumberAnimation { target: eslabones; property: "opacity"; to: 1; duration: 70 }
        NumberAnimation { target: eslabones; property: "opacity"; to: 0; duration: 200 }

        ScriptAction { script: efecto.destroy() }
    }

    // ── nube: bocanadas que suben y se abren ──────────────────────
    Item {
        id: bocanadas
        visible: efecto.forma === "nube"
        anchors.fill: parent
        opacity: 0

        Repeater {
            model: 6

            delegate: Rectangle {
                required property int index

                x: efecto.zonaX + (index + 0.5) * (efecto.zonaAncho / 6) - 9
                y: efecto.zonaY + efecto.zonaAlto * 0.5
                    - (index % 3) * 7
                width: 18
                height: 18
                radius: 9
                color: efecto.tono
                opacity: 0.5
            }
        }
    }

    SequentialAnimation {
        id: nube

        ParallelAnimation {
            NumberAnimation { target: bocanadas; property: "opacity"; to: 1; duration: 160 }
            NumberAnimation {
                target: bocanadas; property: "scale"
                from: 0.6; to: 1.15; duration: 420; easing.type: Easing.OutQuad
            }
        }
        NumberAnimation { target: bocanadas; property: "opacity"; to: 0; duration: 320 }

        ScriptAction { script: efecto.destroy() }
    }

    // ── motas: chispas que suben desde el grupo ───────────────────
    Item {
        id: subida
        visible: efecto.forma === "motas"
        anchors.fill: parent
        opacity: 0

        Repeater {
            model: 8

            delegate: Rectangle {
                required property int index

                x: efecto.zonaX + (index + 0.5) * (efecto.zonaAncho / 8) - 2
                y: efecto.zonaY + efecto.zonaAlto * 0.8 - (index % 4) * 5
                width: 4
                height: 4
                radius: 2
                color: efecto.tono
            }
        }
    }

    SequentialAnimation {
        id: motas

        ParallelAnimation {
            NumberAnimation { target: subida; property: "opacity"; to: 1; duration: 130 }
            NumberAnimation {
                target: subida; property: "y"
                from: 0; to: -26; duration: 560; easing.type: Easing.OutQuad
            }
        }
        NumberAnimation { target: subida; property: "opacity"; to: 0; duration: 220 }

        ScriptAction { script: efecto.destroy() }
    }

    // ── aura: anillo que late sobre uno solo ──────────────────────
    Rectangle {
        id: cerco
        visible: efecto.forma === "aura"
        x: efecto.zonaX + efecto.zonaAncho / 2 - width / 2
        y: efecto.zonaY + efecto.zonaAlto / 2 - height / 2
        width: 20
        height: 20
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: efecto.tono
        opacity: 0
    }

    SequentialAnimation {
        id: aura

        ParallelAnimation {
            NumberAnimation {
                target: cerco; property: "width"
                from: 16; to: 52; duration: 460; easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: cerco; property: "height"
                from: 16; to: 52; duration: 460; easing.type: Easing.OutQuad
            }
            SequentialAnimation {
                NumberAnimation { target: cerco; property: "opacity"; to: 1; duration: 110 }
                NumberAnimation { target: cerco; property: "opacity"; to: 0; duration: 350 }
            }
        }

        ScriptAction { script: efecto.destroy() }
    }
}
